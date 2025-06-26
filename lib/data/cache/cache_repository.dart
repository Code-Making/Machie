// =========================================
// NEW FILE: lib/data/cache/cache_repository.dart
// =========================================

/// Abstract interface for a key-value caching system.
///
/// This defines a generic contract for storing, retrieving, and deleting
/// data, allowing the underlying implementation (e.g., Hive, Isar) to be
/// swapped without affecting the services that use it.
abstract class CacheRepository {
  /// Initializes the cache database. Must be called once on app startup.
  Future<void> init();

  /// Retrieves a value of type [T] from a specified [boxName] using a [key].
  /// Returns null if the key is not found or if the data is of a different type.
  Future<T?> get<T>(String boxName, String key);

  /// Saves or updates a [value] of type [T] in a specified [boxName] with a [key].
  Future<void> put<T>(String boxName, String key, T value);

  /// Deletes a specific entry from a [boxName] identified by its [key].
  Future<void> delete(String boxName, String key);

  /// Deletes all data within a given [boxName]. This is useful for clearing
  /// all cache related to a specific scope, like a project.
  Future<void> clearBox(String boxName);

  /// Closes the cache database and releases any resources.
  /// Should be called when the application is shutting down.
  Future<void> close();
}