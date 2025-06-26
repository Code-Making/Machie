// =========================================
// NEW FILE: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'package:hive_flutter/hive_flutter.dart';
import 'cache_repository.dart';

/// A [CacheRepository] implementation that uses the Hive database for storage.
class HiveCacheRepository implements CacheRepository {
  @override
  Future<void> init() async {
    // Initializes Hive in a platform-appropriate directory.
    await Hive.initFlutter();
  }

  /// Helper to safely open a Hive box.
  Future<Box<T>> _openBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

  @override
  Future<T?> get<T>(String boxName, String key) async {
    final box = await _openBox<T>(boxName);
    return box.get(key);
  }

  @override
  Future<void> put<T>(String boxName, String key, T value) async {
    final box = await _openBox<T>(boxName);
    await box.put(key, value);
  }

  @override
  Future<void> delete(String boxName, String key) async {
    final box = await _openBox(boxName);
    await box.delete(key);
  }

  @override
  Future<void> clearBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      final box = Hive.box(boxName);
      await box.clear();
    }
    // Hive also provides a way to delete the entire box file from disk.
    // This is more thorough for complete cleanup.
    await Hive.deleteBoxFromDisk(boxName);
  }

  @override
  Future<void> close() async {
    await Hive.close();
  }
}