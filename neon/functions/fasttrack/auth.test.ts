import { rejects, strictEqual } from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { beforeEach, test } from "node:test";

import { NeonAuth, resetJwksCache, verifyJwt } from "./auth.ts";

const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "k1", alg: "EdDSA" };
const jwksFetch = (async () => Response.json({ keys: [jwk] })) as unknown as typeof fetch;

const ISS = "https://ep-x.neonauth.example";
const UID = "830a7029-718c-41dd-adcd-8829bfbae50b";

function jwt(claims: Record<string, unknown>, kid = "k1") {
  const enc = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const head = `${enc({ alg: "EdDSA", kid })}.${enc(claims)}`;
  return `${head}.${sign(null, Buffer.from(head), privateKey).toString("base64url")}`;
}
const opts = { jwksUrl: "https://x/jwks", issuer: ISS, fetcher: jwksFetch };
const exp = () => Math.floor(Date.now() / 1000) + 600;

beforeEach(() => resetJwksCache());

test("valid Neon Auth JWT verifies", async () => {
  const c = await verifyJwt(jwt({ sub: UID, email: "a@b.c", iss: ISS, exp: exp() }), opts);
  strictEqual(c.sub, UID);
});

test("expired, wrong issuer, tampered and unknown-key tokens are rejected", async () => {
  await rejects(verifyJwt(jwt({ sub: UID, iss: ISS, exp: 1 }), opts), /expired/);
  await rejects(verifyJwt(jwt({ sub: UID, iss: "https://evil", exp: exp() }), opts), /issuer/);
  const [h, , s] = jwt({ sub: UID, iss: ISS, exp: exp() }).split(".");
  const forged = Buffer.from(JSON.stringify({ sub: UID, iss: ISS, exp: exp() + 1 })).toString("base64url");
  await rejects(verifyJwt(`${h}.${forged}.${s}`, opts), /signature/);
  await rejects(verifyJwt(jwt({ sub: UID, iss: ISS, exp: exp() }, "other"), opts), /Unknown signing key/);
  await rejects(verifyJwt("not.a.jwt", opts), /Malformed/);
});

test("sign-in proxies Better Auth and swaps the session cookie for a JWT", async () => {
  const calls: { url: string; cookie?: string; origin?: string }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    const h = new Headers(init.headers);
    calls.push({ url, cookie: h.get("cookie") ?? undefined, origin: h.get("origin") ?? undefined });
    if (url.endsWith("/sign-in/email")) {
      const res = Response.json({ token: "sess", user: { id: UID, email: "a@b.c" } });
      res.headers.append("set-cookie", "__Secure-neonauth.session_token=abc.sig%2F; Path=/; HttpOnly; Secure");
      return res;
    }
    if (url.endsWith("/token")) return Response.json({ token: jwt({ sub: UID, iss: ISS, exp: 42 }) });
    return new Response(null, { status: 404 });
  }) as unknown as typeof fetch;

  const auth = new NeonAuth("https://ep-x.neonauth.example/fasttrack/auth/", fetcher);
  const s = await auth.signIn("a@b.c", "pw");
  strictEqual(s.user.id, UID);
  strictEqual(s.expires_at, 42);
  strictEqual(calls[0].origin, "https://ep-x.neonauth.example");
  strictEqual(calls[1].url, "https://ep-x.neonauth.example/fasttrack/auth/token");
  strictEqual(calls[1].cookie, "__Secure-neonauth.session_token=abc.sig%2F");

  const r = await auth.refresh(s.refresh_token);
  strictEqual(r.expires_at, 42);
  strictEqual(calls[2].cookie, "__Secure-neonauth.session_token=abc.sig%2F");
  await rejects(auth.refresh(Buffer.from("x\r\nHost: evil").toString("base64url")), /Invalid refresh token/);
});

test("bad credentials surface Better Auth's message as 401", async () => {
  const fetcher = (async () =>
    Response.json({ code: "INVALID_EMAIL_OR_PASSWORD", message: "Invalid email or password" }, { status: 401 })) as unknown as typeof fetch;
  const auth = new NeonAuth("https://ep-x.neonauth.example/db/auth", fetcher);
  await rejects(auth.signIn("a@b.c", "nope"), (e: Error & { status?: number }) => {
    strictEqual(e.status, 401);
    strictEqual(e.message, "Invalid email or password");
    return true;
  });
});
