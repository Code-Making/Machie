// =========================================
// UPDATED: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'cache_repository.dart';

class HiveCacheRepository implements CacheRepository {
  
  @override
  Future<void> init() async {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
  }

  Future<Box<T>> _openBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

// REFACTORED: The 'get' method is now type-safe.
// REFACTORED: The 'get' method is now type-safe.
@override
Future<T?> get<T>(String boxName, String key) async {
  // We open the box without a strict type argument initially, as Hive
  // stores maps as Map<dynamic, dynamic>.
  final box = await _openBox(boxName);
  final dynamic value = box.get(key);

  if (value == null) {
    return null;
  }

  // This is the crucial part. If the requested type T is a Map,
  // we perform a safe, manual cast from Map<dynamic, dynamic>
  // to the specific Map type required (e.g., Map<String, dynamic>).
  if (T.toString() == 'Map<String, dynamic>' && value is Map) {
    return Map<String, dynamic>.from(value) as T;
  }

  // If it's not a map or if the types already match, we can cast directly.
  if (value is T) {
    return value;
  }

  // If the cast is not possible, return null to prevent a runtime crash.
  return null;
}

  @override
  Future<void> put<T>(String boxName, String key, T value) async {
    // The 'put' method is generally safe, as Hive handles serialization.
    final box = await _openBox<T>(boxName);
    await box.put(key, value);
  }
  
  // ... The rest of the file is unchanged and correct ...
  
  @override
  Future<void> delete(String boxName, String key) async {
    final box = await _openBox(boxName);
    await box.delete(key);
  }

  @override
  Future<void> clearBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box(boxName).close();
    }
    await Hive.deleteBoxFromDisk(boxName);
  }

  @override
  Future<void> close() async {
    await Hive.close();
  }
}