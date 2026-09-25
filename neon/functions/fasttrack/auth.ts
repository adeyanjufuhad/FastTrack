// Sign-in for the fasttrack function.
//
// Neon Auth (Managed Better Auth) owns users and passwords. The Flutter app
// can't hold Better Auth's HTTP-only cookie cross-origin, so the function
// proxies the three calls it needs and hands the app two strings:
//
//   access_token  — Neon Auth JWT (EdDSA, 15 min). Sent as `Bearer` on every
//                   API call and verified here against the branch JWKS.
//   refresh_token — the Better Auth session cookie, base64url-wrapped.
//                   Opaque to the app; swapped for a fresh JWT on /auth/refresh.
//
// Verification uses node:crypto directly (Ed25519 / ES256), no JWT library.

import { createPublicKey, verify, type JsonWebKey, type KeyObject } from "node:crypto";

export interface Claims {
  sub: string;
  email?: string;
  exp: number;
  iss?: string;
  [k: string]: unknown;
}

export class AuthError extends Error {
  readonly status: number;
  constructor(message: string, status = 401) {
    super(message);
    this.status = status;
  }
}

const b64url = (s: string) => Buffer.from(s, "base64url");

// ── JWKS cache ───────────────────────────────────────────────────────────

type Jwk = JsonWebKey & { kid?: string; alg?: string };
let keys = new Map<string, { key: KeyObject; alg: string }>();
let fetchedAt = 0;
const JWKS_TTL_MS = 10 * 60_000;

async function loadJwks(url: string, fetcher: typeof fetch = fetch) {
  const res = await fetcher(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new AuthError(`JWKS ${res.status}`, 503);
  const body = (await res.json()) as { keys?: Jwk[] };
  const next = new Map<string, { key: KeyObject; alg: string }>();
  for (const jwk of body.keys ?? []) {
    const alg = jwk.alg ?? (jwk.crv === "Ed25519" ? "EdDSA" : jwk.crv === "P-256" ? "ES256" : "");
    if (!jwk.kid || !alg) continue;
    next.set(jwk.kid, { key: createPublicKey({ key: jwk, format: "jwk" }), alg });
  }
  keys = next;
  fetchedAt = Date.now();
}

/** Test hook: forget cached keys. */
export function resetJwksCache() {
  keys = new Map();
  fetchedAt = 0;
}

async function keyFor(kid: string, jwksUrl: string, fetcher?: typeof fetch) {
  if (!keys.has(kid) || Date.now() - fetchedAt > JWKS_TTL_MS) {
    await loadJwks(jwksUrl, fetcher); // refetch also covers key rotation
  }
  const k = keys.get(kid);
  if (!k) throw new AuthError("Unknown signing key.");
  return k;
}

/**
 * Verifies signature, expiry and issuer. The issuer Neon Auth puts in its
 * tokens is the origin of NEON_AUTH_BASE_URL.
 */
export async function verifyJwt(
  token: string,
  opts: { jwksUrl: string; issuer: string; now?: number; fetcher?: typeof fetch },
): Promise<Claims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new AuthError("Malformed token.");
  const [h, p, s] = parts;
  let header: { alg?: string; kid?: string };
  let claims: Claims;
  try {
    header = JSON.parse(b64url(h).toString("utf8"));
    claims = JSON.parse(b64url(p).toString("utf8"));
  } catch {
    throw new AuthError("Malformed token.");
  }
  if (!header.kid || (header.alg !== "EdDSA" && header.alg !== "ES256")) {
    throw new AuthError("Unsupported token.");
  }
  const { key, alg } = await keyFor(header.kid, opts.jwksUrl, opts.fetcher);
  if (alg !== header.alg) throw new AuthError("Token algorithm mismatch.");

  const data = Buffer.from(`${h}.${p}`);
  const ok = header.alg === "EdDSA"
    ? verify(null, data, key, b64url(s))
    : verify("sha256", data, { key, dsaEncoding: "ieee-p1363" }, b64url(s));
  if (!ok) throw new AuthError("Invalid token signature.");

  const now = Math.floor((opts.now ?? Date.now()) / 1000);
  if (typeof claims.exp !== "number" || claims.exp <= now) throw new AuthError("Session expired.");
  if (claims.iss !== opts.issuer) throw new AuthError("Wrong token issuer.");
  if (typeof claims.sub !== "string" || !/^[0-9a-f-]{36}$/i.test(claims.sub)) {
    throw new AuthError("Token has no user.");
  }
  return claims;
}

