// =========================================
// UPDATED: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Ensure this is imported
import 'cache_repository.dart';

/// A [CacheRepository] implementation that uses the Hive database for storage.
class HiveCacheRepository implements CacheRepository {
  
  // REFACTORED: The init method now uses path_provider to ensure
  // the database is stored in a permanent location.
  @override
  Future<void> init() async {
    // 1. Get the directory for storing permanent application files.
    final appDocumentDir = await getApplicationDocumentsDirectory();

    // 2. Initialize Hive in that specific, permanent directory.
    // This prevents the OS from clearing the cache.
    Hive.init(appDocumentDir.path);
    
    // Note: We are no longer calling Hive.initFlutter() as we are now
    // explicitly providing the path. Hive.init() is sufficient.
  }

  /// Helper to safely open a Hive box.
  Future<Box<T>> _openBox<T>(String boxName) async {
    // This part of the logic remains robust. If a box is already open,
    // it returns the instance; otherwise, it opens it.
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      // Hive will use the path we provided in init() to open/create the box file.
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
    // To ensure all resources are released, we should close the box
    // before deleting it from disk.
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