import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/enums.dart';
import '../models/extract.dart';
import '../models/records.dart';
import '../scoring/narrative.dart';
import '../scoring/score_engine.dart';
import '../utils/money.dart';
import 'demo_store.dart';
import 'fixtures.dart';
import 'local_extractor.dart';
import 'repository.dart';

typedef _Account = ({String id, String passwordHash, bool officer});

/// Offline backend so the pitch never depends on the network. Used when
/// SUPABASE_URL is not supplied at build time. State is saved to a
/// [DemoStore] after every change, so a page refresh mid-pitch loses nothing.
class DemoRepository implements FastTrackRepository {
  DemoRepository._(this._store);

  /// Restores the saved demo, or seeds a fresh one.
  static Future<DemoRepository> open([DemoStore? store]) async {
    final repo = DemoRepository._(store ?? PrefsDemoStore());
    var restored = false;
    try {
      final saved = await repo._store.read();
      if (saved != null) {
        repo._restore(jsonDecode(saved) as Map<String, dynamic>);
        restored = true;
      }
    } catch (_) {
      // Corrupt or old-format state: start clean rather than crash the pitch.
    }
    if (!restored) {
      repo._seed();
      await repo._save();
    }
    return repo;
  }

  static const officerEmail = 'officer@fasttrack.demo';
  static const applicantEmail = 'applicant@fasttrack.demo';
  static const demoPassword = 'FastTrack!demo1';
  static const _modelVersion = 'demo-fixture-cache';

  /// Larger uploads keep their metadata but not their bytes, so the saved
  /// state stays well under the browser's ~5 MB localStorage quota.
  static const _maxPersistedBytes = 600 * 1024;

  final DemoStore _store;
  final _rng = Random.secure();
  final _accounts = <String, _Account>{};
  final _profiles = <String, ApplicantProfile>{};
  final _applications = <String, Application>{};
  final _results = <String, Eligibility>{};
  final _documents = <String, List<DocumentRecord>>{};
  final _notes = <String, List<OfficerNote>>{};
  SessionUser? _user;
  Future<void> _saving = Future.value();

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

  static String _hash(String password) => sha256.convert(utf8.encode(password)).toString();

  Future<void> _latency([int ms = 250]) => Future.delayed(Duration(milliseconds: ms));

  /// Wipes everything back to the three seed personas and signs out.
  Future<void> resetDemo() async {
    _accounts.clear();
    _profiles.clear();
    _applications.clear();
    _results.clear();
    _documents.clear();
    _notes.clear();
    _user = null;
    _seed();
    await _save();
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  @override
  Future<SessionUser> signUp(String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const AuthFailure('An account with this email already exists. Sign in instead.');
    }
    final id = _uuid();
    _accounts[key] = (id: id, passwordHash: _hash(password), officer: false);
    _profiles[id] = ApplicantProfile(id: id, fields: {'email': key});
    _user = SessionUser(id: id, email: key, isOfficer: false);
    await _save();
    return _user!;
  }

  @override
  Future<SessionUser> signIn(String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    final acct = _accounts[key];
    if (acct == null || acct.passwordHash != _hash(password)) {
      throw const AuthFailure('Email or password is incorrect.');
    }
    _user = SessionUser(id: acct.id, email: key, isOfficer: acct.officer);
    await _save();
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    await _save();
  }

  // ── Applicant ─────────────────────────────────────────────────────────

  SessionUser get _me => _user ?? (throw const AuthFailure('Please sign in.'));

  @override
  Future<ApplicantProfile> loadProfile() async =>
      _profiles.putIfAbsent(_me.id, () => ApplicantProfile(id: _me.id, fields: {'email': _me.email}));

  @override
  Future<void> saveProfile(ApplicantProfile profile) async {
    _profiles[profile.id] = profile;
    await _save();
  }

  @override
  Future<Application> loadOrCreateApplication() async {
    final mine = _applications.values.where((a) => a.applicantId == _me.id);
    if (mine.isNotEmpty) return mine.first;
    final app = Application(id: _uuid(), applicantId: _me.id);
    _applications[app.id] = app;
    await _save();
    return app;
  }

