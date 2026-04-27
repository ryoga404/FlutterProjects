import 'dart:convert';
import 'package:flutter/material.dart';
import '../platform/app_storage.dart';

/// アプリ全体の設定を管理する Provider。
/// Web: localStorage / Native: settings.json
class AppSettingsProvider extends ChangeNotifier {
  static const _settingsKey = 'settings.json';
  final _storage = AppStorage.instance;

  // ── 外観 ──
  ThemeMode _themeMode = ThemeMode.system;
  double _fontScale = 1.0;

  // ── 演習オプション（永続化） ──
  bool _timeLimitEnabled = false;
  int _timeLimitSeconds = 45;
  bool _shuffleChoices = false;

  ThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;
  bool get isDark => _themeMode == ThemeMode.dark;

  bool get timeLimitEnabled => _timeLimitEnabled;
  int get timeLimitSeconds => _timeLimitSeconds;
  bool get shuffleChoices => _shuffleChoices;

  String get fontScaleLabel {
    if (_fontScale <= 0.86) return '小';
    if (_fontScale >= 1.14) return '大';
    return '標準';
  }

  AppSettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(_settingsKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final mode = data['themeMode'] as String?;
      _themeMode = mode == 'dark'
          ? ThemeMode.dark
          : mode == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
      _fontScale = (data['fontScale'] as num?)?.toDouble() ?? 1.0;

      // 演習オプション
      _timeLimitEnabled = data['timeLimitEnabled'] as bool? ?? false;
      _timeLimitSeconds = (data['timeLimitSeconds'] as num?)?.toInt() ?? 45;
      _shuffleChoices   = data['shuffleChoices'] as bool? ?? false;

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final modeStr = _themeMode == ThemeMode.dark
          ? 'dark'
          : _themeMode == ThemeMode.light
              ? 'light'
              : 'system';
      await _storage.write(_settingsKey, jsonEncode({
        'themeMode': modeStr,
        'fontScale': _fontScale,
        'timeLimitEnabled': _timeLimitEnabled,
        'timeLimitSeconds': _timeLimitSeconds,
        'shuffleChoices': _shuffleChoices,
      }));
    } catch (_) {}
  }

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _save();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _save();
  }

  void setFontScale(double scale) {
    _fontScale = scale;
    notifyListeners();
    _save();
  }

  void setTimeLimitEnabled(bool v) {
    _timeLimitEnabled = v;
    notifyListeners();
    _save();
  }

  void setTimeLimitSeconds(int v) {
    _timeLimitSeconds = v.clamp(5, 600);
    notifyListeners();
    _save();
  }

  void setShuffleChoices(bool v) {
    _shuffleChoices = v;
    notifyListeners();
    _save();
  }
}
