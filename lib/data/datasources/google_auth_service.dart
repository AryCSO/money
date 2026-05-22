import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cuida do login OAuth com o Google em ambiente desktop.
///
/// Usa o fluxo de "aplicativo instalado" (`clientViaUserConsent`), que sobe um
/// servidor de loopback em `localhost` e abre o navegador do sistema para o
/// consentimento. As credenciais (incluindo refresh token) são persistidas em
/// SharedPreferences para reconectar automaticamente na próxima execução.
class GoogleAuthService {
  static const _kCredentials = 'google.credentials';

  /// Escopos: leitura do Drive (listar arquivos) e leitura de Planilhas.
  static const List<String> scopes = <String>[
    'email',
    drive.DriveApi.driveReadonlyScope,
    sheets.SheetsApi.spreadsheetsReadonlyScope,
  ];

  AutoRefreshingAuthClient? _client;

  AutoRefreshingAuthClient? get client => _client;
  bool get isSignedIn => _client != null;

  /// Tenta reconectar a partir de credenciais salvas. `true` se conseguiu.
  Future<bool> restore({
    required String clientId,
    required String clientSecret,
  }) async {
    if (clientId.trim().isEmpty) {
      return false;
    }
    final credentials = await _loadCredentials();
    if (credentials == null || credentials.refreshToken == null) {
      return false;
    }
    try {
      final id = ClientId(
        clientId.trim(),
        clientSecret.trim().isEmpty ? null : clientSecret.trim(),
      );
      final client = autoRefreshingClient(id, credentials, http.Client());
      client.credentialUpdates.listen(_persistCredentials);
      _client = client;
      return true;
    } catch (e) {
      debugPrint('GoogleAuthService.restore erro: $e');
      return false;
    }
  }

  /// Inicia o consentimento OAuth abrindo o navegador.
  Future<void> signIn({
    required String clientId,
    required String clientSecret,
  }) async {
    final id = ClientId(
      clientId.trim(),
      clientSecret.trim().isEmpty ? null : clientSecret.trim(),
    );

    final client = await clientViaUserConsent(id, scopes, (url) async {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError(
          'Não foi possível abrir o navegador para o login do Google.',
        );
      }
    });

    await _persistCredentials(client.credentials);
    client.credentialUpdates.listen(_persistCredentials);
    _client = client;
  }

  Future<void> signOut() async {
    _client?.close();
    _client = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCredentials);
    } catch (e) {
      debugPrint('GoogleAuthService.signOut erro: $e');
    }
  }

  // ── Persistência das credenciais ──

  Future<void> _persistCredentials(AccessCredentials credentials) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        'type': credentials.accessToken.type,
        'data': credentials.accessToken.data,
        'expiry': credentials.accessToken.expiry.toIso8601String(),
        'refreshToken': credentials.refreshToken,
        'idToken': credentials.idToken,
        'scopes': credentials.scopes,
      };
      await prefs.setString(_kCredentials, jsonEncode(map));
    } catch (e) {
      debugPrint('GoogleAuthService._persistCredentials erro: $e');
    }
  }

  Future<AccessCredentials?> _loadCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCredentials);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final token = AccessToken(
        map['type'] as String,
        map['data'] as String,
        DateTime.parse(map['expiry'] as String).toUtc(),
      );
      return AccessCredentials(
        token,
        map['refreshToken'] as String?,
        (map['scopes'] as List<dynamic>).cast<String>(),
        idToken: map['idToken'] as String?,
      );
    } catch (e) {
      debugPrint('GoogleAuthService._loadCredentials erro: $e');
      return null;
    }
  }
}
