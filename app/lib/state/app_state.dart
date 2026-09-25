import 'package:flutter/foundation.dart';

import '../data/fixtures.dart';
import '../data/repository.dart';
import '../models/enums.dart';
import '../models/records.dart';

/// Session + the applicant's single in-flight application (v1: one each).
class AppState extends ChangeNotifier {
  AppState(this.repo) : _user = repo.currentUser;

  final FastTrackRepository repo;

  SessionUser? _user;
  SessionUser? get user => _user;
  bool get signedIn => _user != null;
  bool get isOfficer => _user?.isOfficer ?? false;

  /// Chosen on A2 before an account exists; applied on first profile load.
  ApplicantRole pendingRole = ApplicantRole.individual;

  ApplicantProfile? profile;
  Application? application;
  Eligibility? eligibility;
  final Map<DocKind, DocumentRecord> documents = {};

  Future<void> signUp(String email, String password) async {
    _user = await repo.signUp(email, password);
    await loadApplicant(applyPendingRole: true);
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    _user = await repo.signIn(email, password);
    if (!isOfficer) await loadApplicant();
    notifyListeners();
  }

  Future<void> signOut() async {
    await repo.signOut();
    _user = null;
    profile = null;
    application = null;
    eligibility = null;
    documents.clear();
    notifyListeners();
  }

  /// Restores profile, application, documents and last result.
  Future<void> loadApplicant({bool applyPendingRole = false}) async {
    if (_user == null || isOfficer) return;
    final p = await repo.loadProfile();
    if (applyPendingRole && p.role != pendingRole) {
      p.role = pendingRole;
      await repo.saveProfile(p);
    }
    profile = p;
    application = await repo.loadOrCreateApplication();
    documents
      ..clear()
      ..addEntries((await repo.myDocuments()).map((d) => MapEntry(d.kind, d)));
    eligibility = await repo.latestEligibility(application!.id);
    notifyListeners();
  }

  Future<void> ensureApplicant() async {
    if (profile == null || application == null) await loadApplicant();
  }

  Future<void> setRole(ApplicantRole role) async {
    pendingRole = role;
    final p = profile;
    if (p != null && p.role != role) {
      p.role = role;
      await repo.saveProfile(p);
    }
    notifyListeners();
  }

  Future<void> saveDraft() async {
    if (profile != null) await repo.saveProfile(profile!);
    if (application != null) await repo.saveApplication(application!);
    notifyListeners();
  }

  Future<KycResult> checkKyc({String? bvn, String? nin}) async {
    final r = await repo.kycCheck(bvn: bvn, nin: nin, legalName: profile?.signingName ?? '');
    profile = await repo.loadProfile();
    notifyListeners();
    return r;
  }

  Future<void> upload(DocKind kind, String name, String mime, Uint8List data) async {
    documents[kind] = await repo.uploadDocument(kind: kind, name: name, mime: mime, data: data);
    notifyListeners();
  }

  void removeDocument(DocKind kind) {
    documents.remove(kind);
    notifyListeners();
  }

  Future<void> submit() async {
    final a = application!;
    a.status = ApplicationStatus.submitted;
    await repo.saveApplication(a);
    notifyListeners();
  }

  Future<Eligibility> process() async {
    final a = application!;
    try {
      // Seeded walks pass their fixture key so the pitch never waits on Gemini.
      final sms = a.smsText;
      eligibility = await repo.processApplication(
        a.id,
        fixtureKey: sms == null ? null : fixtureKeyFor(sms),
      );
      return eligibility!;
    } finally {
      // Status moves server-side (scored / more_info); pull it back.
      await refreshApplication();
    }
  }

  Future<void> refreshApplication() async {
    if (_user == null || isOfficer) return;
    application = await repo.loadOrCreateApplication();
    eligibility = await repo.latestEligibility(application!.id);
    notifyListeners();
  }
}
