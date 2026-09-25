# Sprint plan (10–14 focused days)

One squad. Exit criteria are gates — do not start the next phase without them.

## Phase 0 — Setup (0.5 day)

Repo, Flutter runs on Chrome, Supabase project, schema + RLS + seed, two Auth users, Gemini secret or fixture stub.

**Exit:** officer@ and applicant@ can sign in; `select * from applicants` as each role behaves under RLS.

## Phase 1 — Onboarding UI (2–3 days)

A1–A7 individual path writes applicants + documents + signature. Corporate reuses A4.

**Exit:** one individual record with ID + signature in Storage, visible in Table Editor.

## Phase 2 — Document intelligence (2–3 days)

Fixture statement / SMS returns valid JSON into `eligibility_results`. Failures are user-visible.

**Exit:** Adaeze SMS fixture → cached extract row.

## Phase 3 — KYC sandbox (1–2 days)

Dummy pass/fail. Amber chip. `LIVE_KYC=false`.

**Exit:** 22222222222 passes, 00000000000 fails, unknown mismatches.

## Phase 4 — Scoring (2–3 days)

Pure function + narrative. A9 and O2 agree.

**Exit:** unit tests for Adaeze and Ibrahim vectors; disclaimer on A9.

## Phase 5 — Officer dashboard (1–2 days)

O1–O3. Decisions persist to A10.

**Exit:** approve Adaeze, refresh applicant home, chip = approved.

## Phase 6 — Demo polish (1 day)

Seeds, 1366×768 pass, 90-second recording, hosted web link.

**Exit:** definition-of-done checklist ticked.

## Parallelism

Flutter can build A1–A7 against local models while backend lands schema. Do not block UI on Gemini. Stub `process-application` with fixture JSON on day 2.
