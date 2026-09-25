# User stories

Format: `FT-XX` — copy these IDs into the issue tracker.

## Epic A — Account and onboarding

**FT-01** As a new user I can register with email and password so I have a session.  
AC: invalid email rejected; session survives refresh.

**FT-02** As an applicant I choose Individual or Corporate before details.  
AC: role stored; A4 fields switch.

**FT-03** As an individual I complete details and save a draft.  
AC: leaving A4 and returning restores fields.

**FT-04** As a corporate applicant I complete business + two signatories.  
AC: RC number required; cannot submit with one signatory.

## Epic B — KYC sandbox

**FT-05** As an applicant I submit BVN and NIN and see a sandbox result.  
AC: dummy match and dummy mismatch both work; amber chip visible.

**FT-06** As an applicant with KYC mismatch I still finish the form but get no amount.  
AC: A9 shows “we need to confirm identity”, no NGN figure.

## Epic C — Documents and signature

**FT-07** As an applicant I upload an ID image/PDF ≤ 8 MB.  
AC: reject larger files with a message; thumbnail shown.

**FT-08** As an applicant I upload a statement **or** paste SMS.  
AC: either path enables Continue.

**FT-09** As an applicant I sign on a canvas and see my legal name under it.  
AC: PNG lands in Storage as kind=signature.

## Epic D — Intelligence and scoring

**FT-10** As the system I extract structured JSON from statement text or SMS.  
AC: payload validates against schema in `gemini-prompts.md`; failures set more_info.

**FT-11** As the system I compute amount + tier from rules only.  
AC: same extract in → same amount out twice; unit tests on the rules file.

**FT-12** As the system I generate an 80–140 word officer narrative that does not change the amount.  
AC: narrative stored; amount field untouched by this call.

**FT-13** As an applicant I see a result in under ~20s on seed data (cache hit instant).  
AC: A8 has three labelled steps; A9 disclaimer present.

## Epic E — Officer

**FT-14** As an officer I log in and see a queue.  
AC: applicant role cannot load O1 data (RLS).

**FT-15** As an officer I open a file and see docs, extract, score, narrative.  
AC: amount equals A9.

**FT-16** As an officer I add a note and set approved / more_info / declined.  
AC: A10 status updates for that applicant.

## Epic F — Demo polish

**FT-17** Seed Adaeze, Ibrahim, Northshore (and optional Chioma).  
AC: officer queue shows them after `seed.sql`; scoring uses cached extracts.

**FT-18** Flutter web usable at 1366×768 for A9 and O2.  
AC: no horizontal cut-off of primary CTAs.

**FT-19** Demo chip and disclaimer visible without hunting.  
AC: screenshot test or checklist on A5, A9, O2.
