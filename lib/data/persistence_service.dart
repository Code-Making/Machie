// =========================================
// UPDATED: lib/data/persistence_service.dart
// =========================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dto/app_state_dto.dart'; // ADDED
import '../logs/logs_provider.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

/// Manages saving and loading the app state DTO to/from SharedPreferences.
class AppStateRepository {
  static const _appStateKey = 'app_state';
  final SharedPreferences _prefs;
  final Talker _talker;

  AppStateRepository(this._prefs, this._talker);

  /// Loads the AppStateDto from SharedPreferences.
  Future<AppStateDto> loadAppStateDto() async {
    final jsonString = _prefs.getString(_appStateKey);
    if (jsonString != null) {
      try {
        return AppStateDto.fromJson(jsonDecode(jsonString));
      } catch (e, st) {
        // Corrupted data, start with a fresh DTO.
        _talker.handle(e, st, 'Error loading app state, starting fresh');
        return const AppStateDto();
      }
    }
    return const AppStateDto(); // Return fresh DTO if nothing is saved.
  }

  /// Saves the AppStateDto to SharedPreferences.
  Future<void> saveAppStateDto(AppStateDto dto) async {
    await _prefs.setString(_appStateKey, jsonEncode(dto.toJson()));
  }
}