// Entry point of the `fasttrack` Neon Function. Everything Neon injects
// (DATABASE_URL, NEON_AUTH_*, AWS_* for Object Storage, NEON_AI_GATEWAY_*)
// is read here once per instance; routes live in api.ts.

import { createHandler } from "./api.ts";
import { NeonAuth, verifyJwt } from "./auth.ts";
import { createQuery } from "./db.ts";
import { s3Storage } from "./storage.ts";

const authBase = process.env.NEON_AUTH_BASE_URL;
if (!authBase) throw new Error("NEON_AUTH_BASE_URL is not set: provision Neon Auth on this branch.");
const jwksUrl = process.env.NEON_AUTH_JWKS_URL ?? `${authBase.replace(/\/$/, "")}/.well-known/jwks.json`;
const issuer = new URL(authBase).origin;

const fetch = createHandler({
  query: createQuery(),
  storage: s3Storage(),
  auth: new NeonAuth(authBase),
  verify: (token) => verifyJwt(token, { jwksUrl, issuer }),
});

export default { fetch };
