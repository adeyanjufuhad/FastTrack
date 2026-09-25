# Setup

## 1. Flutter

```bash
flutter create fasttrack --org com.fasttrack --platforms=android,ios,web
cd fasttrack
flutter pub add supabase_flutter http crypto
```

Suggested packages (stay on maintained versions):

- `supabase_flutter` — auth, db, storage
- `go_router` — A1–O3 routes
- `flutter_signature_pad` or a 40-line CustomPainter
- `file_picker`
- `google_generative_ai` **only inside Edge Functions**, not the app

## 2. Supabase

1. New project, any region.
2. SQL editor: `schema.sql` → `rls.sql` → `seed.sql`.
3. Auth → add `applicant@fasttrack.demo` and `officer@fasttrack.demo`, password `FastTrack!demo1`.
4. Officer user → App metadata `{"role":"officer"}`.
5. Storage → new bucket `documents`, private.
6. Edge Functions: `kyc-check`, `process-application`.
7. Secrets: `GEMINI_API_KEY`.

Until Gemini is wired, `process-application` may return `extract_cache` rows when `fixture_key` is set. Ship that stub on day 2.

## 3. Role claim

`is_officer()` reads `auth.jwt() -> app_metadata -> role`.  
Set metadata with the Admin API or dashboard. A custom `user_roles` table is an acceptable substitute if metadata is painful — update `is_officer()` accordingly.

## 4. Flutter env

Load `SUPABASE_URL` and `SUPABASE_ANON_KEY` via `--dart-define` or a gitignored `env.dart`. Never the service role.

## 5. Host the demo

```bash
flutter build web
# deploy build/web to Firebase Hosting or Vercel
```

Pitch surface is web. Do not block on Play Console.
