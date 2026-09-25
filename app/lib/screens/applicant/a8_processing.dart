import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/records.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';

/// A8 — three honest steps. Never a bare spinner; failures offer a retry.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  static const _steps = [
    ('Verifying identity', 'Checking the sandbox register'),
    ('Reading statement', 'Extracting income, spend and repayments'),
    ('Scoring', 'Applying the firm’s lending rules'),
  ];

  int _done = 0;
  ProcessFailure? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _done = 0;
      _error = null;
    });
    // Visual pacing for the first two ticks; the last one waits for the result.
    _ticker = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted || _done >= 2) return t.cancel();
      setState(() => _done++);
    });
    try {
      await context.appRead.process();
      _ticker?.cancel();
      if (!mounted) return;
      setState(() => _done = 3);
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted) context.go('/result');
    } on ProcessFailure catch (e) {
      _ticker?.cancel();
      if (!mounted) return;
      // KYC mismatch still lands on A9, which explains that no amount is shown.
      if (e.code == 409) return context.go('/result');
      setState(() => _error = e);
    } catch (e) {
      _ticker?.cancel();
      if (mounted) setState(() => _error = ProcessFailure(0, '$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final err = _error;

    return ApplicantFrame(
      title: err == null ? 'Preparing your file' : 'We hit a snag',
      subtitle: err == null
          ? 'This usually takes a few seconds. Please keep this page open.'
          : err.message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            child: Column(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  _StepRow(
                    title: _steps[i].$1,
                    body: _steps[i].$2,
                    state: i < _done
                        ? _S.done
                        : (err != null && i == _done ? _S.failed : (i == _done ? _S.active : _S.waiting)),
                    last: i == _steps.length - 1,
                  ),
              ],
            ),
          ),
          if (err != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            if (err.unreadable) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.go('/documents'),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Paste SMS alerts instead'),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.go('/home'), child: const Text('Save and finish later')),
          ] else ...[
            const SizedBox(height: 18),
            Text(
              'A specialist reviews every file. Nothing is approved automatically.',
              textAlign: TextAlign.center,
              style: t.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

enum _S { waiting, active, done, failed }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.title, required this.body, required this.state, required this.last});

  final String title;
  final String body;
  final _S state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final Widget icon = switch (state) {
      _S.done => const Icon(Icons.check_circle, color: FT.blue, size: 28, key: ValueKey('d')),
      _S.failed => const Icon(Icons.error, color: FT.danger, size: 28, key: ValueKey('f')),
      _S.active => const SizedBox.square(
        key: ValueKey('a'),
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: FT.blue),
      ),
      _S.waiting => const Icon(Icons.circle_outlined, color: FT.line, size: 28, key: ValueKey('w')),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 18),
      child: Row(
        children: [
          SizedBox.square(dimension: 30, child: Center(child: AnimatedSwitcher(duration: FT.motion, child: icon))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.titleSmall?.copyWith(
                    color: state == _S.waiting ? FT.muted : FT.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(body, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
