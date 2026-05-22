import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/database_service.dart';

/// Usuário autenticado na sessão atual.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.nomeCompleto,
    required this.nomePreferido,
  });

  final int id;
  final String email;
  final String nomeCompleto;
  final String nomePreferido;

  /// Nome para saudação: prefere o apelido, cai para o 1º nome / e-mail.
  String get displayName {
    if (nomePreferido.trim().isNotEmpty) return nomePreferido.trim();
    if (nomeCompleto.trim().isNotEmpty) return nomeCompleto.trim().split(' ').first;
    return email;
  }
}

/// Gerencia login/cadastro/logout.
///
/// A sessão é persistida em SharedPreferences (id do usuário + data do último
/// login) e fica válida até o fim do dia: o usuário só precisa logar 1x por
/// dia. Na virada do dia, ou após logout explícito, a tela de login volta.
class AuthViewModel extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  // Chaves de persistência. "v1" para permitir migração futura sem conflito.
  static const _kSessionUserId = 'auth.session.userId.v1';
  static const _kSessionDate = 'auth.session.date.v1'; // yyyy-MM-dd local

  AuthUser? _user;
  AuthUser? get user => _user;
  bool get isAuthenticated => _user != null;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  /// `true` enquanto a tentativa de restaurar a sessão do disco está em curso.
  /// A UI pode usar para evitar exibir a tela de login num "piscar" antes do
  /// restore concluir.
  bool _isRestoring = false;
  bool get isRestoring => _isRestoring;

  String? _error;
  String? get error => _error;

  /// Tenta restaurar a sessão persistida. Só restaura se o último login foi
  /// no mesmo dia de calendário (hora local). Caso contrário, descarta.
  Future<void> restore() async {
    _isRestoring = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt(_kSessionUserId);
      final savedDate = prefs.getString(_kSessionDate);
      if (savedId == null || savedId <= 0 || savedDate == null) {
        return;
      }
      if (savedDate != _today()) {
        // Sessão de outro dia — limpa e volta para a tela de login.
        await _clearPersisted(prefs);
        return;
      }
      final row = await _db.carregarUsuarioPorId(savedId);
      if (row == null) {
        await _clearPersisted(prefs);
        return;
      }
      _user = AuthUser(
        id: row['id'] as int? ?? 0,
        email: row['email']?.toString() ?? '',
        nomeCompleto: row['nome_completo']?.toString() ?? '',
        nomePreferido: row['nome_preferido']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('AuthViewModel.restore erro: $e');
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Realiza o login. Retorna `true` em sucesso.
  Future<bool> login({required String email, required String senha}) async {
    if (email.trim().isEmpty || senha.isEmpty) {
      _setError('Informe e-mail e senha.');
      return false;
    }

    _setBusy(true);
    try {
      final row = await _db.autenticarUsuario(
        email: email,
        senha: senha,
      );
      if (row == null) {
        _setError('E-mail ou senha inválidos.');
        return false;
      }
      _user = AuthUser(
        id: row['id'] as int? ?? 0,
        email: row['email']?.toString() ?? '',
        nomeCompleto: row['nome_completo']?.toString() ?? '',
        nomePreferido: row['nome_preferido']?.toString() ?? '',
      );
      await _persistSession(_user!);
      _error = null;
      return true;
    } catch (e) {
      _setError('Falha ao acessar: $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Cadastra um novo usuário (exige token de administrador válido).
  /// Em sucesso, já autentica o usuário recém-criado.
  Future<bool> register({
    required String email,
    required String nomeCompleto,
    required String nomePreferido,
    required String senha,
    required String confirmarSenha,
    required String tokenAdmin,
  }) async {
    final emailTrim = email.trim();
    if (!_isValidEmail(emailTrim)) {
      _setError('Informe um e-mail válido.');
      return false;
    }
    if (nomeCompleto.trim().isEmpty) {
      _setError('Informe seu nome completo.');
      return false;
    }
    if (nomePreferido.trim().isEmpty) {
      _setError('Informe como prefere ser chamado.');
      return false;
    }
    if (senha.length < 6) {
      _setError('A senha deve ter pelo menos 6 caracteres.');
      return false;
    }
    if (senha != confirmarSenha) {
      _setError('As senhas não coincidem.');
      return false;
    }
    if (tokenAdmin.trim().isEmpty) {
      _setError('Informe o token de administrador.');
      return false;
    }

    _setBusy(true);
    try {
      final tokenOk = await _db.validarTokenAdmin(tokenAdmin);
      if (!tokenOk) {
        _setError('Token de administrador inválido.');
        return false;
      }
      if (await _db.emailJaCadastrado(emailTrim)) {
        _setError('Este e-mail já está cadastrado.');
        return false;
      }

      final id = await _db.registrarUsuario(
        email: emailTrim,
        senha: senha,
        nomeCompleto: nomeCompleto,
        nomePreferido: nomePreferido,
      );
      _user = AuthUser(
        id: id,
        email: emailTrim.toLowerCase(),
        nomeCompleto: nomeCompleto.trim(),
        nomePreferido: nomePreferido.trim(),
      );
      await _persistSession(_user!);
      _error = null;
      return true;
    } catch (e) {
      _setError('Falha ao cadastrar: $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    _user = null;
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearPersisted(prefs);
    } catch (e) {
      debugPrint('AuthViewModel.logout erro ao limpar sessão: $e');
    }
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  // ── Helpers de persistência ──

  Future<void> _persistSession(AuthUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSessionUserId, user.id);
      await prefs.setString(_kSessionDate, _today());
    } catch (e) {
      debugPrint('AuthViewModel._persistSession erro: $e');
    }
  }

  Future<void> _clearPersisted(SharedPreferences prefs) async {
    await prefs.remove(_kSessionUserId);
    await prefs.remove(_kSessionDate);
  }

  /// Data de hoje no formato yyyy-MM-dd em hora local.
  static String _today() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(email);
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }
}
