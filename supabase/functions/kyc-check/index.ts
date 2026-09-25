// POST /functions/v1/kyc-check — sandbox BVN / NIN check (docs/kyc-sandbox.md).
// Demo rule: a BVN *or* NIN hit on the dummy table passes; names are ignored
// so a pitch-room typist cannot fail KYC. 00000000000 always fails.

import { adminClient, corsHeaders, fail, json, last4, mask, requireUser } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "POST only");

  // LIVE_KYC must stay false in v1 — no provider integration exists.
  if (Deno.env.get("LIVE_KYC") === "true") return fail(501, "Live KYC is not part of this build.");

  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;

  let body: { bvn?: string; nin?: string; legal_name?: string };
  try {
    body = await req.json();
  } catch {
    return fail(400, "Invalid JSON body.");
  }
  const eleven = /^\d{11}$/;
  const bvn = body.bvn && eleven.test(body.bvn) ? body.bvn : null;
  const nin = body.nin && eleven.test(body.nin) ? body.nin : null;
  if (!bvn && !nin) return fail(400, "Provide an 11-digit BVN or NIN.");

  const admin = adminClient();
  const filters = [bvn && `bvn.eq.${bvn}`, nin && `nin.eq.${nin}`].filter(Boolean).join(",");
  const { data: rows, error } = await admin.from("kyc_sandbox").select("matched_name, result").or(filters).limit(1);
  if (error) return fail(500, "Sandbox lookup failed.");

  const hit = rows?.[0];
  const result: "sandbox_pass" | "sandbox_fail" | "mismatch" = hit ? hit.result : "mismatch";

  // Only masked values are stored on the applicant; logs keep last four digits.
  await admin.from("applicants").upsert({
    id: auth.user.id,
    kyc_result: result,
    bvn_masked: mask(bvn),
    nin_masked: mask(nin),
    updated_at: new Date().toISOString(),
  });
  await admin.from("kyc_logs").insert({
    applicant_id: auth.user.id,
    bvn_last4: last4(bvn),
    nin_last4: last4(nin),
    result,
    mode: "sandbox",
  });

  return json({ result, matched_name: hit?.matched_name ?? undefined, mode: "sandbox" });
});