  @override
  Future<void> saveApplication(Application application) async {
    _applications[application.id] = application;
    await _save();
  }

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
    await _save();
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
    await _save();
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
      await _save();
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
    await _save();
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
    await _save();
  }

  @override
  Future<void> decide(String applicationId, ApplicationStatus status) async {
    final a = _applications[applicationId]!;
    a
      ..status = status
      ..decidedAt = status == ApplicationStatus.inReview ? null : DateTime.now();
    await _save();
  }

  @override
  Future<String?> signedUrl(DocumentRecord doc) async => null;

  // ── Persistence ───────────────────────────────────────────────────────

  /// Saves are chained so two quick writes can never land out of order.
  Future<void> _save() {
    final snapshot = jsonEncode(_toJson());
    return _saving = _saving.then((_) => _store.write(snapshot)).catchError((_) {});
  }

  Map<String, dynamic> _toJson() => {
    'v': 1,
    'session': _user == null ? null : {'id': _user!.id, 'email': _user!.email, 'officer': _user!.isOfficer},
    'accounts': {
      for (final e in _accounts.entries)
        e.key: {'id': e.value.id, 'hash': e.value.passwordHash, 'officer': e.value.officer},
    },
    'profiles': [
      for (final p in _profiles.values)
        {
          'id': p.id,
          'role': p.role.wire,
          'fields': p.fields,
          'bvn': p.bvnMasked,
          'nin': p.ninMasked,
          'kyc': p.kycResult?.wire,
          'holdings': p.holdingsNgn,
        },
    ],
    'applications': [
      for (final a in _applications.values)
        {
          'id': a.id,
          'applicant': a.applicantId,
          'requested': a.requestedAmount,
          'tenor': a.tenorMonths,
          'purpose': a.purpose,
          'sms': a.smsText,
          'status': a.status.wire,
          'created': a.createdAt.toIso8601String(),
          'decided': a.decidedAt?.toIso8601String(),
        },
    ],
    'results': [
      for (final r in _results.values)
        {
          'app': r.applicationId,
          'amount': r.amount,
          'tier': r.tier?.wire,
          'warnings': r.warnings,
          'narrative': r.narrative,
          'extract': r.extract?.toJson(),
          'model': r.modelVersion,
          'created': r.createdAt.toIso8601String(),
        },
    ],
    'documents': {
      for (final e in _documents.entries)
        e.key: [
          for (final d in e.value)
            {
              'id': d.id,
              'kind': d.kind.wire,
              'name': d.name,
              'mime': d.mime,
              'bytes': d.bytes,
              'path': d.storagePath,
              'data': d.data != null && d.data!.length <= _maxPersistedBytes ? base64Encode(d.data!) : null,
            },
        ],
    },
    'notes': {
      for (final e in _notes.entries)
        e.key: [
          for (final n in e.value) {'body': n.body, 'at': n.createdAt.toIso8601String(), 'by': n.author},
        ],
    },
  };

  void _restore(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('Unknown demo state version');
    DateTime date(Object? v) => DateTime.tryParse('$v') ?? DateTime.now();

    for (final e in (j['accounts'] as Map).entries) {
      final a = e.value as Map;
      _accounts['${e.key}'] = (id: '${a['id']}', passwordHash: '${a['hash']}', officer: a['officer'] == true);
    }
    for (final raw in j['profiles'] as List) {
      final p = raw as Map;
      _profiles['${p['id']}'] = ApplicantProfile(
        id: '${p['id']}',
        role: ApplicantRole.fromWire(p['role'] as String?),
        fields: Map<String, String>.from(p['fields'] as Map),
        bvnMasked: p['bvn'] as String?,
        ninMasked: p['nin'] as String?,
        kycResult: KycResult.fromWire(p['kyc'] as String?),
        holdingsNgn: (p['holdings'] as num?)?.toInt(),
      );
    }
    for (final raw in j['applications'] as List) {
      final a = raw as Map;
      _applications['${a['id']}'] = Application(
        id: '${a['id']}',
        applicantId: '${a['applicant']}',
        requestedAmount: (a['requested'] as num?)?.toInt(),
        tenorMonths: (a['tenor'] as num?)?.toInt() ?? 12,
        purpose: a['purpose'] as String?,
        smsText: a['sms'] as String?,
        status: ApplicationStatus.fromWire(a['status'] as String?),
        createdAt: date(a['created']),
        decidedAt: a['decided'] == null ? null : date(a['decided']),
      );
    }
    for (final raw in j['results'] as List) {
      final r = raw as Map;
      _results['${r['app']}'] = Eligibility(
        applicationId: '${r['app']}',
        amount: (r['amount'] as num?)?.toInt(),
        tier: Tier.fromWire(r['tier'] as String?),
        warnings: [for (final w in (r['warnings'] as List? ?? const [])) '$w'],
        narrative: r['narrative'] as String?,
        extract: r['extract'] == null ? null : Extract.fromJson(Map<String, dynamic>.from(r['extract'] as Map)),
        modelVersion: r['model'] as String?,
        createdAt: date(r['created']),
      );
    }
    for (final e in (j['documents'] as Map).entries) {
      _documents['${e.key}'] = [
        for (final raw in e.value as List)
          () {
            final d = raw as Map;
            return DocumentRecord(
              id: '${d['id']}',
              kind: DocKind.fromWire(d['kind'] as String?),
              name: '${d['name']}',
              mime: '${d['mime']}',
              bytes: (d['bytes'] as num?)?.toInt() ?? 0,
              storagePath: '${d['path']}',
              data: d['data'] == null ? null : base64Decode(d['data'] as String),
            );
          }(),
      ];
    }
    for (final e in (j['notes'] as Map).entries) {
      _notes['${e.key}'] = [
        for (final raw in e.value as List)
          OfficerNote(
            body: '${(raw as Map)['body']}',
            createdAt: date(raw['at']),
            author: raw['by'] as String?,
          ),
      ];
    }
    final s = j['session'] as Map?;
    if (s != null && _accounts.values.any((a) => a.id == s['id'])) {
      _user = SessionUser(id: '${s['id']}', email: '${s['email']}', isOfficer: s['officer'] == true);
    }
  }

  // ── Seed ──────────────────────────────────────────────────────────────

  void _seed() {
    _accounts[officerEmail] = (id: _uuid(), passwordHash: _hash(demoPassword), officer: true);
    final applicantId = _uuid();
    _accounts[applicantEmail] = (id: applicantId, passwordHash: _hash(demoPassword), officer: false);
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
