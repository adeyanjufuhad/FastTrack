-- Run after schema.sql

alter table public.applicants enable row level security;
alter table public.documents enable row level security;
alter table public.applications enable row level security;
alter table public.eligibility_results enable row level security;
alter table public.officer_notes enable row level security;
alter table public.kyc_logs enable row level security;
alter table public.kyc_sandbox enable row level security;
alter table public.extract_cache enable row level security;

-- Applicants
drop policy if exists applicants_own_select on public.applicants;
create policy applicants_own_select on public.applicants
  for select using (id = auth.uid() or public.is_officer());

drop policy if exists applicants_own_update on public.applicants;
create policy applicants_own_update on public.applicants
  for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists applicants_own_insert on public.applicants;
create policy applicants_own_insert on public.applicants
  for insert with check (id = auth.uid());

-- Documents
drop policy if exists documents_own on public.documents;
create policy documents_own on public.documents
  for all using (applicant_id = auth.uid() or public.is_officer())
  with check (applicant_id = auth.uid() or public.is_officer());

-- Applications
drop policy if exists applications_own_select on public.applications;
create policy applications_own_select on public.applications
  for select using (applicant_id = auth.uid() or public.is_officer());

drop policy if exists applications_own_write on public.applications;
create policy applications_own_write on public.applications
  for insert with check (applicant_id = auth.uid());

drop policy if exists applications_own_update on public.applications;
create policy applications_own_update on public.applications
  for update using (applicant_id = auth.uid() or public.is_officer())
  with check (applicant_id = auth.uid() or public.is_officer());

-- Eligibility
drop policy if exists eligibility_select on public.eligibility_results;
create policy eligibility_select on public.eligibility_results
  for select using (
    public.is_officer()
    or exists (
      select 1 from public.applications a
      where a.id = application_id and a.applicant_id = auth.uid()
    )
  );

drop policy if exists eligibility_insert_service on public.eligibility_results;
-- Writes come from Edge Functions using the user JWT after scoring,
-- or the service role. Allow insert if the caller owns the application.
create policy eligibility_insert_service on public.eligibility_results
  for insert with check (
    public.is_officer()
    or exists (
      select 1 from public.applications a
      where a.id = application_id and a.applicant_id = auth.uid()
    )
  );

-- Notes
drop policy if exists notes_officer on public.officer_notes;
create policy notes_officer on public.officer_notes
  for all using (public.is_officer())
  with check (public.is_officer());

-- KYC logs: own or officer
drop policy if exists kyc_logs_own on public.kyc_logs;
create policy kyc_logs_own on public.kyc_logs
  for all using (applicant_id = auth.uid() or public.is_officer())
  with check (applicant_id = auth.uid() or public.is_officer());

-- Sandbox table readable by authenticated users (dummy data only)
drop policy if exists kyc_sandbox_read on public.kyc_sandbox;
create policy kyc_sandbox_read on public.kyc_sandbox
  for select using (auth.role() = 'authenticated');

-- Extract cache: readable/writable by authenticated (demo convenience)
drop policy if exists extract_cache_auth on public.extract_cache;
create policy extract_cache_auth on public.extract_cache
  for all using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- Storage: create bucket in dashboard named "documents", private.
-- Policy example (run in storage if you use SQL policies):
-- allow authenticated users to upload under their uid prefix.
