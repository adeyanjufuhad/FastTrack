// POST /functions/v1/process-application — the single orchestrator
// (docs/architecture.md): load → cache / Gemini extract → rules → narrative →
// write eligibility_results → status "scored".
//
// Errors follow docs/api-contracts.md:
//   401 no JWT · 403 not owner/officer · 409 KYC mismatch · 422 unreadable · 503 Gemini down, no cache

import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import {
  extractWithGemini,
  GeminiUnavailable,
  MODEL,
  narrativeWithGemini,
  validateExtract,
} from "../_shared/gemini.ts";
import { adminClient, corsHeaders, fail, json, requireUser, sha256 } from "../_shared/http.ts";
import { type Extract, score, templateNarrative } from "../_shared/score.ts";

const MAX_BYTES = 8 * 1024 * 1024;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "POST only");

  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;

  let body: { application_id?: string; fixture_key?: string };
  try {
    body = await req.json();
  } catch {
    return fail(400, "Invalid JSON body.");
  }
  if (!body.application_id) return fail(400, "application_id is required.");

  // Ownership check with the caller's JWT: RLS hides other people's files.
  const { data: app } = await auth.client
    .from("applications")
    .select("*")
    .eq("id", body.application_id)
    .maybeSingle();
  if (!app) return fail(403, "Application not found for this user.");

  const admin = adminClient();
  const { data: applicant } = await admin
    .from("applicants")
    .select("role, kyc_result, holdings_ngn")
    .eq("id", app.applicant_id)
    .single();
  if (!applicant) return fail(422, "Applicant profile missing.");

  const setStatus = (status: string) =>
    admin.from("applications").update({ status, updated_at: new Date().toISOString() }).eq("id", app.id);

  // ── 1. Extract (cache first) ────────────────────────────────────────────
  let extract: Extract | null = null;
  let modelVersion = "fixture-cache";
  let rawOutput: string | null = null;
  let cacheKey: string | null = null;

  const readCache = async (key: string) => {
    const { data } = await admin.from("extract_cache").select("payload").eq("input_hash", key).maybeSingle();
    return data ? validateExtract(data.payload) : null;
  };

  if (body.fixture_key?.startsWith("fixture:")) {
    extract = await readCache(body.fixture_key);
  }

  try {
    if (!extract && app.sms_text && String(app.sms_text).trim().length > 0) {
      cacheKey = await sha256(`${applicant.role}${app.tenor_months}sms${app.sms_text}`);
      extract = await readCache(cacheKey);
      if (!extract) {
        const r = await extractWithGemini({
          role: applicant.role,
          tenor: app.tenor_months,
          source: "sms",
          text: app.sms_text,
        });
        extract = r.extract;
        rawOutput = r.raw;
        modelVersion = MODEL;
      }
    } else if (!extract) {
      const { data: doc } = await admin
        .from("documents")
        .select("storage_path, mime, bytes")
        .eq("applicant_id", app.applicant_id)
        .eq("kind", "statement")
        .order("uploaded_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!doc) {
        await setStatus("more_info");
        return fail(422, "We could not read this file. Try SMS paste or a clearer PDF.");
      }
      if ((doc.bytes ?? 0) > MAX_BYTES) {
        await setStatus("more_info");
        return fail(422, "Statement is larger than 8 MB.");
      }
      const { data: blob, error } = await admin.storage.from("documents").download(doc.storage_path);
      if (error || !blob) return fail(422, "We could not read this file. Try SMS paste or a clearer PDF.");
      const bytes = new Uint8Array(await blob.arrayBuffer());
      cacheKey = await sha256(`${applicant.role}${app.tenor_months}statement` + (await sha256(bytes)));
      extract = await readCache(cacheKey);
      if (!extract) {
        // v1: send the PDF / image to Gemini multimodal directly.
        const r = await extractWithGemini({
          role: applicant.role,
          tenor: app.tenor_months,
          source: "statement",
          file: { mime: doc.mime ?? "application/pdf", base64: encodeBase64(bytes) },
        });
        extract = r.extract;
        rawOutput = r.raw;
        modelVersion = MODEL;
      }
    }
  } catch (e) {
    if (e instanceof GeminiUnavailable) return fail(503, "Statement reader unavailable and no cached extract.");
    throw e;
  }

  if (!extract) {
    await setStatus("more_info");
    return fail(422, "We could not read this file. Try SMS paste or a clearer PDF.");
  }
  if (cacheKey && rawOutput) {
    await admin.from("extract_cache").upsert({ input_hash: cacheKey, payload: extract });
  }

  // ── 2. Rules (Stage A) ──────────────────────────────────────────────────
  const result = score(extract, {
    kyc: applicant.kyc_result,
    tenorMonths: app.tenor_months,
    holdingsNgn: applicant.holdings_ngn,
  });

  // ── 3. Narrative (Stage B) — never allowed to change the number ─────────
  let narrative: string | null = null;
  if (!result.blocked && result.amount !== null) {
    try {
      narrative = await narrativeWithGemini(result.amount, result.tier, result.warnings, extract);
    } catch {
      narrative = null; // fall back to the template below
    }
  }
  narrative ??= templateNarrative(extract, result, applicant.role);

  // ── 4. Persist ──────────────────────────────────────────────────────────
  const { error: insertError } = await admin.from("eligibility_results").insert({
    application_id: app.id,
    monthly_income_est: extract.monthly_income_est,
    income_regularity: extract.income_regularity,
    spend_categories: extract.top_spend_categories,
    existing_debts: extract.existing_loan_debits,
    extract,
    tier: result.blocked ? null : result.tier,
    amount_prequalified: result.amount,
    warnings: result.warnings,
    narrative,
    model_version: modelVersion,
    raw_model_output: rawOutput,
  });
  if (insertError) return fail(500, "Could not save the result.");

  if (result.blocked) {
    await setStatus("more_info");
    return fail(409, "We need to confirm your identity before we can show an amount.");
  }
  await setStatus("scored");

  const applicantSummary = narrative.split(/(?<=\.)\s+/).slice(0, 4).join(" ");
  return json({
    application_id: app.id,
    status: "scored",
    amount_prequalified: result.amount,
    tier: result.tier,
    warnings: result.warnings,
    narrative,
    applicant_summary: applicantSummary,
  });
});
