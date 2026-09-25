-- Seed personas for the officer queue (definition of done: Adaeze, Ibrahim
-- and Northshore appear in O1 after seeding). Run AFTER the migrations and
-- seed.sql, in the Supabase SQL editor (as postgres).
--
-- Personas are dummy auth users that cannot sign in (no identity rows,
-- random passwords). Amounts / tiers / narratives are exactly what the rules
-- engine produces for the cached fixture extracts — see app/test/score_engine_test.dart.

do $$
declare
  p record;
begin
  for p in
    select * from (values
      ('a0000000-0000-4000-8000-00000000ada1'::uuid, 'adaeze.persona@fasttrack.demo',     'individual'::public.applicant_role, 'Adaeze Okafor',          '*******2222', '*******1111'),
      ('a0000000-0000-4000-8000-00000000b1b2'::uuid, 'ibrahim.persona@fasttrack.demo',    'individual'::public.applicant_role, 'Ibrahim Musa',           '*******3333', '*******1112'),
      ('a0000000-0000-4000-8000-00000000c0c3'::uuid, 'northshore.persona@fasttrack.demo', 'corporate'::public.applicant_role,  'Northshore Trading Ltd', '*******5555', '*******1114')
    ) as t(id, email, role, name, bvn, nin)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', p.id, 'authenticated', 'authenticated', p.email,
      crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"],"role":"applicant"}', '{"persona":true}', now(), now(),
      '', '', '', ''
    ) on conflict (id) do nothing;

    insert into public.applicants (id, role, legal_name, email, bvn_masked, nin_masked, kyc_result)
    values (p.id, p.role, p.name, p.email, p.bvn, p.nin, 'sandbox_pass')
    on conflict (id) do update
      set role = excluded.role, legal_name = excluded.legal_name,
          bvn_masked = excluded.bvn_masked, nin_masked = excluded.nin_masked,
          kyc_result = excluded.kyc_result;
  end loop;
end $$;

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

-- Optional helper: give the demo officer their role claim (after creating
-- officer@fasttrack.demo in Auth → Users).
update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"officer"}'::jsonb
  where email = 'officer@fasttrack.demo';
