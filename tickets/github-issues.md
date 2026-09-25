# Issues to paste into GitHub / Linear

Create labels: `phase-0` `phase-1` `phase-2` `phase-3` `phase-4` `phase-5` `phase-6` `flutter` `backend` `blocked-on-product`

---

## FT-00 Repo and environments
**Labels:** phase-0  
Create repo, add this handoff pack, Flutter counter-app replaced with empty `lib/main.dart` routing stub, `.env.example`, `.gitignore`.  
**AC:** `flutter run -d chrome` shows splash placeholder.

## FT-00b Supabase schema
**Labels:** phase-0 backend  
Run `db/schema.sql`, `db/rls.sql`, `db/seed.sql`. Create Auth users. Set officer `app_metadata.role=officer`. Private bucket `documents`.  
**AC:** RLS check: applicant cannot select another applicant row.

## FT-01 Register / login
**Labels:** phase-1 flutter  
**AC:** see user-stories.md

## FT-02 Role selection
## FT-03 Individual details draft
## FT-04 Corporate details
## FT-05 KYC sandbox UI + function
## FT-06 Mismatch blocks amount
## FT-07 ID upload
## FT-08 Statement or SMS
## FT-09 Signature canvas
## FT-10 Extract function + schema validation
## FT-11 Score pure function + unit tests
## FT-12 Narrative call
## FT-13 Result screen A8/A9
## FT-14 Officer queue
## FT-15 Officer file
## FT-16 Decision + notes
## FT-17 Seed personas in queue
## FT-18 1366×768 pass
## FT-19 Disclaimer + amber chip checklist

Each of FT-01…FT-19 uses the AC already written in `docs/user-stories.md`. Do not rewrite AC in the tracker.

---

## Bugs that are out of scope if they appear

- “Add WhatsApp OTP”
- “Add Paystack”
- “Build iOS TestFlight for v1”
- “Dark mode”
- “Fourteen screens”
