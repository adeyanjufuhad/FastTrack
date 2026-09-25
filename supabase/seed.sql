-- Dummy KYC + cached extracts.
-- Auth users cannot be created from SQL in all Supabase projects.
-- After this file:
--   1. Auth → Add user  applicant@fasttrack.demo  /  FastTrack!demo1
--   2. Auth → Add user  officer@fasttrack.demo    /  FastTrack!demo1
--   3. For the officer, set app_metadata to {"role":"officer"}
--      (Dashboard → user → raw app meta, or Admin API).
--   4. Copy the applicant uuid into the optional block at the bottom if you
--      want a pre-scored Adaeze without walking the UI.

insert into public.kyc_sandbox (bvn, nin, matched_name, result) values
  ('22222222222', '11111111111', 'ADA EZE OKAFOR', 'sandbox_pass'),
  ('33333333333', '11111111112', 'IBRAHIM MUSA', 'sandbox_pass'),
  ('44444444444', '11111111113', 'CHIOMA KALU', 'sandbox_pass'),
  ('55555555555', '11111111114', 'NORTHSHORE SIGNATORY', 'sandbox_pass'),
  ('00000000000', '00000000000', 'FAIL CASE', 'sandbox_fail')
on conflict (bvn) do update
  set nin = excluded.nin,
      matched_name = excluded.matched_name,
      result = excluded.result;

-- Cached extract: Adaeze
insert into public.extract_cache (input_hash, payload) values (
  'fixture:adaeze-sms',
  '{
    "monthly_income_est": 420000,
    "income_regularity": "stable",
    "inflow_months_observed": 3,
    "top_spend_categories": [
      {"category": "pos_retail", "monthly_avg": 85000, "share_of_outflow": 0.31},
      {"category": "airtime_data", "monthly_avg": 18000, "share_of_outflow": 0.07}
    ],
    "existing_loan_debits": [
      {"label": "Carbon", "monthly_avg": 15000}
    ],
    "overdraft_or_reversals": false,
    "average_balance_proxy": 190000,
    "confidence": 0.82,
    "warnings": ["external_lender_detected"]
  }'::jsonb
) on conflict (input_hash) do update set payload = excluded.payload;

insert into public.extract_cache (input_hash, payload) values (
  'fixture:ibrahim-sms',
  '{
    "monthly_income_est": 280000,
    "income_regularity": "lumpy",
    "inflow_months_observed": 3,
    "top_spend_categories": [
      {"category": "transfers_out", "monthly_avg": 90000, "share_of_outflow": 0.4}
    ],
    "existing_loan_debits": [
      {"label": "Palmpay", "monthly_avg": 40000},
      {"label": "unknown lender", "monthly_avg": 25000}
    ],
    "overdraft_or_reversals": true,
    "average_balance_proxy": 22000,
    "confidence": 0.6,
    "warnings": ["external_lender_detected", "irregular_income", "reversals_present"]
  }'::jsonb
) on conflict (input_hash) do update set payload = excluded.payload;

insert into public.extract_cache (input_hash, payload) values (
  'fixture:northshore-sms',
  '{
    "monthly_income_est": 1800000,
    "income_regularity": "lumpy",
    "inflow_months_observed": 3,
    "top_spend_categories": [
      {"category": "suppliers", "monthly_avg": 620000, "share_of_outflow": 0.45}
    ],
    "existing_loan_debits": [],
    "overdraft_or_reversals": false,
    "average_balance_proxy": 740000,
    "confidence": 0.7,
    "warnings": ["irregular_income"]
  }'::jsonb
) on conflict (input_hash) do update set payload = excluded.payload;
