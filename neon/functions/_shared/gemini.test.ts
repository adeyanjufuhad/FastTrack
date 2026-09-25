import { rejects } from "node:assert/strict";
import { afterEach, test } from "node:test";

import { extractWithGemini, GeminiUnavailable } from "./gemini.ts";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
  delete process.env.NEON_AI_GATEWAY_TOKEN;
  delete process.env.NEON_AI_GATEWAY_BASE_URL;
});

test("a refused Gemini call keeps the provider's reason for the log", async () => {
  process.env.NEON_AI_GATEWAY_TOKEN = "nt_test";
  process.env.NEON_AI_GATEWAY_BASE_URL = "https://gw.example";
  globalThis.fetch = (async () =>
    new Response(JSON.stringify({ error: { message: "model requires a verified account" } }), { status: 403 })) as typeof fetch;
  await rejects(
    extractWithGemini({ role: "individual", tenor: 12, source: "sms", text: "x" }),
    (e: Error) => e instanceof GeminiUnavailable && /403 via gemini-3-flash: .*verified account/.test(e.message),
  );
});

test("no key and no gateway → GeminiUnavailable without a network call", async () => {
  globalThis.fetch = (async () => {
    throw new Error("should not be called");
  }) as typeof fetch;
  await rejects(extractWithGemini({ role: "individual", tenor: 12, source: "sms", text: "x" }), GeminiUnavailable);
});
