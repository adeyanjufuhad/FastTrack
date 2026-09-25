# Scoring engine

Two stages. Stage A is deterministic. Stage B writes prose. Stage B **must not** write `amount_prequalified` or `tier`.

Implement Stage A as a pure function so it can be unit-tested without Flutter or Gemini.

```dart
ScoreResult score(Extract extract, KycResult kyc, ScoreConfig cfg)
```

## Config defaults (`score_config`)

```
income_multiplier_annual_factor = 3     // base = monthly_income * 3 * (tenor_months/12)
cap_as_months_of_income        = 6      // cap facility at 6 * monthly_income
lumpy_haircut                  = 0.70
insufficient_haircut           = 0.40
reversal_haircut               = 0.75
low_confidence_haircut         = 0.80
debt_income_deduction          = 0.30    // 30% of detected monthly lender debits
stacking_lender_threshold      = 3
low_confidence_cutoff          = 0.45
holdings_sleeve_rate           = 0.30    // optional, off by default
holdings_sleeve_enabled        = false
```

## Stage A

1. If `kyc_result` in (`mismatch`, `sandbox_fail`) → no amount, status `more_info`, stop.
2. `usable_income = monthly_income_est - debt_income_deduction * sum(existing_loan_debits.monthly)`
3. `base = usable_income * income_multiplier_annual_factor * (tenor_months / 12)`
4. Cap `base` at `cap_as_months_of_income * monthly_income_est`
5. Apply regularity haircut (stable=1.0, lumpy/seasonal=0.70, insufficient=0.40)
6. If `overdraft_or_reversals` apply 0.75
7. If `confidence < 0.45` apply 0.80 and floor tier Medium
8. Round down to nearest NGN 10,000
9. If amount < NGN 50,000 → treat as manual review, tier High, amount may still show
10. Tier:
    - start Low if regularity=stable and no flags
    - floor Medium if lumpy/seasonal or reversals or low confidence
    - floor High if insufficient_history OR lender count ≥ 3
11. Optional holdings sleeve (Chioma only):  
    `amount += min(holdings * 0.30, base)` and allow Low if salary clean

## Worked examples (tests must match)

### Adaeze

- income 420_000, stable, 1 lender debit 15_000/mo, confidence 0.82, tenor 12, KYC pass  
- usable = 420000 - 0.3*15000 = 415500  
- base = 415500 * 3 * 1 = 1_246_500 → cap 6*420000=2_520_000 → no cap  
- no extra haircuts  
- amount = **1_240_000**  
- tier **Medium** (one external lender present — product choice: treat any detected lender as Medium).  
  Implement: `if existing_loan_debits.isNotEmpty floor Medium`.

### Ibrahim

- income 280_000 lumpy, 2 lenders 40_000+25_000, reversal true, confidence 0.6, tenor 12  
- usable = 280000 - 0.3*65000 = 260500  
- base = 260500 * 3 = 781_500  
- *0.70 lumpy = 547_050  
- *0.75 reversal = 410_287 → **410_000**  
- tier **High** if you also count lumpy+reversal+two lenders as High.  
  Implement: flags ≥ 2 of {lumpy/seasonal, reversal, lenders≥2} → High.

Lock the test vectors in `fixtures/expected_scores.json` after the first implementation so product cannot silently drift.

## Stage B narrative brief

Inputs: extract JSON, amount, tier, warnings[].  
Output: 80–140 words, officer second person (“The applicant’s salary…”).  
Forbidden: new numbers, medical speculation, changing tier.  
Last sentence: one next action (approve to offer letter / request 6-month statement / decline with a speakable reason).

## Warnings the rules layer should attach

- `external_lender_detected`
- `loan_stacking_suspected` (lenders ≥ 3)
- `irregular_income`
- `reversals_present`
- `thin_history`
- `low_model_confidence`
- `kyc_mismatch`
