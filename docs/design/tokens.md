# Design tokens

**Blue and white. Fintech, not payday.** Colours are taken from the FastTrack
mark: the upper bar is `blue`, the lower bar and the wordmark are `navy`.

> Change from the original handoff pack: the navy / ivory / gold palette was
> replaced by blue and white at product's request (September 2026). Functional
> colours (amber sandbox chip, approve green, decline red) are unchanged.

| Token | Value | Use |
|---|---|---|
| navy | `#0A2463` | wordmark, headings, primary buttons |
| navySoft | `#14337F` | officer chrome, hover, "Medium" tier |
| blue | `#2B76E5` | logo accent, links, focus, progress, "Low" tier |
| blueDeep | `#1D5BC6` | eyebrow labels, text links |
| sky | `#EAF2FE` | tinted cards, icon wells, "High" tier |
| mist | `#F5F8FD` | page wash behind white cards |
| white | `#FFFFFF` | surfaces |
| line | `#DCE5F2` | borders, dividers |
| slate | `#475569` | body text |
| amber | `#B45309` on `#FEF3C7` | **sandbox chip only** |
| ok | `#15803D` on `#DCFCE7` | approve / pass |
| danger | `#B91C1C` on `#FEE2E2` | decline / mismatch |

Source of truth in code: `app/lib/theme/tokens.dart` and the `:root` block in
`website/styles.css`.

## Type

Plus Jakarta Sans (Google Fonts) throughout — geometric, close to the
wordmark. Headings 700–800 with slight negative tracking. No rounded
"lender" fonts.

## Layout

Fluid by default. The app interpolates padding and heading sizes between a
360 px and a 1280 px viewport (`fluid()` in `tokens.dart`); the website uses
CSS `clamp()` for the same scale. A9 and O2 must look right at 1366×768.

## Motion

Short (200 ms). A8 ticks, subtle reveal on the website. No looping marketing
animation inside the app. `prefers-reduced-motion` disables motion on the site.

## Copy voice

Short sentences. No slang on officer screens. No "Congrats you are approved!!".
