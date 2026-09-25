import 'dart:typed_data';

import '../models/enums.dart';
import '../models/records.dart';

/// One seam between the UI and the backend. `DemoRepository` runs fully
/// offline with seed personas; `SupabaseRepository` talks to the real stack.
abstract class FastTrackRepository {
  bool get isDemo;

  SessionUser? get currentUser;
  Future<SessionUser> signUp(String email, String password);
  Future<SessionUser> signIn(String email, String password);
  Future<void> signOut();

  // Applicant
  Future<ApplicantProfile> loadProfile();
  Future<void> saveProfile(ApplicantProfile profile);
  Future<Application> loadOrCreateApplication();
  Future<void> saveApplication(Application application);
  Future<KycResult> kycCheck({String? bvn, String? nin, required String legalName});
  Future<DocumentRecord> uploadDocument({
    required DocKind kind,
    required String name,
    required String mime,
    required Uint8List data,
  });
  Future<List<DocumentRecord>> myDocuments();

  /// Extract → rules → narrative. Throws [ProcessFailure].
  Future<Eligibility> processApplication(String applicationId, {String? fixtureKey});
  Future<Eligibility?> latestEligibility(String applicationId);

  // Officer
  Future<List<ApplicationFile>> queue();
  Future<ApplicationFile?> file(String applicationId);
  Future<void> addNote(String applicationId, String body);
  Future<void> decide(String applicationId, ApplicationStatus status);

  /// Short-lived (≤ 10 min) link for a stored document, or null if in memory.
  Future<String?> signedUrl(DocumentRecord doc);
}
