import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where settings are saved. SharedPreferences in the app, memory in tests.
abstract interface class SettingsStore {
  Future<bool?> readBool(String key);
  Future<void> writeBool(String key, bool value);
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  @override
  Future<bool?> readBool(String key) async => (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> writeBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);

  @override
  Future<String?> readString(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

class MemorySettingsStore implements SettingsStore {
  final values = <String, Object>{};

  @override
  Future<bool?> readBool(String key) async => values[key] as bool?;

  @override
  Future<void> writeBool(String key, bool value) async => values[key] = value;

  @override
  Future<String?> readString(String key) async => values[key] as String?;

  @override
  Future<void> writeString(String key, String value) async => values[key] = value;
}

/// App preferences. Listeners rebuild when a setting changes.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store);

  static const String dataSaverKey = 'dataSaver';
  static const String themeModeKey = 'themeMode';

  final SettingsStore _store;
  bool _dataSaver = false;
  ThemeMode _themeMode = ThemeMode.light;

  /// When on, report photos load only after a tap, to save mobile data.
  bool get dataSaver => _dataSaver;

  /// Light (the default) or dark. The app does not follow the phone's setting.
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    _dataSaver = await _store.readBool(dataSaverKey) ?? false;
    final mode = await _store.readString(themeModeKey);
    _themeMode = mode == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDataSaver(bool value) async {
    if (_dataSaver == value) return;
    _dataSaver = value;
    notifyListeners();
    await _store.writeBool(dataSaverKey, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    // Only light and dark are offered.
    if (mode == ThemeMode.system) mode = ThemeMode.light;
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _store.writeString(themeModeKey, mode.name);
  }
}
