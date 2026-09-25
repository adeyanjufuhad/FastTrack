import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/enums.dart';
import '../models/records.dart';
import 'repository.dart';
import 'rows.dart';
import 'session_store.dart';

/// A non-2xx answer from the fasttrack function: `{"error": "…"}`.
class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);

  /// HTTP status, or 0 when the request never got an answer.
  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Real backend on Neon: the `fasttrack` Neon Function (neon/functions/fasttrack).
/// Neon Auth issues 15-minute JWTs; the opaque refresh token is kept in a
/// [SessionStore] and swapped for a fresh JWT before one expires, or once
/// after a 401. No database, storage or model credentials reach the app.
class NeonRepository implements FastTrackRepository {
  NeonRepository._(this._base, this._http, this._store);

  /// Restores a saved session (refreshing its JWT) or starts signed out.
  static Future<NeonRepository> open(
    String apiUrl, {
    http.Client? client,
    SessionStore? store,
  }) async {
    final base = Uri.parse(apiUrl.endsWith('/') ? apiUrl : '$apiUrl/');
    final repo = NeonRepository._(base, client ?? http.Client(), store ?? PrefsSessionStore());
    await repo._restore();
    return repo;
  }

  final Uri _base;
  final http.Client _http;
  final SessionStore _store;

  SessionUser? _user;
  String? _access;
  String? _refresh;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _refreshing;

  @override
  bool get isDemo => false;

  @override
  SessionUser? get currentUser => _user;

  // ── Transport ─────────────────────────────────────────────────────────

  Future<dynamic> _call(
    String method,
    String path, {
    Object? json,
    Uint8List? bytes,
    String? contentType,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    if (auth) await _ensureAccess();
    Future<http.Response> send() async {
      final req = http.Request(method, _base.resolve(path).replace(queryParameters: query));
      if (auth && _access != null) req.headers['Authorization'] = 'Bearer $_access';
      if (bytes != null) {
        req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
        req.bodyBytes = bytes;
      } else if (json != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(json);
      }
      return http.Response.fromStream(await _http.send(req));
    }

    http.Response res;
    try {
      res = await send();
      if (res.statusCode == 401 && auth && _refresh != null) {
        await _refreshAccess(force: true);
        res = await send();
      }
    } on ApiFailure {
      rethrow;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(0, 'Network problem. Check your connection and retry.');
    }

    final body = res.body.isEmpty ? null : _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final message = body is Map && body['error'] is String
        ? body['error'] as String
        : 'Request failed (${res.statusCode}).';
    throw ApiFailure(res.statusCode, message);
  }

  static dynamic _decode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);
  static List<Map<String, dynamic>> _list(dynamic v) => [for (final e in (v as List? ?? const [])) _map(e)];

  // ── Session ───────────────────────────────────────────────────────────

  Future<void> _ensureAccess() async {
    if (_refresh == null) throw const AuthFailure('Please sign in.');
    final soon = DateTime.now().add(const Duration(seconds: 60));
    if (_access == null || _expiresAt.isBefore(soon)) await _refreshAccess();
  }

  /// One refresh at a time; concurrent callers share it.
  Future<void> _refreshAccess({bool force = false}) {
    if (!force && _refreshing != null) return _refreshing!;
    return _refreshing = () async {
      try {
        final r = _map(await _call(
          'POST',
          'auth/refresh',
          json: {'refresh_token': _refresh},
          auth: false,
        ));
        _setAccess(r);
      } on ApiFailure catch (e) {
        if (e.status == 401 || e.status == 400) {
          await _forget();
          throw const AuthFailure('Your session has ended. Please sign in again.');
        }
        rethrow;
      } finally {
        _refreshing = null;
      }
    }();
  }

  void _setAccess(Map<String, dynamic> r) {
    _access = r['access_token'] as String?;
    final exp = (r['expires_at'] as num?)?.toInt() ?? 0;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }

