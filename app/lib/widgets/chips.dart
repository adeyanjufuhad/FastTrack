import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../scoring/score_engine.dart';
import '../theme/tokens.dart';

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 4 : 7),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 14 : 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 12 : 13,
              height: 1.25,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Fixed copy from docs/kyc-sandbox.md — do not rewrite.
const sandboxChipCopy =
    'Demo mode — sandbox verification. Production requires a licensed KYC provider.';

/// The amber chip. Must be visible on A5 and A9 without anyone pointing at it.
class SandboxChip extends StatelessWidget {
  const SandboxChip({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: sandboxChipCopy,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FT.amberBg,
        borderRadius: BorderRadius.circular(FT.radiusSm),
        border: Border.all(color: FT.amber.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 18, color: FT.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              sandboxChipCopy,
              style: TextStyle(color: FT.amber, fontWeight: FontWeight.w700, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}

class TierChip extends StatelessWidget {
  const TierChip(this.tier, {super.key, this.applicantFacing = false, this.dense = false});

  final Tier? tier;
  final bool applicantFacing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = tier;
    if (t == null) {
      return Pill(label: 'Not scored', fg: FT.muted, bg: FT.mist, dense: dense);
    }
    final (fg, bg) = switch (t) {
      Tier.low => (FT.white, FT.blue),
      Tier.medium => (FT.white, FT.navySoft),
      Tier.high => (FT.navy, FT.sky),
    };
    return Pill(
      label: applicantFacing ? t.applicantWords : '${t.label} risk',
      fg: fg,
      bg: bg,
      icon: Icons.verified_user_outlined,
      dense: dense,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false, this.applicantFacing = false});

  final ApplicationStatus status;
  final bool dense;

  /// Officers see "New" for a freshly scored file; applicants see "In queue".
  final bool applicantFacing;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (status) {
      ApplicationStatus.approved => (FT.ok, FT.okBg, Icons.check_circle_outline),
      ApplicationStatus.declined => (FT.danger, FT.dangerBg, Icons.cancel_outlined),
      ApplicationStatus.moreInfo => (FT.amber, FT.amberBg, Icons.help_outline),
      ApplicationStatus.inReview => (FT.blueDeep, FT.sky, Icons.visibility_outlined),
      ApplicationStatus.scored => (FT.navy, FT.sky, Icons.fiber_new_outlined),
      _ => (FT.muted, FT.mist, Icons.edit_note),
    };
    final label = applicantFacing && status == ApplicationStatus.scored ? 'In queue' : status.label;
    return Pill(label: label, fg: fg, bg: bg, icon: icon, dense: dense);
  }
}

class WarningChip extends StatelessWidget {
  const WarningChip(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) => Pill(
    label: Warnings.describe(code),
    fg: code == Warnings.kycMismatch ? FT.danger : FT.navy,
    bg: code == Warnings.kycMismatch ? FT.dangerBg : FT.sky,
    icon: Icons.flag_outlined,
    dense: true,
  );
}
