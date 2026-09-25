import 'enums.dart';

/// The locked Gemini extract schema (docs/gemini-prompts.md).
class SpendCategory {
  const SpendCategory(this.category, this.monthlyAvg, this.shareOfOutflow);

  final String category;
  final int monthlyAvg;
  final double shareOfOutflow;

  factory SpendCategory.fromJson(Map<String, dynamic> j) => SpendCategory(
    j['category'] as String? ?? 'other',
    (j['monthly_avg'] as num?)?.toInt() ?? 0,
    (j['share_of_outflow'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'category': category,
    'monthly_avg': monthlyAvg,
    'share_of_outflow': shareOfOutflow,
  };
}

class LoanDebit {
  const LoanDebit(this.label, this.monthlyAvg);

  final String label;
  final int monthlyAvg;

  factory LoanDebit.fromJson(Map<String, dynamic> j) => LoanDebit(
    j['label'] as String? ?? 'unknown lender',
    (j['monthly_avg'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'label': label, 'monthly_avg': monthlyAvg};
}

class Extract {
  const Extract({
    required this.monthlyIncomeEst,
    required this.regularity,
    this.inflowMonthsObserved,
    this.topSpendCategories = const [],
    this.existingLoanDebits = const [],
    this.overdraftOrReversals = false,
    this.averageBalanceProxy,
    required this.confidence,
    this.warnings = const [],
  });

  final int monthlyIncomeEst;
  final Regularity regularity;
  final int? inflowMonthsObserved;
  final List<SpendCategory> topSpendCategories;
  final List<LoanDebit> existingLoanDebits;
  final bool overdraftOrReversals;
  final int? averageBalanceProxy;
  final double confidence;
  final List<String> warnings;

  factory Extract.fromJson(Map<String, dynamic> j) => Extract(
    monthlyIncomeEst: (j['monthly_income_est'] as num?)?.toInt() ?? 0,
    regularity: Regularity.fromWire(j['income_regularity'] as String?),
    inflowMonthsObserved: (j['inflow_months_observed'] as num?)?.toInt(),
    topSpendCategories: [
      for (final c in (j['top_spend_categories'] as List? ?? const []))
        SpendCategory.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    existingLoanDebits: [
      for (final d in (j['existing_loan_debits'] as List? ?? const []))
        LoanDebit.fromJson(Map<String, dynamic>.from(d as Map)),
    ],
    overdraftOrReversals: j['overdraft_or_reversals'] as bool? ?? false,
    averageBalanceProxy: (j['average_balance_proxy'] as num?)?.toInt(),
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
    warnings: [for (final w in (j['warnings'] as List? ?? const [])) '$w'],
  );

  Map<String, dynamic> toJson() => {
    'monthly_income_est': monthlyIncomeEst,
    'income_regularity': regularity.wire,
    'inflow_months_observed': inflowMonthsObserved,
    'top_spend_categories': [for (final c in topSpendCategories) c.toJson()],
    'existing_loan_debits': [for (final d in existingLoanDebits) d.toJson()],
    'overdraft_or_reversals': overdraftOrReversals,
    'average_balance_proxy': averageBalanceProxy,
    'confidence': confidence,
    'warnings': warnings,
  };
}
