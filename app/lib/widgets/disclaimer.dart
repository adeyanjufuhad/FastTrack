import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// Locked copy — docs/PRD.md. Do not edit without product sign-off.
const applicantDisclaimer =
    'This is a pre-qualification for demonstration purposes, not an offer of '
    'credit. A specialist will review your file. Identity checks in this build '
    'use sandbox data.';

const officerDisclaimer =
    'Demo build. Sandbox KYC. Amount is rules-engine output, not a '
    'credit-committee decision.';

const officerFooterLine =
    'What you just watched used sandbox identity data. Going live means a '
    'verification-provider contract.';

class DisclaimerCard extends StatelessWidget {
  const DisclaimerCard(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: FT.sky,
      borderRadius: BorderRadius.circular(FT.radiusSm),
      border: const Border(left: BorderSide(color: FT.blue, width: 4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: FT.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: FT.navy, fontSize: 13, height: 1.45, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}
