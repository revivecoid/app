import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Locale persistence key ───────────────────────────────────────────────────
const _kLocaleKey = 'app_locale';

// ─── Supported locales ────────────────────────────────────────────────────────
const supportedLocales = [
  Locale('id'), // Bahasa Indonesia — default
  Locale('en'), // English
];

// ─── Notifier ─────────────────────────────────────────────────────────────────
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    // Start with Indonesian; async load will update if user previously chose EN
    _loadSaved();
    return const Locale('id');
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code != null) {
      final locale = supportedLocales.firstWhere(
        (l) => l.languageCode == code,
        orElse: () => const Locale('id'),
      );
      state = locale;
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }

  void toggle() {
    setLocale(state.languageCode == 'id' ? const Locale('en') : const Locale('id'));
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
