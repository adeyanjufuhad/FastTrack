import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/demo_repository.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand.dart';
import '../applicant/a3_auth.dart' show emailPattern;

/// O3 — officer-only sign in. Non-officer sessions are rejected.
class OfficerLoginScreen extends StatefulWidget {
  const OfficerLoginScreen({super.key});

  @override
  State<OfficerLoginScreen> createState() => _OfficerLoginScreenState();
}

class _OfficerLoginScreenState extends State<OfficerLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
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
      await app.signIn(_email.text, _password.text);
      if (!app.isOfficer) {
        await app.signOut();
        throw const FormatException('This account does not have officer access.');
      }
      if (mounted) context.go('/officer');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
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

    final form = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.isWide) ...[const Wordmark(size: 22), const SizedBox(height: 28)],
          Text('Officer sign in', style: t.headlineMedium?.copyWith(fontSize: fluid(context, 24, 30))),
          const SizedBox(height: 6),
          Text('Review scored files and record decisions.', style: t.bodyMedium),
          const SizedBox(height: 24),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => emailPattern.hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
            validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: FT.danger, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: FT.white))
                : const Text('Sign in'),
          ),
          if (demo) ...[
            const SizedBox(height: 16),
            Text(
              'Demo: ${DemoRepository.officerEmail} / ${DemoRepository.demoPassword}',
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: FT.muted),
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: FT.white,
      body: Row(
        children: [
          if (context.isWide)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [FT.navy, FT.navySoft],
                  ),
                ),
                padding: const EdgeInsets.all(56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Wordmark(size: 26, onDark: true),
                    const Spacer(),
                    Text(
                      'A scored file,\nnot a blank PDF.',
                      style: t.headlineLarge?.copyWith(color: FT.white, fontSize: 44, height: 1.1),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Amount and tier come from your rules. The narrative is a first read. You decide.',
                      style: TextStyle(color: Color(0xFFB9C8E8), fontSize: 16, height: 1.5),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(fluid(context, 20, 48)),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: form),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
