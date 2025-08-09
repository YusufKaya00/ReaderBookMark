import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kDark = 'dark_mode';
  static const _kAdCss = 'ad_block_css';
  bool _dark = false;
  bool _adBlockCss = false;
  bool get isDarkMode => _dark;
  bool get adBlockCssEnabled => _adBlockCss;

  SettingsProvider() {
    load();
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _dark = sp.getBool(_kDark) ?? false;
    _adBlockCss = sp.getBool(_kAdCss) ?? false;
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
}


