import 'dart:convert';
import 'dart:typed_data';

import 'package:fasttrack/data/neon_repository.dart';
import 'package:fasttrack/data/session_store.dart';
import 'package:fasttrack/models/enums.dart';
import 'package:fasttrack/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _api = 'https://fn.example';
const _uid = '11111111-1111-4111-8111-111111111111';
const _appId = 'f0000000-0000-4000-8000-0000000000a1';

int _in(Duration d) => DateTime.now().add(d).millisecondsSinceEpoch ~/ 1000;

/// A scripted stand-in for the fasttrack Neon Function.
class _FakeApi {
  final calls = <http.Request>[];
  int tokenSerial = 0;
  bool refreshAllowed = true;
  bool officer = false;
  int accessLifetimeMinutes = 15;
  final responses = <String, http.Response Function(http.Request)>{};

  String _token() => 'jwt-${++tokenSerial}';
  String get currentToken => 'jwt-$tokenSerial';

  http.Response _json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, dynamic> _session() => {
    'access_token': _token(),
    'refresh_token': 'refresh-abc',
    'expires_at': _in(Duration(minutes: accessLifetimeMinutes)),
    'user': {'id': _uid, 'email': 'a@x.io', 'is_officer': officer},
  };

  late final client = MockClient((req) async {
    calls.add(req);
    final key = '${req.method} ${req.url.path}';
    switch (key) {
      case 'POST /auth/sign-in' || 'POST /auth/sign-up':
        final b = jsonDecode(req.body) as Map;
        if (b['password'] != 'pw') return _json({'error': 'Invalid email or password'}, 401);
        return _json(_session());
      case 'POST /auth/refresh':
        if (!refreshAllowed) return _json({'error': 'Session expired. Please sign in again.'}, 401);
        return _json({'access_token': _token(), 'expires_at': _in(Duration(minutes: accessLifetimeMinutes))});
      case 'POST /auth/sign-out':
        return _json({'ok': true});
    }
    if (req.headers['Authorization'] != 'Bearer $currentToken') {
      return _json({'error': 'Session expired.'}, 401);
    }
    if (key == 'GET /me') return _json({'id': _uid, 'email': 'a@x.io', 'is_officer': officer});
    final handler = responses[key];
    return handler == null ? _json({'error': 'Not found.'}, 404) : handler(req);
  });
}

Future<(NeonRepository, _FakeApi, MemorySessionStore)> _signedIn({bool officer = false}) async {
  final api = _FakeApi()..officer = officer;
  final store = MemorySessionStore();
  final repo = await NeonRepository.open(_api, client: api.client, store: store);
  await repo.signIn('a@x.io', 'pw');
  return (repo, api, store);
}

