# API contracts

Prefer one orchestrator. REST via Supabase Edge Functions. Auth: `Authorization: Bearer <user access token>`.

See `api/openapi.yaml` for the machine-readable version.

## POST /functions/v1/kyc-check

```json
// request
{ "bvn": "22222222222", "nin": "11111111111", "legal_name": "Adaeze Okafor" }

// response
{ "result": "sandbox_pass", "matched_name": "ADA EZE OKAFOR", "mode": "sandbox" }
```

Side effect: updates `applicants.kyc_result`, `bvn_masked`, `nin_masked`; inserts `kyc_logs`.

## POST /functions/v1/process-application

```json
// request
{ "application_id": "uuid", "fixture_key": "fixture:adaeze-sms" }

// fixture_key is optional. If present, skip Gemini and use extract_cache.
// Demo builds should pass fixture_key for seeded walks.

// response
{
  "application_id": "uuid",
  "status": "scored",
  "amount_prequalified": 1240000,
  "tier": "medium",
  "warnings": ["external_lender_detected"],
  "narrative": "…",
  "applicant_summary": "…"
}
```

Errors:

| HTTP | when |
|---|---|
| 401 | no/invalid JWT |
| 403 | application not owned and caller not officer |
| 409 | KYC mismatch — status set more_info, no amount |
| 422 | unreadable statement / invalid extract after retry |
| 503 | Gemini down and no cache |

## Direct table access (client)

Allowed through the Supabase Dart client with RLS:

- insert/update `applicants`, `applications`, `documents`
- select `eligibility_results` for own application
- officer select-all + insert `officer_notes` + update `applications.status`

Do not expose service-role CRUD to Flutter.
