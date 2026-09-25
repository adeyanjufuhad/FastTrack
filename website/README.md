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

```bash
cd app
flutter build web --release --base-href /app/
cp -r build/web ../website/app      # website/app/ is gitignored
```

Deploy the `website/` folder to any static host (Vercel, Netlify, Firebase
Hosting, GitHub Pages). The applicant flow is at `/app/` and the officer
dashboard at `/app/#/officer/login` (Flutter web uses hash URLs by default,
so no server rewrites are needed).
