import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config/app_config_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../viewmodels/connection_viewmodel.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController _baseUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfigController>();
    _baseUrlController = TextEditingController(text: config.baseUrl);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveBaseUrl() async {
    final config = context.read<AppConfigController>();
    final connectionVm = context.read<ConnectionViewModel>();
    setState(() => _isSaving = true);

    final success = config.updateBaseUrlFromInput(_baseUrlController.text);
    if (!success) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'URL inválida. Informe uma porta (ex: 50010) ou URL completa.',
          type: ToastType.warning,
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    _baseUrlController.text = config.baseUrl;
    await connectionVm.initialize();

    if (mounted) {
      AppToast.show(
        context,
        message: 'Conexão atualizada para: ${config.baseUrl}',
        type: ToastType.success,
      );
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectionViewModel>();
    final config = context.watch<AppConfigController>();

    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status banner
                _StatusBanner(vm: vm),
                const SizedBox(height: 24),
                // 2-col layout on wide screens
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;
                    final qrCard = _QrCard(vm: vm);
                    final urlCard = _UrlCard(
                      controller: _baseUrlController,
                      config: config,
                      isSaving: _isSaving,
                      onSave: _saveBaseUrl,
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: qrCard),
                          const SizedBox(width: 20),
                          Expanded(child: urlCard),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        qrCard,
                        const SizedBox(height: 16),
                        urlCard,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// STATUS BANNER
// ──────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.vm});
  final ConnectionViewModel vm;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final String description;
    late final IconData icon;

    if (vm.isDisconnecting) {
      color = AppColors.warning;
      label = 'Desconectando';
      description = 'Aguarde enquanto a instância é desconectada...';
      icon = Icons.logout_rounded;
    } else if (vm.isLoading) {
      color = AppColors.info;
      label = 'Verificando conexão';
      description = 'Checando o status da instância WhatsApp...';
      icon = Icons.sync_rounded;
    } else if (vm.isConnected) {
      color = AppColors.success;
      label = 'WhatsApp Conectado';
      description = 'Sua instância está ativa e pronta para enviar mensagens.';
      icon = Icons.check_circle_rounded;
    } else {
      color = AppColors.warning;
      label = 'Aguardando Conexão';
      description = 'Escaneie o QR Code abaixo com o WhatsApp para conectar.';
      icon = Icons.qr_code_scanner_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (vm.isConnected)
            OutlinedButton.icon(
              onPressed: vm.isDisconnecting ? null : vm.disconnectAndGoToQr,
              icon: vm.isDisconnecting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded, size: 14),
              label: Text(
                vm.isDisconnecting ? 'Saindo...' : 'Desconectar',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// QR CODE CARD
// ──────────────────────────────────────────
class _QrCard extends StatelessWidget {
  const _QrCard({required this.vm});
  final ConnectionViewModel vm;

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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.qr_code_rounded,
                  color: AppColors.primaryLight,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'QR Code',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (vm.lastQrRefreshAt != null)
                Text(
                  _formatTime(vm.lastQrRefreshAt!),
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Escaneie com o WhatsApp para conectar',
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          // QR state
          Center(child: _QrDisplay(vm: vm)),
          const SizedBox(height: 16),
          if (vm.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                vm.errorMessage!,
                style: GoogleFonts.inter(
                  color: AppColors.errorLight,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: vm.isRefreshingQr
                ? null
                : () async {
                    await vm.refreshQrCode();
                    await vm.checkConnection();
                  },
            icon: vm.isRefreshingQr
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 15),
            label: Text(
              vm.isRefreshingQr ? 'Atualizando...' : 'Atualizar QR Code',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _QrDisplay extends StatelessWidget {
  const _QrDisplay({required this.vm});
  final ConnectionViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (vm.isConnected) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Conectado com sucesso',
              style: GoogleFonts.inter(
                color: AppColors.success,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final qr = vm.qrCode;
    if (qr == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(
              Icons.qr_code_2_rounded,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              'QR Code indisponível',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final imageBytes = _decodeBase64(qr.base64);
    final qrSize = 200.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: imageBytes != null
              ? Image.memory(
                  imageBytes,
                  width: qrSize,
                  height: qrSize,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                )
              : QrImageView(
                  data: qr.code,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
        ),
        if (qr.pairingCode.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              'Código de pareamento: ${qr.pairingCode}',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Uint8List? _decodeBase64(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(',');
    final encoded = parts.isNotEmpty ? parts.last.trim() : trimmed;
    if (encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}

// ──────────────────────────────────────────
// URL CONFIGURATION CARD
// ──────────────────────────────────────────
class _UrlCard extends StatelessWidget {
  const _UrlCard({
    required this.controller,
    required this.config,
    required this.isSaving,
    required this.onSave,
  });

  final TextEditingController controller;
  final AppConfigController config;
  final bool isSaving;
  final VoidCallback onSave;

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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.settings_ethernet_rounded,
                  color: AppColors.accent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Porta / Base URL',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Informe a porta local ou URL completa da API Evolution',
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              labelText: 'Base URL / Porta',
              hintText: 'http://localhost:52062 ou 50010',
              prefixIcon: const Icon(
                Icons.link_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'URL atual: ${config.baseUrl}',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 15),
            label: Text(
              isSaving ? 'Aplicando...' : 'Salvar e reconectar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
            ),
          ),
          const SizedBox(height: 20),
          // Instrucoes
          _InstructionsBox(),
        ],
      ),
    );
  }
}

class _InstructionsBox extends StatelessWidget {
  const _InstructionsBox();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Abra o WhatsApp no seu celular',
      'Vá em Dispositivos Conectados',
      'Toque em "Conectar dispositivo"',
      'Escaneie o QR Code ao lado',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como conectar',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Center(
                      child: Text(
                        '${e.key + 1}',
                        style: GoogleFonts.inter(
                          color: AppColors.primaryLight,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.value,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