// ── Neon Auth proxy ──────────────────────────────────────────────────────

export interface Session {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  user: { id: string; email: string };
}

const wrap = (cookie: string) => Buffer.from(cookie, "utf8").toString("base64url");
const unwrap = (token: string) => {
  const c = Buffer.from(token, "base64url").toString("utf8");
  if (!/^[\w.-]+=[^;\r\n]+(; [\w.-]+=[^;\r\n]+)*$/.test(c)) throw new AuthError("Invalid refresh token.");
  return c;
};

/** `name=value; name=value` from a response's Set-Cookie headers. */
function cookieHeader(res: Response): string {
  return res.headers
    .getSetCookie()
    .map((c) => c.split(";")[0].trim())
    .filter((c) => c.includes("=") && !c.endsWith("="))
    .join("; ");
}

const jwtExp = (jwt: string) => {
  try {
    return (JSON.parse(b64url(jwt.split(".")[1]).toString("utf8")) as Claims).exp ?? 0;
  } catch {
    return 0;
  }
};

export class NeonAuth {
  private readonly baseUrl: string;
  private readonly origin: string;
  private readonly fetcher: typeof fetch;

  constructor(baseUrl: string, fetcher: typeof fetch = fetch) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.origin = new URL(this.baseUrl).origin;
    this.fetcher = fetcher;
  }

  private call(path: string, init: { method?: string; body?: unknown; cookie?: string } = {}) {
    return this.fetcher(`${this.baseUrl}${path}`, {
      method: init.method ?? "POST",
      headers: {
        // Better Auth checks Origin on cookie-bearing POSTs. Its own origin
        // is always trusted.
        Origin: this.origin,
        ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
        ...(init.cookie ? { Cookie: init.cookie } : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      signal: AbortSignal.timeout(15_000),
    });
  }

  private static async failure(res: Response, fallback: string): Promise<never> {
    let message = fallback;
    try {
      const b = (await res.json()) as { message?: string };
      if (b?.message) message = b.message;
    } catch { /* keep fallback */ }
    throw new AuthError(message, res.status >= 500 ? 503 : res.status === 422 ? 422 : 401);
  }

  /** Session cookie → short-lived JWT. */
  private async jwt(cookie: string): Promise<string> {
    const res = await this.call("/token", { method: "GET", cookie });
    if (!res.ok) await NeonAuth.failure(res, "Session expired. Please sign in again.");
    const body = (await res.json()) as { token?: string };
    if (!body.token) throw new AuthError("Session expired. Please sign in again.");
    return body.token;
  }

  private async session(res: Response): Promise<Session> {
    const body = (await res.json()) as { user?: { id?: string; email?: string } };
    const cookie = cookieHeader(res);
    if (!cookie || !body.user?.id) {
      throw new AuthError("Check your inbox to confirm your email, then sign in.");
    }
    const access = res.headers.get("set-auth-jwt") || (await this.jwt(cookie));
    return {
      access_token: access,
      refresh_token: wrap(cookie),
      expires_at: jwtExp(access),
      user: { id: body.user.id, email: body.user.email ?? "" },
    };
  }

  async signUp(email: string, password: string, name?: string): Promise<Session> {
    const res = await this.call("/sign-up/email", {
      body: { email, password, name: name?.trim() || email.split("@")[0] },
    });
    if (!res.ok) await NeonAuth.failure(res, "Could not create the account.");
    return this.session(res);
  }

  async signIn(email: string, password: string): Promise<Session> {
    const res = await this.call("/sign-in/email", { body: { email, password } });
    if (!res.ok) await NeonAuth.failure(res, "Email or password is incorrect.");
    return this.session(res);
  }

  async refresh(refreshToken: string): Promise<{ access_token: string; expires_at: number }> {
    const access = await this.jwt(unwrap(refreshToken));
    return { access_token: access, expires_at: jwtExp(access) };
  }

  async signOut(refreshToken: string): Promise<void> {
    await this.call("/sign-out", { body: {}, cookie: unwrap(refreshToken) });
  }
}
