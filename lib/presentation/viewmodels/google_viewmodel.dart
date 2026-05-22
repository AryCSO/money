import 'package:flutter/foundation.dart';

import '../../core/config/google_config_controller.dart';
import '../../data/datasources/google_auth_service.dart';
import '../../data/datasources/google_drive_service.dart';
import '../../data/models/google_spreadsheet_file.dart';

/// Estado da integração com o Google: login, conta conectada e planilhas
/// disponíveis no Drive do usuário.
class GoogleViewModel extends ChangeNotifier {
  GoogleViewModel({
    required GoogleAuthService authService,
    required GoogleConfigController config,
  }) : _auth = authService,
       _config = config;

  final GoogleAuthService _auth;
  final GoogleConfigController _config;
  GoogleDriveService? _drive;

  bool _initialized = false;

  bool _isSignedIn = false;
  bool get isSignedIn => _isSignedIn;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String? _userEmail;
  String? get userEmail => _userEmail;

  String? _error;
  String? get error => _error;

  List<GoogleSpreadsheetFile> _files = [];
  List<GoogleSpreadsheetFile> get files => _files;

  bool get isConfigured => _config.isConfigured;

  /// Reconecta automaticamente usando credenciais salvas (se houver).
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!_config.isConfigured) {
      return;
    }

    _setBusy(true);
    try {
      final restored = await _auth.restore(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
      );
      if (restored && _auth.client != null) {
        _drive = GoogleDriveService(_auth.client!);
        _isSignedIn = true;
        await _afterSignIn();
      }
    } catch (e) {
      debugPrint('GoogleViewModel.initialize erro: $e');
    } finally {
      _setBusy(false);
    }
  }

  /// Inicia o fluxo de login (abre o navegador).
  Future<void> connect() async {
    if (!_config.isConfigured) {
      _error = 'Configure o Client ID do Google antes de conectar.';
      notifyListeners();
      return;
    }

    _setBusy(true);
    _error = null;
    try {
      await _auth.signIn(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
      );
      _drive = GoogleDriveService(_auth.client!);
      _isSignedIn = true;
      await _afterSignIn();
    } catch (e) {
      _error = 'Falha no login com o Google: $e';
      _isSignedIn = false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() async {
    await _auth.signOut();
    _drive = null;
    _isSignedIn = false;
    _userEmail = null;
    _files = [];
    _error = null;
    notifyListeners();
  }

  /// Recarrega a lista de planilhas do Drive.
  Future<void> refreshFiles() async {
    final drive = _drive;
    if (drive == null) {
      return;
    }
    _setBusy(true);
    try {
      _files = await drive.listSpreadsheets();
      _error = null;
    } catch (e) {
      _error = 'Falha ao listar planilhas: $e';
    } finally {
      _setBusy(false);
    }
  }

  /// Lê o conteúdo de uma planilha como linhas para alimentar o parser.
  Future<List<List<dynamic>>> fetchRows(GoogleSpreadsheetFile file) {
    final drive = _drive;
    if (drive == null) {
      throw StateError('Não conectado ao Google.');
    }
    return drive.fetchRows(file);
  }

  Future<void> _afterSignIn() async {
    _userEmail = await _drive!.getUserEmail();
    await refreshFiles();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
