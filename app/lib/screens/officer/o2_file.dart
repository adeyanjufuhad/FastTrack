import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/enums.dart';
import '../../models/records.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../utils/money.dart';
import '../../widgets/chips.dart';
import '../../widgets/disclaimer.dart';
import 'o1_queue.dart' show submittedAgo;
import 'officer_shell.dart';

/// O2 — left: documents + extract. Right: score, narrative, notes, decision.
class OfficerFileScreen extends StatefulWidget {
  const OfficerFileScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  State<OfficerFileScreen> createState() => _OfficerFileScreenState();
}

class _OfficerFileScreenState extends State<OfficerFileScreen> {
  ApplicationFile? _file;
  bool _loading = true;
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(markOpened: true));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool markOpened = false}) async {
    final repo = context.appRead.repo;
    try {
      var f = await repo.file(widget.applicationId);
      // Opening a new scored file moves it to "In review".
      if (markOpened && f != null && f.application.status == ApplicationStatus.scored) {
        await repo.decide(f.application.id, ApplicationStatus.inReview);
        f = await repo.file(widget.applicationId);
      }
      if (mounted) {
        setState(() {
          _file = f;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.toast('Could not load file: $e');
      }
    }
  }

  Future<void> _decide(ApplicationStatus s) async {
    final note = _note.text.trim();
    setState(() => _busy = true);
    try {
      final repo = context.appRead.repo;
      if (note.isNotEmpty) await repo.addNote(widget.applicationId, note);
      await repo.decide(widget.applicationId, s);
      _note.clear();
      await _load();
      if (mounted) context.toast('Marked ${s.label.toLowerCase()}');
    } catch (e) {
      if (mounted) context.toast('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addNote() async {
    final note = _note.text.trim();
    if (note.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.appRead.repo.addNote(widget.applicationId, note);
      _note.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final back = IconButton(
      tooltip: 'Back to queue',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => context.canPop() ? context.pop() : context.go('/officer'),
    );
    final f = _file;
    if (_loading) {
      return OfficerShell(leading: back, child: const Padding(padding: EdgeInsets.all(64), child: Center(child: CircularProgressIndicator())));
    }
    if (f == null) {
      return OfficerShell(leading: back, child: const Card(child: Padding(padding: EdgeInsets.all(32), child: Text('Application not found.'))));
    }

    final t = Theme.of(context).textTheme;
    final left = [_DocumentsCard(f), const SizedBox(height: 16), _ExtractCard(f)];
    final right = [
      _ScoreCard(f),
      const SizedBox(height: 16),
      _NarrativeCard(f),
      const SizedBox(height: 16),
      _DecisionCard(
        file: f,
        note: _note,
        busy: _busy,
        onDecide: _decide,
        onAddNote: _addNote,
      ),
    ];

    return OfficerShell(
      leading: back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(f.applicant.displayName, style: t.headlineMedium?.copyWith(fontSize: fluid(context, 22, 30))),
              StatusChip(f.application.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${f.applicant.role == ApplicantRole.corporate ? 'Corporate' : 'Individual'} · '
            '${reference(f.application.id)} · ${f.application.tenorMonths}-month tenor · '
            'submitted ${submittedAgo(f.application.createdAt)}'
            '${f.application.purpose == null || f.application.purpose!.isEmpty ? '' : ' · ${f.application.purpose}'}',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          const DisclaimerCard(officerDisclaimer),
          const SizedBox(height: 20),
          if (context.width >= 1000)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 20),
                Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...right, const SizedBox(height: 16), ...left],
            ),
          const SizedBox(height: 24),
          Text(officerFooterLine, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: FT.muted)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: FT.blueDeep,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard(this.f);
  final ApplicationFile f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = f.eligibility;
    final kyc = f.applicant.kycResult;
    return _Panel(
      title: 'Rules-engine result',
      child: e == null
          ? Text('Scoring pending or failed.', style: t.titleMedium)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      e.amount == null ? 'No amount — identity unconfirmed' : ngn(e.amount!),
                      style: t.headlineMedium?.copyWith(fontSize: fluid(context, 24, 34)),
                    ),
                    TierChip(e.tier),
                  ],
                ),
                const SizedBox(height: 14),
                if (e.warnings.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final w in e.warnings) WarningChip(w)]),
                const Divider(height: 28),
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    _kv(t, 'KYC (sandbox)', kyc?.wire.replaceAll('_', ' ') ?? 'not run'),
                    _kv(t, 'BVN', f.applicant.bvnMasked ?? '—'),
                    _kv(t, 'NIN', f.applicant.ninMasked ?? '—'),
                    _kv(t, 'Requested', f.application.requestedAmount == null ? 'Max' : ngn(f.application.requestedAmount!)),
                    _kv(t, 'Model', e.modelVersion ?? '—'),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _kv(TextTheme t, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: t.bodySmall),
      Text(v, style: t.bodyMedium?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
    ],
  );
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard(this.f);
  final ApplicationFile f;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Officer narrative',
    child: SelectableText(
      f.eligibility?.narrative ?? 'Scoring pending or failed.',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: FT.ink, height: 1.6),
    ),
  );
}

