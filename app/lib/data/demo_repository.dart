import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/enums.dart';
import '../models/extract.dart';
import '../models/records.dart';
import '../scoring/narrative.dart';
import '../scoring/score_engine.dart';
import '../utils/money.dart';
import 'fixtures.dart';
import 'local_extractor.dart';
import 'repository.dart';

/// Offline, in-memory backend so the pitch never depends on the network.
/// Used when SUPABASE_URL is not supplied at build time.
class DemoRepository implements FastTrackRepository {
  DemoRepository() {
    _seed();
  }

  static const officerEmail = 'officer@fasttrack.demo';
  static const applicantEmail = 'applicant@fasttrack.demo';
  static const demoPassword = 'FastTrack!demo1';
  static const _modelVersion = 'demo-fixture-cache';

  final _rng = Random.secure();
  final _accounts = <String, ({String id, String password, bool officer})>{};
  final _profiles = <String, ApplicantProfile>{};
  final _applications = <String, Application>{};
  final _results = <String, Eligibility>{};
  final _documents = <String, List<DocumentRecord>>{};
  final _notes = <String, List<OfficerNote>>{};
  SessionUser? _user;

  @override
  bool get isDemo => true;

  @override
  SessionUser? get currentUser => _user;

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _latency([int ms = 250]) => Future.delayed(Duration(milliseconds: ms));

  // ── Auth ──────────────────────────────────────────────────────────────

