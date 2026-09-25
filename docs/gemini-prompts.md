# Gemini contracts

Two calls. Temperature 0.2 extract, 0.5 narrative. Store `model_version` and raw text every time.

## Extract output schema (reject if invalid)

```json
{
  "monthly_income_est": 420000,
  "income_regularity": "stable",
  "inflow_months_observed": 3,
  "top_spend_categories": [
    { "category": "pos_retail", "monthly_avg": 85000, "share_of_outflow": 0.31 }
  ],
  "existing_loan_debits": [
    { "label": "Carbon", "monthly_avg": 15000 }
  ],
  "overdraft_or_reversals": false,
  "average_balance_proxy": 190000,
  "confidence": 0.82,
  "warnings": []
}
```

Enums:

- `income_regularity`: `stable` | `lumpy` | `seasonal` | `insufficient_history`
- Integers are naira with **no commas**
- Unknown → `null` or `[]`, never invented rows

## System prompt — extract

```
You extract facts from Nigerian bank statements or bank-alert SMS.
Return ONLY valid JSON matching the schema. No markdown.
Do not invent transactions. If a field is unknown, use null or [].
Amounts are integers in NGN with no commas or symbols.
income_regularity must be one of: stable, lumpy, seasonal, insufficient_history.
existing_loan_debits: repayment-like debits to known or obvious lenders
(Carbon, Palmpay, FairMoney, Branch, Renmoney, EasyCredit, loan, repayment).
If you are unsure a debit is a loan, omit it.
```

## User prompt — extract

```
role={{role}}
tenor_months={{tenor}}
source={{sms|statement}}

TEXT:
{{raw}}
```

## System prompt — narrative

```
You write a risk narrative for a human loan officer in Nigeria.
80 to 140 words. Professional English. Do not address the applicant.
Do not change or restate a different amount than AMOUNT_PREQUALIFIED.
Do not invent facts that are not in EXTRACT.
End with exactly one recommended next action.
```

## User prompt — narrative

```
AMOUNT_PREQUALIFIED={{amount}}
TIER={{tier}}
WARNINGS={{warnings_csv}}
EXTRACT={{extract_json}}
```

## Client-side validation

If JSON parse fails, retry once with “Return JSON only.”  
If still invalid: do not score; status `more_info`.

## Caching

`sha256(role + tenor + source + raw_text)` → cache. Seed hashes for fixture files in `fixtures/`.
