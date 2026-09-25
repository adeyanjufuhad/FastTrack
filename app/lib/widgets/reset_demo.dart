import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/scope.dart';
import '../theme/tokens.dart';

/// Offline demo only. Run before each pitch to start from the seed personas.
Future<void> confirmResetDemo(BuildContext context, {String then = '/'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reset demo data?'),
      content: const Text(
        'This removes every application and account created on this device and '
        'restores Adaeze, Ibrahim and Northshore. You will be signed out.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: FT.danger, minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await context.appRead.resetDemo();
  if (!context.mounted) return;
  context.go(then);
  context.toast('Demo reset to seed data');
}
