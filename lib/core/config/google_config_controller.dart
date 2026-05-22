import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda as credenciais do cliente OAuth "Desktop" do Google fornecidas
/// pelo usuário (Client ID e Client Secret obtidos no Google Cloud Console).
///
/// Não são segredos de servidor: num app desktop instalado o "client secret"
/// é considerado público pelo próprio fluxo OAuth de aplicativo instalado.
/// Persistimos via SharedPreferences para não pedir a cada execução.
class GoogleConfigController extends ChangeNotifier {
  static const _kClientId = 'google.clientId';
  static const _kClientSecret = 'google.clientSecret';

  String _clientId = '';
  String _clientSecret = '';

  String get clientId => _clientId;
  String get clientSecret => _clientSecret;

  /// Há credenciais mínimas para iniciar o fluxo OAuth.
  bool get isConfigured => _clientId.trim().isNotEmpty;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clientId = prefs.getString(_kClientId) ?? '';
      _clientSecret = prefs.getString(_kClientSecret) ?? '';
    } catch (e) {
      debugPrint('GoogleConfigController.load erro: $e');
    }
    notifyListeners();
  }

  Future<void> save({required String clientId, required String clientSecret}) async {
    _clientId = clientId.trim();
    _clientSecret = clientSecret.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kClientId, _clientId);
      await prefs.setString(_kClientSecret, _clientSecret);
    } catch (e) {
      debugPrint('GoogleConfigController.save erro: $e');
    }
    notifyListeners();
  }
}
