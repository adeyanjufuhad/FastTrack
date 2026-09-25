# Security and PII

v1 is a demo. Still treat uploads as sensitive.

## Must

- RLS on all tables before any UI ships
- Service role key only on Edge Functions
- Gemini key only as Function secret
- Private Storage bucket; signed URLs ≤ 10 minutes
- Store `bvn_masked` / `nin_masked` as `*******1234` (last 4). Full values only in `kyc_logs` if you must, and wipe the demo project after public laptops
- No real customer data in git
- `.env` in `.gitignore`

## Must not

- Email statements around
- Commit seed copies of real statements
- Print full BVN in officer UI (show last 4)
- Call a live KYC URL from the demo flavour

## Roles

```
applicant → select/insert/update own applicants, documents, applications
            select own eligibility_results
officer   → select all of the above
            insert officer_notes
            update applications.status, officer_id, decided_at
```

## NDPR posture for a prototype

Minimum collection, privacy note on A3, seed data in pitches, wipe on request. A paid pilot starts with the firm’s DPO, not more Flutter.
