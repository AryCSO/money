import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../viewmodels/auto_reply_viewmodel.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/overview_viewmodel.dart';
import '../viewmodels/template_viewmodel.dart';
import '../widgets/activity_chart.dart';
import '../widgets/anti_ban_health_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/pending_clients_card.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _MetricsRow(),
            SizedBox(height: 24),
            PendingClientsCard(),
            SizedBox(height: 24),
            AntiBanHealthCard(),
            SizedBox(height: 24),
            _ChartsRow(),
            SizedBox(height: 24),
            _BottomRow(),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// MÉTRICAS
// ──────────────────────────────────────────
class _MetricsRow extends StatelessWidget {
  const _MetricsRow();

  @override
  Widget build(BuildContext context) {
    final overviewVm = context.watch<OverviewViewModel>();
    final templateVm = context.watch<TemplateViewModel>();
    final autoReplyVm = context.watch<AutoReplyViewModel>();
    final connectionVm = context.watch<ConnectionViewModel>();

    // Combinar dados do banco (persistidos) com dados da sessão atual
    final dbEnviosHoje = overviewVm.enviosHoje;
    final dbFalhasHoje = overviewVm.falhasHoje;
    final dbRespostasHoje = overviewVm.respostasHoje;

    // Sessão atual (ainda não persistidos no banco)
    final sessionSuccess = templateVm.sendResults.where((r) => r.success).length;
    final sessionFailed = templateVm.sendResults.where((r) => !r.success).length;

    final totalEnviadas = dbEnviosHoje + sessionSuccess;
    final totalFalhas = dbFalhasHoje + sessionFailed;
    final repliedCount = autoReplyVm.repliedCount;
    final unansweredCount = autoReplyVm.queueCount;
    final returnRate = overviewVm.taxaRetorno.toStringAsFixed(1);

    final cards = [
      MetricCard(
        label: 'Enviadas Hoje',
        value: totalEnviadas.toString(),
        icon: Icons.send_rounded,
        accentColor: AppColors.metricSent,
        subtitle: 'Total: ${overviewVm.enviosTotal + sessionSuccess}',
        trend: totalFalhas > 0 ? '$totalFalhas falhas' : 'Sem falhas',
        trendPositive: totalFalhas == 0 ? true : false,
      ),
      MetricCard(
        label: 'Pendentes',
        value: templateVm.isSending
            ? '${templateVm.sendTotal - templateVm.sendProgress}'
            : (templateVm.filteredServers.isNotEmpty && !templateVm.isSending
                ? templateVm.filteredServers.length.toString()
                : '0'),
        icon: Icons.hourglass_bottom_rounded,
        accentColor: AppColors.metricPending,
        subtitle: templateVm.isSending
            ? 'Disparando ${templateVm.sendProgress}/${templateVm.sendTotal}'
            : 'Na fila para envio',
        trend: templateVm.isSending ? 'Em andamento' : null,
        trendPositive: null,
      ),
      MetricCard(
        label: 'Respostas Hoje',
        value: dbRespostasHoje.toString(),
        icon: Icons.mark_chat_unread_rounded,
        accentColor: AppColors.warning,
        subtitle: 'Total: ${overviewVm.respostasTotal}',
        trend: unansweredCount > 0 ? '$unansweredCount na fila' : 'Nenhum pendente',
        trendPositive: unansweredCount == 0 ? true : false,
      ),
      MetricCard(
        label: 'Auto-respostas',
        value: repliedCount.toString(),
        icon: Icons.reply_all_rounded,
        accentColor: AppColors.metricUnread,
        subtitle: autoReplyVm.isEnabled ? 'Auto-reply ativo' : 'Auto-reply pausado',
        trend: autoReplyVm.isEnabled ? 'Ativo' : 'Pausado',
        trendPositive: autoReplyVm.isEnabled ? true : null,
      ),
      MetricCard(
        label: 'Taxa de Retorno',
        value: '$returnRate%',
        icon: Icons.trending_up_rounded,
        accentColor: AppColors.metricReturn,
        subtitle: 'Respostas / Enviadas (geral)',
        trend: connectionVm.isConnected ? 'Online' : 'Offline',
        trendPositive: connectionVm.isConnected ? true : false,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Determine columns: 5 only on very wide, scale down gracefully
        final int cols;
        if (width >= 1200) {
          cols = 5;
        } else if (width >= 900) {
          cols = 4;
        } else if (width >= 600) {
          cols = 3;
        } else if (width >= 380) {
          cols = 2;
        } else {
          cols = 1;
        }

        const double gap = 14;
        final cardWidth = (width - (gap * (cols - 1))) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              child: card,
            );
          }).toList(),
        );
      },
    );
  }
}

