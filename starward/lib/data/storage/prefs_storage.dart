import 'package:shared_preferences/shared_preferences.dart';

import 'storage_backend.dart';

/// [StorageBackend] backed by [SharedPreferences] — the on-device persistence
/// used by the running app.
class PrefsStorage implements StorageBackend {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsStorage(prefs);
  }

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> delete(String key) async => _prefs.remove(key);
}
