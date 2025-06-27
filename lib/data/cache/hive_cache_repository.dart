// =========================================
// UPDATED: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'cache_repository.dart';

class HiveCacheRepository implements CacheRepository {
  final Talker _talker;

  HiveCacheRepository(this._talker);

  @override
  Future<void> init() async {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
    _talker.info('HiveCacheRepository initialized at: ${appDocumentDir.path}');
  }

  // REFACTORED: We will always open boxes as containing `dynamic` data
  // to avoid type issues when Hive deserializes maps.
  Future<Box> _openBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    } else {
      return await Hive.openBox(boxName);
    }
  }

  // REFACTORED: This is the corrected 'get' method.
  @override
  Future<T?> get<T>(String boxName, String key) async {
    final box = await _openBox(boxName);
    final dynamic value = box.get(key);

    if (value == null) {
      return null;
    }

    _talker.verbose('CACHE GET: box="$boxName", key="$key"');

    // THE FIX: Check if the retrieved value is an instance of the
    // type T that the caller expects.
    if (value is T) {
      // If it's already the correct type (e.g., for simple types like String, int),
      // we can return it directly.
      return value;
    }
    
    // If the value is a Map, but not of the exact type T, we attempt a cast.
    // This handles the case where Hive returns Map<dynamic, dynamic> and we
    // expect Map<String, dynamic>.
    if (value is Map) {
      try {
        // Attempt to cast the map. This is where the conversion happens.
        final castedMap = Map<String, dynamic>.from(value);
        // We then check if this newly casted map is compatible with the
        // requested type T before returning.
        if (castedMap is T) {
          return castedMap;
        }
      } catch (e) {
        _talker.error('HiveCacheRepository: Failed to cast map for key "$key" in box "$boxName". Error: $e');
        return null;
      }
    }

    // If all checks and casts fail, log a warning and return null.
    _talker.warning('HiveCacheRepository: Type mismatch for key "$key" in box "$boxName". Expected $T but got ${value.runtimeType}.');
    return null;
  }

  // UPDATED: The put method now uses the generic _openBox helper.
  @override
  Future<void> put<T>(String boxName, String key, T value) async {
    final box = await _openBox(boxName); // No type argument needed here.
    await box.put(key, value);
    
    String formattedValue;
    if (value is Map) {
      formattedValue = const JsonEncoder.withIndent('  ').convert(value);
    } else {
      formattedValue = value.toString();
    }
    
    _talker.verbose(
      'CACHE PUT: box="$boxName", key="$key"\nValue:\n$formattedValue'
    );
        await box.flush();
  }

  // --- The rest of the file is unchanged and correct ---

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