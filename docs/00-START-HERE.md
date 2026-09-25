# Start here

## One-sentence brief

Replace PDF-and-email account opening and calculator-only loan desks with a five-minute digital flow that lands a **scored file** on an officer’s desk.

## Team shape this pack assumes

| Seat | Owns |
|---|---|
| Product / founder | Scope lock, disclaimer copy, demo script, seed persona review |
| Flutter engineer | Applicant + officer UI, signature canvas, routing, state |
| Backend engineer | Supabase schema, RLS, Storage, Edge Functions, scoring module |
| (Optional) designer | Two Figma frames only: applicant happy path, officer file |

One strong full-stack engineer can do both Flutter and backend. Do not wait for a designer to start Phase 1.

## Decisions already made

Do not reopen these in standup.

- Product name: **FastTrack**
- Client: Flutter (one codebase, web is the pitch surface)
- Backend: Supabase
- AI: Gemini, structured extract first, narrative second
- Amounts come from **rules**, never from the model
- KYC is **sandbox** with an amber chip on A5 and A9
- Officer is a Flutter web route, not a separate React app
- Currency display: `NGN 1,800,000` (no naira glyph in places fonts break)
- Visual tone: navy / ivory / gold. Private-client pack, not neon lender

## Day-1 checklist

- [ ] Repo created, this pack committed
- [ ] Flutter app runs on Chrome (`flutter run -d chrome`)
- [ ] Supabase project exists in any region
- [ ] `schema.sql` + `rls.sql` + `seed.sql` applied
- [ ] Auth users `applicant@fasttrack.demo` and `officer@fasttrack.demo` can sign in
- [ ] Private Storage bucket `documents` exists
- [ ] Edge Function secret `GEMINI_API_KEY` set (or a stub function returns fixtures)
- [ ] Tickets imported
- [ ] Demo disclaimer text locked (see PRD)

## Working rules

1. Cache Gemini outputs by hash of input text. Rehearsals will burn quota otherwise.
2. Scoring constants live in **one file**. Product will change the multiplier during practice.
3. Applicant result and officer file must show the **same amount**.
4. If a fourteenth screen appears, it is scope creep. Challenge it.
5. Compile-time flag `LIVE_KYC=false`. Live provider URLs must not compile into the demo build.
6. No real customer PII in the repo. Seed data only.

## Definition of “we can demo this on HDMI”

See `definition-of-done.md`. Short version: Adaeze walks A2→A9 in under five minutes, officer opens the file, numbers match, amber chip is visible without pointing at it.
