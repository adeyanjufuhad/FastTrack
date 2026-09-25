// Gemini contracts — docs/gemini-prompts.md. Two calls: extract (0.2) and
// narrative (0.5). Node port of supabase/functions/_shared/gemini.ts.
//
// Route, in order:
//   1. GEMINI_API_KEY set (function env) → Google's API directly.
//   2. Else the branch's Neon AI Gateway, whose token Neon injects into the
//      function (NEON_AI_GATEWAY_TOKEN / NEON_AI_GATEWAY_BASE_URL).
//   3. Neither → GeminiUnavailable; the caller falls back to the extract
//      cache and the template narrative.
// Keys live only in the function's environment, never in the app.

import type { Extract } from "./score.ts";

const env = (k: string) => process.env[k] || undefined;

function route(): { url: string; headers: Record<string, string>; model: string } | null {
  const key = env("GEMINI_API_KEY");
  if (key) {
    const model = env("GEMINI_MODEL") ?? "gemini-2.5-flash";
    return {
      model,
      url: `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      headers: { "x-goog-api-key": key },
    };
  }
  const token = env("NEON_AI_GATEWAY_TOKEN");
  const base = env("NEON_AI_GATEWAY_BASE_URL");
  if (token && base) {
    const model = env("GEMINI_MODEL") ?? "gemini-3-flash";
    return {
      model,
      url: `${base.replace(/\/$/, "")}/gemini/v1beta/models/${model}:generateContent`,
      headers: { Authorization: `Bearer ${token}` },
    };
  }
  return null;
}

/** Model label stored in eligibility_results.model_version. */
export const modelName = () => route()?.model ?? "none";

export class GeminiUnavailable extends Error {}

const EXTRACT_SYSTEM = `You extract facts from Nigerian bank statements or bank-alert SMS.
Return ONLY valid JSON matching the schema. No markdown.
Do not invent transactions. If a field is unknown, use null or [].
Amounts are integers in NGN with no commas or symbols.
income_regularity must be one of: stable, lumpy, seasonal, insufficient_history.
existing_loan_debits: repayment-like debits to known or obvious lenders
(Carbon, Palmpay, FairMoney, Branch, Renmoney, EasyCredit, loan, repayment).
If you are unsure a debit is a loan, omit it.
Schema: {"monthly_income_est": int, "income_regularity": enum, "inflow_months_observed": int,
"top_spend_categories": [{"category": str, "monthly_avg": int, "share_of_outflow": number}],
"existing_loan_debits": [{"label": str, "monthly_avg": int}], "overdraft_or_reversals": bool,
"average_balance_proxy": int|null, "confidence": number 0-1, "warnings": [str]}`;

const NARRATIVE_SYSTEM = `You write a risk narrative for a human loan officer in Nigeria.
80 to 140 words. Professional English. Do not address the applicant.
Do not change or restate a different amount than AMOUNT_PREQUALIFIED.
Do not invent facts that are not in EXTRACT.
End with exactly one recommended next action.`;

type Part = { text: string } | { inline_data: { mime_type: string; data: string } };

async function generate(system: string, parts: Part[], temperature: number, asJson: boolean) {
  const r = route();
  if (!r) throw new GeminiUnavailable("No GEMINI_API_KEY and no Neon AI Gateway on this branch");
  let res: Response;
  try {
    res = await fetch(r.url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...r.headers },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts }],
        generationConfig: { temperature, ...(asJson ? { responseMimeType: "application/json" } : {}) },
      }),
      signal: AbortSignal.timeout(60_000),
    });
  } catch (e) {
    throw new GeminiUnavailable(`Gemini unreachable: ${(e as Error).message}`);
  }
  if (!res.ok) {
    // Keep the provider's reason (e.g. "model requires a verified account")
    // for the function log; error bodies carry no credentials.
    const detail = (await res.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 200);
    throw new GeminiUnavailable(`Gemini ${res.status} via ${r.model}${detail ? `: ${detail}` : ""}`);
  }
  const body = await res.json();
  const text: string | undefined = body?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("");
  if (!text) throw new GeminiUnavailable("Empty Gemini response");
  return text;
}

const REGULARITY = ["stable", "lumpy", "seasonal", "insufficient_history"];
const isInt = (v: unknown) => typeof v === "number" && Number.isFinite(v);

/** Returns a normalised extract, or null if the payload breaks the schema. */
export function validateExtract(raw: unknown): Extract | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  if (!isInt(o.monthly_income_est) || (o.monthly_income_est as number) < 0) return null;
  if (!REGULARITY.includes(o.income_regularity as string)) return null;
  if (typeof o.confidence !== "number" || o.confidence < 0 || o.confidence > 1) return null;
  const spend = Array.isArray(o.top_spend_categories) ? o.top_spend_categories : [];
  const debts = Array.isArray(o.existing_loan_debits) ? o.existing_loan_debits : [];
  return {
    monthly_income_est: Math.round(o.monthly_income_est as number),
    income_regularity: o.income_regularity as Extract["income_regularity"],
    inflow_months_observed: isInt(o.inflow_months_observed) ? Math.round(o.inflow_months_observed as number) : null,
    top_spend_categories: spend
      .filter((c) => c && typeof c === "object" && isInt((c as Record<string, unknown>).monthly_avg))
      .map((c) => {
        const r = c as Record<string, unknown>;
        return {
          category: String(r.category ?? "other"),
          monthly_avg: Math.round(r.monthly_avg as number),
          share_of_outflow: typeof r.share_of_outflow === "number" ? r.share_of_outflow : 0,
        };
      }),
    existing_loan_debits: debts
      .filter((d) => d && typeof d === "object" && isInt((d as Record<string, unknown>).monthly_avg))
      .map((d) => {
        const r = d as Record<string, unknown>;
        return { label: String(r.label ?? "unknown lender"), monthly_avg: Math.round(r.monthly_avg as number) };
      }),
    overdraft_or_reversals: o.overdraft_or_reversals === true,
    average_balance_proxy: isInt(o.average_balance_proxy) ? Math.round(o.average_balance_proxy as number) : null,
    confidence: o.confidence as number,
    warnings: Array.isArray(o.warnings) ? o.warnings.map(String) : [],
  };
}

/** Extract with one "Return JSON only." retry. Null = unreadable. */
export async function extractWithGemini(
  input: { role: string; tenor: number; source: "sms" | "statement"; text?: string; file?: { mime: string; base64: string } },
): Promise<{ extract: Extract | null; raw: string }> {
  const header = `role=${input.role}\ntenor_months=${input.tenor}\nsource=${input.source}\n\nTEXT:\n`;
  const parts: Part[] = input.file
    ? [{ text: header + "(see attached statement)" }, { inline_data: { mime_type: input.file.mime, data: input.file.base64 } }]
    : [{ text: header + (input.text ?? "") }];

  let raw = await generate(EXTRACT_SYSTEM, parts, 0.2, true);
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const parsed = validateExtract(JSON.parse(raw.replace(/^```(?:json)?|```$/g, "").trim()));
      if (parsed) return { extract: parsed, raw };
    } catch { /* fall through to retry */ }
    if (attempt === 0) raw = await generate(EXTRACT_SYSTEM, [...parts, { text: "Return JSON only." }], 0.2, true);
  }
  return { extract: null, raw };
}

/** Narrative; returns null if the text breaks the brief (length or amounts). */
export async function narrativeWithGemini(
  amount: number,
  tier: string,
  warnings: string[],
  extract: Extract,
): Promise<string | null> {
  const text = (await generate(
    NARRATIVE_SYSTEM,
    [{ text: `AMOUNT_PREQUALIFIED=${amount}\nTIER=${tier}\nWARNINGS=${warnings.join(",")}\nEXTRACT=${JSON.stringify(extract)}` }],
    0.5,
    false,
  )).trim();
  const words = text.split(/\s+/).length;
  if (words < 60 || words > 170) return null;
  // Any naira figure ≥ 100k that is not the computed amount or an extract
  // fact means the model restated a different amount — reject it.
  const allowed = new Set<number>([
    amount,
    extract.monthly_income_est,
    extract.average_balance_proxy ?? -1,
    ...extract.existing_loan_debits.map((d) => d.monthly_avg),
    ...extract.top_spend_categories.map((c) => c.monthly_avg),
  ]);
  for (const m of text.matchAll(/(\d{1,3}(?:,\d{3})+|\d{6,})/g)) {
    const n = Number(m[1].replaceAll(",", ""));
    if (n >= 100_000 && !allowed.has(n)) return null;
  }
  return text;
}
