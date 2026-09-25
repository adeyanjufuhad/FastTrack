// Access rules and the process-application pipeline, against fakes for
// Postgres, storage and Neon Auth. No network, no database.
import { deepStrictEqual, match, ok, strictEqual } from "node:assert/strict";
import { test } from "node:test";

import { createHandler, type Deps } from "./api.ts";
import { AuthError, type NeonAuth } from "./auth.ts";
import type { Query } from "./db.ts";
import type { Storage } from "./storage.ts";

const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const OFFICER = "33333333-3333-4333-8333-333333333333";
const APP = "f0000000-0000-4000-8000-0000000000a1";

type Rule = [RegExp, (params: unknown[]) => unknown[]];

function setup(rules: Rule[] = [], storage: Partial<Storage> = {}) {
  const log: { sql: string; params: unknown[] }[] = [];
  const query: Query = async <T,>(sql: string, params: unknown[] = []) => {
    log.push({ sql, params });
    if (/from public\.staff where user_id/.test(sql)) return (params[0] === OFFICER ? [{ "?column?": 1 }] : []) as T[];
    for (const [re, fn] of rules) if (re.test(sql)) return fn(params) as T[];
    return [] as T[];
  };
  const deps: Deps = {
    query,
    storage: {
      put: async () => {},
      get: async () => new Uint8Array(),
      signedUrl: async (k) => `https://s3.example/${k}?sig`,
      ...storage,
    },
    auth: {} as NeonAuth,
    verify: async (t) => {
      if (![ALICE, BOB, OFFICER].includes(t)) throw new AuthError("Invalid token signature.");
      return { sub: t, email: `${t.slice(0, 4)}@x.io`, exp: 0 };
    },
    env: {},
  };
  const handle = createHandler(deps);
  const call = async (method: string, path: string, as?: string, body?: unknown, headers: Record<string, string> = {}) => {
    const res = await handle(
      new Request(`https://fn.example${path}`, {
        method,
        headers: {
          ...(as ? { authorization: `Bearer ${as}` } : {}),
          ...(body !== undefined && !(body instanceof Uint8Array) ? { "content-type": "application/json" } : {}),
          ...headers,
        },
        body: body === undefined ? undefined : body instanceof Uint8Array ? (body as Uint8Array<ArrayBuffer>) : JSON.stringify(body),
      }),
    );
    return { status: res.status, body: await res.json() as Record<string, unknown> };
  };
  return { call, log };
}

const aliceApp = { id: APP, applicant_id: ALICE, status: "draft", tenor_months: 12, sms_text: null };
const appRule: Rule = [/select \* from public\.applications where id = \$1/, () => [aliceApp]];

test("no or bad bearer → 401; CORS preflight answers without auth", async () => {
  const { call } = setup();
  strictEqual((await call("GET", "/me")).status, 401);
  strictEqual((await call("GET", "/me", "forged")).status, 401);
  strictEqual((await call("GET", "/health")).status, 200);
});

test("officer routes need a staff row", async () => {
  const { call } = setup();
  strictEqual((await call("GET", "/officer/queue", ALICE)).status, 403);
  strictEqual((await call("GET", "/officer/queue", OFFICER)).status, 200);
  deepStrictEqual((await call("GET", "/me", OFFICER)).body.is_officer, true);
});

test("applicants cannot read or edit someone else's application", async () => {
  const { call } = setup([appRule]);
  strictEqual((await call("GET", `/applications/${APP}/eligibility`, BOB)).status, 403);
  strictEqual((await call("PUT", `/applications/${APP}`, BOB, { purpose: "x" })).status, 403);
  strictEqual((await call("GET", `/applications/${APP}/eligibility`, ALICE)).status, 200);
  strictEqual((await call("GET", `/applications/${APP}/eligibility`, OFFICER)).status, 200);
});

