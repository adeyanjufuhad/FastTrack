import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/brand.dart';

/// A1 — wordmark, one sentence, Get started.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final pad = fluid(context, 20, 64);
    final wide = context.isWide;

    final copy = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: FT.sky, borderRadius: BorderRadius.circular(999)),
          child: Text(
            'DIGITAL ONBOARDING · INSTANT PRE-QUALIFICATION',
            textAlign: TextAlign.center,
            style: t.labelSmall?.copyWith(color: FT.blueDeep, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
        ),
        SizedBox(height: fluid(context, 18, 26)),
        Text(
          'Built for investment\nand lending desks.',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: t.headlineLarge?.copyWith(fontSize: fluid(context, 34, 60), height: 1.05),
        ),
        SizedBox(height: fluid(context, 14, 20)),
        Text(
          'Onboarding + scored loan files. Human still approves.',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: t.titleMedium?.copyWith(color: FT.blue, fontWeight: FontWeight.w600, fontSize: fluid(context, 16, 20)),
        ),
        const SizedBox(height: 10),
        Text(
          'Five minutes from details to a pre-qualified amount — no PDF, no printer.',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: t.bodyLarge?.copyWith(height: 1.5),
        ),
        SizedBox(height: fluid(context, 24, 36)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => context.go(app.signedIn ? (app.isOfficer ? '/officer' : '/home') : '/role'),
              icon: const Icon(Icons.arrow_forward_rounded),
              iconAlignment: IconAlignment.end,
              label: Text(app.signedIn ? 'Continue' : 'Get started'),
            ),
            if (!app.signedIn)
              OutlinedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('I have an account'),
              ),
          ],
        ),
        if (app.repo.isDemo) ...[
          const SizedBox(height: 20),
          Text(
            'Offline demo build · seed data only',
            style: t.bodySmall?.copyWith(color: FT.muted),
          ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: FT.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: fluid(context, 20, 36)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: Wordmark(size: fluid(context, 22, 28))),
                    SizedBox(height: fluid(context, 40, 72)),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: wide
                            ? Row(
                                children: [
                                  Expanded(flex: 6, child: copy),
                                  const SizedBox(width: 48),
                                  const Expanded(flex: 5, child: Center(child: ResultPreview())),
                                ],
                              )
                            : Column(
                                children: [
                                  copy,
                                  const SizedBox(height: 44),
                                  const ResultPreview(),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone-and-result motif from the brand illustration.
class ResultPreview extends StatelessWidget {
  const ResultPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: FT.navy,
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(color: FT.blue.withValues(alpha: 0.18), blurRadius: 60, offset: const Offset(0, 30)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        decoration: BoxDecoration(color: FT.mist, borderRadius: BorderRadius.circular(34)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 70,
                height: 6,
                decoration: BoxDecoration(color: FT.line, borderRadius: BorderRadius.circular(9)),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: IconWell(Icons.request_quote_outlined, size: 60)),
                    const SizedBox(height: 10),
                    Center(child: Text('Pre-qualification result', style: t.bodyMedium)),
                    const Divider(height: 28),
                    Text('Amount', style: t.bodySmall),
                    const SizedBox(height: 4),
                    Text('Up to NGN 1,240,000',
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 21)),
                    const Divider(height: 28),
                    Text('Tier', style: t.bodySmall),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: FT.blue, borderRadius: BorderRadius.circular(999)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user, color: FT.white, size: 16),
                          SizedBox(width: 6),
                          Text('Elevated review',
                              style: TextStyle(color: FT.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: FT.blue),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Specialist reviews this file', style: t.bodyMedium?.copyWith(color: FT.navy))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
