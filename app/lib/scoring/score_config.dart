// Every scoring constant lives in this one file (docs/scoring-engine.md).
// Product will change the multiplier during rehearsals — change it here only.
// The Edge Function mirror is supabase/functions/_shared/score.ts.

class ScoreConfig {
  const ScoreConfig({
    this.incomeMultiplierAnnualFactor = 3,
    this.capAsMonthsOfIncome = 6,
    this.lumpyHaircut = 0.70,
    this.insufficientHaircut = 0.40,
    this.reversalHaircut = 0.75,
    this.lowConfidenceHaircut = 0.80,
    this.debtIncomeDeduction = 0.30,
    this.stackingLenderThreshold = 3,
    this.lowConfidenceCutoff = 0.45,
    this.manualReviewFloor = 50000,
    this.roundDownTo = 10000,
    this.holdingsSleeveRate = 0.30,
    this.holdingsSleeveEnabled = false,
  });

  final num incomeMultiplierAnnualFactor;
  final int capAsMonthsOfIncome;
  final double lumpyHaircut;
  final double insufficientHaircut;
  final double reversalHaircut;
  final double lowConfidenceHaircut;
  final double debtIncomeDeduction;
  final int stackingLenderThreshold;
  final double lowConfidenceCutoff;
  final int manualReviewFloor;
  final int roundDownTo;
  final double holdingsSleeveRate;
  final bool holdingsSleeveEnabled;
}

const defaultScoreConfig = ScoreConfig();