test("applicants cannot self-approve or set server-managed fields", async () => {
  const { call, log } = setup([appRule, [/insert into public\.applicants \(id, role/, () => [{}]]]);
  strictEqual((await call("PUT", `/applications/${APP}`, ALICE, { status: "approved" })).status, 403);
  strictEqual((await call("PUT", `/applications/${APP}`, ALICE, { status: "submitted", tenor_months: 12 })).status, 200);

  await call("PUT", "/applicant", ALICE, { role: "individual", legal_name: "Alice", kyc_result: "sandbox_pass", holdings_ngn: 9e9 });
  const upsert = log.find((l) => /insert into public\.applicants \(id, role/.test(l.sql))!;
  ok(!/kyc_result|holdings_ngn|bvn_masked/.test(upsert.sql));
  ok(!upsert.params.includes("sandbox_pass"));
});

test("KYC sandbox stores only masked numbers", async () => {
  const { call, log } = setup([[/from public\.kyc_sandbox/, () => [{ matched_name: "ADA EZE OKAFOR", result: "sandbox_pass" }]]]);
  const r = await call("POST", "/kyc-check", ALICE, { bvn: "22222222222", legal_name: "Ada" });
  deepStrictEqual(r.body, { result: "sandbox_pass", matched_name: "ADA EZE OKAFOR", mode: "sandbox" });
  const saved = log.find((l) => /kyc_result, bvn_masked/.test(l.sql))!;
  deepStrictEqual(saved.params.slice(2), ["sandbox_pass", "*******2222", null]);
  ok(!log.some((l) => l.params.includes("22222222222") && !/kyc_sandbox/.test(l.sql)));
  strictEqual((await call("POST", "/kyc-check", ALICE, { bvn: "123" })).status, 400);
});

test("uploads go under the caller's folder; wrong type or size is refused", async () => {
  const puts: string[] = [];
  const { call } = setup(
    [[/insert into public\.documents/, (p) => [{ id: "d1", storage_key: p[2], bytes: p[5] }]]],
    { put: async (k) => void puts.push(k) },
  );
  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46]);
  const ok1 = await call("POST", "/documents?kind=statement&name=my%20statement.pdf", ALICE, pdf, { "content-type": "application/pdf" });
  strictEqual(ok1.status, 200);
  match(puts[0], new RegExp(`^${ALICE}/statement-\\d+-my_statement\\.pdf$`));
  strictEqual((await call("POST", "/documents?kind=statement", ALICE, pdf, { "content-type": "text/html" })).status, 415);
  strictEqual((await call("POST", "/documents?kind=nope", ALICE, pdf, { "content-type": "application/pdf" })).status, 400);
  strictEqual(
    (await call("POST", "/documents?kind=id", ALICE, pdf, { "content-type": "image/png", "content-length": String(9 * 1024 * 1024) })).status,
    413,
  );
});

test("signed document links only for the owner or an officer", async () => {
  const doc = { applicant_id: ALICE, storage_key: `${ALICE}/id-1-x.png` };
  const { call } = setup([[/from public\.documents where id = \$1/, () => [doc]]]);
  const id = "44444444-4444-4444-8444-444444444444";
  strictEqual((await call("GET", `/documents/${id}/url`, BOB)).status, 404);
  strictEqual((await call("GET", `/documents/${id}/url`, ALICE)).body.url, `https://s3.example/${doc.storage_key}?sig`);
  strictEqual((await call("GET", `/documents/${id}/url`, OFFICER)).status, 200);
});

const adaezeExtract = {
  monthly_income_est: 420000,
  income_regularity: "stable",
  inflow_months_observed: 3,
  top_spend_categories: [{ category: "pos_retail", monthly_avg: 85000, share_of_outflow: 0.31 }],
  existing_loan_debits: [{ label: "Carbon", monthly_avg: 15000 }],
  overdraft_or_reversals: false,
  average_balance_proxy: 190000,
  confidence: 0.82,
  warnings: ["external_lender_detected"],
};

test("process-application: cached fixture → rules amount, template narrative, status scored", async () => {
  let kyc = "sandbox_pass";
  const { call, log } = setup([
    appRule,
    [/from public\.applicants where id/, () => [{ role: "individual", kyc_result: kyc, holdings_ngn: null }]],
    [/from public\.extract_cache where input_hash/, (p) => (p[0] === "fixture:adaeze-sms" ? [{ payload: adaezeExtract }] : [])],
  ]);
  const r = await call("POST", "/process-application", ALICE, { application_id: APP, fixture_key: "fixture:adaeze-sms" });
  strictEqual(r.status, 200);
  strictEqual(r.body.amount_prequalified, 1240000);
  strictEqual(r.body.tier, "medium");
  match(String(r.body.narrative), /pre-qualifies NGN 1,240,000 at medium risk/);
  const status = log.filter((l) => /update public\.applications set status/.test(l.sql)).at(-1)!;
  strictEqual(status.params[1], "scored");

  kyc = "mismatch";
  const blocked = await call("POST", "/process-application", ALICE, { application_id: APP, fixture_key: "fixture:adaeze-sms" });
  strictEqual(blocked.status, 409);
  strictEqual(log.filter((l) => /update public\.applications set status/.test(l.sql)).at(-1)!.params[1], "more_info");

  strictEqual((await call("POST", "/process-application", BOB, { application_id: APP })).status, 403);
});

test("process-application without a statement or SMS → 422 and more_info", async () => {
  const { call, log } = setup([
    appRule,
    [/from public\.applicants where id/, () => [{ role: "individual", kyc_result: "sandbox_pass", holdings_ngn: null }]],
  ]);
  strictEqual((await call("POST", "/process-application", ALICE, { application_id: APP })).status, 422);
  strictEqual(log.filter((l) => /update public\.applications set status/.test(l.sql)).at(-1)!.params[1], "more_info");
});

test("officer decisions are limited to review outcomes", async () => {
  const { call } = setup([[/update public\.applications\s+set status = \$2::public\.application_status, officer_id/, (p) => [{ id: p[0], status: p[1] }]]]);
  strictEqual((await call("POST", `/officer/applications/${APP}/decision`, OFFICER, { status: "scored" })).status, 400);
  strictEqual((await call("POST", `/officer/applications/${APP}/decision`, OFFICER, { status: "approved" })).body.status, "approved");
  strictEqual((await call("POST", `/officer/applications/${APP}/decision`, ALICE, { status: "approved" })).status, 403);
});
