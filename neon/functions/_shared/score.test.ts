// Parity with app/test/score_engine_test.dart and the seeded persona amounts
// in neon/seeds/0002_personas.sql — run: npm test (in neon/)
import { deepStrictEqual as assertEquals } from "node:assert/strict";
import { test } from "node:test";
import { type Extract, score } from "./score.ts";

const base = {
  inflow_months_observed: 3,
  top_spend_categories: [],
  average_balance_proxy: null,
  warnings: [],
};

const adaeze: Extract = {
  ...base,
  monthly_income_est: 420000,
  income_regularity: "stable",
  existing_loan_debits: [{ label: "Carbon", monthly_avg: 15000 }],
  overdraft_or_reversals: false,
  confidence: 0.82,
};
const ibrahim: Extract = {
  ...base,
  monthly_income_est: 280000,
  income_regularity: "lumpy",
  existing_loan_debits: [{ label: "Palmpay", monthly_avg: 40000 }, { label: "unknown lender", monthly_avg: 25000 }],
  overdraft_or_reversals: true,
  confidence: 0.6,
};
const northshore: Extract = {
  ...base,
  monthly_income_est: 1800000,
  income_regularity: "lumpy",
  existing_loan_debits: [],
  overdraft_or_reversals: false,
  confidence: 0.7,
};

test("Adaeze → 1,240,000 medium", () => {
  const r = score(adaeze, { kyc: "sandbox_pass" });
  assertEquals([r.amount, r.tier], [1240000, "medium"]);
});

test("Ibrahim → 410,000 high", () => {
  const r = score(ibrahim, { kyc: "sandbox_pass" });
  assertEquals([r.amount, r.tier], [410000, "high"]);
});

test("Northshore → 3,780,000 medium (no float drop)", () => {
  const r = score(northshore, { kyc: "sandbox_pass" });
  assertEquals([r.amount, r.tier], [3780000, "medium"]);
});

test("KYC mismatch → no amount", () => {
  const r = score(adaeze, { kyc: "mismatch" });
  assertEquals([r.amount, r.blocked, r.warnings], [null, true, ["kyc_mismatch"]]);
});
