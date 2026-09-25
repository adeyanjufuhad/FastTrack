import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/applicant_frame.dart';

/// A2 — Individual / Corporate, large tap targets.
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _pick(BuildContext context, ApplicantRole role) async {
    final app = context.appRead;
    await app.setRole(role);
    if (!context.mounted) return;
    context.go(app.signedIn ? '/details' : '/auth');
  }

  @override
  Widget build(BuildContext context) {
    final current = context.app.profile?.role ?? context.app.pendingRole;
    final cards = [
      _RoleCard(
        icon: Icons.person_outline_rounded,
        title: 'Individual',
        body: 'Salary earners and professionals. BVN, NIN, ID and a bank statement or SMS alerts.',
        selected: current == ApplicantRole.individual,
        onTap: () => _pick(context, ApplicantRole.individual),
      ),
      _RoleCard(
        icon: Icons.apartment_rounded,
        title: 'Corporate',
        body: 'Registered companies. RC number, CAC certificate and two signatories — no courier.',
        selected: current == ApplicantRole.corporate,
        onTap: () => _pick(context, ApplicantRole.corporate),
      ),
    ];

    return ApplicantFrame(
      back: '/',
      maxWidth: 760,
      title: 'Who is applying?',
      subtitle: 'Choose one. You can change it before you submit.',
      child: context.width >= 640
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              ),
            )
          : Column(children: [cards[0], const SizedBox(height: 14), cards[1]]),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: FT.white,
      borderRadius: BorderRadius.circular(FT.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FT.radius),
        child: AnimatedContainer(
          duration: FT.motion,
          padding: EdgeInsets.all(fluid(context, 20, 28)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FT.radius),
            border: Border.all(color: selected ? FT.blue : FT.line, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconWell(icon, size: 52),
                  const Spacer(),
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? FT.blue : FT.line,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(title, style: t.titleLarge),
              const SizedBox(height: 6),
              Text(body, style: t.bodyMedium?.copyWith(height: 1.5)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Continue', style: t.labelLarge?.copyWith(color: FT.blueDeep)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: FT.blueDeep),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
