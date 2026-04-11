import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

class ActivityBarData {
  const ActivityBarData({required this.label, required this.sent, required this.received});
  final String label;
  final double sent;
  final double received;
}

class ActivityBarChart extends StatefulWidget {
  const ActivityBarChart({super.key, required this.data});
  final List<ActivityBarData> data;

  @override
  State<ActivityBarChart> createState() => _ActivityBarChartState();
}

class _ActivityBarChartState extends State<ActivityBarChart> {
  int? _touchedGroup;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Center(
        child: Text(
          'Sem dados de atividade',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
        ),
      );
    }

    final maxY = widget.data
        .map((d) => d.sent + d.received)
        .reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxY * 1.3,
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            setState(() {
              if (response?.spot != null &&
                  event is! FlPointerExitEvent &&
                  event is! FlTapUpEvent) {
                _touchedGroup = response!.spot!.touchedBarGroupIndex;
              } else {
                _touchedGroup = null;
              }
            });
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceAlt,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = widget.data[groupIndex];
              final label = rodIndex == 0 ? 'Enviadas' : 'Recebidas';
              final value = rodIndex == 0 ? d.sent : d.received;
              return BarTooltipItem(
                '$label\n${value.toStringAsFixed(0)}',
                GoogleFonts.inter(
                  color: rodIndex == 0
                      ? AppColors.metricSent
                      : AppColors.metricUnread,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= widget.data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.data[idx].label,
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY > 0 ? (maxY / 4).ceilToDouble() : 10,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.toInt().toString(),
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? (maxY / 4).ceilToDouble() : 10,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.border.withValues(alpha: 0.6),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(widget.data.length, (i) {
          final d = widget.data[i];
          final isTouched = _touchedGroup == i;
          return BarChartGroupData(
            x: i,
            groupVertically: false,
            barsSpace: 4,
            barRods: [
              BarChartRodData(
                toY: d.sent,
                color: isTouched
                    ? AppColors.primaryLight
                    : AppColors.metricSent.withValues(alpha: 0.85),
                width: 10,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
              BarChartRodData(
                toY: d.received,
                color: isTouched
                    ? AppColors.accent
                    : AppColors.metricUnread.withValues(alpha: 0.7),
                width: 10,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class ActivityLineChart extends StatelessWidget {
  const ActivityLineChart({super.key, required this.data});
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i]),
    );
    final maxY = data.reduce((a, b) => a > b ? a : b) * 1.3;

    return LineChart(
      LineChartData(
        maxY: maxY,
        minY: 0,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceAlt,
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    s.y.toStringAsFixed(0),
                    GoogleFonts.inter(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        titlesData: const FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primaryLight,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.25),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