void main() {
  test('sign-in stores the session and sends the JWT as a bearer token', () async {
    final (repo, api, store) = await _signedIn();
    expect(repo.currentUser!.id, _uid);
    expect(repo.currentUser!.isOfficer, isFalse);
    expect(repo.isDemo, isFalse);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['refresh_token'], 'refresh-abc');
    expect(store.value, isNot(contains('pw')));

    api.responses['GET /applicant'] = (_) => api._json({'id': _uid, 'role': 'individual', 'legal_name': 'Ada', 'email': 'a@x.io'});
    final p = await repo.loadProfile();
    expect(p.displayName, 'Ada');
    expect(api.calls.last.headers['Authorization'], 'Bearer jwt-1');
  });

  test('wrong password surfaces the server message as AuthFailure', () async {
    final api = _FakeApi();
    final repo = await NeonRepository.open(_api, client: api.client, store: MemorySessionStore());
    await expectLater(
      repo.signIn('a@x.io', 'nope'),
      throwsA(isA<AuthFailure>().having((e) => e.message, 'message', 'Invalid email or password')),
    );
    expect(repo.currentUser, isNull);
  });

  test('an expiring JWT is refreshed before the call; a 401 retries once', () async {
    final api = _FakeApi()..accessLifetimeMinutes = 0; // already inside the refresh window
    final repo = await NeonRepository.open(_api, client: api.client, store: MemorySessionStore());
    await repo.signIn('a@x.io', 'pw');
    api.responses['GET /application'] = (_) => api._json({'id': _appId, 'applicant_id': _uid, 'status': 'draft'});
    await repo.loadOrCreateApplication();
    expect(api.calls.map((c) => c.url.path), containsAllInOrder(['/auth/refresh', '/application']));

    // Server-side expiry the client did not predict: 401 → refresh → retry.
    api.accessLifetimeMinutes = 15;
    await repo.loadOrCreateApplication(); // refreshes (window) and succeeds
    api.tokenSerial++; // server rotates keys; the held token is now stale
    final before = api.calls.length;
    await repo.loadOrCreateApplication();
    expect(api.calls.skip(before).map((c) => c.url.path), ['/application', '/auth/refresh', '/application']);
  });

  test('a refused refresh signs out and asks to sign in again', () async {
    final (repo, api, store) = await _signedIn();
    api
      ..refreshAllowed = false
      ..tokenSerial += 1;
    await expectLater(repo.loadProfile(), throwsA(isA<AuthFailure>()));
    expect(repo.currentUser, isNull);
    expect(store.value, isNull);
  });

  test('a saved session is restored and officer rights re-checked', () async {
    final (_, api, store) = await _signedIn();
    api.officer = true; // promoted while the app was closed
    final again = await NeonRepository.open(_api, client: api.client, store: store);
    expect(again.currentUser?.id, _uid);
    expect(again.currentUser?.isOfficer, isTrue);
  });

  test('an ended session restores as signed out', () async {
    final (_, api, store) = await _signedIn();
    api.refreshAllowed = false;
    final again = await NeonRepository.open(_api, client: api.client, store: store);
    expect(again.currentUser, isNull);
    expect(store.value, isNull);
  });

  test('process-application maps the API contract to ProcessFailure', () async {
    final (repo, api, _) = await _signedIn();
    for (final (status, words) in [(409, 'confirm your identity'), (422, 'could not read'), (503, 'busy')]) {
      api.responses['POST /process-application'] = (_) => api._json({'error': 'x'}, status);
      await expectLater(
        repo.processApplication(_appId),
        throwsA(isA<ProcessFailure>()
            .having((e) => e.code, 'code', status)
            .having((e) => e.message, 'message', contains(words))),
      );
    }
    api.responses['POST /process-application'] = (_) => api._json({'status': 'scored'});
    api.responses['GET /applications/$_appId/eligibility'] = (_) => api._json({
      'application_id': _appId,
      'amount_prequalified': 1240000,
      'tier': 'medium',
      'warnings': ['external_lender_detected'],
      'created_at': '2026-09-25T12:22:22.123456+00:00',
    });
    final e = await repo.processApplication(_appId, fixtureKey: 'fixture:adaeze-sms');
    expect(e.amount, 1240000);
    expect(e.tier, Tier.medium);
    expect(jsonDecode(api.calls.lastWhere((c) => c.url.path == '/process-application').body),
        {'application_id': _appId, 'fixture_key': 'fixture:adaeze-sms'});
  });

  test('saving a locked (scored) application is a no-op, other errors surface', () async {
    final (repo, api, _) = await _signedIn();
    final a = Application(id: _appId, applicantId: _uid, status: ApplicationStatus.scored);
    api.responses['PUT /applications/$_appId'] = (_) => api._json({'error': 'locked'}, 409);
    await repo.saveApplication(a);
    api.responses['PUT /applications/$_appId'] = (_) => api._json({'error': 'Status can only be draft or submitted.'}, 403);
    await expectLater(repo.saveApplication(a), throwsA(isA<ApiFailure>()));
  });

  test('uploads send raw bytes with their type; newest document per kind wins', () async {
    final (repo, api, _) = await _signedIn();
    api.responses['POST /documents'] = (req) => api._json({
      'id': 'd1', 'kind': req.url.queryParameters['kind'], 'storage_key': '$_uid/id-1-p.png',
      'file_name': req.url.queryParameters['name'], 'mime': req.headers['Content-Type'], 'bytes': req.bodyBytes.length,
    });
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    final d = await repo.uploadDocument(kind: DocKind.id, name: 'passport.png', mime: 'image/png', data: bytes);
    expect(d.name, 'passport.png');
    expect(d.data, bytes);
    final sent = api.calls.last;
    expect(sent.headers['Content-Type'], 'image/png');
    expect(sent.bodyBytes, bytes);

    api.responses['GET /documents'] = (_) => api._json([
      {'id': 'new', 'kind': 'statement', 'storage_key': 'k2', 'uploaded_at': '2026-09-25T13:00:00Z'},
      {'id': 'old', 'kind': 'statement', 'storage_key': 'k1', 'uploaded_at': '2026-09-25T12:00:00Z'},
    ]);
    final byKind = {for (final d in await repo.myDocuments()) d.kind: d.id};
    expect(byKind[DocKind.statement], 'new');
  });

  test('officer queue and file map applicant, result, notes and documents', () async {
    final (repo, api, _) = await _signedIn(officer: true);
    expect(repo.currentUser!.isOfficer, isTrue);
    Map<String, dynamic> file() => {
      'application': {'id': _appId, 'applicant_id': _uid, 'status': 'scored', 'created_at': '2026-09-25T10:00:00+00:00'},
      'applicant': {'id': _uid, 'role': 'corporate', 'legal_name': 'Northshore Trading Ltd'},
      'eligibility': {'application_id': _appId, 'amount_prequalified': 3780000, 'tier': 'medium', 'warnings': []},
      'notes': [
        {'body': 'Called the MD.', 'officer_email': 'officer@fasttrack.demo', 'created_at': '2026-09-25T11:00:00+00:00'},
      ],
    };
    api.responses['GET /officer/queue'] = (_) => api._json([file()]);
    api.responses['GET /officer/applications/$_appId'] = (_) => api._json({
      ...file(),
      'documents': [{'id': 'd1', 'kind': 'cac', 'storage_key': '$_uid/cac-1-c.pdf', 'file_name': 'c.pdf', 'mime': 'application/pdf', 'bytes': 9}],
    });
    api.responses['GET /documents/d1/url'] = (_) => api._json({'url': 'https://s3.example/signed', 'expires_in': 600});

    final q = await repo.queue();
    expect(q.single.applicant.displayName, 'Northshore Trading Ltd');
    expect(q.single.eligibility!.amount, 3780000);
    expect(q.single.notes.single.author, 'officer@fasttrack.demo');

    final f = (await repo.file(_appId))!;
    expect(f.documents.single.name, 'c.pdf');
    expect(await repo.signedUrl(f.documents.single), 'https://s3.example/signed');
    expect(await repo.file('00000000-0000-4000-8000-000000000000'), isNull); // 404 → null
  });

  test('sign-out forgets the session even when offline', () async {
    final (repo, api, store) = await _signedIn();
    api.responses.clear();
    await repo.signOut();
    expect(repo.currentUser, isNull);
    expect(store.value, isNull);
    expect(api.calls.last.url.path, '/auth/sign-out');
  });
}
