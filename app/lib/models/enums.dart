// Mirrors the Postgres enums in supabase/migrations/0001_schema.sql.
// Postgres is the source of truth; `wire` is the exact enum label.

enum ApplicantRole {
  individual('individual'),
  corporate('corporate');

  const ApplicantRole(this.wire);
  final String wire;

  static ApplicantRole fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => individual);
}

enum KycResult {
  sandboxPass('sandbox_pass'),
  sandboxFail('sandbox_fail'),
  mismatch('mismatch');

  const KycResult(this.wire);
  final String wire;

  static KycResult? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum ApplicationStatus {
  draft('draft', 'Draft'),
  submitted('submitted', 'Submitted'),
  scored('scored', 'New'),
  inReview('in_review', 'In review'),
  moreInfo('more_info', 'More info'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined');

  const ApplicationStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ApplicationStatus fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => draft);
}

enum Tier {
  low('low', 'Low', 'Standard review'),
  medium('medium', 'Medium', 'Elevated review'),
  high('high', 'High', 'High review');

  const Tier(this.wire, this.label, this.applicantWords);
  final String wire;
  final String label;

  /// A9 shows the tier in words, never a score.
  final String applicantWords;

  static Tier? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum DocKind {
  id('id', 'Government ID'),
  statement('statement', 'Bank statement'),
  cac('cac', 'CAC certificate'),
  signature('signature', 'Signature'),
  other('other', 'Other');

  const DocKind(this.wire, this.label);
  final String wire;
  final String label;

  static DocKind fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => other);
}

enum Regularity {
  stable('stable'),
  lumpy('lumpy'),
  seasonal('seasonal'),
  insufficientHistory('insufficient_history');

  const Regularity(this.wire);
  final String wire;

  static Regularity fromWire(String? v) => values.firstWhere(
    (e) => e.wire == v,
    orElse: () => insufficientHistory,
  );
}