// ──────────────────────────────────────────
// GRÁFICOS
// ──────────────────────────────────────────
class _ChartsRow extends StatelessWidget {
  const _ChartsRow();

  @override
  Widget build(BuildContext context) {
    final overviewVm = context.watch<OverviewViewModel>();

    final activityData = overviewVm.weeklyActivity;
    final responseData = overviewVm.weeklyResponses;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final chart = _DashCard(
          title: 'Atividade da Semana',
          subtitle: 'Mensagens enviadas vs. recebidas (banco)',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Legend(color: AppColors.metricSent, label: 'Enviadas'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.metricUnread, label: 'Recebidas'),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  onPressed: overviewVm.loadStats,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  tooltip: 'Atualizar dados',
                  padding: EdgeInsets.zero,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          child: SizedBox(
            height: 220,
            child: overviewVm.isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : activityData.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum envio registrado nos últimos 7 dias',
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ActivityBarChart(data: activityData),
          ),
        );

        final responseRate = _DashCard(
          title: 'Respostas Recebidas',
          subtitle: 'Últimos 7 dias (banco)',
          child: SizedBox(
            height: 220,
            child: overviewVm.isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : responseData.every((v) => v == 0)
                    ? Center(
                        child: Text(
                          'Nenhuma resposta registrada',
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ActivityLineChart(data: responseData),
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: chart),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: responseRate),
            ],
          );
        }
        return Column(
          children: [
            chart,
            const SizedBox(height: 16),
            responseRate,
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────
// LINHA INFERIOR
// ──────────────────────────────────────────
class _BottomRow extends StatelessWidget {
  const _BottomRow();

  @override
  Widget build(BuildContext context) {
    final overviewVm = context.watch<OverviewViewModel>();
    final recent = overviewVm.recentEnvios;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final recentActivity = _DashCard(
          title: 'Resultados Recentes',
          subtitle: 'Últimos envios persistidos no banco (hoje)',
          child: overviewVm.isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : recent.isEmpty
                  ? _EmptyState(
                      icon: Icons.inbox_rounded,
                      message: 'Nenhum envio registrado hoje',
                    )
                  : _ResultsTable(results: recent),
        );

        final quickStatus = _DashCard(
          title: 'Status do Sistema',
          subtitle: 'Visão rápida',
          child: _SystemStatus(),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: recentActivity),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: quickStatus),
            ],
          );
        }
        return Column(
          children: [
            recentActivity,
            const SizedBox(height: 16),
            quickStatus,
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────
// COMPONENTES AUXILIARES
// ──────────────────────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.results});
  final List<RecentEnvio> results;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: results.map<Widget>((r) {
        final isSuccess = r.success;
        final phone = r.phone;
        final message = r.message;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isSuccess ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  isSuccess ? Icons.check_rounded : Icons.close_rounded,
                  size: 15,
                  color: isSuccess ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phone,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      message,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SystemStatus extends StatelessWidget {
  const _SystemStatus();

  @override
  Widget build(BuildContext context) {
    final connectionVm = context.watch<ConnectionViewModel>();
    final autoReplyVm = context.watch<AutoReplyViewModel>();
    final templateVm = context.watch<TemplateViewModel>();
    final overviewVm = context.watch<OverviewViewModel>();

    final items = [
      _StatusItem(
        label: 'WhatsApp',
        value: connectionVm.isConnected ? 'Conectado' : 'Desconectado',
        color: connectionVm.isConnected ? AppColors.success : AppColors.warning,
        icon: Icons.phone_android_rounded,
      ),
      _StatusItem(
        label: 'Auto-Reply',
        value: autoReplyVm.isEnabled ? 'Ativo' : 'Inativo',
        color: autoReplyVm.isEnabled ? AppColors.success : AppColors.textMuted,
        icon: Icons.reply_rounded,
      ),
      _StatusItem(
        label: 'Campanha',
        value: templateVm.isSending
            ? '${templateVm.sendProgress}/${templateVm.sendTotal}'
            : (templateVm.hasSpreadsheet ? 'Planilha carregada' : 'Sem campanha'),
        color: templateVm.isSending
            ? AppColors.primary
            : (templateVm.hasSpreadsheet ? AppColors.info : AppColors.textMuted),
        icon: Icons.rocket_launch_rounded,
      ),
      _StatusItem(
        label: 'Banco de Dados',
        value: overviewVm.dbReady ? 'Conectado' : 'Indisponivel',
        color: overviewVm.dbReady ? AppColors.success : AppColors.warning,
        icon: Icons.storage_rounded,
      ),
    ];

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, size: 15, color: item.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.value,
                      style: GoogleFonts.inter(
                        color: item.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatusItem {
  const _StatusItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;
}
