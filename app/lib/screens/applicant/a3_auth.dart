import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/demo_repository.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';

final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// A3 — register / sign in (email + password).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.appRead;
    try {
      if (_register) {
        await app.signUp(_email.text, _password.text);
      } else {
        await app.signIn(_email.text, _password.text);
      }
      if (!mounted) return;
      if (app.isOfficer) {
        context.go('/officer');
      } else {
        final status = app.application?.status.wire;
        context.go(status == null || status == 'draft' ? '/details' : '/home');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final demo = context.app.repo.isDemo;

    return ApplicantFrame(
      back: '/role',
      maxWidth: 460,
      title: _register ? 'Create your account' : 'Welcome back',
      subtitle: _register
          ? 'Your application is saved as you go.'
          : 'Sign in to continue your application.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Register')),
                ButtonSegment(value: false, label: Text('Sign in')),
              ],
              selected: {_register},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                _register = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              validator: (v) => emailPattern.hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: _register ? 'At least 8 characters' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: FT.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: FT.white))
                  : Text(_register ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 22),
            const _PrivacyNote(),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Officer?', style: t.bodyMedium),
                TextButton(
                  onPressed: () => context.go('/officer/login'),
                  child: const Text('Use the web dashboard'),
                ),
              ],
            ),
            if (demo)
              Text(
                'Demo: any email works, or sign in as ${DemoRepository.applicantEmail} / ${DemoRepository.demoPassword}.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: FT.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// NDPR posture: minimum collection, a privacy note on A3.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: FT.sky, borderRadius: BorderRadius.circular(FT.radiusSm)),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: FT.navy),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Privacy: we collect only what a loan file needs. Documents are stored privately, '
            'only the last four digits of your BVN and NIN are kept, and nothing is emailed. '
            'You can ask us to delete your data at any time.',
            style: TextStyle(color: FT.navy, fontSize: 12.5, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
