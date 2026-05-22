import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';

/// Tela inicial de autenticação: login e cadastro (alternados).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _registerMode = false;

  // Login
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  // Cadastro
  final _regEmailController = TextEditingController();
  final _nomeController = TextEditingController();
  final _apelidoController = TextEditingController();
  final _regSenhaController = TextEditingController();
  final _regConfirmarController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _regEmailController.dispose();
    _nomeController.dispose();
    _apelidoController.dispose();
    _regSenhaController.dispose();
    _regConfirmarController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _switchMode(bool register) {
    setState(() => _registerMode = register);
    context.read<AuthViewModel>().clearError();
  }

  Future<void> _doLogin() async {
    await context.read<AuthViewModel>().login(
      email: _emailController.text,
      senha: _senhaController.text,
    );
  }

  Future<void> _doRegister() async {
    await context.read<AuthViewModel>().register(
      email: _regEmailController.text,
      nomeCompleto: _nomeController.text,
      nomePreferido: _apelidoController.text,
      senha: _regSenhaController.text,
      confirmarSenha: _regConfirmarController.text,
      tokenAdmin: _tokenController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(registerMode: _registerMode),
                  const SizedBox(height: 24),
                  if (_registerMode) _buildRegister(vm) else _buildLogin(vm),
                  if (vm.error != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBox(message: vm.error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogin(AuthViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          controller: _emailController,
          label: 'E-mail',
          hint: 'voce@exemplo.com',
          icon: Icons.email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _senhaController,
          label: 'Senha',
          icon: Icons.lock_rounded,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          onSubmitted: (_) => _doLogin(),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Acessar',
          busy: vm.isBusy,
          onPressed: vm.isBusy ? null : _doLogin,
        ),
        const SizedBox(height: 14),
        _SwitchModeRow(
          question: 'Não é cadastrado ainda?',
          action: 'Cadastrar-se',
          onTap: () => _switchMode(true),
        ),
      ],
    );
  }

  Widget _buildRegister(AuthViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          controller: _regEmailController,
          label: 'E-mail válido',
          hint: 'voce@exemplo.com',
          icon: Icons.email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _nomeController,
          label: 'Nome completo',
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _apelidoController,
          label: 'Como prefere ser chamado',
          icon: Icons.person_rounded,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _regSenhaController,
          label: 'Senha',
          icon: Icons.lock_rounded,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _regConfirmarController,
          label: 'Confirmar senha',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _tokenController,
          label: 'Token de administrador',
          hint: 'Fornecido pelo desenvolvimento',
          icon: Icons.vpn_key_rounded,
          obscure: true,
          onSubmitted: (_) => _doRegister(),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Cadastrar',
          busy: vm.isBusy,
          onPressed: vm.isBusy ? null : _doRegister,
        ),
        const SizedBox(height: 14),
        _SwitchModeRow(
          question: 'Já tem conta?',
          action: 'Fazer login',
          onTap: () => _switchMode(false),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.registerMode});
  final bool registerMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          registerMode ? 'Criar conta' : 'Bem-vindo ao Money',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          registerMode
              ? 'Preencha os dados para solicitar acesso'
              : 'Faça login para continuar',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.onToggleObscure,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              )
            : null,
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: onPressed,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
              ),
      ),
    );
  }
}

class _SwitchModeRow extends StatelessWidget {
  const _SwitchModeRow({
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          question,
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: GoogleFonts.inter(
              color: AppColors.primaryLight,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(color: AppColors.errorLight, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
