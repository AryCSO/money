import 'package:flutter_test/flutter_test.dart';

import 'package:money/core/utils/phone_utils.dart';

void main() {
  group('PhoneUtils.normalize', () {
    test('adiciona prefixo 55 a numero sem DDI', () {
      expect(PhoneUtils.normalize('62999999999'), '5562999999999');
    });

    test('mantem numero que ja comeca com 55', () {
      expect(PhoneUtils.normalize('5562999999999'), '5562999999999');
    });

    test('remove caracteres nao-numericos', () {
      expect(PhoneUtils.normalize('+55 (62) 99999-9999'), '5562999999999');
    });

    test('retorna vazio para entrada vazia', () {
      expect(PhoneUtils.normalize(''), '');
    });

    test('retorna vazio para entrada sem digitos', () {
      expect(PhoneUtils.normalize('abc---'), '');
    });

    test('trata numeros curtos', () {
      expect(PhoneUtils.normalize('999'), '55999');
    });

    test('remove parenteses e tracos', () {
      expect(PhoneUtils.normalize('(62)99999-9999'), '5562999999999');
    });
  });
}
