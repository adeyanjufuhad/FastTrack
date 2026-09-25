import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../models/extract.dart';
import '../../scoring/narrative.dart';
import '../../scoring/score_engine.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../utils/money.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/chips.dart';
import '../../widgets/disclaimer.dart';

/// A9 — "Up to NGN X", tier in words, four-line summary, reference,
/// disclaimer and the amber sandbox chip. Amount must equal O2.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final e = app.eligibility;
    final a = app.application;

    if (e == null || a == null) {
      return ApplicantFrame(
        title: 'Scoring pending',
        subtitle: 'Your file has not been scored yet.',
        child: FilledButton(onPressed: () => context.go('/processing'), child: const Text('Score my file')),
      );
    }

    final blocked = e.amount == null;
    final summary = applicantSummary(
      e.extract ?? const Extract(monthlyIncomeEst: 0, regularity: Regularity.insufficientHistory, confidence: 0),
      ScoreResult(amount: e.amount, tier: e.tier ?? Tier.high, warnings: e.warnings, blocked: blocked),
    );

    final wide = context.isWide;
    final card = SectionCard(
            padding: EdgeInsets.all(fluid(context, 20, 28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: IconWell(blocked ? Icons.badge_outlined : Icons.request_quote_outlined, size: 72)),
                const SizedBox(height: 12),
                Center(child: Text('Pre-qualification result', style: t.bodyLarge)),
                const Divider(height: 36),
                if (blocked) ...[
                  Text('We need to confirm your identity', style: t.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your BVN / NIN did not match our records, so we cannot show an amount yet. '
                    'Your application is saved and a specialist will be in touch.',
                    style: t.bodyMedium?.copyWith(height: 1.5),
                  ),
                ] else ...[
                  Text('Amount', style: t.bodySmall),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Up to ${ngn(e.amount!)}',
                      style: t.headlineLarge?.copyWith(fontSize: fluid(context, 30, 40)),
                    ),
                  ),
                  Text('Over ${a.tenorMonths} months', style: t.bodySmall),
                  const Divider(height: 32),
                  Text('Review tier', style: t.bodySmall),
                  const SizedBox(height: 8),
                  TierChip(e.tier, applicantFacing: true),
                ],
                const Divider(height: 32),
                for (final line in summary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_outline, size: 18, color: FT.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(line, style: t.bodyMedium?.copyWith(color: FT.navy))),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: FT.mist, borderRadius: BorderRadius.circular(FT.radiusSm)),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('Reference', style: t.bodySmall),
                      SelectableText(
                        reference(a.id),
                        style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    // The amber chip and disclaimer must be visible without scrolling on a
    // 1366×768 pitch screen: beside the result when wide, above it on phones.
    return ApplicantFrame(
      maxWidth: wide ? 980 : 560,
      bottom: FilledButton(
        onPressed: () => context.go('/home'),
        child: const Text('Go to my application'),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: card),
                const SizedBox(width: 20),
                const Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [SandboxChip(), SizedBox(height: 12), DisclaimerCard(applicantDisclaimer)],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SandboxChip(),
                const SizedBox(height: 12),
                card,
                const SizedBox(height: 12),
                const DisclaimerCard(applicantDisclaimer),
              ],
            ),
    );
  }
}
