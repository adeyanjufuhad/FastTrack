// Stage A — deterministic rules. TypeScript mirror of
// app/lib/scoring/score_engine.dart + score_config.dart. Keep them in step:
// the applicant (A9) and officer (O2) must always show the same amount.
// Gemini never sets the amount or the tier.

export type Regularity = "stable" | "lumpy" | "seasonal" | "insufficient_history";
export type Tier = "low" | "medium" | "high";
export type KycResult = "sandbox_pass" | "sandbox_fail" | "mismatch";

export interface Extract {
  monthly_income_est: number;
  income_regularity: Regularity;
  inflow_months_observed: number | null;
  top_spend_categories: { category: string; monthly_avg: number; share_of_outflow: number }[];
  existing_loan_debits: { label: string; monthly_avg: number }[];
  overdraft_or_reversals: boolean;
  average_balance_proxy: number | null;
  confidence: number;
  warnings: string[];
}

export const scoreConfig = {
  incomeMultiplierAnnualFactor: 3,
  capAsMonthsOfIncome: 6,
  lumpyHaircut: 0.7,
  insufficientHaircut: 0.4,
  reversalHaircut: 0.75,
  lowConfidenceHaircut: 0.8,
  debtIncomeDeduction: 0.3,
  stackingLenderThreshold: 3,
  lowConfidenceCutoff: 0.45,
  manualReviewFloor: 50_000,
  roundDownTo: 10_000,
  holdingsSleeveRate: 0.3,
  holdingsSleeveEnabled: false,
};

export interface ScoreResult {
  amount: number | null;
  tier: Tier;
  warnings: string[];
  blocked: boolean;
}

export function score(
  x: Extract,
  opts: { kyc: KycResult | null; tenorMonths?: number; holdingsNgn?: number | null },
  cfg = scoreConfig,
): ScoreResult {
  if (opts.kyc !== "sandbox_pass") {
    return { amount: null, tier: "high", warnings: ["kyc_mismatch"], blocked: true };
  }
  const tenor = opts.tenorMonths ?? 12;
  const lenders = x.existing_loan_debits ?? [];
  const debtMonthly = lenders.reduce((a, d) => a + (d.monthly_avg ?? 0), 0);
  const irregular = x.income_regularity === "lumpy" || x.income_regularity === "seasonal";
  const thin = x.income_regularity === "insufficient_history";
  const lowConf = x.confidence < cfg.lowConfidenceCutoff;

  const warnings: string[] = [];
  if (lenders.length > 0) warnings.push("external_lender_detected");
  if (lenders.length >= cfg.stackingLenderThreshold) warnings.push("loan_stacking_suspected");
  if (irregular || thin) warnings.push("irregular_income");
  if (x.overdraft_or_reversals) warnings.push("reversals_present");
  if (thin) warnings.push("thin_history");
  if (lowConf) warnings.push("low_model_confidence");

  const usable = x.monthly_income_est - cfg.debtIncomeDeduction * debtMonthly;
  const base = usable * cfg.incomeMultiplierAnnualFactor * (tenor / 12);
  const cap = x.monthly_income_est * cfg.capAsMonthsOfIncome;
  let amount = Math.max(0, Math.min(base, cap));
  const cappedBase = amount;

  if (irregular) amount *= cfg.lumpyHaircut;
  if (thin) amount *= cfg.insufficientHaircut;
  if (x.overdraft_or_reversals) amount *= cfg.reversalHaircut;
  if (lowConf) amount *= cfg.lowConfidenceHaircut;

  const holdings = opts.holdingsNgn ?? 0;
  if (cfg.holdingsSleeveEnabled && holdings > 0) {
    amount += Math.min(holdings * cfg.holdingsSleeveRate, cappedBase);
  }

  // Snap to whole naira first so float noise cannot drop a 10k step.
  const rounded = Math.floor(Math.round(amount) / cfg.roundDownTo) * cfg.roundDownTo;

  let tier: Tier = "low";
  if (irregular || x.overdraft_or_reversals || lowConf || lenders.length > 0) tier = "medium";
  const flags = [irregular, x.overdraft_or_reversals, lenders.length >= 2].filter(Boolean).length;
  if (thin || lenders.length >= cfg.stackingLenderThreshold || flags >= 2) tier = "high";

  if (rounded < cfg.manualReviewFloor) {
    tier = "high";
    warnings.push("manual_review_small_amount");
  }
  return { amount: rounded, tier, warnings, blocked: false };
}

const ngn = (n: number) => `NGN ${Math.round(n).toLocaleString("en-US")}`;

/** Template narrative — used when Gemini is unavailable or its text fails checks. */
export function templateNarrative(x: Extract, r: ScoreResult, role: "individual" | "corporate"): string {
  if (r.blocked) {
    return "Identity could not be confirmed against the sandbox register, so the rules engine has not produced an amount. " +
      "The statement extract is retained for reference but should not be relied on until identity is resolved. " +
      "Recommended next action: request a clear government ID and re-run the identity check.";
  }
  const who = role === "corporate" ? "The business's" : "The applicant's";
  const months = x.inflow_months_observed ? ` across ${x.inflow_months_observed} observed months` : "";
  const s: string[] = [];
  s.push({
    stable: `${who} income is regular at about ${ngn(x.monthly_income_est)} a month${months}.`,
    lumpy: `${who} inflows are lumpy, averaging about ${ngn(x.monthly_income_est)} a month${months}.`,
    seasonal: `${who} inflows are seasonal, averaging about ${ngn(x.monthly_income_est)} a month${months}.`,
    insufficient_history: `${who} statement shows too little history to establish a reliable income pattern.`,
  }[x.income_regularity]);
  s.push(x.existing_loan_debits.length === 0
    ? "No repayments to other lenders were detected."
    : `Repayment debits to other lenders were detected: ${x.existing_loan_debits.map((d) => `${d.label} (${ngn(d.monthly_avg)} a month)`).join(", ")}.`);
  const top = x.top_spend_categories[0];
  if (top) s.push(`The largest spend category is ${top.category.replaceAll("_", " ")} at about ${ngn(top.monthly_avg)} a month.`);
  s.push(x.overdraft_or_reversals
    ? "The statement shows reversals, which reduce confidence in cash flow."
    : "No overdraft or reversal pattern was observed.");
  s.push(`The rules engine pre-qualifies ${ngn(r.amount ?? 0)} at ${r.tier} risk, with extraction confidence of ${Math.round(x.confidence * 100)}%.`);
  s.push(`Recommended next action: ${
    r.tier === "low"
      ? "approve into an offer letter subject to standard documentation."
      : r.tier === "medium"
      ? (x.existing_loan_debits.length > 0
        ? "confirm the external repayment and a landlord or employer reference, then move to offer letter."
        : "confirm one income reference, then move to offer letter.")
      : "request a six-month statement before any offer."
  }`);
  return s.join(" ");
}
