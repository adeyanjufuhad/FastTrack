# FastTrack app (Flutter)

One codebase for the applicant app (Android, iOS, web) and the officer
dashboard (web, `/officer`). Thirteen screens — see `../docs/screens.md`.

## Run

```bash
flutter pub get

# Offline demo mode — no backend, seed personas, sandbox KYC
flutter run -d chrome

# Against Supabase (anon / publishable key only — never the service role)
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Without `SUPABASE_URL` the app uses `DemoRepository`: it runs fully offline
with Adaeze, Ibrahim and Northshore already in the officer queue. Demo state
is saved on the device (browser localStorage on web), so a refresh mid-pitch
loses nothing. **Reset demo** (under the splash buttons, or ↺ on the officer
queue) restores the three seed personas. Passwords in the demo store are
SHA-256 hashes; uploads over 600 KB keep metadata only.

| Demo login | Password |
|---|---|
| `applicant@fasttrack.demo` (or register any email) | `FastTrack!demo1` |
| `officer@fasttrack.demo` → `/officer/login` | `FastTrack!demo1` |

Dummy identities for A5 (BVN / NIN): `22222222222` / `11111111111` (Adaeze,
pass), `33333333333` (Ibrahim), `55555555555` (Northshore signatory),
`00000000000` (always fails), anything else → mismatch. A5 and A6 have
one-tap "sample" chips for these.

## Test

```bash
flutter analyze
flutter test
```

- `score_engine_test.dart` — locks the Adaeze / Ibrahim / Northshore vectors and the rules.
- `demo_repository_test.dart` — demo state survives a reload; reset; hashed passwords.
- `layout_test.dart` — every screen at 360×740, 768×1024 and 1366×768 with no
  overflow (cut-off content fails the test), plus A9 amount === O2 amount.

## Build

```bash
flutter build web --release            # add --base-href /app/ to host beside the website
flutter build apk --release            # Android
```

## Layout

```
lib/
├── main.dart, app.dart        # bootstrap + go_router with role guards
├── config/env.dart            # --dart-define values, LIVE_KYC guard
├── scoring/                   # PURE DART — rules engine, config, narrative template
├── data/                      # repository interface, demo + Supabase implementations
├── models/                    # enums mirror Postgres; records
├── state/                     # AppState (ChangeNotifier) + AppScope
├── theme/                     # blue & white tokens, fluid() sizing
├── widgets/                   # logo, chips (sandbox/tier/status), frame, signature pad
└── screens/applicant (A1–A10), screens/officer (O1–O3)
```

Scoring constants live in one file: `lib/scoring/score_config.dart`. The Edge
Function mirror is `../supabase/functions/_shared/score.ts`; both are tested
against the same vectors.
