// =========================================
// UPDATED: lib/data/persistence_service.dart
// =========================================

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Project imports:
import '../logs/logs_provider.dart';

import '../data/dto/app_state_dto.dart'; // ADDED

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
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
    _talker.info("Loading app state");
    final jsonString = _prefs.getString(_appStateKey);
    if (jsonString != null) {
      _talker.info("loading appState String: $jsonString");
      try {
        return AppStateDto.fromJson(jsonDecode(jsonString));
      } catch (e, st) {
        // Corrupted data, start with a fresh DTO.
        _talker.handle(e, st, 'Error loading app state, starting fresh');
        return const AppStateDto();
      }
    }
    _talker.info("No app state to load");
    return const AppStateDto(); // Return fresh DTO if nothing is saved.
  }

  /// Saves the AppStateDto to SharedPreferences.
  Future<void> saveAppStateDto(AppStateDto dto) async {
    final appStateString = jsonEncode(dto.toJson());
    _talker.info("saving appState String: $appStateString");
    await _prefs.setString(_appStateKey, appStateString);
  }
}
