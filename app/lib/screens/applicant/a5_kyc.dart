import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures.dart';
import '../../models/enums.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';
import '../../widgets/chips.dart';

/// A5 — BVN + NIN against the sandbox register. Amber chip always visible.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _form = GlobalKey<FormState>();
  final _bvn = TextEditingController();
  final _nin = TextEditingController();
  bool _busy = false;
  KycResult? _result;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final p = context.appRead.profile;
    _result = p?.kycResult;
    if (p?.role == ApplicantRole.corporate) _bvn.text = p?.fields['signatory_1_bvn'] ?? '';
  }

  @override
  void dispose() {
    _bvn.dispose();
    _nin.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final r = await context.appRead.checkKyc(bvn: _bvn.text, nin: _nin.text);
      setState(() => _result = r);
    } catch (e) {
      if (mounted) context.toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _eleven(String? v) =>
      RegExp(r'^\d{11}$').hasMatch(v ?? '') ? null : 'Must be exactly 11 digits';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final corporate = context.app.profile?.role == ApplicantRole.corporate;
    final samples = corporate
        ? personas.where((p) => p.key == 'northshore')
        : personas.where((p) => p.key != 'northshore');

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      counterText: '',
      prefixIcon: const Icon(Icons.badge_outlined),
    );

    return ApplicantFrame(
      step: 2,
      back: '/details',
      title: 'Confirm identity',
      subtitle: corporate
          ? 'We check the first signatory against the identity register.'
          : 'We check your BVN and NIN against the identity register. Only the last four digits are kept.',
      bottom: ActionBar(
        status: _result == null ? 'Verify to continue' : 'Result saved to your file',
        action: FilledButton(
          onPressed: _result == null ? null : () => context.go('/documents'),
          child: const Text('Continue to documents'),
        ),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SandboxChip(),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _bvn,
                    maxLength: 11,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: deco(corporate ? 'Signatory BVN' : 'BVN'),
                    validator: _eleven,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nin,
                    maxLength: 11,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: deco(corporate ? 'Signatory NIN' : 'NIN'),
                    validator: _eleven,
                    onFieldSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _verify,
                    icon: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.fingerprint),
                    label: Text(_result == null ? 'Verify identity' : 'Verify again'),
                  ),
                ],
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              AnimatedSwitcher(duration: FT.motion, child: _ResultBanner(_result!, key: ValueKey(_result))),
            ],
            const SizedBox(height: 22),
            Text('Sample identities (sandbox)', style: t.labelLarge?.copyWith(color: FT.navy)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in samples)
                  ActionChip(
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(p.label),
                    onPressed: () => setState(() {
                      _bvn.text = p.bvn;
                      _nin.text = p.nin;
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.block, size: 16),
                  label: const Text('Fail case'),
                  onPressed: () => setState(() {
                    _bvn.text = '00000000000';
                    _nin.text = '00000000000';
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner(this.result, {super.key});
  final KycResult result;

  @override
  Widget build(BuildContext context) {
    final pass = result == KycResult.sandboxPass;
    final (fg, bg, icon, title, body) = pass
        ? (FT.ok, FT.okBg, Icons.verified_outlined, 'Identity matched (sandbox)',
            'Your BVN / NIN matched the sandbox register.')
        : (FT.danger, FT.dangerBg, Icons.error_outline, 'We could not confirm this identity',
            'You can finish your application, but we will not show an amount until a specialist confirms your identity.');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(FT.radiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: fg, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
