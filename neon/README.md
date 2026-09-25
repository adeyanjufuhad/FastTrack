# FastTrack on Neon

The FastTrack backend on [Neon](https://neon.com): the same data, rules and API behaviour as [`../supabase/`](../supabase/), built on Neon Postgres, Neon Auth (Managed Better Auth), Neon Object Storage and **one** Neon Function.

The Flutter app talks to it through [`NeonRepository`](../app/lib/data/neon_repository.dart) when built with the function's URL:

```bash
cd app
flutter run -d chrome --dart-define=NEON_API_URL=https://br-little-hat-b492f9op-fasttrack.compute.c-6.us-east-2.aws.neon.tech
```

## What runs where

| Piece | Neon service | Notes |
|---|---|---|
| Tables, enums, seeds | Postgres, database `fasttrack` on branch `main` | [`migrations/0001_schema.sql`](migrations/0001_schema.sql) matches the live schema column for column |
| Users and passwords | Neon Auth (email + password) | Users live in `neon_auth."user"`. Tokens are EdDSA JWTs that expire after 15 minutes |
| Officers | `public.staff` | Neon Auth JWTs can't carry custom claims, so officer status is a row in this table, granted only by SQL ([`seeds/0003_staff.sql`](seeds/0003_staff.sql)) |
| IDs, statements, signatures | Object Storage, private bucket `documents` | Stored as `<user id>/<kind>-<ms>-<name>`, 8 MB max, JPEG/PNG/PDF only. Viewing uses presigned links that expire after 10 minutes |
| Everything else | Neon Function `fasttrack` | Sign-in proxy, applicant API, KYC sandbox, uploads, extract → rules → narrative, officer queue |
| Statement reader | Gemini | `GEMINI_API_KEY` if set; otherwise the branch's Neon AI Gateway (`gemini-3-flash`); otherwise cached fixtures only |

**Access control lives in the function.** The function connects as the table owner. RLS is enabled on every table with no policies, so any other role sees nothing, and the Data API stays off. The rules from [`supabase/migrations/*_rls.sql`](../supabase/migrations/20260925000002_rls.sql) are enforced in [`functions/fasttrack/api.ts`](functions/fasttrack/api.ts) and covered by [`api.test.ts`](functions/fasttrack/api.test.ts):

- An applicant only sees their own profile, application, documents and results.
- KYC fields, holdings, eligibility rows and the `scored` / decision statuses are written by the server only. Request bodies can't set them.
- An applicant can only move their file between `draft` and `submitted`.
- Officers read every file, add notes and decide (`in_review`, `more_info`, `approved`, `declined`).

## API

All bodies are JSON unless noted. Every route except `/health` and `/auth/*` needs `Authorization: Bearer <access_token>`.

| Method + path | Who | Does |
|---|---|---|
| `POST /auth/sign-up` `{email, password, name?}` | anyone | Creates a Neon Auth user and returns `{access_token, refresh_token, expires_at, user: {id, email, is_officer}}` |
| `POST /auth/sign-in` `{email, password}` | anyone | Same response |
| `POST /auth/refresh` `{refresh_token}` | anyone | New `{access_token, expires_at}`. Call it when the JWT expires or on a 401 |
| `POST /auth/sign-out` `{refresh_token}` | anyone | Ends the Better Auth session |
| `GET /me` | signed in | `{id, email, is_officer}` |
| `GET /applicant` · `PUT /applicant` | applicant | Own profile row, created on first read. `PUT` accepts `role`, `legal_name` and the A4 detail columns |
| `GET /application` | applicant | Own application, created as `draft` on first read |
| `PUT /applications/:id` | owner | `requested_amount`, `tenor_months`, `purpose`, `sms_text`, `status` (`draft`/`submitted`) |
| `POST /kyc-check` `{bvn?, nin?, legal_name}` | applicant | Sandbox check. Stores only masked numbers |
| `POST /documents?kind=<kind>&name=<file name>` | applicant | Raw file body with `Content-Type` `image/jpeg`, `image/png` or `application/pdf` |
| `GET /documents` | applicant | Own documents |
| `GET /documents/:id/url` | owner, officer | `{url, expires_in: 600}` presigned download link |
| `POST /process-application` `{application_id, fixture_key?}` | owner, officer | Extract → rules → narrative. Errors: 409 KYC mismatch, 422 unreadable, 503 reader down and no cache |
| `GET /applications/:id/eligibility` | owner, officer | Latest result or `null` |
| `GET /officer/queue` | officer | Every non-draft file: `{application, applicant, eligibility, notes}` |
| `GET /officer/applications/:id` | officer | One file, plus `documents` |
| `POST /officer/applications/:id/notes` `{body}` | officer | Adds a note |
| `POST /officer/applications/:id/decision` `{status}` | officer | `in_review` · `more_info` · `approved` · `declined` |

Errors are `{"error": "<message>"}`. The codes follow [`docs/api-contracts.md`](../docs/api-contracts.md).

## Set up and deploy

Needs Node 22.6+ (24 recommended) and the [Neon CLI](https://neon.com/docs/cli), signed in (`npm i -g neon && neon auth`).

```bash
cd neon
npm install
neon link --project-id hidden-dream-89003932      # FastTrack project, branch main

# 1. Schema + seeds (idempotent; already applied on main)
DATABASE_URL="$(neon connection-string --database-name fasttrack)" npm run migrate

# 2. Deploy the function (the CLI bundles it with esbuild)
neon functions deploy fasttrack --src functions/fasttrack/index.ts
neon functions get fasttrack                      # → invocation_url

# 3. Demo accounts (documented in docs/SETUP.md)
F=<invocation_url without trailing slash>
curl -s -X POST $F/auth/sign-up -H 'content-type: application/json' \
  -d '{"email":"applicant@fasttrack.demo","password":"FastTrack!demo1"}'
curl -s -X POST $F/auth/sign-up -H 'content-type: application/json' \
  -d '{"email":"officer@fasttrack.demo","password":"FastTrack!demo1"}'
psql "$(neon connection-string --database-name fasttrack)" -f seeds/0003_staff.sql   # officer rights
```

Optional function settings, passed with `--env KEY=VALUE` on deploy:

| Variable | Default | Purpose |
|---|---|---|
| `GEMINI_API_KEY` | unset → AI Gateway | Call Google directly instead of the Neon AI Gateway |
| `GEMINI_MODEL` | `gemini-2.5-flash` (direct) / `gemini-3-flash` (gateway) | Model for extract + narrative |
| `ALLOWED_ORIGINS` | unset → `*` | Comma-separated CORS allowlist, e.g. your web app's origin |
| `LIVE_KYC` | unset | Must stay unset. `true` makes `/kyc-check` refuse (no live provider exists) |

Neon injects `DATABASE_URL`, `NEON_AUTH_*`, `AWS_*` (storage) and `NEON_AI_GATEWAY_*` itself. Don't set them.

To deploy without the CLI, `npm run bundle` writes `dist/fasttrack.zip` (one `index.mjs`, about 40 KB), which is the archive the [deploy API](https://neon.com/docs/compute/functions/deploy#deploy-with-the-api) expects.

## Develop

```bash
npm run typecheck   # tsc, strict
npm test            # scoring parity, JWT checks, sign-in proxy, API access rules
npm run bundle      # dist/index.mjs + dist/fasttrack.zip
```

`functions/_shared/score.ts` is the same code as `supabase/functions/_shared/score.ts`, and both mirror `app/lib/scoring/`. Change all three together; the parity tests pin the persona amounts (1,240,000 · 410,000 · 3,780,000).

| File | Contents |
|---|---|
| `functions/fasttrack/index.ts` | Entry point. Reads Neon's injected env once |
| `functions/fasttrack/api.ts` | Routes and access rules |
| `functions/fasttrack/auth.ts` | JWT verification (`node:crypto`, Ed25519/ES256 against the branch JWKS) and the Better Auth sign-in proxy |
| `functions/fasttrack/storage.ts` | S3 put/get/presign via `aws4fetch` |
| `functions/fasttrack/db.ts` | `pg` pool on the pooled `DATABASE_URL` |
| `functions/_shared/` | Rules engine and Gemini client (ported from Deno) |
| `scripts/migrate.mjs` · `scripts/bundle.mjs` | Apply SQL · build the deploy zip |
