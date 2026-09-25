import 'package:shared_preferences/shared_preferences.dart';

/// Where the Neon backend's sign-in session is kept between launches:
/// browser localStorage on web, platform preferences on Android / iOS.
/// Holds the opaque refresh token and the signed-in user, never a password.
abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

class PrefsSessionStore implements SessionStore {
  static const _key = 'fasttrack.neon.session.v1';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read() => _prefs.getString(_key);

  @override
  Future<void> write(String json) => _prefs.setString(_key, json);

  @override
  Future<void> clear() => _prefs.remove(_key);
}

/// Non-persistent store for tests.
class MemorySessionStore implements SessionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;

  @override
  Future<void> clear() async => value = null;
}
