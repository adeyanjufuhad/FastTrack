import '../models/enums.dart';
import '../models/extract.dart';
import '../models/records.dart';

/// Row ↔ model mapping shared by the Supabase and Neon repositories. Both
/// backends return the same Postgres rows as JSON (PostgREST / to_jsonb).

/// A4 form keys that are real `applicants` columns. Anything else (e.g.
/// signatory BVNs) stays on the device and is never persisted.
const applicantColumns = [
  'email', 'phone', 'dob', 'address', 'occupation', 'next_of_kin_name',
  'next_of_kin_phone', 'rc_number', 'nature_of_business',
  'registered_address', 'signatory_1_name', 'signatory_2_name',
];

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

ApplicantProfile profileFromRow(Map<String, dynamic> row) {
  final role = ApplicantRole.fromWire(row['role'] as String?);
  final fields = <String, String>{
    for (final c in applicantColumns)
      if (row[c] != null) c: '${row[c]}',
  };
  final name = row['legal_name'] as String?;
  if (name != null) {
    fields[role == ApplicantRole.corporate ? 'registered_name' : 'legal_name'] = name;
  }
  return ApplicantProfile(
    id: row['id'] as String,
    role: role,
    fields: fields,
    bvnMasked: row['bvn_masked'] as String?,
    ninMasked: row['nin_masked'] as String?,
    kycResult: KycResult.fromWire(row['kyc_result'] as String?),
    holdingsNgn: (row['holdings_ngn'] as num?)?.toInt(),
  );
}

/// The writable profile fields: role, legal name and the A4 columns.
Map<String, dynamic> profileToRow(ApplicantProfile p) => {
  'role': p.role.wire,
  'legal_name': _clean(
    p.role == ApplicantRole.corporate ? p.fields['registered_name'] : p.fields['legal_name'],
  ),
  for (final c in applicantColumns) c: _clean(p.fields[c]),
};

Application applicationFromRow(Map<String, dynamic> r) => Application(
  id: r['id'] as String,
  applicantId: r['applicant_id'] as String,
  requestedAmount: (r['requested_amount'] as num?)?.toInt(),
  tenorMonths: (r['tenor_months'] as num?)?.toInt() ?? 12,
  purpose: r['purpose'] as String?,
  smsText: r['sms_text'] as String?,
  status: ApplicationStatus.fromWire(r['status'] as String?),
  createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal(),
  decidedAt: DateTime.tryParse('${r['decided_at']}')?.toLocal(),
);

Eligibility eligibilityFromRow(Map<String, dynamic> r) => Eligibility(
  applicationId: r['application_id'] as String,
  amount: (r['amount_prequalified'] as num?)?.toInt(),
  tier: Tier.fromWire(r['tier'] as String?),
  warnings: [for (final w in (r['warnings'] as List? ?? const [])) '$w'],
  narrative: r['narrative'] as String?,
  extract: r['extract'] == null
      ? null
      : Extract.fromJson(Map<String, dynamic>.from(r['extract'] as Map)),
  modelVersion: r['model_version'] as String?,
  createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
);
