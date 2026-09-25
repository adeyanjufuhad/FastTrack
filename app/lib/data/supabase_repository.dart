import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/records.dart';
import 'repository.dart';
import 'rows.dart';

/// Real backend: Supabase Auth + Postgres (RLS) + Storage + Edge Functions.
/// Only the anon key ever reaches this class. Never the service role.
class SupabaseRepository implements FastTrackRepository {
  SupabaseRepository(this._sb);

  final SupabaseClient _sb;
  static const _bucket = 'documents';

  @override
  bool get isDemo => false;

  @override
  SessionUser? get currentUser {
    final u = _sb.auth.currentUser;
    if (u == null) return null;
    return SessionUser(
      id: u.id,
      email: u.email ?? '',
      isOfficer: u.appMetadata['role'] == 'officer',
    );
  }

  String get _uid => _sb.auth.currentUser?.id ?? (throw const AuthFailure('Please sign in.'));

  // ── Auth ──────────────────────────────────────────────────────────────

  @override
  Future<SessionUser> signUp(String email, String password) async {
    try {
      final res = await _sb.auth.signUp(email: email.trim(), password: password);
      if (res.session == null) {
        throw const AuthFailure('Check your inbox to confirm your email, then sign in.');
      }
      return currentUser!;
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<SessionUser> signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email.trim(), password: password);
      return currentUser!;
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<void> signOut() => _sb.auth.signOut();

  // ── Applicant ─────────────────────────────────────────────────────────

  @override
  Future<ApplicantProfile> loadProfile() async {
    final row = await _sb.from('applicants').select().eq('id', _uid).maybeSingle();
    if (row != null) return profileFromRow(row);
    final p = ApplicantProfile(id: _uid, fields: {'email': _sb.auth.currentUser?.email ?? ''});
    await saveProfile(p);
    return p;
  }

  @override
  Future<void> saveProfile(ApplicantProfile p) async {
    await _sb.from('applicants').upsert({
      'id': p.id,
      ...profileToRow(p),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<Application> loadOrCreateApplication() async {
    final row = await _sb
        .from('applications')
        .select()
        .eq('applicant_id', _uid)
        .order('created_at')
        .limit(1)
        .maybeSingle();
    if (row != null) return applicationFromRow(row);
    final created = await _sb
        .from('applications')
        .insert({'applicant_id': _uid})
        .select()
        .single();
    return applicationFromRow(created);
  }

  @override
  Future<void> saveApplication(Application a) async {
    await _sb.from('applications').update({
      'requested_amount': a.requestedAmount,
      'tenor_months': a.tenorMonths,
      'purpose': a.purpose,
      'sms_text': a.smsText,
      'status': a.status.wire,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', a.id);
  }

  @override
  Future<KycResult> kycCheck({String? bvn, String? nin, required String legalName}) async {
    try {
      final res = await _sb.functions.invoke('kyc-check', body: {
        'bvn': ?bvn,
        'nin': ?nin,
        'legal_name': legalName,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return KycResult.fromWire(data['result'] as String?) ?? KycResult.mismatch;
    } on FunctionException catch (e) {
      throw ProcessFailure(e.status, 'Identity check is unavailable. Try again.');
    }
  }

  @override
  Future<DocumentRecord> uploadDocument({
    required DocKind kind,
    required String name,
    required String mime,
    required Uint8List data,
  }) async {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$_uid/${kind.wire}-${DateTime.now().millisecondsSinceEpoch}-$safe';
    await _sb.storage.from(_bucket).uploadBinary(
      path,
      data,
      fileOptions: FileOptions(contentType: mime, upsert: true),
    );
    final row = await _sb
        .from('documents')
        .insert({
          'applicant_id': _uid,
          'kind': kind.wire,
          'storage_path': path,
          'mime': mime,
          'bytes': data.length,
        })
        .select()
        .single();
    return DocumentRecord(
      id: row['id'] as String,
      kind: kind,
      name: name,
      mime: mime,
      bytes: data.length,
      storagePath: path,
      data: data,
    );
  }

  DocumentRecord _docFrom(Map<String, dynamic> r) {
    final path = r['storage_path'] as String;
    return DocumentRecord(
      id: r['id'] as String,
      kind: DocKind.fromWire(r['kind'] as String?),
      name: path.split('/').last,
      mime: r['mime'] as String? ?? 'application/octet-stream',
      bytes: (r['bytes'] as num?)?.toInt() ?? 0,
      storagePath: path,
    );
  }

  @override
  Future<List<DocumentRecord>> myDocuments() async {
    final rows = await _sb.from('documents').select().eq('applicant_id', _uid);
    return [for (final r in rows) _docFrom(r)];
  }

  @override
  Future<Eligibility> processApplication(String applicationId, {String? fixtureKey}) async {
    try {
      await _sb.functions.invoke('process-application', body: {
        'application_id': applicationId,
        'fixture_key': ?fixtureKey,
      });
    } on FunctionException catch (e) {
      final detail = e.details is Map ? (e.details as Map)['error'] as String? : null;
      throw ProcessFailure(e.status, switch (e.status) {
        409 => 'We need to confirm your identity before we can show an amount.',
        422 => 'We could not read this file. Try SMS paste or a clearer PDF.',
        503 => 'Our statement reader is busy. Please retry in a moment.',
        _ => detail ?? 'Something went wrong while scoring. Please retry.',
      });
    } catch (_) {
      throw const ProcessFailure(0, 'Network problem. Check your connection and retry.');
    }
    final r = await latestEligibility(applicationId);
    if (r == null) throw const ProcessFailure(500, 'Scoring pending or failed.');
    return r;
  }

  @override
  Future<Eligibility?> latestEligibility(String applicationId) async {
    final row = await _sb
        .from('eligibility_results')
        .select()
        .eq('application_id', applicationId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : eligibilityFromRow(row);
  }

  // ── Officer ───────────────────────────────────────────────────────────

  static const _fileSelect =
      '*, applicants(*), eligibility_results(*), officer_notes(*)';

  ApplicationFile _fileFrom(Map<String, dynamic> r, {List<DocumentRecord> docs = const []}) {
    final results = [
      for (final e in (r['eligibility_results'] as List? ?? const []))
        eligibilityFromRow(Map<String, dynamic>.from(e as Map)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final notes = [
      for (final n in (r['officer_notes'] as List? ?? const []))
        OfficerNote(
          body: '${n['body']}',
          createdAt: DateTime.tryParse('${n['created_at']}')?.toLocal() ?? DateTime.now(),
        ),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ApplicationFile(
      applicant: profileFromRow(Map<String, dynamic>.from(r['applicants'] as Map)),
      application: applicationFromRow(r),
      eligibility: results.isEmpty ? null : results.first,
      documents: docs,
      notes: notes,
    );
  }

  @override
  Future<List<ApplicationFile>> queue() async {
    final rows = await _sb
        .from('applications')
        .select(_fileSelect)
        .neq('status', 'draft')
        .order('created_at', ascending: false);
    return [for (final r in rows) _fileFrom(r)];
  }

  @override
  Future<ApplicationFile?> file(String applicationId) async {
    final r = await _sb.from('applications').select(_fileSelect).eq('id', applicationId).maybeSingle();
    if (r == null) return null;
    final docs = await _sb.from('documents').select().eq('applicant_id', r['applicant_id'] as String);
    return _fileFrom(r, docs: [for (final d in docs) _docFrom(d)]);
  }

  @override
  Future<void> addNote(String applicationId, String body) async {
    await _sb.from('officer_notes').insert({
      'application_id': applicationId,
      'officer_id': _uid,
      'body': body,
    });
  }

  @override
  Future<void> decide(String applicationId, ApplicationStatus status) async {
    final open = status == ApplicationStatus.inReview;
    await _sb.from('applications').update({
      'status': status.wire,
      'officer_id': _uid,
      'decided_at': open ? null : DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', applicationId);
  }

  @override
  Future<String?> signedUrl(DocumentRecord doc) =>
      _sb.storage.from(_bucket).createSignedUrl(doc.storagePath, 600);
}
