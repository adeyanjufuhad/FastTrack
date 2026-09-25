import 'package:fasttrack/data/fixtures.dart';
import 'package:fasttrack/data/local_extractor.dart';
import 'package:fasttrack/models/enums.dart';
import 'package:fasttrack/models/extract.dart';
import 'package:fasttrack/scoring/narrative.dart';
import 'package:fasttrack/scoring/score_config.dart';
import 'package:fasttrack/scoring/score_engine.dart';
import 'package:fasttrack/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

// Test vectors are locked in fixtures/expected_scores.json and
// docs/scoring-engine.md. If these fail, product changed the policy —
// update the fixtures on purpose, never silently.

Extract fixture(String key) => Extract.fromJson(extractFixtures[key]!);

void main() {
  group('worked examples', () {
    test('Adaeze → NGN 1,240,000 · medium', () {
      final r = score(fixture('fixture:adaeze-sms'), kyc: KycResult.sandboxPass);
      expect(r.amount, 1240000);
      expect(r.tier, Tier.medium);
      expect(r.warnings, contains(Warnings.externalLender));
      expect(r.blocked, isFalse);
    });

    test('Ibrahim → NGN 410,000 · high', () {
      final r = score(fixture('fixture:ibrahim-sms'), kyc: KycResult.sandboxPass);
      expect(r.amount, 410000);
      expect(r.tier, Tier.high);
      expect(r.warnings, containsAll([Warnings.irregularIncome, Warnings.reversals]));
    });

    test('Northshore → rules on 1,800,000 lumpy · medium', () {
      final r = score(fixture('fixture:northshore-sms'), kyc: KycResult.sandboxPass);
      // 1.8m × 3 = 5.4m (under the 10.8m cap) × 0.70 lumpy = 3.78m
      expect(r.amount, 3780000);
      expect(r.tier, Tier.medium);
    });

    test('deterministic: same extract in, same amount out', () {
      final a = score(fixture('fixture:adaeze-sms'), kyc: KycResult.sandboxPass);
      final b = score(fixture('fixture:adaeze-sms'), kyc: KycResult.sandboxPass);
      expect(a.amount, b.amount);
      expect(a.tier, b.tier);
    });
  });

  group('rules', () {
    test('KYC mismatch or fail → no amount', () {
      for (final k in [KycResult.mismatch, KycResult.sandboxFail, null]) {
        final r = score(fixture('fixture:adaeze-sms'), kyc: k);
        expect(r.blocked, isTrue);
        expect(r.amount, isNull);
        expect(r.warnings, [Warnings.kycMismatch]);
      }
    });

    test('stable salary, no flags → low', () {
      const x = Extract(monthlyIncomeEst: 500000, regularity: Regularity.stable, confidence: 0.9);
      final r = score(x, kyc: KycResult.sandboxPass);
      expect(r.tier, Tier.low);
      expect(r.amount, 1500000);
    });

    test('cap at 6 × monthly income on long tenor', () {
      const x = Extract(monthlyIncomeEst: 100000, regularity: Regularity.stable, confidence: 0.9);
      final r = score(x, kyc: KycResult.sandboxPass, tenorMonths: 24);
      expect(r.amount, 600000); // base 600k == cap 600k
      final r36 = score(x, kyc: KycResult.sandboxPass, tenorMonths: 36);
      expect(r36.amount, 600000); // base 900k capped
    });

    test('low confidence haircuts 20% and floors medium', () {
      const x = Extract(monthlyIncomeEst: 500000, regularity: Regularity.stable, confidence: 0.3);
      final r = score(x, kyc: KycResult.sandboxPass);
      expect(r.amount, 1200000);
      expect(r.tier, Tier.medium);
      expect(r.warnings, contains(Warnings.lowConfidence));
    });

    test('three lenders → high + stacking warning', () {
      const x = Extract(
        monthlyIncomeEst: 400000,
        regularity: Regularity.stable,
        confidence: 0.8,
        existingLoanDebits: [LoanDebit('Carbon', 10000), LoanDebit('Palmpay', 10000), LoanDebit('Branch', 10000)],
      );
      final r = score(x, kyc: KycResult.sandboxPass);
      expect(r.tier, Tier.high);
      expect(r.warnings, contains(Warnings.stacking));
    });

    test('insufficient history → 40% haircut, high', () {
      const x = Extract(monthlyIncomeEst: 200000, regularity: Regularity.insufficientHistory, confidence: 0.7);
      final r = score(x, kyc: KycResult.sandboxPass);
      expect(r.amount, 240000);
      expect(r.tier, Tier.high);
    });

    test('tiny amounts go to manual review', () {
      const x = Extract(monthlyIncomeEst: 12000, regularity: Regularity.stable, confidence: 0.9);
      final r = score(x, kyc: KycResult.sandboxPass);
      expect(r.amount, lessThan(50000));
      expect(r.tier, Tier.high);
      expect(r.warnings, contains(Warnings.manualReview));
    });

    test('holdings sleeve only when enabled', () {
      const x = Extract(monthlyIncomeEst: 600000, regularity: Regularity.stable, confidence: 0.9);
      final off = score(x, kyc: KycResult.sandboxPass, holdingsNgn: 8000000);
      expect(off.amount, 1800000);
      final on = score(
        x,
        kyc: KycResult.sandboxPass,
        holdingsNgn: 8000000,
        cfg: const ScoreConfig(holdingsSleeveEnabled: true),
      );
      // + min(30% × 8m = 2.4m, base 1.8m) = 3.6m
      expect(on.amount, 3600000);
      expect(on.tier, Tier.low);
    });
  });

  group('supporting pieces', () {
    test('seed SMS maps to its fixture', () {
      expect(fixtureKeyFor(smsAdaeze), 'fixture:adaeze-sms');
      expect(fixtureKeyFor('  $smsIbrahim\n'), 'fixture:ibrahim-sms');
      expect(fixtureKeyFor('hello'), isNull);
    });

    test('offline extractor is conservative', () {
      final x = extractFromSms(smsAdaeze)!;
      expect(x.confidence, lessThan(0.45));
      expect(x.existingLoanDebits.single.label, 'Carbon');
      expect(extractFromSms('not an alert'), isNull);
    });

    test('narrative restates the rules amount and ends with a next action', () {
      final x = fixture('fixture:adaeze-sms');
      final r = score(x, kyc: KycResult.sandboxPass);
      final n = officerNarrative(x, r, role: ApplicantRole.individual);
      expect(n, contains('NGN 1,240,000'));
      expect(n, contains('Recommended next action'));
      final words = n.split(RegExp(r'\s+')).length;
      expect(words, inInclusiveRange(60, 160));
    });

    test('money formatting', () {
      expect(ngn(1240000), 'NGN 1,240,000');
      expect(maskId('22222222222'), '*******2222');
      expect(reference('3f2a9c1e-0000-4000-8000-000000000000'), 'FT-3F2A9C1E');
    });
  });
}
