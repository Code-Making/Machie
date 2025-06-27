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

  // REFACTORED: This is the final, simplified, and type-safe `get` method.
  @override
  Future<T?> get<T>(String boxName, String key) async {
    final box = await _openBox(boxName);
    final dynamic value = box.get(key);

    if (value == null) {
      return null;
    }
    
    _talker.verbose('CACHE GET: box="$boxName", key="$key"');

    try {
      // If the retrieved value is a Map (which is what Hive returns for JSON-like objects),
      // we perform the cast to the specific Map type our app uses.
      if (value is Map) {
        // This cast is safe because the call site in CacheService
        // specifically requests Future<Map<String, dynamic>?>.
        return Map<String, dynamic>.from(value) as T?;
      }
      
      // If it's a simple type (String, int, etc.), this cast will work directly.
      return value as T?;
    } catch (e) {
      _talker.error(
        'HiveCacheRepository: Failed to cast value for key "$key" in box "$boxName". '
        'Expected type $T but got ${value.runtimeType}. Error: $e'
      );
      return null;
    }
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