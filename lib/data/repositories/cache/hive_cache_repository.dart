// =========================================
// UPDATED: lib/data/cache/hive_cache_repository.dart
// =========================================

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'cache_repository.dart';

class HiveCacheRepository implements CacheRepository {
  final Talker _talker;

  HiveCacheRepository(this._talker);

  @override
  Future<void> init() async {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    IsolatedHive.init(appDocumentDir.path);
    _talker.info(
      'IsolatedHiveCacheRepository initialized at: ${appDocumentDir.path}',
    );
  }

  // REFACTORED: We will always open boxes as containing `dynamic` data
  // to avoid type issues when Hive deserializes maps.
  Future<IsolatedBox> _openBox(String boxName) async {
    if (IsolatedHive.isBoxOpen(boxName)) {
      return IsolatedHive.box(boxName);
    } else {
      return await IsolatedHive.openBox(boxName);
    }
  }

  // REFACTORED: This is the final, simplified, and type-safe `get` method.
  @override
  Future<T?> get<T>(String boxName, String key) async {
    final box = await _openBox(boxName);

    // CORRECTED: Added 'await' here. This is the fix.
    final dynamic value = await box.get(key);

    if (value == null) {
      return null;
    }

    _talker.verbose('CACHE GET: box="$boxName", key="$key"');
    try {
      if (value is Map) {
        // Now that 'value' is a real Map, this cast will succeed.
        return Map<String, dynamic>.from(value) as T?;
      }
      return value as T?;
    } catch (e) {
      _talker.error(
        'HiveCacheRepository: Failed to cast value for key "$key" in box "$boxName". '
        'Expected type $T but got ${value.runtimeType}. Error: $e',
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
      'CACHE PUT: box="$boxName", key="$key"\nValue:\n$formattedValue',
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
    if (IsolatedHive.isBoxOpen(boxName)) {
      await IsolatedHive.box(boxName).close();
    }
    await IsolatedHive.deleteBoxFromDisk(boxName);
    _talker.info('CACHE CLEARED: box="$boxName"');
  }

  @override
  Future<void> close() async {
    await IsolatedHive.close();
  }
}
