# Product requirements — FastTrack v1

## Problem

Boutique Nigerian investment and lending desks still open accounts and take loan applications through PDF / email / a rate calculator. Staff re-key. Officers start from a raw scan. Clients who just opened a bank account in twelve minutes notice.

## Outcome

A rehearsed applicant reaches a pre-qualification result in under five minutes. The same record is a scored file on the officer dashboard. A human decides.

## Users

| ID | User | Primary job |
|---|---|---|
| U1 | Individual applicant | Open a relationship and see if a loan is even possible |
| U2 | Corporate applicant | Submit CAC + signatories without courier |
| U3 | Existing portfolio client (optional path) | Borrow against holdings the firm already manages |
| U4 | Loan officer / RM | Decide from a scored file |
| U5 | Demo operator | Run Adaeze / Ibrahim / Northshore without network drama |

## In scope (v1)

- Email/password auth
- Individual and corporate onboarding tracks
- Document upload: government ID, bank statement, CAC (corporate), signature PNG
- SMS paste alternative to statement PDF
- Sandbox BVN / NIN
- Gemini structured extract + officer narrative
- Rules engine → amount + Low / Medium / High
- Applicant result screen with disclaimer
- Officer queue + file + approve / more-info / decline + notes
- Three seeded personas

## Out of scope (v1)

Live KYC, bureau, payments, disbursement, collections, notifications, multi-product catalogue, accounting export, native store release as a requirement (web demo is enough to pitch).

## Product rules

1. Pre-qualification is **not an offer**. Copy is mandatory on A9 and O2.
2. KYC mismatch → no amount. Status `more_info`.
3. Gemini must not invent transactions or change the computed amount.
4. Confidence `< 0.45` haircuts amount 20% and floors tier at Medium.
5. Three or more detected lenders → floor tier High + stacking warning.
6. Demo chip copy is fixed (see `kyc-sandbox.md`).
7. One application per applicant in v1. No product catalogue.

## Disclaimer (lock this text)

**A9 / applicant**

> This is a pre-qualification for demonstration purposes, not an offer of credit. A specialist will review your file. Identity checks in this build use sandbox data.

**O2 / officer**

> Demo build. Sandbox KYC. Amount is rules-engine output, not a credit-committee decision.

## Success metrics for the MVP (demo, not production analytics)

- Happy-path click-through A2→A9 ≤ 5 minutes with seed data
- Officer can decide Adaeze in ≤ 2 minutes
- Applicant amount === officer amount on every seed
- Zero crashes on Flutter web at 1366×768

## Open questions the team must not block on

| Question | Default until product says otherwise |
|---|---|
| Tenor options | 6 / 12 / 24 months |
| Default requested amount | Applicant types it; empty → engine still returns a cap |
| Holdings sleeve | Off unless persona Chioma is seeded |
| Languages | English only |
| Officer 2FA | Not in v1 |
