-- Seed personas for the officer queue: Adaeze, Ibrahim and Northshore appear
-- in O1 with the exact amounts the rules engine produces for their cached
-- extracts (see neon/functions/_shared/score.test.ts). Run after
-- 0001_reference.sql. Idempotent.
--
-- Personas are applicant rows only. They have no neon_auth user, so nobody
-- can sign in as them.

insert into public.applicants (id, role, legal_name, email, bvn_masked, nin_masked, kyc_result)
values
  ('a0000000-0000-4000-8000-00000000ada1', 'individual', 'Adaeze Okafor',          'adaeze.persona@fasttrack.demo',     '*******2222', '*******1111', 'sandbox_pass'),
  ('a0000000-0000-4000-8000-00000000b1b2', 'individual', 'Ibrahim Musa',           'ibrahim.persona@fasttrack.demo',    '*******3333', '*******1112', 'sandbox_pass'),
  ('a0000000-0000-4000-8000-00000000c0c3', 'corporate',  'Northshore Trading Ltd', 'northshore.persona@fasttrack.demo', '*******5555', '*******1114', 'sandbox_pass')
on conflict (id) do update
  set role = excluded.role, legal_name = excluded.legal_name, email = excluded.email,
      bvn_masked = excluded.bvn_masked, nin_masked = excluded.nin_masked,
      kyc_result = excluded.kyc_result;

update public.applicants set occupation = 'Operations manager'
  where id = 'a0000000-0000-4000-8000-00000000ada1';
update public.applicants set occupation = 'Trader'
  where id = 'a0000000-0000-4000-8000-00000000b1b2';
update public.applicants
  set rc_number = 'RC 1234567', nature_of_business = 'Food distribution',
      signatory_1_name = 'Tunde Bakare', signatory_2_name = 'Ngozi Eze'
  where id = 'a0000000-0000-4000-8000-00000000c0c3';

insert into public.applications (id, applicant_id, product, tenor_months, purpose, status, created_at)
values
  ('f0000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000ada1', 'personal',  12, 'Rent renewal',    'scored', now() - interval '3 hours'),
  ('f0000000-0000-4000-8000-0000000000b2', 'a0000000-0000-4000-8000-00000000b1b2', 'personal',  12, 'Stock purchase',  'scored', now() - interval '5 hours'),
  ('f0000000-0000-4000-8000-0000000000c3', 'a0000000-0000-4000-8000-00000000c0c3', 'corporate', 12, 'Working capital', 'scored', now() - interval '26 hours')
on conflict (id) do nothing;

delete from public.eligibility_results
where application_id in (
  'f0000000-0000-4000-8000-0000000000a1',
  'f0000000-0000-4000-8000-0000000000b2',
  'f0000000-0000-4000-8000-0000000000c3'
);

insert into public.eligibility_results
  (application_id, monthly_income_est, income_regularity, spend_categories, existing_debts,
   extract, tier, amount_prequalified, warnings, narrative, model_version)
select
  v.app_id::uuid,
  (c.payload ->> 'monthly_income_est')::int,
  (c.payload ->> 'income_regularity')::public.income_regularity,
  c.payload -> 'top_spend_categories',
  c.payload -> 'existing_loan_debits',
  c.payload,
  v.tier::public.risk_tier,
  v.amount,
  v.warnings,
  v.narrative,
  'fixture-cache'
from (values
  ('f0000000-0000-4000-8000-0000000000a1', 'fixture:adaeze-sms', 'medium', 1240000,
   array['external_lender_detected'],
   'The applicant''s income is regular at about NGN 420,000 a month across 3 observed months. Repayment debits to other lenders were detected: Carbon (NGN 15,000 a month). The largest spend category is pos retail at about NGN 85,000 a month. No overdraft or reversal pattern was observed. The rules engine pre-qualifies NGN 1,240,000 at medium risk, with extraction confidence of 82%. Recommended next action: confirm the external repayment and a landlord or employer reference, then move to offer letter.'),
  ('f0000000-0000-4000-8000-0000000000b2', 'fixture:ibrahim-sms', 'high', 410000,
   array['external_lender_detected', 'irregular_income', 'reversals_present'],
   'The applicant''s inflows are lumpy, averaging about NGN 280,000 a month across 3 observed months. Repayment debits to other lenders were detected: Palmpay (NGN 40,000 a month), unknown lender (NGN 25,000 a month). The largest spend category is transfers out at about NGN 90,000 a month. The statement shows reversals, which reduce confidence in cash flow. The rules engine pre-qualifies NGN 410,000 at high risk, with extraction confidence of 60%. Recommended next action: request a six-month statement before any offer.'),
  ('f0000000-0000-4000-8000-0000000000c3', 'fixture:northshore-sms', 'medium', 3780000,
   array['irregular_income'],
   'The business''s inflows are lumpy, averaging about NGN 1,800,000 a month across 3 observed months. No repayments to other lenders were detected. The largest spend category is suppliers at about NGN 620,000 a month. No overdraft or reversal pattern was observed. The rules engine pre-qualifies NGN 3,780,000 at medium risk, with extraction confidence of 70%. Recommended next action: confirm one income reference, then move to offer letter.')
) as v(app_id, fixture, tier, amount, warnings, narrative)
join public.extract_cache c on c.input_hash = v.fixture;
