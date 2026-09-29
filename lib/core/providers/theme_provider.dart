import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revive/core/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'app_theme';

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadSaved();
    return ThemeMode.dark;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kThemeKey);
    if (name != null) {
      state = ThemeMode.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ThemeMode.dark,
      );
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
