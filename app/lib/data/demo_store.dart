import 'package:shared_preferences/shared_preferences.dart';

/// Where the offline demo keeps its state between page refreshes.
/// Browser localStorage on web, platform preferences on Android / iOS.
abstract class DemoStore {
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

class PrefsDemoStore implements DemoStore {
  static const _key = 'fasttrack.demo.v1';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read() => _prefs.getString(_key);

  @override
  Future<void> write(String json) => _prefs.setString(_key, json);

  @override
  Future<void> clear() => _prefs.remove(_key);
}

/// Non-persistent store for tests.
class MemoryDemoStore implements DemoStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;

  @override
  Future<void> clear() async => value = null;
}
