import 'package:fasttrack/data/demo_repository.dart';
import 'package:fasttrack/data/demo_store.dart';
import 'package:fasttrack/data/fixtures.dart';
import 'package:fasttrack/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

// A refresh mid-pitch must not lose the live application (demo mode).

void main() {
  test('seeds three scored personas on first open', () async {
    final repo = await DemoRepository.open(MemoryDemoStore());
    await repo.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
    final queue = await repo.queue();
    expect(queue.map((f) => f.eligibility?.amount), containsAll([1240000, 410000, 3780000]));
  });

  test('live application, session and decision survive a reload', () async {
    final store = MemoryDemoStore();
    final repo = await DemoRepository.open(store);

    await repo.signUp('adaeze@example.com', 'demo-pass-123');
    final app = await repo.loadOrCreateApplication();
    expect(await repo.kycCheck(bvn: '22222222222', nin: '11111111111', legalName: 'Adaeze'), KycResult.sandboxPass);
    app.smsText = smsAdaeze;
    await repo.saveApplication(app);
    final result = await repo.processApplication(app.id);
    expect(result.amount, 1240000);

    // "Refresh the page": a brand-new repository over the same store.
    final reloaded = await DemoRepository.open(store);
    expect(reloaded.currentUser?.email, 'adaeze@example.com');
    final again = await reloaded.loadOrCreateApplication();
    expect(again.id, app.id);
    expect(again.status, ApplicationStatus.scored);
    expect((await reloaded.latestEligibility(app.id))?.amount, 1240000);

    // Officer decision persists too, and the applicant sees it after reload.
    await reloaded.signOut();
    await reloaded.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
    await reloaded.addNote(app.id, 'Confirm landlord reference');
    await reloaded.decide(app.id, ApplicationStatus.approved);

    final third = await DemoRepository.open(store);
    final file = await third.file(app.id);
    expect(file!.application.status, ApplicationStatus.approved);
    expect(file.notes.single.body, 'Confirm landlord reference');
  });

  test('passwords are stored hashed, never in plain text', () async {
    final store = MemoryDemoStore();
    final repo = await DemoRepository.open(store);
    await repo.signUp('someone@example.com', 'super-secret-pw');
    expect(store.value, isNot(contains('super-secret-pw')));
    expect(store.value, isNot(contains(DemoRepository.demoPassword)));
    await expectLater(repo.signIn('someone@example.com', 'wrong-password'), throwsA(anything));
  });

  test('reset restores the seed personas and signs out', () async {
    final store = MemoryDemoStore();
    final repo = await DemoRepository.open(store);
    await repo.signUp('temp@example.com', 'demo-pass-123');
    await repo.resetDemo();
    expect(repo.currentUser, isNull);
    await expectLater(repo.signIn('temp@example.com', 'demo-pass-123'), throwsA(anything));

    final reloaded = await DemoRepository.open(store);
    await reloaded.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
    expect(await reloaded.queue(), hasLength(3));
  });

  test('corrupt saved state falls back to a fresh seed', () async {
    final store = MemoryDemoStore()..value = '{not json';
    final repo = await DemoRepository.open(store);
    await repo.signIn(DemoRepository.officerEmail, DemoRepository.demoPassword);
    expect(await repo.queue(), hasLength(3));
  });
}
