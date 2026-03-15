class PhoneUtils {
  static String normalize(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      return '';
    }

    if (digits.startsWith('55')) {
      return digits;
    }

    return '55$digits';
  }
}
