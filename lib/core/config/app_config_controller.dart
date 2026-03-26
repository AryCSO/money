import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

class AppConfigController extends ChangeNotifier {
  String _baseUrl = AppConstants.baseUrl;

  String get baseUrl => _baseUrl;

  bool updateBaseUrlFromInput(String rawInput) {
    final normalized = _normalizeBaseUrl(rawInput);
    if (normalized == null) {
      return false;
    }

    if (normalized == _baseUrl) {
      return true;
    }

    _baseUrl = normalized;
    notifyListeners();
    return true;
  }

  String? _normalizeBaseUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return null;
    }

    if (RegExp(r'^\d{2,5}$').hasMatch(value)) {
      return 'http://localhost:$value';
    }

    final withScheme = value.startsWith('http://') || value.startsWith('https://')
        ? value
        : 'http://$value';

    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    final normalizedPath = uri.path == '/' ? '' : uri.path;
    final normalized = uri.replace(path: normalizedPath).toString();
    return normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}
