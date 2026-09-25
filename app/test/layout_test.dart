import 'package:fasttrack/app.dart';
import 'package:fasttrack/data/demo_repository.dart';
import 'package:fasttrack/data/demo_store.dart';
import 'package:fasttrack/data/fixtures.dart';
import 'package:fasttrack/state/app_state.dart';
import 'package:fasttrack/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Every screen at phone, tablet and the 1366×768 conference-room HDMI size
// (docs/definition-of-done.md). Any RenderFlex overflow — i.e. cut-off
// content or CTAs — is reported by Flutter and fails the test.

const sizes = {
  'phone 360×740': Size(360, 740),
  'tablet 768×1024': Size(768, 1024),
  'HDMI 1366×768': Size(1366, 768),
};

final theme = buildTheme(googleFonts: false);

enum Who { nobody, applicantDraft, applicantScored, officer }

Future<(AppState, String?)> prepare(WidgetTester tester, Who who) async {
  late AppState state;
  String? seedId;
  await tester.runAsync(() async {
    final repo = await DemoRepository.open(MemoryDemoStore());
    state = AppState(repo);
    switch (who) {
      case Who.nobody:
        break;
      case Who.applicantDraft:
        await state.signUp('adaeze@example.com', 'demo-pass-123');
      case Who.applicantScored:
        await state.signUp('adaeze@example.com', 'demo-pass-123');
        state.profile!.fields['legal_name'] = 'Adaeze Okafor';
        await state.checkKyc(bvn: '22222222222', nin: '11111111111');
        state.application!
          ..smsText = smsAdaeze
          ..purpose = 'Rent renewal';
        await state.saveDraft();
        await state.submit();
        await state.process();
      case Who.officer:
        await state.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
        seedId = (await repo.queue()).first.application.id;
    }
  });
  return (state, seedId);
}

Future<void> pumpScreen(WidgetTester tester, Size size, AppState state, String route) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh key per pump, so a second pump builds a new router at [route].
  await tester.pumpWidget(FastTrackApp(key: UniqueKey(), state: state, theme: theme, initialLocation: route));
  // Let post-frame loads finish. The demo store's save chain was started on
  // the real event loop (in prepare), so advance real time as well as the
  // fake test clock — otherwise screens stay on their loading spinner.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pump();
}

void main() {
  final screens = <String, (Who, String Function(String? seedId))>{
    'A1 splash': (Who.nobody, (_) => '/'),
    'A2 role': (Who.nobody, (_) => '/role'),
    'A3 auth': (Who.nobody, (_) => '/auth'),
    'A4 details': (Who.applicantDraft, (_) => '/details'),
    'A5 kyc': (Who.applicantDraft, (_) => '/kyc'),
    'A6 documents': (Who.applicantDraft, (_) => '/documents'),
    'A7 sign': (Who.applicantDraft, (_) => '/sign'),
    'A9 result': (Who.applicantScored, (_) => '/result'),
    'A10 home': (Who.applicantScored, (_) => '/home'),
    'O3 officer login': (Who.nobody, (_) => '/officer/login'),
    'O1 queue': (Who.officer, (_) => '/officer'),
    'O2 file': (Who.officer, (id) => '/officer/applications/$id'),
  };

  for (final s in sizes.entries) {
    group(s.key, () {
      for (final screen in screens.entries) {
        testWidgets(screen.key, (tester) async {
          final (state, seedId) = await prepare(tester, screen.value.$1);
          await pumpScreen(tester, s.value, state, screen.value.$2(seedId));
          expect(tester.takeException(), isNull);
          // Loaded, not stuck on a spinner (A8 is the only screen that spins).
          expect(find.byType(CircularProgressIndicator), findsNothing);
        });
      }
    });
  }

  testWidgets('A9 and O2 show the same amount at 1366×768', (tester) async {
    final (state, _) = await prepare(tester, Who.applicantScored);
    final appId = state.application!.id;
    await pumpScreen(tester, sizes['HDMI 1366×768']!, state, '/result');
    expect(find.text('Up to NGN 1,240,000'), findsOneWidget);
    expect(find.textContaining('Demo mode — sandbox verification'), findsOneWidget);
    expect(find.textContaining('not an offer of credit'), findsOneWidget);

    await tester.runAsync(() async {
      await state.signOut();
      await state.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
    });
    await pumpScreen(tester, sizes['HDMI 1366×768']!, state, '/officer/applications/$appId');
    expect(find.text('NGN 1,240,000'), findsOneWidget);
    expect(find.textContaining('not a credit-committee decision'), findsOneWidget);
  });
}
