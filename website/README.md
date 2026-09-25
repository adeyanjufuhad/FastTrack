# FastTrack website

Static download / marketing site — plain HTML, CSS and a little JS. No build step.

```
website/
├── index.html      # page
├── styles.css      # blue & white tokens, fluid type/spacing via clamp()
├── main.js         # download links, mobile menu, reveal-on-scroll
└── assets/         # logo mark (SVG), brand illustration, icons, share image
```

## Preview locally

```bash
python -m http.server 8765 --directory website
```

Then open http://localhost:8765.

## Download buttons

Links live in one place, `DOWNLOADS` at the top of `main.js`:

| Button | Default target |
|---|---|
| Android (APK) | `https://github.com/adeyanjufuhad/FastTrack/releases/latest/download/fasttrack.apk` |
| Web app | `app/` — the Flutter web build hosted beside this site |
| iPhone | "Coming soon" (no iOS store build in v1) |

To make the Android button live, build the APK and attach it to a GitHub
Release with the file name `fasttrack.apk`:

```bash
cd app
flutter build apk --release
# upload build/app/outputs/flutter-apk/app-release.apk to a Release as fasttrack.apk
```

## Host the site and the web app together

`.github/workflows/publish.yml` does this on every push to `main` that touches
`app/` or `website/`: it builds the Flutter web app against the Neon backend
(`NEON_API_URL`), puts it under `app/` beside this site and deploys both to
GitHub Pages at **https://adeyanjufuhad.github.io/FastTrack/**. The applicant
flow is at `/FastTrack/app/`, and the officer dashboard at
`/FastTrack/app/#/officer/login`. Flutter web uses hash URLs, so no server
rewrites are needed.

One-time setup: **Settings → Pages → Build and deployment → Source: GitHub
Actions**.

To publish a new APK too, run the workflow by hand (**Actions → Publish → Run
workflow**) with a release tag such as `v0.2.0`. It builds `fasttrack.apk` against
Neon and attaches it to that release, which becomes the latest, so the
Android button above picks it up.

To host elsewhere, build it yourself:

```bash
cd app
flutter build web --release --base-href /app/ \
  --dart-define=NEON_API_URL=https://br-little-hat-b492f9op-fasttrack.compute.c-6.us-east-2.aws.neon.tech
cp -r build/web ../website/app      # website/app/ is gitignored
```

and deploy the `website/` folder to any static host.
