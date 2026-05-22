import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla preferências de comportamento da janela do desktop.
class WindowBehaviorController extends ChangeNotifier {
  static const _kCloseToTrayKey = 'window.closeToTray';

  bool _closeToTray = false;
  bool _initialized = false;

  bool get closeToTray => _closeToTray;
  bool get initialized => _initialized;

  Future<void> load() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _closeToTray = prefs.getBool(_kCloseToTrayKey) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) return;
    _closeToTray = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCloseToTrayKey, value);
  }
}
