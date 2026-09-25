/// Compile-time configuration. Pass with --dart-define (see app/README.md).
/// Only public values belong here: the Neon function URL or the Supabase
/// anon key — never a database URL, service role or Gemini key.
abstract final class Env {
  /// The `fasttrack` Neon Function's invocation URL. Takes precedence over
  /// Supabase when both are set.
  static const neonApiUrl = String.fromEnvironment('NEON_API_URL');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Must stay false in v1. No live KYC provider code exists in this build.
  static const liveKyc = bool.fromEnvironment('LIVE_KYC');

  static bool get hasNeon => neonApiUrl.isNotEmpty;
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Without either backend the app runs fully offline on seed data.
  static bool get hasBackend => hasNeon || hasSupabase;
}
