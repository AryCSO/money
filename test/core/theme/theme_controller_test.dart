import 'package:flutter_test/flutter_test.dart';

import 'package:money/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';

void main() {
  group('ThemeController', () {
    test('inicia no modo escuro', () {
      final ctrl = ThemeController();
      expect(ctrl.isDark, isTrue);
      expect(ctrl.mode, ThemeMode.dark);
    });

    test('toggle alterna para modo claro', () {
      final ctrl = ThemeController();
      ctrl.toggle();
      expect(ctrl.isDark, isFalse);
      expect(ctrl.mode, ThemeMode.light);
    });

    test('toggle duplo retorna ao modo escuro', () {
      final ctrl = ThemeController();
      ctrl.toggle();
      ctrl.toggle();
      expect(ctrl.isDark, isTrue);
    });

    test('setMode define modo explicitamente', () {
      final ctrl = ThemeController();
      ctrl.setMode(ThemeMode.light);
      expect(ctrl.mode, ThemeMode.light);
      ctrl.setMode(ThemeMode.dark);
      expect(ctrl.mode, ThemeMode.dark);
    });

    test('notifica listeners ao mudar', () {
      final ctrl = ThemeController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.toggle();
      expect(notified, isTrue);
    });

    test('nao notifica se setMode com mesmo valor', () {
      final ctrl = ThemeController();
      var callCount = 0;
      ctrl.addListener(() => callCount++);
      ctrl.setMode(ThemeMode.dark); // already dark
      expect(callCount, 0);
    });
  });
}
