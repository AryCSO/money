import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/config/google_config_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/google_spreadsheet_file.dart';
import '../viewmodels/google_viewmodel.dart';

/// Página da seção "Google": login OAuth e gestão das planilhas do usuário.
class GoogleDocsPage extends StatelessWidget {
  const GoogleDocsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoogleViewModel>();

    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccountCard(vm: vm),
            const SizedBox(height: 16),
            if (!vm.isConfigured) const _CredentialsCard() else if (vm.isSignedIn)
              _FilesCard(vm: vm)
            else
              const _ConnectHint(),
            if (vm.error != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: vm.error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.vm});
  final GoogleViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.cloud_rounded, color: AppColors.info, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.isSignedIn ? 'Conta Google conectada' : 'Google Drive / Planilhas',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vm.isSignedIn
                      ? (vm.userEmail ?? 'Conectado')
                      : 'Faça login para usar suas planilhas no envio em massa',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (vm.isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (vm.isSignedIn)
            OutlinedButton.icon(
              onPressed: vm.disconnect,
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: Text('Sair', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
            )
          else if (vm.isConfigured)
            FilledButton.icon(
              onPressed: vm.connect,
              icon: const Icon(Icons.login_rounded, size: 16),
              label: Text(
                'Conectar com Google',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formulário para configurar o Client ID/Secret do OAuth (uma vez).
class _CredentialsCard extends StatefulWidget {
  const _CredentialsCard();

  @override
  State<_CredentialsCard> createState() => _CredentialsCardState();
}

class _CredentialsCardState extends State<_CredentialsCard> {
  final _idController = TextEditingController();
  final _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final config = context.read<GoogleConfigController>();
    _idController.text = config.clientId;
    _secretController.text = config.clientSecret;
  }

  @override
  void dispose() {
    _idController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<GoogleConfigController>().save(
      clientId: _idController.text,
      clientSecret: _secretController.text,
    );
    if (mounted) {
      // Reinicia a tentativa de reconexão com as novas credenciais.
      await context.read<GoogleViewModel>().initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuração OAuth (Google Cloud)',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Crie um cliente OAuth do tipo "App para computador" no Google Cloud '
            'Console, habilite as APIs Google Drive e Google Sheets, e cole as '
            'credenciais abaixo. Elas ficam salvas neste computador.',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _idController,
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Client ID',
              hintText: 'xxxxxxxx.apps.googleusercontent.com',
              labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _secretController,
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Client Secret',
              hintText: 'GOCSPX-...',
              labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, size: 16),
              label: Text(
                'Salvar credenciais',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectHint extends StatelessWidget {
  const _ConnectHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Clique em "Conectar com Google" para autorizar o acesso às suas '
              'planilhas. Uma janela do navegador será aberta.',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.vm});
  final GoogleViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Suas planilhas (${vm.files.length})',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: vm.isBusy ? null : vm.refreshFiles,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: AppColors.textMuted,
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (vm.isBusy && vm.files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (vm.files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nenhuma planilha encontrada no seu Google Drive.',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else
            ...vm.files.map((file) => _FileRow(file: file)),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});
  final GoogleSpreadsheetFile file;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            file.isNativeSheet ? Icons.grid_on_rounded : Icons.description_rounded,
            size: 18,
            color: file.isNativeSheet ? AppColors.success : AppColors.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  file.isNativeSheet ? 'Google Sheets' : 'Excel (.xlsx)',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
