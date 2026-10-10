/// Abstraction over the raw key/value persistence mechanism.
///
/// The game logic depends only on this interface, so the SharedPreferences
/// implementation can be swapped for a cloud-synced backend later without
/// touching the repository or controller. Tests use the in-memory variant.
abstract class StorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// A simple map-backed implementation for tests and previews.
class MemoryStorage implements StorageBackend {
  MemoryStorage([Map<String, String>? seed])
      : _store = <String, String>{...?seed};

  final Map<String, String> _store;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}
