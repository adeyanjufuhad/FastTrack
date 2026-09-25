# Screen inventory

Thirteen screens. Visual: navy `#0B1F3A`, ivory `#FBF8F2`, gold `#C4A35A`. See `design/tokens.md`.

## Applicant

| ID | Route | Purpose | Done when |
|---|---|---|---|
| A1 | `/` | Splash, wordmark, Get started | Tapping continues |
| A2 | `/role` | Individual / Corporate | Role persisted on applicant row |
| A3 | `/auth` | Register / login | Session exists |
| A4 | `/details` | Stepped form 1/4 | Required fields valid, draft saved |
| A5 | `/kyc` | BVN + NIN + sandbox chip | `kyc_result` stored; mismatch still allows continue but blocks amount later |
| A6 | `/documents` | ID + statement dropzones, SMS toggle | ≥1 ID and (statement file or SMS ≥ 20 lines) |
| A7 | `/sign` | Canvas + legal name | PNG uploaded as document kind=signature |
| A8 | `/processing` | Three ticks: identity, statement, scoring | Function returns or errors with retry |
| A9 | `/result` | Amount, tier, 4-line summary, disclaimer, reference | Matches officer amount |
| A10 | `/home` | Status of the one application | Status chip reflects officer decision |

## Officer

| ID | Route | Purpose | Done when |
|---|---|---|---|
| O1 | `/officer` | Queue table + filters | Lists seed + live apps |
| O2 | `/officer/applications/:id` | Docs, extract, narrative, notes, decision | Decision persists; applicant A10 updates |
| O3 | `/officer/login` | Officer only | Non-officer session is rejected |

## Field lists

### A4 Individual

legal_name, dob, phone, email (from auth), residential_address, occupation, next_of_kin_name, next_of_kin_phone, requested_amount (optional), tenor_months (6/12/24), purpose

### A4 Corporate

registered_name, rc_number, nature_of_business, registered_address, signatory_1_name, signatory_1_bvn, signatory_2_name, signatory_2_bvn, requested_amount, tenor_months, purpose

### A5

bvn (11 digits), nin (11 digits), amber chip always visible

### A6

kind=id required  
kind=statement **or** sms_text  
corporate also kind=cac

### A9 content

- Band: “Up to NGN X”
- Tier in words: standard / elevated / high review (map Low/Medium/High)
- Four-line summary (first 4 sentences of narrative, or a shorter applicant-facing rewrite — do not invent a second score)
- Reference = `applications.id` short prefix `FT-` + first 8 of uuid
- Disclaimer from PRD

## Empty / error states (required)

- Gemini / network fail on A8: retry button, no crash
- Unreadable statement: guidance to paste SMS
- Officer opens file with no extract: “Scoring pending or failed”
- Wrong role hits /officer: bounce to A10
