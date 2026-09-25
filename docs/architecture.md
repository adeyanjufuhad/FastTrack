# Architecture

## Logical flow

```
Flutter client (applicant + officer web)
        │
        ├── Supabase Auth          email / session / role claim
        ├── Supabase Storage       ID, statement, CAC, signature
        ├── Edge Function kyc      sandbox BVN / NIN
        ├── Edge Function extract  Gemini → locked JSON
        └── Edge Function score    rules + Gemini narrative
                │
                ▼
        Supabase Postgres
        applicants, documents, applications,
        eligibility_results, officer_notes
                │
                ▼
        Officer dashboard (same Flutter web app, /officer)
```

## Environments

| Name | Purpose | Data |
|---|---|---|
| local | Emulator + local Flutter | Seed only |
| demo | Hosted Flutter web + one Supabase project | Seed + whatever is typed in a pitch |
| (later) prod | Out of v1 | Real PII, live KYC flag still off until contract |

There is no staging requirement for v1.

## Auth model

- Supabase Auth user `id` = `applicants.id`
- App metadata: `{ "role": "applicant" | "officer" }`
- Flutter reads role after session restore and routes to `/home` or `/officer`
- Never ship the service-role key in the client

## Trust boundaries

- Gemini sees statement text or SMS blob + role + tenor. Not password. Prefer masked BVN.
- Storage bucket `documents` is private. Client uses signed URLs (≤ 10 minutes).
- RLS: applicant sees own rows; officer sees all applications.
- `LIVE_KYC` compile flag defaults false.

## Edge Functions

| Function | Trigger | Timeout |
|---|---|---|
| `kyc-check` | POST from client after A5 submit | 5s |
| `extract-statement` | POST after documents saved | 40s (Gemini) |
| `score-application` | POST after extract row exists | 40s |

Client may call `extract` then `score`, or a single `process-application` orchestrator that does both. Prefer one orchestrator to keep A8 simple.

Suggested single function: `process-application`

1. Load application + documents
2. Pull statement text (PDF text extract on function side, or client-sent SMS)
3. Check extract cache by sha256(text)
4. Else Gemini extract
5. Run rules
6. Gemini narrative
7. Write `eligibility_results`
8. Set application.status = `scored`

## PDF / image text

v1 acceptable path:

- SMS paste: client sends raw text
- PDF: Edge Function uses a simple text extract if possible; if extract is empty, Gemini multimodal on first page images
- Image statement: send to Gemini as inline image (watch free-tier payload size; cap 8 MB)

If extract fails: application.status = `more_info`, applicant sees “We could not read this file. Try SMS paste or a clearer PDF.”

## Caching

Table `extract_cache(input_hash text primary key, payload jsonb, created_at)`.  
Also seed cache rows for Adaeze / Ibrahim / Northshore so the pitch room does not depend on Gemini.

## Hosting

Flutter web build of the same app. Officer routes exist in the same deploy. Hide officer login from the applicant marketing page; `/officer/login` is enough.
