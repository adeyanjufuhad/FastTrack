# Definition of done

## A story is done when

- AC on the ticket are ticked
- Works on Flutter web at 1366×768
- No new screen beyond the inventory
- No service-role key in client code
- Seed data still scores the same after the change

## The MVP is done when

Verified 2026-09-25 on the hosted build (GitHub Pages + Neon) unless noted.

- [x] Hosted Flutter web link works without a local machine: https://fastrack.name.ng/app/ (live) and `/demo/` (offline)
- [x] Adaeze, Ibrahim, Northshore appear in the officer queue after seed: NGN 1,240,000 · 410,000 · 3,780,000
- [x] Adaeze walk A2→A9 < 5 minutes: about 80 s scripted in a browser
- [x] A9 amount === O2 amount: both NGN 1,240,000
- [x] Amber sandbox chip visible on A5 and A9
- [x] Disclaimer visible on A9 and O2
- [x] Officer can approve / more_info / decline; A10 updates: approve walked in the browser, A10 showed Approved; decline via the API
- [x] Gemini cache protects the three personas from quota: they score from the extract cache (`model_version = fixture-cache`)
- [x] README in the app repo explains `.env` and dummy BVNs
- [x] 90-second screen recording exists in case the room has no network: [`assets/fasttrack-demo.mp4`](assets/fasttrack-demo.mp4)

Beyond the MVP: Gemini reads non-persona SMS live (a new file scored in
about 3 s on 2026-09-25). Still open: the APK has not been tried on a
physical phone.

## Explicitly not done (do not claim)

- Live identity verification
- Production NDPR certification
- An offer of credit
- App Store / Play listing
