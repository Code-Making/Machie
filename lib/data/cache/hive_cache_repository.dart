// =========================================
// UPDATED: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'dart:convert'; // ADDED for jsonEncode
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart'; // ADDED
import 'cache_repository.dart';

/// A [CacheRepository] implementation that uses the Hive database for storage.
class HiveCacheRepository implements CacheRepository {
  // ADDED: A logger instance.
  final Talker _talker;

  // ADDED: The constructor now accepts a Talker instance.
  HiveCacheRepository(this._talker);

  @override
  Future<void> init() async {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
    _talker.info('HiveCacheRepository initialized at: ${appDocumentDir.path}');
  }

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
    final value = box.get(key);
    
    // ADDED: Log when data is retrieved from the cache.
    if (value != null) {
      _talker.verbose('CACHE GET: box="$boxName", key="$key"');
    }
    
    return value;
  }

  // UPDATED: The put method now logs the data being saved.
  @override
  Future<void> put<T>(String boxName, String key, T value) async {
    final box = await _openBox<T>(boxName);
    await box.put(key, value);

    // --- LOGGING THE SAVED DATA ---
    String formattedValue;
    // Use a pretty-printed JSON format for maps, which is most of our state.
    if (value is Map) {
      formattedValue = const JsonEncoder.withIndent('  ').convert(value);
    } else {
      formattedValue = value.toString();
    }
    
    // Log with 'verbose' level so it's detailed but can be filtered out in production.
    _talker.verbose(
      'CACHE PUT: box="$boxName", key="$key"\nValue:\n$formattedValue'
    );
    // --- END OF LOGGING ---
  }

  @override
  Future<void> delete(String boxName, String key) async {
    final box = await _openBox(boxName);
    await box.delete(key);
    _talker.verbose('CACHE DELETE: box="$boxName", key="$key"');
  }

  @override
  Future<void> clearBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box(boxName).close();
    }
    await Hive.deleteBoxFromDisk(boxName);
    _talker.info('CACHE CLEARED: box="$boxName"');
  }

  @override
  Future<void> close() async {
    await Hive.close();
  }
}