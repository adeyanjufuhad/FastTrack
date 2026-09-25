# KYC sandbox

Live NIBSS-backed BVN/NIN is paid everywhere in Nigeria. v1 is a local table.

## UI copy (do not rewrite)

Amber chip on A5 and A9:

> Demo mode — sandbox verification. Production requires a licensed KYC provider.

Spoken line for the pitch (also in O2 footer):

> What you just watched used sandbox identity data. Going live means a verification-provider contract.

## Interface (swap later)

```ts
type KycRequest = { bvn?: string; nin?: string; legal_name: string };
type KycResponse = {
  result: "sandbox_pass" | "sandbox_fail" | "mismatch";
  matched_name?: string;
  mode: "sandbox";
};
```

`LIVE_KYC` must be false in the demo build. Do not import provider SDKs in v1.

## Dummy table (also in `db/seed.sql`)

| BVN | NIN | Name | Result |
|---|---|---|---|
| 22222222222 | 11111111111 | ADA EZE OKAFOR | sandbox_pass (Adaeze) |
| 33333333333 | 11111111112 | IBRAHIM MUSA | sandbox_pass |
| 44444444444 | 11111111113 | CHIOMA KALU | sandbox_pass |
| 55555555555 | 11111111114 | NORTHSHORE SIGNATORY | sandbox_pass |
| 00000000000 | 00000000000 | — | sandbox_fail |
| any other 11 digits | any | — | mismatch unless name ignored |

Matching rule for demo: BVN **or** NIN hit on the dummy table → pass, ignore exact name match so typists in a pitch room do not fail KYC.  
`00000000000` always fails.  
Unknown numbers → `mismatch` (good for FT-06).

Log every check to `kyc_logs` (see schema). Never log a live lookup from the demo APK.
