import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where settings are saved. SharedPreferences in the app, memory in tests.
abstract interface class SettingsStore {
  Future<bool?> readBool(String key);
  Future<void> writeBool(String key, bool value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  @override
  Future<bool?> readBool(String key) async => (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> writeBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
}

class MemorySettingsStore implements SettingsStore {
  final values = <String, bool>{};

  @override
  Future<bool?> readBool(String key) async => values[key];

  @override
  Future<void> writeBool(String key, bool value) async => values[key] = value;
}

/// App preferences. Listeners rebuild when a setting changes.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store);

  static const String dataSaverKey = 'dataSaver';

  final SettingsStore _store;
  bool _dataSaver = false;

  /// When on, report photos load only after a tap, to save mobile data.
  bool get dataSaver => _dataSaver;

  Future<void> load() async {
    _dataSaver = await _store.readBool(dataSaverKey) ?? false;
    notifyListeners();
  }

  Future<void> setDataSaver(bool value) async {
    if (_dataSaver == value) return;
    _dataSaver = value;
    notifyListeners();
    await _store.writeBool(dataSaverKey, value);
  }
}
