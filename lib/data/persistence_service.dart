// lib/data/persistence_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_state.dart';

// Global provider for SharedPreferences, used by the PersistenceService.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// Manages saving and loading the global application state.
class PersistenceService {
  static const _appStateKey = 'app_state';

  final SharedPreferences _prefs;

  PersistenceService(this._prefs);

  Future<AppState> loadAppState() async {
    final jsonString = _prefs.getString(_appStateKey);
    if (jsonString != null) {
      try {
        return AppState.fromJson(jsonDecode(jsonString));
      } catch (e) {
        print('Error decoding app state, starting fresh. Error: $e');
        return AppState.initial();
      }
    }
    return AppState.initial();
  }

  Future<void> saveAppState(AppState state) async {
    await _prefs.setString(_appStateKey, jsonEncode(state.toJson()));
  }
}