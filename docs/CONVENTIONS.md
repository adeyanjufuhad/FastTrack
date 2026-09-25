# Engineering conventions

- Dart for Flutter and for the scoring function. Edge Functions may be TypeScript.
- Amounts are integers (kobo-less naira). Format only in the UI: `NGN 1,240,000`.
- Enums in Postgres are the source of truth; mirror them in Dart.
- One PR per ticket ID (`FT-11`).
- Do not merge client code that prints the service role or Gemini key.
- Fixture keys start with `fixture:`.
- If product asks for a new screen, point at `docs/screens.md` and ask which one it replaces.
