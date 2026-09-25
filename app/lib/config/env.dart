/// Compile-time configuration. Pass with --dart-define (see app/README.md).
/// Only the anon key belongs here — never the service role or Gemini key.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Must stay false in v1. No live KYC provider code exists in this build.
  static const liveKyc = bool.fromEnvironment('LIVE_KYC');

  /// Without Supabase config the app runs fully offline on seed data.
  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
