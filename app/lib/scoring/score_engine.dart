// Stage A — deterministic rules. Pure Dart: no Flutter, no network, no model.
// Gemini never sets the amount or the tier; this function does.

import '../models/enums.dart';
import '../models/extract.dart';
import 'score_config.dart';

class ScoreResult {
  const ScoreResult({
    required this.amount,
    required this.tier,
    required this.warnings,
    this.blocked = false,
  });

  /// Null when KYC blocked the amount.
  final int? amount;
  final Tier tier;
  final List<String> warnings;

  /// True on KYC mismatch/fail: no amount, status more_info.
  final bool blocked;
}

class Warnings {
  static const externalLender = 'external_lender_detected';
  static const stacking = 'loan_stacking_suspected';
  static const irregularIncome = 'irregular_income';
  static const reversals = 'reversals_present';
  static const thinHistory = 'thin_history';
  static const lowConfidence = 'low_model_confidence';
  static const kycMismatch = 'kyc_mismatch';
  static const manualReview = 'manual_review_small_amount';

  static String describe(String w) => switch (w) {
    externalLender => 'External lender detected',
    stacking => 'Loan stacking suspected',
    irregularIncome => 'Irregular income',
    reversals => 'Reversals present',
    thinHistory => 'Thin history',
    lowConfidence => 'Low model confidence',
    kycMismatch => 'KYC mismatch',
    manualReview => 'Below NGN 50,000 — manual review',
    _ => w.replaceAll('_', ' '),
  };
}

ScoreResult score(
  Extract x, {
  required KycResult? kyc,
  int tenorMonths = 12,
  int? holdingsNgn,
  ScoreConfig cfg = defaultScoreConfig,
}) {
  // 1. KYC mismatch or fail → no amount.
  if (kyc != KycResult.sandboxPass) {
    return const ScoreResult(
      amount: null,
      tier: Tier.high,
      warnings: [Warnings.kycMismatch],
      blocked: true,
    );
  }

  final lenders = x.existingLoanDebits;
  final debtMonthly = lenders.fold<int>(0, (a, d) => a + d.monthlyAvg);
  final irregular =
      x.regularity == Regularity.lumpy || x.regularity == Regularity.seasonal;
  final thin = x.regularity == Regularity.insufficientHistory;
  final lowConf = x.confidence < cfg.lowConfidenceCutoff;

  final warnings = <String>[
    if (lenders.isNotEmpty) Warnings.externalLender,
    if (lenders.length >= cfg.stackingLenderThreshold) Warnings.stacking,
    if (irregular || thin) Warnings.irregularIncome,
    if (x.overdraftOrReversals) Warnings.reversals,
    if (thin) Warnings.thinHistory,
    if (lowConf) Warnings.lowConfidence,
  ];

  // 2–4. Usable income → base facility → cap.
  final usable = x.monthlyIncomeEst - cfg.debtIncomeDeduction * debtMonthly;
  final base =
      usable * cfg.incomeMultiplierAnnualFactor * (tenorMonths / 12);
  final cap = (x.monthlyIncomeEst * cfg.capAsMonthsOfIncome).toDouble();
  var amount = base > cap ? cap : base;
  if (amount < 0) amount = 0;
  final cappedBase = amount;

  // 5–7. Haircuts.
  if (irregular) amount *= cfg.lumpyHaircut;
  if (thin) amount *= cfg.insufficientHaircut;
  if (x.overdraftOrReversals) amount *= cfg.reversalHaircut;
  if (lowConf) amount *= cfg.lowConfidenceHaircut;

  // 11. Optional holdings sleeve (existing portfolio clients only).
  final sleeve = cfg.holdingsSleeveEnabled && (holdingsNgn ?? 0) > 0;
  if (sleeve) {
    final secured = holdingsNgn! * cfg.holdingsSleeveRate;
    amount += secured < cappedBase ? secured : cappedBase;
  }

  // 8. Round down to the nearest NGN 10,000. Snap to whole naira first so
  // float noise (5.4m × 0.7 = 3,779,999.99…) cannot drop a whole step.
  final naira = amount.round();
  final rounded = (naira ~/ cfg.roundDownTo) * cfg.roundDownTo;

  // 10. Tier.
  var tier = Tier.low;
  if (irregular || x.overdraftOrReversals || lowConf || lenders.isNotEmpty) {
    tier = Tier.medium;
  }
  final flagCount = [
    irregular,
    x.overdraftOrReversals,
    lenders.length >= 2,
  ].where((f) => f).length;
  if (thin ||
      lenders.length >= cfg.stackingLenderThreshold ||
      flagCount >= 2) {
    tier = Tier.high;
  }

  // 9. Tiny amounts go to manual review.
  if (rounded < cfg.manualReviewFloor) {
    tier = Tier.high;
    warnings.add(Warnings.manualReview);
  }

  return ScoreResult(amount: rounded, tier: tier, warnings: warnings);
}