class _ExtractCard extends StatelessWidget {
  const _ExtractCard(this.f);
  final ApplicationFile f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final x = f.eligibility?.extract;
    if (x == null) {
      return const _Panel(title: 'Statement extract', child: Text('No extract yet — scoring pending or failed.'));
    }

    Widget row(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(k, style: t.bodyMedium)),
          Text(v, style: t.bodyMedium?.copyWith(color: FT.navy, fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );

    return _Panel(
      title: 'Statement extract',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Monthly income (est.)', ngn(x.monthlyIncomeEst), strong: true),
          const Divider(),
          row('Income regularity', x.regularity.wire.replaceAll('_', ' ')),
          const Divider(),
          row('Months observed', '${x.inflowMonthsObserved ?? '—'}'),
          const Divider(),
          row('Average balance', x.averageBalanceProxy == null ? '—' : ngn(x.averageBalanceProxy!)),
          const Divider(),
          row('Overdraft / reversals', x.overdraftOrReversals ? 'Yes' : 'No'),
          const Divider(),
          row('Model confidence', '${(x.confidence * 100).round()}%'),
          if (x.existingLoanDebits.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Other lenders', style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
            for (final d in x.existingLoanDebits) row(d.label, '${ngn(d.monthlyAvg)} / mo'),
          ],
          if (x.topSpendCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Top spend', style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
            for (final c in x.topSpendCategories)
              row(c.category.replaceAll('_', ' '), '${ngn(c.monthlyAvg)} · ${(c.shareOfOutflow * 100).round()}%'),
          ],
        ],
      ),
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard(this.f);
  final ApplicationFile f;

  Future<void> _open(BuildContext context, DocumentRecord d) async {
    // In-memory images (demo mode, just-uploaded) preview in place.
    if (d.data != null && d.isImage) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(d.kind.label),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Flexible(child: InteractiveViewer(child: Image.memory(d.data!))),
            ],
          ),
        ),
      );
      return;
    }
    final url = await context.appRead.repo.signedUrl(d);
    if (url == null) {
      if (context.mounted) context.toast('Seed document — no file attached in demo mode.');
      return;
    }
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Panel(
      title: 'Documents',
      child: f.documents.isEmpty && f.application.smsText == null
          ? const Text('No documents uploaded.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in f.documents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox.square(
                        dimension: 44,
                        child: d.data != null && d.isImage
                            ? Image.memory(d.data!, fit: BoxFit.cover)
                            : Container(
                                color: FT.sky,
                                child: Icon(d.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined, color: FT.blue),
                              ),
                      ),
                    ),
                    title: Text(d.kind.label, style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
                    subtitle: Text('${d.name} · ${(d.bytes / 1024).round()} KB', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(onPressed: () => _open(context, d), child: const Text('Open')),
                  ),
                if (f.application.smsText != null && f.application.smsText!.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: FT.sky, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.sms_outlined, color: FT.blue),
                    ),
                    title: Text('Pasted SMS alerts', style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
                    subtitle: Text('${f.application.smsText!.split('\n').length} lines'),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: FT.mist, borderRadius: BorderRadius.circular(8)),
                        child: SelectableText(
                          f.application.smsText!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.file,
    required this.note,
    required this.busy,
    required this.onDecide,
    required this.onAddNote,
  });

  final ApplicationFile file;
  final TextEditingController note;
  final bool busy;
  final ValueChanged<ApplicationStatus> onDecide;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String stamp(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    ButtonStyle tone(Color c) => FilledButton.styleFrom(backgroundColor: c, minimumSize: const Size(0, 48));

    return _Panel(
      title: 'Notes & decision',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in file.notes)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: FT.mist, borderRadius: BorderRadius.circular(FT.radiusSm)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.body, style: t.bodyMedium?.copyWith(color: FT.ink)),
                  const SizedBox(height: 4),
                  Text('${n.author ?? 'Officer'} · ${stamp(n.createdAt)}', style: t.bodySmall),
                ],
              ),
            ),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Add a note, e.g. "Confirm landlord reference"',
              suffixIcon: IconButton(
                tooltip: 'Add note',
                onPressed: busy ? null : onAddNote,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final buttons = [
                FilledButton.icon(
                  style: tone(FT.ok),
                  onPressed: busy ? null : () => onDecide(ApplicationStatus.approved),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
                FilledButton.icon(
                  style: tone(FT.navySoft),
                  onPressed: busy ? null : () => onDecide(ApplicationStatus.moreInfo),
                  icon: const Icon(Icons.help_outline_rounded),
                  label: const Text('More info'),
                ),
                FilledButton.icon(
                  style: tone(FT.danger),
                  onPressed: busy ? null : () => onDecide(ApplicationStatus.declined),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Decline'),
                ),
              ];
              if (box.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b)],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: buttons[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text('The note above is saved with your decision. The applicant sees the status on their page.',
              style: t.bodySmall),
        ],
      ),
    );
  }
}
