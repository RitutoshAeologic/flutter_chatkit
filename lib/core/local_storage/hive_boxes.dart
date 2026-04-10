import 'package:shared_preferences/shared_preferences.dart';

class HiveBoxes {
  static SharedPreferences? _prefs;

  /// Keeps the API identical to previous Hive implementation for compatibility.
  /// Now wraps SharedPreferences for native and web support.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Compatibility method signature
  static Future<void> openAll() async => init();

  static Future<void> put(String key, dynamic value) async {
    if (value is String) await _prefs?.setString(key, value);
    if (value is bool) await _prefs?.setBool(key, value);
    if (value is int) await _prefs?.setInt(key, value);
    if (value is double) await _prefs?.setDouble(key, value);
  }

  static dynamic get(String key, {dynamic defaultValue}) {
    return _prefs?.get(key) ?? defaultValue;
  }

  static Future<void> clear() async {
    await _prefs?.clear();
  }
}
