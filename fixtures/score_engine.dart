// ORIGINAL HANDOFF REFERENCE — superseded by app/lib/scoring/score_engine.dart.
// Kept for history. Note: `_floor10k` below floors raw doubles, so
// 5,400,000 × 0.70 (= 3,779,999.99…) rounds to 3,770,000. The app version
// snaps to whole naira first and is covered by app/test/score_engine_test.dart.
//
// Drop into packages/scoring or lib/scoring/score_engine.dart
// Pure Dart. No Flutter imports. Unit-test this file.

enum Regularity { stable, lumpy, seasonal, insufficientHistory }

enum Tier { low, medium, high }

class LoanDebit {
  LoanDebit(this.label, this.monthlyAvg);
  final String label;
  final int monthlyAvg;
}

class Extract {
  Extract({
    required this.monthlyIncomeEst,
    required this.regularity,
    required this.existingDebts,
    required this.overdraftOrReversals,
    required this.confidence,
  });

  final int monthlyIncomeEst;
  final Regularity regularity;
  final List<LoanDebit> existingDebts;
  final bool overdraftOrReversals;
  final double confidence;
}

class ScoreConfig {
  const ScoreConfig({
    this.incomeMultiplier = 3,
    this.capMonths = 6,
    this.lumpyHaircut = 0.70,
    this.insufficientHaircut = 0.40,
    this.reversalHaircut = 0.75,
    this.lowConfidenceHaircut = 0.80,
    this.debtDeduction = 0.30,
    this.lowConfidenceCutoff = 0.45,
  });

  final num incomeMultiplier;
  final int capMonths;
  final double lumpyHaircut;
  final double insufficientHaircut;
  final double reversalHaircut;
  final double lowConfidenceHaircut;
  final double debtDeduction;
  final double lowConfidenceCutoff;
}

class ScoreResult {
  ScoreResult({
    required this.amount,
    required this.tier,
    required this.warnings,
    this.blocked = false,
  });

  final int amount;
  final Tier tier;
  final List<String> warnings;
  final bool blocked;
}

int _floor10k(num v) => (v ~/ 10000) * 10000;

ScoreResult score(Extract x, {required bool kycPass, int tenorMonths = 12, ScoreConfig cfg = const ScoreConfig()}) {
  final warnings = <String>[];
  if (!kycPass) {
    return ScoreResult(amount: 0, tier: Tier.high, warnings: ['kyc_mismatch'], blocked: true);
  }

  final debtMonthly = x.existingDebts.fold<int>(0, (a, d) => a + d.monthlyAvg);
  if (x.existingDebts.isNotEmpty) warnings.add('external_lender_detected');
  if (x.existingDebts.length >= 3) warnings.add('loan_stacking_suspected');
  if (x.regularity != Regularity.stable) warnings.add('irregular_income');
  if (x.overdraftOrReversals) warnings.add('reversals_present');
  if (x.regularity == Regularity.insufficientHistory) warnings.add('thin_history');
  if (x.confidence < cfg.lowConfidenceCutoff) warnings.add('low_model_confidence');

  final usable = x.monthlyIncomeEst - cfg.debtDeduction * debtMonthly;
  var amount = usable * cfg.incomeMultiplier * (tenorMonths / 12);
  final cap = x.monthlyIncomeEst * cfg.capMonths;
  if (amount > cap) amount = cap.toDouble();

  if (x.regularity == Regularity.lumpy || x.regularity == Regularity.seasonal) {
    amount *= cfg.lumpyHaircut;
  } else if (x.regularity == Regularity.insufficientHistory) {
    amount *= cfg.insufficientHaircut;
  }
  if (x.overdraftOrReversals) amount *= cfg.reversalHaircut;
  if (x.confidence < cfg.lowConfidenceCutoff) amount *= cfg.lowConfidenceHaircut;

  var tier = Tier.low;
  if (x.regularity == Regularity.stable && x.existingDebts.isEmpty && !x.overdraftOrReversals) {
    tier = Tier.low;
  } else {
    tier = Tier.medium;
  }
  final flagCount = [
    x.regularity == Regularity.lumpy || x.regularity == Regularity.seasonal,
    x.overdraftOrReversals,
    x.existingDebts.length >= 2,
  ].where((e) => e).length;
  if (x.regularity == Regularity.insufficientHistory || x.existingDebts.length >= 3 || flagCount >= 2) {
    tier = Tier.high;
  }
  if (x.confidence < cfg.lowConfidenceCutoff && tier == Tier.low) tier = Tier.medium;
  if (x.existingDebts.isNotEmpty && tier == Tier.low) tier = Tier.medium;

  return ScoreResult(amount: _floor10k(amount), tier: tier, warnings: warnings);
}