  @override
  Future<SessionUser> signUp(String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const AuthFailure('An account with this email already exists. Sign in instead.');
    }
    final id = _uuid();
    _accounts[key] = (id: id, password: password, officer: false);
    _profiles[id] = ApplicantProfile(id: id, fields: {'email': key});
    return _user = SessionUser(id: id, email: key, isOfficer: false);
  }

  @override
  Future<SessionUser> signIn(String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    final acct = _accounts[key];
    if (acct == null || acct.password != password) {
      throw const AuthFailure('Email or password is incorrect.');
    }
    return _user = SessionUser(id: acct.id, email: key, isOfficer: acct.officer);
  }

  @override
  Future<void> signOut() async => _user = null;

  // ── Applicant ─────────────────────────────────────────────────────────

  SessionUser get _me => _user ?? (throw const AuthFailure('Please sign in.'));

  @override
  Future<ApplicantProfile> loadProfile() async =>
      _profiles.putIfAbsent(_me.id, () => ApplicantProfile(id: _me.id, fields: {'email': _me.email}));

  @override
  Future<void> saveProfile(ApplicantProfile profile) async => _profiles[profile.id] = profile;

  @override
  Future<Application> loadOrCreateApplication() async {
    final mine = _applications.values.where((a) => a.applicantId == _me.id);
    if (mine.isNotEmpty) return mine.first;
    final app = Application(id: _uuid(), applicantId: _me.id);
    return _applications[app.id] = app;
  }

  @override
  Future<void> saveApplication(Application application) async =>
      _applications[application.id] = application;

  @override
  Future<KycResult> kycCheck({String? bvn, String? nin, required String legalName}) async {
    await _latency(600);
    // Demo rule: BVN or NIN hit passes; exact name is ignored.
    KycResult result = KycResult.mismatch;
    for (final row in kycSandbox) {
      if ((bvn != null && row.bvn == bvn) || (nin != null && row.nin == nin)) {
        result = row.result;
        break;
      }
    }
    final p = await loadProfile();
    p
      ..kycResult = result
      ..bvnMasked = bvn == null || bvn.isEmpty ? null : maskId(bvn)
      ..ninMasked = nin == null || nin.isEmpty ? null : maskId(nin);
    return result;
  }

  @override
  Future<DocumentRecord> uploadDocument({
    required DocKind kind,
    required String name,
    required String mime,
    required Uint8List data,
  }) async {
    await _latency(300);
    final doc = DocumentRecord(
      id: _uuid(),
      kind: kind,
      name: name,
      mime: mime,
      bytes: data.length,
      storagePath: '${_me.id}/${kind.wire}-$name',
      data: data,
    );
    final list = _documents.putIfAbsent(_me.id, () => []);
    // One ID / statement / CAC / signature per applicant — replace on re-upload.
    list.removeWhere((d) => d.kind == kind);
    list.add(doc);
    return doc;
  }

  @override
  Future<List<DocumentRecord>> myDocuments() async => List.of(_documents[_me.id] ?? const []);

  @override
  Future<Eligibility> processApplication(String applicationId, {String? fixtureKey}) async {
    final app = _applications[applicationId];
    if (app == null) throw const ProcessFailure(404, 'Application not found.');
    final profile = _profiles[app.applicantId]!;

    // Honest pacing so A8's three steps are readable during a pitch.
    await _latency(1200);

    Extract? extract;
    final key = fixtureKey ?? (app.smsText == null ? null : fixtureKeyFor(app.smsText!));
    if (key != null && extractFixtures.containsKey(key)) {
      extract = Extract.fromJson(extractFixtures[key]!);
    } else if (app.smsText != null && app.smsText!.trim().isNotEmpty) {
      extract = extractFromSms(app.smsText!);
    }
    if (extract == null) {
      app.status = ApplicationStatus.moreInfo;
      throw const ProcessFailure(
        422,
        'We could not read this file. Try SMS paste or a clearer PDF.',
      );
    }

    final r = score(
      extract,
      kyc: profile.kycResult,
      tenorMonths: app.tenorMonths,
      holdingsNgn: profile.holdingsNgn,
    );
    final result = Eligibility(
      applicationId: app.id,
      amount: r.amount,
      tier: r.blocked ? null : r.tier,
      warnings: r.warnings,
      narrative: officerNarrative(extract, r, role: profile.role),
      extract: extract,
      modelVersion: key != null ? _modelVersion : 'demo-offline-heuristic',
      createdAt: DateTime.now(),
    );
    _results[app.id] = result;
    app.status = r.blocked ? ApplicationStatus.moreInfo : ApplicationStatus.scored;
    return result;
  }

  @override
  Future<Eligibility?> latestEligibility(String applicationId) async => _results[applicationId];

  // ── Officer ───────────────────────────────────────────────────────────

  @override
  Future<List<ApplicationFile>> queue() async {
    await _latency(200);
    final rows = [
      for (final a in _applications.values)
        if (a.status != ApplicationStatus.draft) _fileFor(a),
    ]..sort((x, y) => y.application.createdAt.compareTo(x.application.createdAt));
    return rows;
  }

  @override
  Future<ApplicationFile?> file(String applicationId) async {
    await _latency(150);
    final a = _applications[applicationId];
    return a == null ? null : _fileFor(a);
  }

  ApplicationFile _fileFor(Application a) => ApplicationFile(
    applicant: _profiles[a.applicantId]!,
    application: a,
    eligibility: _results[a.id],
    documents: List.of(_documents[a.applicantId] ?? const []),
    notes: List.of(_notes[a.id] ?? const []),
  );

  @override
  Future<void> addNote(String applicationId, String body) async {
    _notes.putIfAbsent(applicationId, () => []).add(
      OfficerNote(body: body, createdAt: DateTime.now(), author: _me.email),
    );
  }

  @override
  Future<void> decide(String applicationId, ApplicationStatus status) async {
    final a = _applications[applicationId]!;
    a
      ..status = status
      ..decidedAt = status == ApplicationStatus.inReview ? null : DateTime.now();
  }

  @override
  Future<String?> signedUrl(DocumentRecord doc) async => null;

  // ── Seed ──────────────────────────────────────────────────────────────

  void _seed() {
    _accounts[officerEmail] = (id: _uuid(), password: demoPassword, officer: true);
    final applicantId = _uuid();
    _accounts[applicantEmail] = (id: applicantId, password: demoPassword, officer: false);
    _profiles[applicantId] = ApplicantProfile(id: applicantId, fields: {'email': applicantEmail});

    _seedPersona(
      name: 'Adaeze Okafor',
      role: ApplicantRole.individual,
      fields: {'occupation': 'Operations manager', 'phone': '0803 000 0001'},
      bvn: '22222222222',
      nin: '11111111111',
      fixture: 'fixture:adaeze-sms',
      sms: smsAdaeze,
      purpose: 'Rent renewal',
      hoursAgo: 3,
    );
    _seedPersona(
      name: 'Ibrahim Musa',
      role: ApplicantRole.individual,
      fields: {'occupation': 'Trader', 'phone': '0803 000 0002'},
      bvn: '33333333333',
      nin: '11111111112',
      fixture: 'fixture:ibrahim-sms',
      sms: smsIbrahim,
      purpose: 'Stock purchase',
      hoursAgo: 5,
    );
    _seedPersona(
      name: 'Northshore Trading Ltd',
      role: ApplicantRole.corporate,
      fields: {
        'rc_number': 'RC 1234567',
        'nature_of_business': 'Food distribution',
        'signatory_1_name': 'Tunde Bakare',
        'signatory_2_name': 'Ngozi Eze',
      },
      bvn: '55555555555',
      nin: '11111111114',
      fixture: 'fixture:northshore-sms',
      sms: smsNorthshore,
      purpose: 'Working capital',
      hoursAgo: 26,
    );
  }

  void _seedPersona({
    required String name,
    required ApplicantRole role,
    required Map<String, String> fields,
    required String bvn,
    required String nin,
    required String fixture,
    required String sms,
    required String purpose,
    required int hoursAgo,
  }) {
    final id = _uuid();
    final profile = ApplicantProfile(
      id: id,
      role: role,
      fields: {
        role == ApplicantRole.corporate ? 'registered_name' : 'legal_name': name,
        ...fields,
      },
      bvnMasked: maskId(bvn),
      ninMasked: maskId(nin),
      kycResult: KycResult.sandboxPass,
    );
    _profiles[id] = profile;
    final app = Application(
      id: _uuid(),
      applicantId: id,
      tenorMonths: 12,
      purpose: purpose,
      smsText: sms,
      status: ApplicationStatus.scored,
      createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
    );
    _applications[app.id] = app;
    _documents[id] = [
      DocumentRecord(id: _uuid(), kind: DocKind.id, name: 'government-id.jpg', mime: 'image/jpeg', bytes: 412000, storagePath: '$id/id.jpg'),
      if (role == ApplicantRole.corporate)
        DocumentRecord(id: _uuid(), kind: DocKind.cac, name: 'cac-certificate.pdf', mime: 'application/pdf', bytes: 238000, storagePath: '$id/cac.pdf'),
      DocumentRecord(id: _uuid(), kind: DocKind.signature, name: 'signature.png', mime: 'image/png', bytes: 18000, storagePath: '$id/signature.png'),
    ];
    final x = Extract.fromJson(extractFixtures[fixture]!);
    final r = score(x, kyc: profile.kycResult, tenorMonths: app.tenorMonths);
    _results[app.id] = Eligibility(
      applicationId: app.id,
      amount: r.amount,
      tier: r.tier,
      warnings: r.warnings,
      narrative: officerNarrative(x, r, role: role),
      extract: x,
      modelVersion: _modelVersion,
      createdAt: app.createdAt,
    );
  }
}
