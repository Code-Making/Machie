// lib/data/persistence_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_state.dart';

// REFACTOR: This class is now effectively a repository for AppState.
// Its role is clear: interact with SharedPreferences for global app data.

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});

/// Manages saving and loading the global application state.
class AppStateRepository {
  static const _appStateKey = 'app_state';

  final SharedPreferences _prefs;

  AppStateRepository(this._prefs);

  Future<AppState> loadAppState() async {
    final jsonString = _prefs.getString(_appStateKey);
    if (jsonString != null) {
      try {
        return AppState.fromJson(jsonDecode(jsonString));
      } catch (e /*, st*/) {
        //talker.handle(e, st, 'Forgot to write talker message');
        //print('Error decoding app state, starting fresh. Error: $e');
        return AppState.initial();
      }
    }
    return AppState.initial();
  }

  Future<void> saveAppState(AppState state) async {
    await _prefs.setString(_appStateKey, jsonEncode(state.toJson()));
  }
}