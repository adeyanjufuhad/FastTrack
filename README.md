<p align="center">
  <img src="website/assets/logo-mark.svg" width="72" alt="FastTrack">
</p>

# FastTrack

FastTrack is digital onboarding and instant loan pre-qualification for Nigerian investment and lending firms. It replaces PDF account forms and rate calculators with a five-minute client flow: identity check, bank statement or SMS upload, a pre-qualified amount and risk tier, plus an officer dashboard. A human still reviews and approves each file.

> **Pilot / demo build.** Identity checks use a clearly labelled sandbox. Results are pre-qualifications, not offers of credit. No real customer data belongs in this repo.

## What's in the repo

| Path | What it is |
|---|---|
| [`app/`](app/) | Flutter app — applicant flow A1–A10 (Android, iOS, web) and officer dashboard O1–O3 (web). Runs fully offline in demo mode. |
| [`website/`](website/) | Static download site — blue & white, fluid layout, links to the APK and the web app. |
| [`supabase/`](supabase/) | Postgres schema, hardened RLS, storage bucket, seeds, and the `kyc-check` / `process-application` Edge Functions (Gemini extract + rules + narrative). |
| [`docs/`](docs/) | Product handoff pack: PRD, screens, scoring rules, Gemini contracts, security, sprint plan. Start with [`docs/00-START-HERE.md`](docs/00-START-HERE.md). |
| [`fixtures/`](fixtures/) | Seed personas, sample bank-alert SMS, locked expected scores. |
| [`api/openapi.yaml`](api/openapi.yaml), [`tickets/`](tickets/) | Edge Function contract and issue list (FT-00 … FT-19). |

## Quick start (offline demo — 2 minutes)

```bash
cd app
flutter pub get
flutter run -d chrome
```

Walk **Adaeze**: Get started → Individual → register any email → fill details → tap the *Adaeze O.* sample identity → *Use sample ID* + her *sample alerts* → sign → result **NGN 1,240,000 · Elevated review**. Then sign out, open `/officer/login` as `officer@fasttrack.demo` / `FastTrack!demo1` and approve the file. The applicant's status page updates.

Demo state survives a page refresh; **Reset demo** restores the seed personas. Presenting? Use the one-page [pitch run-sheet](docs/PITCH-RUNSHEET.md).

## Full stack (Supabase + Gemini)

1. Create a Supabase project (free tier).
2. SQL editor, in order: `supabase/migrations/20260925000001_schema.sql` → `…02_rls.sql` → `supabase/seed.sql`.
3. Auth → add `applicant@fasttrack.demo` and `officer@fasttrack.demo` (password `FastTrack!demo1`), then run `supabase/seed_personas.sql` — it seeds the three persona files and gives the officer the `officer` role claim.
4. Deploy functions and set the Gemini key **as a function secret only**:
   ```bash
   supabase functions deploy kyc-check
   supabase functions deploy process-application
   supabase secrets set GEMINI_API_KEY=your-key
   ```
5. Run the app with `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` (see [`app/README.md`](app/README.md)).

Seeded walks pass a `fixture:` key, so the pitch never depends on Gemini quota or network.

## Rules that matter

- **Amounts come from rules, never from the model.** `app/lib/scoring/score_config.dart` holds every constant; `supabase/functions/_shared/score.ts` mirrors it and both are tested on the same vectors (Adaeze 1,240,000 medium · Ibrahim 410,000 high · Northshore 3,780,000 medium).
- **Applicant amount === officer amount** — both read the same `eligibility_results` row.
- **KYC mismatch → no amount**, status `more_info`.
- **Only the anon key ships in the app.** Service role and Gemini keys live in Edge Function secrets. Clients cannot write KYC results, scores or decisions (see the RLS migration header).
- **Amber sandbox chip** on A5 and A9, locked disclaimer on A9 and O2.

## Tests

```bash
cd app && flutter analyze && flutter test
deno test supabase/functions/_shared/     # TS scoring parity
```

CI runs both on every push (`.github/workflows/ci.yml`).

## Design

Blue and white, taken from the FastTrack mark (blue `#2B76E5` over navy `#0A2463`), Plus Jakarta Sans, fluid sizing in both the app and the site. See [`docs/design/tokens.md`](docs/design/tokens.md).
