import 'dart:typed_data';

import 'enums.dart';
import 'extract.dart';

class SessionUser {
  const SessionUser({required this.id, required this.email, required this.isOfficer});
  final String id;
  final String email;
  final bool isOfficer;
}

/// One row of `applicants`. Detail fields keep their column names as keys so
/// the A4 form, the demo store and Supabase all speak the same language.
class ApplicantProfile {
  ApplicantProfile({
    required this.id,
    this.role = ApplicantRole.individual,
    Map<String, String>? fields,
    this.bvnMasked,
    this.ninMasked,
    this.kycResult,
    this.holdingsNgn,
  }) : fields = fields ?? {};

  final String id;
  ApplicantRole role;
  final Map<String, String> fields;
  String? bvnMasked;
  String? ninMasked;
  KycResult? kycResult;
  int? holdingsNgn;

  String get displayName {
    final n = role == ApplicantRole.corporate
        ? fields['registered_name']
        : fields['legal_name'];
    return (n == null || n.trim().isEmpty) ? (fields['email'] ?? 'Applicant') : n.trim();
  }

  /// Name printed under the signature: the person signing.
  String get signingName => role == ApplicantRole.corporate
      ? (fields['signatory_1_name'] ?? displayName)
      : displayName;
}

class Application {
  Application({
    required this.id,
    required this.applicantId,
    this.requestedAmount,
    this.tenorMonths = 12,
    this.purpose,
    this.smsText,
    this.status = ApplicationStatus.draft,
    DateTime? createdAt,
    this.decidedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String applicantId;
  int? requestedAmount;
  int tenorMonths;
  String? purpose;
  String? smsText;
  ApplicationStatus status;
  final DateTime createdAt;
  DateTime? decidedAt;
}

class Eligibility {
  const Eligibility({
    required this.applicationId,
    required this.amount,
    required this.tier,
    required this.warnings,
    required this.narrative,
    required this.extract,
    required this.modelVersion,
    required this.createdAt,
  });

  final String applicationId;
  final int? amount;
  final Tier? tier;
  final List<String> warnings;
  final String? narrative;
  final Extract? extract;
  final String? modelVersion;
  final DateTime createdAt;
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.mime,
    required this.bytes,
    required this.storagePath,
    this.data,
  });

  final String id;
  final DocKind kind;
  final String name;
  final String mime;
  final int bytes;
  final String storagePath;

  /// In-memory bytes (demo mode, or just-uploaded files).
  final Uint8List? data;

  bool get isImage => mime.startsWith('image/');
}

class OfficerNote {
  const OfficerNote({required this.body, required this.createdAt, this.author});
  final String body;
  final DateTime createdAt;
  final String? author;
}

/// Everything O1 and O2 need about one application.
class ApplicationFile {
  const ApplicationFile({
    required this.applicant,
    required this.application,
    required this.eligibility,
    this.documents = const [],
    this.notes = const [],
  });

  final ApplicantProfile applicant;
  final Application application;
  final Eligibility? eligibility;
  final List<DocumentRecord> documents;
  final List<OfficerNote> notes;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Result of process-application, mapped from its HTTP contract.
class ProcessFailure implements Exception {
  const ProcessFailure(this.code, this.message);

  /// 409 KYC mismatch · 422 unreadable · 503 model down · 0 network.
  final int code;
  final String message;

  bool get unreadable => code == 422;

  @override
  String toString() => message;
}
