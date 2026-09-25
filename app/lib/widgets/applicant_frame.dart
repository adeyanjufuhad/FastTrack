import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import 'brand.dart';

/// Shared chrome for applicant screens: white top bar with the mark, an
/// optional "Step n of 4" progress bar, and a fluid, centred content column.
class ApplicantFrame extends StatelessWidget {
  const ApplicantFrame({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.step,
    this.back,
    this.bottom,
    this.maxWidth = 560,
    this.actions = const [],
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// 1–4 across Details → Identity → Documents → Sign.
  final int? step;
  final String? back;
  final Widget? bottom;
  final double maxWidth;
  final List<Widget> actions;

  static const stepNames = ['Details', 'Identity', 'Documents', 'Sign'];

  @override
  Widget build(BuildContext context) {
    final pad = fluid(context, 16, 32);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: FT.mist,
      appBar: AppBar(
        toolbarHeight: 64,
        leading: back == null
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go(back!),
              ),
        automaticallyImplyLeading: false,
        titleSpacing: back == null ? pad : 0,
        title: const Wordmark(size: 20),
        actions: [...actions, SizedBox(width: pad - 8)],
        bottom: step == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: step! / 4),
                  duration: FT.motion,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    color: FT.blue,
                    backgroundColor: FT.sky,
                  ),
                ),
              ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, fluid(context, 20, 40), pad, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (step != null) ...[
                          Text(
                            'STEP $step OF 4 · ${stepNames[step! - 1].toUpperCase()}',
                            style: t.labelSmall?.copyWith(
                              color: FT.blueDeep,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (title != null)
                          Text(
                            title!,
                            style: t.headlineMedium?.copyWith(fontSize: fluid(context, 24, 32)),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(subtitle!, style: t.bodyLarge?.copyWith(height: 1.5)),
                        ],
                        if (title != null || subtitle != null) SizedBox(height: fluid(context, 20, 28)),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (bottom != null)
              Container(
                decoration: const BoxDecoration(
                  color: FT.white,
                  border: Border(top: BorderSide(color: FT.line)),
                ),
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: SizedBox(width: double.infinity, child: bottom),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom action bar: a short status line plus the primary action.
/// Stacks with a full-width button on phones, sits inline on wider screens.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.status, required this.action});

  final String status;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Text(status, style: Theme.of(context).textTheme.bodySmall);
    if (context.isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: text),
          const SizedBox(height: 8),
          action,
        ],
      );
    }
    return Row(children: [Expanded(child: text), action]);
  }
}

/// White card with an optional heading, used to group form sections.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding});

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding ?? EdgeInsets.all(fluid(context, 16, 22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    ),
  );
}

/// Round icon in a pale-blue well — the motif from the brand illustration.
class IconWell extends StatelessWidget {
  const IconWell(this.icon, {super.key, this.size = 56, this.color = FT.blue});
  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: FT.sky, shape: BoxShape.circle),
    child: Icon(icon, color: color, size: size * 0.46),
  );
}