  Future<SessionUser> _startSession(Map<String, dynamic> s) async {
    _setAccess(s);
    _refresh = s['refresh_token'] as String?;
    final u = _map(s['user']);
    _user = SessionUser(
      id: u['id'] as String,
      email: u['email'] as String? ?? '',
      isOfficer: u['is_officer'] == true,
    );
    await _store.write(jsonEncode({
      'refresh_token': _refresh,
      'user': {'id': _user!.id, 'email': _user!.email, 'is_officer': _user!.isOfficer},
    }));
    return _user!;
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.read();
      if (saved == null) return;
      final s = _map(jsonDecode(saved));
      final u = _map(s['user']);
      _refresh = s['refresh_token'] as String?;
      if (_refresh == null) return await _forget();
      _user = SessionUser(
        id: u['id'] as String,
        email: u['email'] as String? ?? '',
        isOfficer: u['is_officer'] == true,
      );
      // Officer rights can change server-side; take the current answer.
      final me = _map(await _call('GET', 'me'));
      _user = SessionUser(id: _user!.id, email: _user!.email, isOfficer: me['is_officer'] == true);
    } on AuthFailure {
      // Session ended while the app was closed: start signed out.
    } on ApiFailure {
      // Offline at launch: keep the saved user; calls refresh when back online.
    } catch (_) {
      await _forget(); // unreadable saved state
    }
  }

  Future<void> _forget() async {
    _user = null;
    _access = null;
    _refresh = null;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    await _store.clear();
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  Future<SessionUser> _signIn(String path, String email, String password) async {
    try {
      final s = await _call(
        'POST',
        path,
        json: {'email': email.trim(), 'password': password},
        auth: false,
      );
      return await _startSession(_map(s));
    } on ApiFailure catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<SessionUser> signUp(String email, String password) => _signIn('auth/sign-up', email, password);

  @override
  Future<SessionUser> signIn(String email, String password) => _signIn('auth/sign-in', email, password);

  @override
  Future<void> signOut() async {
    final token = _refresh;
    await _forget();
    if (token == null) return;
    try {
      await _call('POST', 'auth/sign-out', json: {'refresh_token': token}, auth: false);
    } catch (_) {
      // Signed out locally either way.
    }
  }

  // ── Applicant ─────────────────────────────────────────────────────────

  @override
  Future<ApplicantProfile> loadProfile() async => profileFromRow(_map(await _call('GET', 'applicant')));

  @override
  Future<void> saveProfile(ApplicantProfile p) => _call('PUT', 'applicant', json: profileToRow(p));

  @override
  Future<Application> loadOrCreateApplication() async =>
      applicationFromRow(_map(await _call('GET', 'application')));

  @override
  Future<void> saveApplication(Application a) async {
    try {
      await _call('PUT', 'applications/${a.id}', json: {
        'requested_amount': a.requestedAmount,
        'tenor_months': a.tenorMonths,
        'purpose': a.purpose,
        'sms_text': a.smsText,
        'status': a.status.wire,
      });
    } on ApiFailure catch (e) {
      // Once scored or decided the file is locked. As with the Supabase
      // backend (RLS matches no row), a save then changes nothing.
      if (e.status != 409) rethrow;
    }
  }

  @override
  Future<KycResult> kycCheck({String? bvn, String? nin, required String legalName}) async {
    try {
      final r = _map(await _call('POST', 'kyc-check', json: {
        'bvn': ?bvn,
        'nin': ?nin,
        'legal_name': legalName,
      }));
      return KycResult.fromWire(r['result'] as String?) ?? KycResult.mismatch;
    } on ApiFailure catch (e) {
      throw ProcessFailure(e.status, 'Identity check is unavailable. Try again.');
    }
  }

  DocumentRecord _docFrom(Map<String, dynamic> r, {Uint8List? data}) {
    final key = r['storage_key'] as String;
    return DocumentRecord(
      id: r['id'] as String,
      kind: DocKind.fromWire(r['kind'] as String?),
      name: r['file_name'] as String? ?? key.split('/').last,
      mime: r['mime'] as String? ?? 'application/octet-stream',
      bytes: (r['bytes'] as num?)?.toInt() ?? 0,
      storagePath: key,
      data: data,
    );
  }

  @override
  Future<DocumentRecord> uploadDocument({
    required DocKind kind,
    required String name,
    required String mime,
    required Uint8List data,
  }) async {
    final row = await _call(
      'POST',
      'documents',
      query: {'kind': kind.wire, 'name': name},
      bytes: data,
      contentType: mime,
    );
    return _docFrom(_map(row), data: data);
  }

  @override
  Future<List<DocumentRecord>> myDocuments() async {
    // Oldest first, so the newest upload per kind wins when the caller maps by kind.
    final rows = _list(await _call('GET', 'documents'))
      ..sort((a, b) => '${a['uploaded_at']}'.compareTo('${b['uploaded_at']}'));
    return [for (final r in rows) _docFrom(r)];
  }

  @override
  Future<Eligibility> processApplication(String applicationId, {String? fixtureKey}) async {
    try {
      await _call('POST', 'process-application', json: {
        'application_id': applicationId,
        'fixture_key': ?fixtureKey,
      });
    } on ApiFailure catch (e) {
      throw ProcessFailure(e.status, switch (e.status) {
        409 => 'We need to confirm your identity before we can show an amount.',
        422 => 'We could not read this file. Try SMS paste or a clearer PDF.',
        423 => 'This file is already with a specialist.',
        503 => 'Our statement reader is busy. Please retry in a moment.',
        0 => e.message,
        _ => 'Something went wrong while scoring. Please retry.',
      });
    }
    final r = await latestEligibility(applicationId);
    if (r == null) throw const ProcessFailure(500, 'Scoring pending or failed.');
    return r;
  }

  @override
  Future<Eligibility?> latestEligibility(String applicationId) async {
    final row = await _call('GET', 'applications/$applicationId/eligibility');
    return row == null ? null : eligibilityFromRow(_map(row));
  }

  // ── Officer ───────────────────────────────────────────────────────────

  ApplicationFile _fileFrom(Map<String, dynamic> r) => ApplicationFile(
    applicant: profileFromRow(_map(r['applicant'])),
    application: applicationFromRow(_map(r['application'])),
    eligibility: r['eligibility'] == null ? null : eligibilityFromRow(_map(r['eligibility'])),
    documents: [for (final d in _list(r['documents'])) _docFrom(d)],
    notes: [
      for (final n in _list(r['notes']))
        OfficerNote(
          body: '${n['body']}',
          createdAt: DateTime.tryParse('${n['created_at']}')?.toLocal() ?? DateTime.now(),
          author: n['officer_email'] as String?,
        ),
    ],
  );

  @override
  Future<List<ApplicationFile>> queue() async =>
      [for (final r in _list(await _call('GET', 'officer/queue'))) _fileFrom(r)];

  @override
  Future<ApplicationFile?> file(String applicationId) async {
    try {
      return _fileFrom(_map(await _call('GET', 'officer/applications/$applicationId')));
    } on ApiFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> addNote(String applicationId, String body) =>
      _call('POST', 'officer/applications/$applicationId/notes', json: {'body': body});

  @override
  Future<void> decide(String applicationId, ApplicationStatus status) =>
      _call('POST', 'officer/applications/$applicationId/decision', json: {'status': status.wire});

  @override
  Future<String?> signedUrl(DocumentRecord doc) async =>
      _map(await _call('GET', 'documents/${doc.id}/url'))['url'] as String?;
}
