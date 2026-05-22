import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Gerencia o ícone na bandeja do sistema (system tray) no Windows/macOS/Linux.
///
/// Responsável por:
/// - Inicializar o ícone, tooltip e menu contextual.
/// - Mostrar/esconder a janela quando o usuário interage com a bandeja.
/// - Encerrar a aplicação via menu "Sair".
class SystemTrayService with TrayListener {
  SystemTrayService._();
  static final SystemTrayService instance = SystemTrayService._();

  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;

    trayManager.addListener(this);

    final iconPath = Platform.isWindows
        ? 'assets/app_icon.ico'
        : 'assets/app_icon.ico';

    try {
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Money');
      await _rebuildMenu();
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SystemTrayService: falha ao inicializar tray: $e');
      }
    }
  }

  Future<void> _rebuildMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: 'Abrir Money'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Sair'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _initialized = false;
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // ── TrayListener ────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'exit':
        _exitApp();
        break;
    }
  }

  Future<void> _exitApp() async {
    await windowManager.setPreventClose(false);
    await dispose();
    await windowManager.destroy();
  }
}
