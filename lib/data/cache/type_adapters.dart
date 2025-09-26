// =========================================
// NEW FILE: lib/data/cache/type_adapters.dart
// =========================================

/// Abstract interface for a type adapter that can convert a specific
/// object type [T] to and from a JSON-like map.
///
/// This provides a layer of abstraction over any specific serialization
/// library's adapter implementation (e.g., Hive's TypeAdapter).
abstract class TypeAdapter<T> {
  /// Converts the given [object] of type [T] into a serializable map.
  Map<String, dynamic> toJson(T object);

  /// Creates an object of type [T] from a deserialized [json] map.
  T fromJson(Map<String, dynamic> json);
}
