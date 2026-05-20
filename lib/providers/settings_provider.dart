import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kDark = 'dark_mode';
  static const _kAdCss = 'ad_block_css';
  static const _kLang = 'language_code';

  bool _dark = false;
  bool _adBlockCss = false;
  String _languageCode = 'tr';

  bool get isDarkMode => _dark;
  bool get adBlockCssEnabled => _adBlockCss;
  String get languageCode => _languageCode;

  SettingsProvider() {
    load();
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _dark = sp.getBool(_kDark) ?? false;
    _adBlockCss = sp.getBool(_kAdCss) ?? false;
    _languageCode = sp.getString(_kLang) ?? 'tr';
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _dark = !_dark;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDark, _dark);
  }

  Future<void> toggleAdBlockCss() async {
    _adBlockCss = !_adBlockCss;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAdCss, _adBlockCss);
  }

  Future<void> setLanguageCode(String code) async {
    _languageCode = code;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLang, code);
  }
}


