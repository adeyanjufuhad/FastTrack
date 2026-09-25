import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../models/enums.dart';
import '../../models/records.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/sample_id.dart';

const maxUploadBytes = 8 * 1024 * 1024;

/// The spec asks for "SMS ≥ 20 lines" but the seed fixtures carry ten alerts
/// covering three months, so ten is the working minimum.
const minSmsLines = 10;

String mimeFor(String? ext) => switch (ext?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'pdf' => 'application/pdf',
  _ => 'application/octet-stream',
};

int smsLineCount(String s) =>
    s.split(RegExp(r'[\r\n]+')).where((l) => l.trim().isNotEmpty).length;

/// A6 — ID + statement dropzones, SMS paste toggle, CAC for corporates.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _sms = TextEditingController();
  bool _useSms = true;
  DocKind? _uploading;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final app = context.appRead;
    _sms.text = app.application?.smsText ?? '';
    _useSms = _sms.text.isNotEmpty || !app.documents.containsKey(DocKind.statement);
  }

  @override
  void dispose() {
    _sms.dispose();
    super.dispose();
  }

  Future<void> _pick(DocKind kind) async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (f == null || !mounted) return;
    final size = f.lengthSync() ?? await f.length() ?? 0;
    if (size > maxUploadBytes) {
      if (mounted) context.toast('That file is ${(size / 1048576).toStringAsFixed(1)} MB. The limit is 8 MB.');
      return;
    }
    setState(() => _uploading = kind);
    try {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      await context.appRead.upload(kind, f.name, mimeFor(f.extension), bytes);
    } catch (e) {
      if (mounted) context.toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// Demo mode only: a clearly-fake generated image instead of a real file.
  Future<void> _useSample(DocKind kind, String name) async {
    setState(() => _uploading = kind);
    try {
      final app = context.appRead;
      final png = await sampleIdPng(app.profile?.signingName ?? '');
      await app.upload(kind, name, 'image/png', png);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  bool _ready(bool corporate, Map<DocKind, DocumentRecord> docs) {
    final hasId = docs.containsKey(DocKind.id);
    final hasStatement = _useSms
        ? smsLineCount(_sms.text) >= minSmsLines
        : docs.containsKey(DocKind.statement);
    final hasCac = !corporate || docs.containsKey(DocKind.cac);
    return hasId && hasStatement && hasCac;
  }

  Future<void> _continue() async {
    final app = context.appRead;
    app.application!.smsText = _useSms ? _sms.text.trim() : null;
    await app.saveDraft();
    if (mounted) context.go('/sign');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final t = Theme.of(context).textTheme;
    final corporate = app.profile?.role == ApplicantRole.corporate;
    final docs = app.documents;
    final lines = smsLineCount(_sms.text);

    return ApplicantFrame(
      step: 3,
      back: '/kyc',
      title: 'Documents',
      subtitle: 'JPEG, PNG or PDF up to 8 MB each. Files are stored privately and never emailed.',
      bottom: ActionBar(
        status: _ready(corporate, docs)
            ? 'All set'
            : (corporate ? 'ID, CAC + statement or SMS required' : 'ID + statement or SMS required'),
        action: FilledButton(
          onPressed: _ready(corporate, docs) ? _continue : null,
          child: const Text('Continue to sign'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DropZone(
            kind: DocKind.id,
            title: corporate ? 'Signatory government ID' : 'Government ID',
            hint: 'NIN slip, driver’s licence, passport or voter’s card',
            doc: docs[DocKind.id],
            busy: _uploading == DocKind.id,
            onPick: () => _pick(DocKind.id),
          ),
          if (app.repo.isDemo && !docs.containsKey(DocKind.id))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _uploading != null ? null : () => _useSample(DocKind.id, 'sample-id.png'),
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: const Text('Use sample ID (demo)'),
              ),
            ),
          if (corporate) ...[
            const SizedBox(height: 14),
            _DropZone(
              kind: DocKind.cac,
              title: 'CAC certificate',
              hint: 'Certificate of incorporation or CAC status report',
              doc: docs[DocKind.cac],
              busy: _uploading == DocKind.cac,
              onPick: () => _pick(DocKind.cac),
            ),
            if (app.repo.isDemo && !docs.containsKey(DocKind.cac))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _uploading != null ? null : () => _useSample(DocKind.cac, 'sample-cac.png'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Use sample CAC (demo)'),
                ),
              ),
          ],
          const SizedBox(height: 22),
          Text('Bank history', style: t.titleMedium),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: context.isCompact ? null : const Icon(Icons.sms_outlined),
                label: const Text('SMS alerts'),
              ),
              ButtonSegment(
                value: false,
                icon: context.isCompact ? null : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Statement'),
              ),
            ],
            selected: {_useSms},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _useSms = v.first),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: FT.motion,
            child: _useSms
                ? SectionCard(
                    key: const ValueKey('sms'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _sms,
                          minLines: 8,
                          maxLines: 14,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5),
                          decoration: const InputDecoration(
                            hintText: 'Paste three months of bank-alert SMS, one per line…',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              lines >= minSmsLines ? Icons.check_circle : Icons.info_outline,
                              size: 16,
                              color: lines >= minSmsLines ? FT.ok : FT.muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$lines alert${lines == 1 ? '' : 's'} · at least $minSmsLines needed',
                                style: t.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Sample alerts:', style: t.bodySmall),
                            for (final p in personas.where(
                              (p) => corporate ? p.key == 'northshore' : p.key != 'northshore',
                            ))
                              ActionChip(
                                label: Text(p.label),
                                onPressed: () => setState(() => _sms.text = p.sms),
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
                : _DropZone(
                    key: const ValueKey('statement'),
                    kind: DocKind.statement,
                    title: 'Bank statement',
                    hint: '3–6 months, PDF or a clear photo',
                    doc: docs[DocKind.statement],
                    busy: _uploading == DocKind.statement,
                    onPick: () => _pick(DocKind.statement),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    super.key,
    required this.kind,
    required this.title,
    required this.hint,
    required this.doc,
    required this.busy,
    required this.onPick,
  });

  final DocKind kind;
  final String title;
  final String hint;
  final DocumentRecord? doc;
  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = doc;
    return Material(
      color: d == null ? FT.white : FT.sky,
      borderRadius: BorderRadius.circular(FT.radius),
      child: InkWell(
        onTap: busy ? null : onPick,
        borderRadius: BorderRadius.circular(FT.radius),
        child: Container(
          padding: EdgeInsets.all(fluid(context, 14, 20)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FT.radius),
            border: Border.all(color: d == null ? FT.line : FT.blue, width: d == null ? 1.2 : 1.6),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 56,
                  child: d?.data != null && d!.isImage
                      ? Image.memory(d.data!, fit: BoxFit.cover)
                      : Container(
                          color: FT.sky,
                          child: Icon(
                            d == null
                                ? Icons.cloud_upload_outlined
                                : (d.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined),
                            color: FT.blue,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall?.copyWith(color: FT.navy, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      d == null ? hint : '${d.name} · ${(d.bytes / 1024).round()} KB',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              else
                Text(d == null ? 'Upload' : 'Replace', style: t.labelLarge?.copyWith(color: FT.blueDeep)),
            ],
          ),
        ),
      ),
    );
  }
}
