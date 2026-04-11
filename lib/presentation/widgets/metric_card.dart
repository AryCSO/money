import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

class MetricCard extends StatefulWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.trend,
    this.trendPositive,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String? subtitle;

  /// Texto de tendência, ex: "+12% hoje"
  final String? trend;

  /// null = neutro, true = positivo (verde), false = negativo (vermelho)
  final bool? trendPositive;

  final VoidCallback? onTap;

  @override
  State<MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<MetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withValues(alpha: 0.3)
                  : AppColors.border,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: ícone + label
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.accentColor,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  if (widget.trend != null)
                    _TrendBadge(
                      text: widget.trend!,
                      positive: widget.trendPositive,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Valor principal
              Text(
                widget.value,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              // Label
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.text, this.positive});
  final String text;
  final bool? positive;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    if (positive == null) {
      color = AppColors.textMuted;
      icon = Icons.remove_rounded;
    } else if (positive!) {
      color = AppColors.success;
      icon = Icons.trending_up_rounded;
    } else {
      color = AppColors.error;
      icon = Icons.trending_down_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
