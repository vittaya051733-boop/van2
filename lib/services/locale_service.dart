import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService extends ChangeNotifier {
  LocaleService._();

  static final LocaleService instance = LocaleService._();

  static const String _prefKey = 'app_locale_code';
  static const Locale thai = Locale('th', 'TH');
  static const Locale english = Locale('en', 'US');

  Locale _locale = thai;
  bool _loaded = false;

  Locale get locale => _locale;
  bool get isEnglish => _locale.languageCode == 'en';
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey)?.trim().toLowerCase();
    _locale = code == 'en' ? english : thai;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale next) async {
    final normalized = next.languageCode == 'en' ? english : thai;
    if (_locale == normalized) {
      return;
    }
    _locale = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, normalized.languageCode);
  }

  String labelFor(Locale value) {
    return value.languageCode == 'en' ? 'English' : 'ไทย';
  }
}
