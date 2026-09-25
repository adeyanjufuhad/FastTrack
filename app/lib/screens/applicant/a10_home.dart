import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../utils/money.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/chips.dart';

/// A10 — the status of the one application. No feed, no upsell.
class ApplicationHomeScreen extends StatefulWidget {
  const ApplicationHomeScreen({super.key});

  @override
  State<ApplicationHomeScreen> createState() => _ApplicationHomeScreenState();
}

class _ApplicationHomeScreenState extends State<ApplicationHomeScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await context.appRead.ensureApplicant();
      if (mounted) await context.appRead.refreshApplication();
    } catch (e) {
      if (mounted) context.toast('Could not refresh: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  (String, String) _copy(ApplicationStatus s) => switch (s) {
    ApplicationStatus.draft => ('Application in progress', 'Pick up where you left off.'),
    ApplicationStatus.submitted => ('Submitted', 'We are preparing your file.'),
    ApplicationStatus.scored => ('With a specialist', 'Your scored file is in the review queue.'),
    ApplicationStatus.inReview => ('In review', 'A specialist is reading your file now.'),
    ApplicationStatus.moreInfo => ('More information needed', 'A specialist will contact you about the next step.'),
    ApplicationStatus.approved => ('Approved to offer', 'A specialist will send your offer letter and documentation.'),
    ApplicationStatus.declined => ('Not approved this time', 'A specialist will explain the reason and what could change it.'),
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final a = app.application;
    final e = app.eligibility;

    return ApplicantFrame(
      title: 'My application',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refreshing ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () async {
            await app.signOut();
            if (context.mounted) context.go('/');
          },
          icon: const Icon(Icons.logout),
        ),
      ],
      child: a == null
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusChip(a.status, applicantFacing: true),
                          const Spacer(),
                          if (a.status != ApplicationStatus.draft)
                            Text(reference(a.id), style: t.labelLarge?.copyWith(color: FT.navy, letterSpacing: 1)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(_copy(a.status).$1, style: t.headlineSmall),
                      const SizedBox(height: 6),
                      Text(_copy(a.status).$2, style: t.bodyMedium?.copyWith(height: 1.5)),
                      if (e?.amount != null) ...[
                        const Divider(height: 32),
                        Text('Pre-qualified', style: t.bodySmall),
                        const SizedBox(height: 4),
                        Text('Up to ${ngn(e!.amount!)}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        TierChip(e.tier, applicantFacing: true, dense: true),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (a.status == ApplicationStatus.draft)
                  FilledButton(
                    onPressed: () => context.go('/details'),
                    child: const Text('Continue application'),
                  )
                else if (a.status == ApplicationStatus.moreInfo && e == null)
                  FilledButton(
                    onPressed: () => context.go('/documents'),
                    child: const Text('Update documents'),
                  )
                else if (a.status == ApplicationStatus.submitted)
                  FilledButton(
                    onPressed: () => context.go('/processing'),
                    child: const Text('Finish scoring'),
                  )
                else if (e != null)
                  OutlinedButton(
                    onPressed: () => context.go('/result'),
                    child: const Text('View pre-qualification'),
                  ),
                const SizedBox(height: 20),
                _Timeline(status: a.status),
              ],
            ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});
  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final order = [
      ApplicationStatus.draft,
      ApplicationStatus.submitted,
      ApplicationStatus.scored,
      ApplicationStatus.inReview,
    ];
    final decided = {
      ApplicationStatus.approved,
      ApplicationStatus.declined,
      ApplicationStatus.moreInfo,
    }.contains(status);
    final reached = decided ? order.length : order.indexOf(status) + 1;
    final labels = ['Details', 'Submitted', 'Scored', 'Specialist review', decided ? status.label : 'Decision'];

    return SectionCard(
      title: 'Progress',
      child: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    i < reached || (i == labels.length - 1 && decided)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: i < reached || (i == labels.length - 1 && decided) ? FT.blue : FT.line,
                  ),
                  const SizedBox(width: 12),
                  Text(labels[i], style: t.bodyMedium?.copyWith(color: FT.navy)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
