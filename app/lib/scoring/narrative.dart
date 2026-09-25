// Stage B fallback. In production the officer narrative comes from Gemini
// (supabase/functions/process-application). Offline demo mode — and the Edge
// Function when Gemini is down — uses this template. It only restates facts
// from the extract and the amount the rules produced; it never computes one.

import '../models/enums.dart';
import '../models/extract.dart';
import '../utils/money.dart';
import 'score_engine.dart';

String officerNarrative(Extract x, ScoreResult r, {required ApplicantRole role}) {
  if (r.blocked) {
    return 'Identity could not be confirmed against the sandbox register, so '
        'the rules engine has not produced an amount. The statement extract is '
        'retained for reference but should not be relied on until identity is '
        'resolved. Recommended next action: request a clear government ID and '
        're-run the identity check.';
  }

  final who = role == ApplicantRole.corporate ? "The business's" : "The applicant's";
  final s = <String>[];

  final income = ngn(x.monthlyIncomeEst);
  final months = x.inflowMonthsObserved ?? 0;
  final seen = months > 0 ? ' across $months observed months' : '';
  s.add(switch (x.regularity) {
    Regularity.stable => '$who income is regular at about $income a month$seen.',
    Regularity.lumpy => '$who inflows are lumpy, averaging about $income a month$seen.',
    Regularity.seasonal => '$who inflows are seasonal, averaging about $income a month$seen.',
    Regularity.insufficientHistory =>
      '$who statement shows too little history to establish a reliable income pattern.',
  });

  if (x.existingLoanDebits.isEmpty) {
    s.add('No repayments to other lenders were detected.');
  } else {
    final names = x.existingLoanDebits
        .map((d) => '${d.label} (${ngn(d.monthlyAvg)} a month)')
        .join(', ');
    s.add('Repayment debits to other lenders were detected: $names.');
  }

  if (x.topSpendCategories.isNotEmpty) {
    final top = x.topSpendCategories.first;
    s.add('The largest spend category is ${top.category.replaceAll('_', ' ')} '
        'at about ${ngn(top.monthlyAvg)} a month.');
  }

  s.add(x.overdraftOrReversals
      ? 'The statement shows reversals, which reduce confidence in cash flow.'
      : 'No overdraft or reversal pattern was observed.');

  s.add('The rules engine pre-qualifies ${ngn(r.amount ?? 0)} at '
      '${r.tier.label.toLowerCase()} risk, with extraction confidence of '
      '${(x.confidence * 100).round()}%.');

  s.add('Recommended next action: ${switch (r.tier) {
    Tier.low => 'approve into an offer letter subject to standard documentation.',
    Tier.medium => x.existingLoanDebits.isNotEmpty
        ? 'confirm the external repayment and a landlord or employer reference, then move to offer letter.'
        : 'confirm one income reference, then move to offer letter.',
    Tier.high => 'request a six-month statement before any offer.',
  }}');

  return s.join(' ');
}

/// A9 shows a short applicant-facing summary, never a second score.
List<String> applicantSummary(Extract x, ScoreResult r) {
  if (r.blocked) {
    return const [
      'We need to confirm your identity before we can show an amount.',
      'Your application has been saved.',
      'A specialist will contact you about the next step.',
    ];
  }
  return [
    switch (x.regularity) {
      Regularity.stable => 'Your income looks regular.',
      Regularity.lumpy || Regularity.seasonal => 'Your income varies month to month.',
      Regularity.insufficientHistory => 'We saw limited account history.',
    },
    x.existingLoanDebits.isEmpty
        ? 'We did not see repayments to other lenders.'
        : 'We noticed repayments to ${x.existingLoanDebits.length == 1 ? 'another lender' : '${x.existingLoanDebits.length} other lenders'}.',
    'Your file is ready for a specialist to review.',
    'You will see the decision on your application page.',
  ];
}
