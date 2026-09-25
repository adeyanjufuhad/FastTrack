// Offline stand-in for the Gemini extract, used only in demo mode for SMS
// that is not a seed fixture. It is deliberately conservative: it never
// invents rows, and it reports low confidence so the rules engine haircuts.

import '../models/extract.dart';

const _lenderWords = [
  'CARBON', 'PALMPAY', 'FAIRMONEY', 'BRANCH', 'RENMONEY', 'EASYCREDIT',
  'LOAN', 'REPAY',
];

/// Returns null when the text is unreadable (caller sets more_info).
Extract? extractFromSms(String raw) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final amountRe = RegExp(r'(?:NGN|N)\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
  final monthRe = RegExp(r'\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\b', caseSensitive: false);

  var credits = 0;
  final months = <String>{};
  final monthlyCredits = <String, int>{};
  final lenders = <String, List<int>>{};
  var reversals = false;
  var parsed = 0;

  for (final line in lines) {
    final m = amountRe.firstMatch(line);
    if (m == null) continue;
    final amount = double.tryParse(m.group(1)!.replaceAll(',', ''))?.round();
    if (amount == null) continue;
    parsed++;
    final up = line.toUpperCase();
    final month = monthRe.firstMatch(up)?.group(1) ?? '?';
    months.add(month);
    if (up.contains('REVERSAL')) reversals = true;

    if (up.contains('CREDIT') || up.contains(' CR ')) {
      credits += amount;
      monthlyCredits[month] = (monthlyCredits[month] ?? 0) + amount;
    } else if (up.contains('DEBIT') || up.contains(' DR ')) {
      final hit = _lenderWords.where(up.contains).toList();
      if (hit.isNotEmpty) {
        final name = hit.firstWhere(
          (w) => w != 'LOAN' && w != 'REPAY',
          orElse: () => 'unknown lender',
        );
        final label = name == 'unknown lender'
            ? name
            : name[0] + name.substring(1).toLowerCase();
        lenders.putIfAbsent(label, () => []).add(amount);
      }
    }
  }

  if (parsed < 3 || credits == 0) return null;

  final monthCount = months.where((m) => m != '?').length.clamp(1, 12);
  final income = credits ~/ monthCount;
  final perMonth = monthlyCredits.values.toList();
  final minM = perMonth.reduce((a, b) => a < b ? a : b);
  final maxM = perMonth.reduce((a, b) => a > b ? a : b);
  final regularity = monthCount < 2
      ? 'insufficient_history'
      : (maxM - minM) / (maxM == 0 ? 1 : maxM) < 0.15
          ? 'stable'
          : 'lumpy';

  return Extract.fromJson({
    'monthly_income_est': income,
    'income_regularity': regularity,
    'inflow_months_observed': monthCount,
    'top_spend_categories': <Map<String, dynamic>>[],
    'existing_loan_debits': [
      for (final e in lenders.entries)
        {'label': e.key, 'monthly_avg': e.value.reduce((a, b) => a + b) ~/ monthCount},
    ],
    'overdraft_or_reversals': reversals,
    'average_balance_proxy': null,
    // The offline parser is a heuristic, not a model: stay under 0.45 so the
    // rules engine applies the low-confidence haircut and floors the tier.
    'confidence': 0.4,
    'warnings': ['offline_heuristic_extract'],
  });
}
