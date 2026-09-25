import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/signature_pad.dart';

/// A7 — canvas signature with the legal name and a timestamp under it.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final _pad = SignatureController();
  bool _agreed = false;
  bool _busy = false;
  final _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pad.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final app = context.appRead;
    try {
      final png = await _pad.toPng();
      if (png == null) throw 'Please sign in the box.';
      await app.upload(DocKind.signature, 'signature.png', 'image/png', png);
      await app.submit();
      if (mounted) context.go('/processing');
    } catch (e) {
      if (mounted) context.toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = context.app.profile?.signingName ?? '';
    final ready = !_pad.isEmpty && _agreed && !_busy;

    return ApplicantFrame(
      step: 4,
      back: '/documents',
      title: 'Sign and submit',
      subtitle: 'Sign with your finger or mouse. This confirms the details you gave are true.',
      bottom: ActionBar(
        status: ready ? 'Ready to submit' : 'Sign and tick to submit',
        action: FilledButton.icon(
          onPressed: ready ? _submit : null,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: FT.white))
              : const Icon(Icons.send_rounded, size: 18),
          label: const Text('Submit application'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignaturePad(controller: _pad, height: fluid(context, 180, 240)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.titleMedium),
                    Text('Signed ${_stamp(_openedAt)}', style: t.bodySmall),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _pad.isEmpty ? null : _pad.clear,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            child: CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'I confirm these details are true and I consent to FastTrack reading my statement to prepare a pre-qualification.',
                style: t.bodyMedium?.copyWith(color: FT.navy, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This is an on-device signature for a demonstration build, not a qualified electronic signature.',
            style: t.bodySmall?.copyWith(color: FT.muted),
          ),
        ],
      ),
    );
  }
}
