import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../viewmodels/connection_viewmodel.dart';
import 'developer_options_page.dart';

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectionViewModel>();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF11151E), Color(0xFF0D0E12)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusBadge(isConnected: vm.isConnected),
                            const SizedBox(height: 18),
                            const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 52,
                              color: AppTheme.gold,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Conectar instancia money',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Escaneie o QR Code no WhatsApp. Assim que a conexao abrir, a tela de disparo sera liberada automaticamente.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            _QrState(vm: vm),
                            const SizedBox(height: 16),
                            if (vm.errorMessage != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF7B7B,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFFF7B7B,
                                    ).withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  vm.errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Color(0xFFFFA9A9)),
                                ),
                              ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: vm.isRefreshingQr
                                    ? null
                                    : () async {
                                        await vm.refreshQrCode();
                                        await vm.checkConnection();
                                      },
                                icon: vm.isRefreshingQr
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                                label: Text(
                                  vm.isRefreshingQr
                                      ? 'Atualizando QR Code...'
                                      : 'Atualizar QR Code',
                                ),
                              ),
                            ),
                            if (vm.lastQrRefreshAt != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Ultima atualizacao: ${_formatTime(vm.lastQrRefreshAt!)}',
                                style: const TextStyle(
                                  color: Color(0xFFB8C0CF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Opcoes do desenvolvedor',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DeveloperOptionsPage(),
                      ),
                    );
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.22),
                    foregroundColor: Colors.white.withValues(alpha: 0.85),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _QrState extends StatelessWidget {
  const _QrState({required this.vm});

  final ConnectionViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: CircularProgressIndicator(),
      );
    }

    final qrCode = vm.qrCode;
    if (qrCode == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('QR Code indisponivel no momento.'),
      );
    }

    final qrImageBytes = _decodeQrBase64(qrCode.base64);
    if (qrImageBytes != null) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.memory(
              qrImageBytes,
              width: 240,
              height: 240,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          _PairingCodeText(pairingCode: qrCode.pairingCode),
        ],
      );
    }

    if (qrCode.code.isNotEmpty) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              data: qrCode.code,
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
          _PairingCodeText(pairingCode: qrCode.pairingCode),
        ],
      );
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Text('QR Code indisponivel no momento.'),
    );
  }

  Uint8List? _decodeQrBase64(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parts = trimmed.split(',');
    final encoded = parts.isNotEmpty ? parts.last.trim() : trimmed;
    if (encoded.isEmpty) {
      return null;
    }

    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}

class _PairingCodeText extends StatelessWidget {
  const _PairingCodeText({required this.pairingCode});

  final String pairingCode;

  @override
  Widget build(BuildContext context) {
    if (pairingCode.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SelectableText(
        'Pairing code: $pairingCode',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF3ECF8E)
        : const Color(0xFFFFC857);
    final label = isConnected ? 'Conectado' : 'Aguardando conexao';
    final icon = isConnected
        ? Icons.check_circle_rounded
        : Icons.wifi_tethering_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
