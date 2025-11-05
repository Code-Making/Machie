// =========================================
// UPDATED: lib/data/persistence_service.dart
// =========================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logs/logs_provider.dart';

import '../data/dto/app_state_dto.dart'; // ADDED

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});