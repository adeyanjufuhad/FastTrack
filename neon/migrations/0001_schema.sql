-- FastTrack v1 schema on Neon. Mirrors supabase/migrations/*_schema.sql with
-- three differences:
--   * Users live in neon_auth."user" (Neon Auth / Better Auth), so there are
--     no foreign keys into auth.users.
--   * Officers are rows in public.staff, not a JWT app_metadata claim
--     (Neon Auth JWTs carry no custom claims).
--   * Access control runs in the `fasttrack` Neon Function, not RLS policies.
--     RLS is enabled with no policies, so any role other than the table owner
--     (which the function connects as) sees nothing. The Data API stays off.
--
-- Idempotent: safe to re-run with `npm run migrate`.

create extension if not exists "pgcrypto";

do $$ begin
  create type public.applicant_role as enum ('individual', 'corporate');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.kyc_result as enum ('sandbox_pass', 'sandbox_fail', 'mismatch');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.application_status as enum (
    'draft', 'submitted', 'scored', 'in_review', 'more_info', 'approved', 'declined'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.risk_tier as enum ('low', 'medium', 'high');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.doc_kind as enum ('id', 'statement', 'cac', 'signature', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.income_regularity as enum (
    'stable', 'lumpy', 'seasonal', 'insufficient_history'
  );
exception when duplicate_object then null; end $$;

-- Officers. user_id is neon_auth."user".id; add rows with seeds/0003_staff.sql.
create table if not exists public.staff (
  user_id uuid primary key,
  email text,
  role text not null default 'officer' check (role = 'officer'),
  created_at timestamptz not null default now()
);

-- id = neon_auth."user".id for real users; fixed uuids for seed personas.
create table if not exists public.applicants (
  id uuid primary key,
  role public.applicant_role not null default 'individual',
  legal_name text,
  email text,
  phone text,
  dob date,
  address text,
  occupation text,
  next_of_kin_name text,
  next_of_kin_phone text,
  rc_number text,
  nature_of_business text,
  registered_address text,
  signatory_1_name text,
  signatory_2_name text,
  bvn_masked text,
  nin_masked text,
  kyc_result public.kyc_result,
  holdings_ngn integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- storage_key is the object key inside the private "documents" bucket.
create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.applicants (id) on delete cascade,
  kind public.doc_kind not null,
  storage_key text not null,
  file_name text,
  mime text,
  bytes integer,
  uploaded_at timestamptz not null default now()
);

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.applicants (id) on delete cascade,
  product text not null default 'personal',
  requested_amount integer,
  tenor_months integer not null default 12,
  purpose text,
  sms_text text,
  status public.application_status not null default 'draft',
  officer_id uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.eligibility_results (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  monthly_income_est integer,
  income_regularity public.income_regularity,
  spend_categories jsonb not null default '[]'::jsonb,
  existing_debts jsonb not null default '[]'::jsonb,
  extract jsonb,
  score numeric,
  tier public.risk_tier,
  amount_prequalified integer,
  warnings text[] not null default '{}',
  narrative text,
  model_version text,
  raw_model_output text,
  created_at timestamptz not null default now()
);

create table if not exists public.officer_notes (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  officer_id uuid not null,
  officer_email text,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.kyc_logs (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid references public.applicants (id) on delete set null,
  bvn_last4 text,
  nin_last4 text,
  result public.kyc_result,
  mode text not null default 'sandbox',
  created_at timestamptz not null default now()
);

create table if not exists public.kyc_sandbox (
  bvn text primary key,
  nin text unique,
  matched_name text not null,
  result public.kyc_result not null
);

create table if not exists public.extract_cache (
  input_hash text primary key,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists applications_status_idx on public.applications (status, created_at desc);
create index if not exists applications_applicant_idx on public.applications (applicant_id);
create index if not exists documents_applicant_idx on public.documents (applicant_id, kind, uploaded_at desc);
create index if not exists eligibility_app_idx on public.eligibility_results (application_id, created_at desc);
create index if not exists notes_app_idx on public.officer_notes (application_id, created_at);

-- Deny-by-default for every role except the owner the function connects as.
alter table public.staff enable row level security;
alter table public.applicants enable row level security;
alter table public.documents enable row level security;
alter table public.applications enable row level security;
alter table public.eligibility_results enable row level security;
alter table public.officer_notes enable row level security;
alter table public.kyc_logs enable row level security;
alter table public.kyc_sandbox enable row level security;
alter table public.extract_cache enable row level security;
