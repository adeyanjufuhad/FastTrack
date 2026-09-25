import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../models/records.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../utils/money.dart';
import '../../widgets/chips.dart';
import '../../widgets/reset_demo.dart';
import 'officer_shell.dart';

String submittedAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// O1 — queue table: name, role, tier, amount, submitted, status.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<ApplicationFile>? _rows;
  String? _error;
  ApplicationStatus? _filter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await context.appRead.repo.queue();
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<ApplicationFile> get _visible => (_rows ?? const [])
      .where((r) => _filter == null || r.application.status == _filter)
      .where((r) => _query.isEmpty || r.applicant.displayName.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  Future<void> _open(ApplicationFile f) async {
    await context.push('/officer/applications/${f.application.id}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = _rows;
    int count(Set<ApplicationStatus> s) => rows?.where((r) => s.contains(r.application.status)).length ?? 0;

    return OfficerShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Application queue', style: t.headlineMedium?.copyWith(fontSize: fluid(context, 22, 30))),
                    const SizedBox(height: 4),
                    Text('What arrived, scored and ready for a decision.', style: t.bodyMedium),
                  ],
                ),
              ),
              if (context.app.repo.isDemo) ...[
                IconButton(
                  tooltip: 'Reset demo data',
                  onPressed: () => confirmResetDemo(context, then: '/officer/login'),
                  icon: const Icon(Icons.restart_alt),
                ),
                const SizedBox(width: 4),
              ],
              IconButton.filledTonal(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 900 ? 4 : 2;
              final w = (box.maxWidth - 14 * (cols - 1)) / cols;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _Stat(w, 'In queue', '${rows?.length ?? '–'}', Icons.inbox_outlined),
                  _Stat(w, 'New', '${count({ApplicationStatus.scored})}', Icons.fiber_new_outlined),
                  _Stat(w, 'In review / more info', '${count({ApplicationStatus.inReview, ApplicationStatus.moreInfo})}', Icons.visibility_outlined),
                  _Stat(w, 'Decided', '${count({ApplicationStatus.approved, ApplicationStatus.declined})}', Icons.task_alt),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in <ApplicationStatus?>[
                null,
                ApplicationStatus.scored,
                ApplicationStatus.inReview,
                ApplicationStatus.moreInfo,
                ApplicationStatus.approved,
                ApplicationStatus.declined,
              ])
                ChoiceChip(
                  label: Text(f?.label ?? 'All'),
                  selected: _filter == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              SizedBox(
                width: context.isCompact ? double.infinity : 260,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search by name',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(child: Padding(padding: const EdgeInsets.all(20), child: Text('Could not load the queue: $_error')))
          else if (rows == null)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (_visible.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No applications match.'))))
          else if (context.width >= 860)
            _Table(rows: _visible, onOpen: _open)
          else
            Column(
              children: [
                for (final r in _visible)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: _QueueCard(file: r, onOpen: () => _open(r))),
              ],
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.width, this.label, this.value, this.icon);
  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final iconBox = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: FT.sky, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: FT.blue, size: 22),
    );
    final figures = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
    // Narrow tiles stack icon over figures so labels never truncate.
    final stacked = width < 220;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(stacked ? 14 : 18),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [iconBox, const SizedBox(height: 10), figures],
                )
              : Row(children: [iconBox, const SizedBox(width: 14), Expanded(child: figures)]),
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.onOpen});
  final List<ApplicationFile> rows;
  final ValueChanged<ApplicationFile> onOpen;

  static const _flex = [5, 2, 2, 3, 2, 2];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final head = t.labelSmall?.copyWith(color: FT.muted, fontWeight: FontWeight.w800, letterSpacing: 0.8);

    Widget cells(List<Widget> c) => Row(
      children: [for (var i = 0; i < c.length; i++) Expanded(flex: _flex[i], child: c[i])],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: FT.mist,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: cells([
              Text('APPLICANT', style: head),
              Text('ROLE', style: head),
              Text('TIER', style: head),
              Text('PRE-QUALIFIED', style: head),
              Text('SUBMITTED', style: head),
              Text('STATUS', style: head),
            ]),
          ),
          for (final r in rows) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => onOpen(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: cells([
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: FT.sky,
                        child: Text(
                          r.applicant.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(color: FT.navy, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.applicant.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
                            Text(reference(r.application.id), style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(r.applicant.role == ApplicantRole.corporate ? 'Corporate' : 'Individual', style: t.bodyMedium),
                  Align(alignment: Alignment.centerLeft, child: TierChip(r.eligibility?.tier, dense: true)),
                  Text(
                    r.eligibility?.amount == null ? '—' : ngn(r.eligibility!.amount!),
                    style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w800),
                  ),
                  Text(submittedAgo(r.application.createdAt), style: t.bodyMedium),
                  Align(alignment: Alignment.centerLeft, child: StatusChip(r.application.status, dense: true)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.file, required this.onOpen});
  final ApplicationFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = file.eligibility;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(file.applicant.displayName,
                        style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  StatusChip(file.application.status, dense: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${file.applicant.role == ApplicantRole.corporate ? 'Corporate' : 'Individual'} · '
                '${reference(file.application.id)} · ${submittedAgo(file.application.createdAt)}',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(e?.amount == null ? '—' : ngn(e!.amount!),
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  TierChip(e?.tier, dense: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
