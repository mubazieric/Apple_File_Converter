import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/settings/app_settings.dart';

/// Persistence for [AppSettings].
///
/// The interface exists so the settings controller can be unit-tested without a platform
/// plugin; the production implementation is a thin `shared_preferences` wrapper.
abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// Stores settings as a single JSON string under one key.
///
/// A corrupt or partially-written value is treated as "no settings yet" and the documented
/// defaults are returned, so a bad write can never brick the app.
class SharedPreferencesSettingsStore implements SettingsStore {
  static const String storageKey = 'apple_file_converter.settings.v1';

  @override
  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return const AppSettings();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AppSettings.fromMap(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // Fall through to defaults.
    }
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(settings.toMap()));
  }
}

/// In-memory store used by tests and as a safe fallback.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    saveCount++;
  }
}
