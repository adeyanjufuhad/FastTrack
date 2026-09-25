-- Row Level Security, storage bucket and integrity guards.
--
-- Hardened from docs/handoff-db/rls.sql. The handoff version let an applicant
-- (a) write their own kyc_result, (b) insert their own eligibility row and
-- (c) set their application to "approved" through the public API. Here those
-- writes are reserved for Edge Functions using the service role, which
-- bypasses RLS. Clients only ever hold the anon key.

alter table public.applicants enable row level security;
alter table public.documents enable row level security;
alter table public.applications enable row level security;
alter table public.eligibility_results enable row level security;
alter table public.officer_notes enable row level security;
alter table public.kyc_logs enable row level security;
alter table public.kyc_sandbox enable row level security;
alter table public.extract_cache enable row level security;

-- ── Applicants ───────────────────────────────────────────────────────────
drop policy if exists applicants_own_select on public.applicants;
create policy applicants_own_select on public.applicants
  for select using (id = auth.uid() or public.is_officer());

drop policy if exists applicants_own_insert on public.applicants;
create policy applicants_own_insert on public.applicants
  for insert with check (id = auth.uid());

drop policy if exists applicants_own_update on public.applicants;
create policy applicants_own_update on public.applicants
  for update using (id = auth.uid()) with check (id = auth.uid());

-- KYC columns are written only by the kyc-check Edge Function.
create or replace function public.guard_applicant_kyc()
returns trigger
language plpgsql
as $$
begin
  -- Only API callers are restricted; service_role, postgres and seeds pass.
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.kyc_result := null;
      new.bvn_masked := null;
      new.nin_masked := null;
      new.holdings_ngn := null;
    elsif new.kyc_result is distinct from old.kyc_result
       or new.bvn_masked is distinct from old.bvn_masked
       or new.nin_masked is distinct from old.nin_masked
       or new.holdings_ngn is distinct from old.holdings_ngn then
      raise exception 'kyc and holdings fields are server-managed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists applicants_guard_kyc on public.applicants;
create trigger applicants_guard_kyc
  before insert or update on public.applicants
  for each row execute function public.guard_applicant_kyc();

-- ── Documents ────────────────────────────────────────────────────────────
drop policy if exists documents_own on public.documents;
create policy documents_own on public.documents
  for all using (applicant_id = auth.uid() or public.is_officer())
  with check (applicant_id = auth.uid() or public.is_officer());

-- ── Applications ─────────────────────────────────────────────────────────
drop policy if exists applications_own_select on public.applications;
create policy applications_own_select on public.applications
  for select using (applicant_id = auth.uid() or public.is_officer());

drop policy if exists applications_own_write on public.applications;
create policy applications_own_write on public.applications
  for insert with check (applicant_id = auth.uid() and status in ('draft', 'submitted'));

-- Applicants may edit while drafting, submitting or answering a more-info
-- request, and may only move the file back to draft/submitted. Scoring and
-- decisions happen server-side.
drop policy if exists applications_own_update on public.applications;
create policy applications_own_update on public.applications
  for update
  using (
    public.is_officer()
    or (applicant_id = auth.uid() and status in ('draft', 'submitted', 'more_info'))
  )
  with check (
    public.is_officer()
    or (applicant_id = auth.uid() and status in ('draft', 'submitted'))
  );

-- ── Eligibility (read-only for clients) ──────────────────────────────────
drop policy if exists eligibility_insert_service on public.eligibility_results;
drop policy if exists eligibility_select on public.eligibility_results;
create policy eligibility_select on public.eligibility_results
  for select using (
    public.is_officer()
    or exists (
      select 1 from public.applications a
      where a.id = application_id and a.applicant_id = auth.uid()
    )
  );

-- ── Officer notes ────────────────────────────────────────────────────────
drop policy if exists notes_officer on public.officer_notes;
create policy notes_officer on public.officer_notes
  for all using (public.is_officer())
  with check (public.is_officer() and officer_id = auth.uid());

-- ── KYC logs: read own or officer; written by kyc-check only ─────────────
drop policy if exists kyc_logs_own on public.kyc_logs;
create policy kyc_logs_read on public.kyc_logs
  for select using (applicant_id = auth.uid() or public.is_officer());

-- kyc_sandbox and extract_cache: no client policies → service role only.
drop policy if exists kyc_sandbox_read on public.kyc_sandbox;
drop policy if exists extract_cache_auth on public.extract_cache;

-- ── Storage: private "documents" bucket, files under "<uid>/…" ───────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documents', 'documents', false, 8388608,
        array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists documents_objects_insert on storage.objects;
create policy documents_objects_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists documents_objects_update on storage.objects;
create policy documents_objects_update on storage.objects
  for update to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists documents_objects_select on storage.objects;
create policy documents_objects_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_officer())
  );
