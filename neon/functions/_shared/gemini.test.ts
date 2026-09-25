import { deepStrictEqual, rejects, strictEqual } from "node:assert/strict";
import { afterEach, test } from "node:test";

import { extractWithGemini, GeminiUnavailable } from "./gemini.ts";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
  for (const k of ["NEON_AI_GATEWAY_TOKEN", "NEON_AI_GATEWAY_BASE_URL", "GEMINI_API_KEY", "GEMINI_MODEL", "GEMINI_FALLBACK_MODELS"]) {
    delete process.env[k];
  }
});

const input = { role: "individual", tenor: 12, source: "sms" as const, text: "x" };
const extract = {
  monthly_income_est: 350000,
  income_regularity: "stable",
  inflow_months_observed: 3,
  top_spend_categories: [],
  existing_loan_debits: [],
  overdraft_or_reversals: false,
  average_balance_proxy: null,
  confidence: 0.8,
  warnings: [],
};
const ok = () => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(extract) }] } }] }));

/** Scripted fetch: answers per model name in the URL, and records the order tried. */
function scripted(answers: Record<string, () => Response>) {
  const tried: string[] = [];
  globalThis.fetch = (async (url: string) => {
    const model = /models\/([^:]+):/.exec(url)![1];
    tried.push(model);
    return (answers[model] ?? (() => new Response("{}", { status: 404 })))();
  }) as unknown as typeof fetch;
  return tried;
}

test("an overloaded model falls through to the next one, which is recorded", async () => {
  process.env.GEMINI_API_KEY = "k";
  process.env.GEMINI_MODEL = "gemini-3.8-flash";
  process.env.GEMINI_FALLBACK_MODELS = "gemini-3.5-flash-lite";
  const tried = scripted({
    "gemini-3.8-flash": () => new Response('{"error":{"message":"high demand"}}', { status: 503 }),
    "gemini-3.5-flash-lite": ok,
  });
  const r = await extractWithGemini(input);
  deepStrictEqual(tried, ["gemini-3.8-flash", "gemini-3.5-flash-lite"]);
  strictEqual(r.model, "gemini-3.5-flash-lite");
  strictEqual(r.extract?.monthly_income_est, 350000);
});

test("every model refusing keeps each provider reason for the log", async () => {
  process.env.NEON_AI_GATEWAY_TOKEN = "nt_test";
  process.env.NEON_AI_GATEWAY_BASE_URL = "https://gw.example";
  const refuse = () => new Response(JSON.stringify({ error: { message: "model requires a verified account" } }), { status: 403 });
  scripted({ "gemini-3-flash": refuse, "gemini-3-5-flash-lite": refuse });
  await rejects(extractWithGemini(input), (e: Error) =>
    e instanceof GeminiUnavailable &&
    /gemini-3-flash: 403 .*verified account/.test(e.message) &&
    /gemini-3-5-flash-lite: 403/.test(e.message));
});

test("a bad request stops at the first model instead of trying them all", async () => {
  process.env.GEMINI_API_KEY = "k";
  const tried = scripted({ "gemini-3.5-flash-lite": () => new Response('{"error":{"message":"bad"}}', { status: 400 }) });
  await rejects(extractWithGemini(input), GeminiUnavailable);
  deepStrictEqual(tried, ["gemini-3.5-flash-lite"]);
});

test("no key and no gateway → GeminiUnavailable without a network call", async () => {
  const tried = scripted({});
  await rejects(extractWithGemini(input), GeminiUnavailable);
  deepStrictEqual(tried, []);
});
