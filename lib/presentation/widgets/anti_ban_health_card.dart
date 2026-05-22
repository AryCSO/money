import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/config/anti_ban_controller.dart';
import '../../core/theme/app_colors.dart';
import '../viewmodels/overview_viewmodel.dart';

/// Status agregado de "saúde" anti-ban da conta.
enum HealthLevel { good, warning, danger }

class _HealthSnapshot {
  const _HealthSnapshot({
    required this.level,
    required this.title,
    required this.recommendation,
    required this.responseRate,
    required this.errorRate,
    required this.sentToday,
    required this.dailyCap,
    required this.workingHoursOk,
  });

  final HealthLevel level;
  final String title;
  final String recommendation;
  final double responseRate; // 0..1
  final double errorRate; // 0..1
  final int sentToday;
  final int? dailyCap;
  final bool workingHoursOk;

  Color get color {
    switch (level) {
      case HealthLevel.good:
        return AppColors.success;
      case HealthLevel.warning:
        return AppColors.warning;
      case HealthLevel.danger:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (level) {
      case HealthLevel.good:
        return Icons.shield_rounded;
      case HealthLevel.warning:
        return Icons.warning_amber_rounded;
      case HealthLevel.danger:
        return Icons.dangerous_rounded;
    }
  }
}

/// Card de saúde anti-ban exibido no Overview.
///
/// Avalia, com base nas estatísticas do dia:
///  - Taxa de resposta (alvo: ≥ 30%)
///  - Taxa de erro (alerta: > 10%)
///  - Aderência à janela horária configurada
///  - % de uso do teto diário (warm-up)
/// E gera uma recomendação textual: OK / REDUZA / PARE.
class AntiBanHealthCard extends StatelessWidget {
  const AntiBanHealthCard({super.key});

  _HealthSnapshot _evaluate({
    required OverviewViewModel ov,
    required AntiBanController antiBan,
  }) {
    final enviosHoje = ov.enviosHoje;
    final falhasHoje = ov.falhasHoje;
    final respostasHoje = ov.respostasHoje;

    final totalTries = enviosHoje + falhasHoje;
    final errorRate = totalTries > 0 ? falhasHoje / totalTries : 0.0;
    final responseRate = enviosHoje > 0 ? respostasHoje / enviosHoje : 0.0;

    final workingHoursOk = antiBan.isWithinWorkingHours();

    HealthLevel level = HealthLevel.good;
    String title = 'Saúde da conta: BOA';
    String recommendation = 'Tudo certo. Pode manter o ritmo atual.';

    // Sinais críticos (vermelho)
    if (errorRate > 0.20 && totalTries >= 10) {
      level = HealthLevel.danger;
      title = 'Saúde da conta: PARE';
      recommendation =
          'Taxa de erro acima de 20% (${(errorRate * 100).toStringAsFixed(0)}%). '
          'Pause o envio por 12–24h e revise sua lista.';
    } else if (antiBan.reachedDailyCap) {
      level = HealthLevel.danger;
      title = 'Teto diário atingido';
      recommendation =
          'Você já enviou ${antiBan.sentToday}/${antiBan.dailyCap} mensagens hoje. '
          'Espere até amanhã ou suba o tier nas configurações.';
    }
    // Sinais de atenção (amarelo)
    else if (errorRate > 0.10 && totalTries >= 10) {
      level = HealthLevel.warning;
      title = 'Saúde da conta: ATENÇÃO';
      recommendation =
          'Taxa de erro em ${(errorRate * 100).toStringAsFixed(0)}%. '
          'Reduza o ritmo pela metade e verifique a qualidade da lista.';
    } else if (enviosHoje >= 30 && responseRate < 0.10) {
      level = HealthLevel.warning;
      title = 'Saúde da conta: ATENÇÃO';
      recommendation =
          'Poucas respostas (${(responseRate * 100).toStringAsFixed(0)}%). '
          'Conteúdo pouco engajante = sinal de spam para o WhatsApp.';
    } else if (!workingHoursOk && antiBan.workingHoursEnabled) {
      level = HealthLevel.warning;
      title = 'Fora da janela horária';
      recommendation =
          'Horário atual fora da janela configurada '
          '(${antiBan.workingHourStart}h–${antiBan.workingHourEnd}h). '
          'Disparos serão bloqueados.';
    } else if (antiBan.hasDailyCap && antiBan.sentToday >= antiBan.dailyCap * 0.8) {
      level = HealthLevel.warning;
      title = 'Próximo do teto diário';
      recommendation =
          '${antiBan.sentToday}/${antiBan.dailyCap} hoje (warm-up). '
          'Reduza o ritmo até o reset diário.';
    }
    // Bom
    else if (enviosHoje >= 20 && responseRate >= 0.30) {
      title = 'Saúde da conta: ÓTIMA';
      recommendation =
          'Taxa de resposta em ${(responseRate * 100).toStringAsFixed(0)}% — '
          'sinal forte de legitimidade. Pode manter ou subir gradualmente.';
    }

    return _HealthSnapshot(
      level: level,
      title: title,
      recommendation: recommendation,
      responseRate: responseRate,
      errorRate: errorRate,
      sentToday: enviosHoje,
      dailyCap: antiBan.hasDailyCap ? antiBan.dailyCap : null,
      workingHoursOk: workingHoursOk,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ov = context.watch<OverviewViewModel>();
    final antiBan = context.watch<AntiBanController>();
    final snap = _evaluate(ov: ov, antiBan: antiBan);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: snap.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: snap.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(snap.icon, color: snap.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snap.title,
                      style: GoogleFonts.inter(
                        color: snap.color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Painel de saúde anti-ban',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            snap.recommendation,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _StatPill(
                label: 'Taxa de resposta',
                value: '${(snap.responseRate * 100).toStringAsFixed(0)}%',
                positive: snap.responseRate >= 0.30,
              ),
              _StatPill(
                label: 'Taxa de erro',
                value: '${(snap.errorRate * 100).toStringAsFixed(0)}%',
                positive: snap.errorRate < 0.10,
              ),
              _StatPill(
                label: 'Enviadas hoje',
                value: snap.dailyCap != null
                    ? '${snap.sentToday}/${snap.dailyCap}'
                    : snap.sentToday.toString(),
                positive: snap.dailyCap == null ||
                    snap.sentToday < snap.dailyCap! * 0.8,
              ),
              _StatPill(
                label: 'Janela horária',
                value: snap.workingHoursOk ? 'OK' : 'Fora',
                positive: snap.workingHoursOk,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.positive,
  });

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
