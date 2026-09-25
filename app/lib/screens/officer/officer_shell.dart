import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand.dart';

/// Officer chrome: navy bar, wide fluid canvas (target: 1366×768 HDMI).
class OfficerShell extends StatelessWidget {
  const OfficerShell({super.key, required this.child, this.leading});

  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pad = fluid(context, 16, 40);
    return Scaffold(
      backgroundColor: FT.mist,
      appBar: AppBar(
        backgroundColor: FT.navy,
        foregroundColor: FT.white,
        surfaceTintColor: FT.navy,
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        leading: leading,
        titleSpacing: leading == null ? pad : 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Wordmark(size: 19, onDark: true),
            if (!context.isCompact) ...[
              const SizedBox(width: 12),
              Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FT.blue,
                borderRadius: BorderRadius.circular(6),
              ),
                child: const Text(
                  'OFFICER',
                  style: TextStyle(color: FT.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!context.isCompact)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(app.user?.email ?? '', style: const TextStyle(color: Color(0xFFB9C8E8), fontSize: 13)),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await app.signOut();
              if (context.mounted) context.go('/officer/login');
            },
          ),
          SizedBox(width: pad - 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, fluid(context, 16, 28), pad, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
