import 'package:shared_preferences/shared_preferences.dart';
import '../models/verbosity_level.dart';

/// Persists user settings: verbosity, opted-in friend names, etc.
class SettingsService {
  static const _kVerbosity = 'verbosity';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  VerbosityLevel get verbosity {
    final raw = _prefs?.getString(_kVerbosity) ?? 'normal';
    return VerbosityLevelX.fromString(raw);
  }

  Future<void> setVerbosity(VerbosityLevel v) async {
    await _prefs?.setString(_kVerbosity, v.label);
  }
}
