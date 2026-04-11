import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../viewmodels/connection_viewmodel.dart';

enum NavSection {
  overview,
  campaigns,
  chat,
  connection,
  settings,
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final NavSection selected;
  final ValueChanged<NavSection> onSelect;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final connectionVm = context.watch<ConnectionViewModel>();
    final w = collapsed ? 68.0 : 220.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: w,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(
          right: BorderSide(color: AppColors.sidebarBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          // ── Logo ──
          _SidebarHeader(collapsed: collapsed, onToggleCollapse: onToggleCollapse),
          const SizedBox(height: 8),
          // ── Nav items ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _NavItem(
                    icon: Icons.grid_view_rounded,
                    label: 'Visão Geral',
                    section: NavSection.overview,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: onSelect,
                  ),
                  _NavItem(
                    icon: Icons.rocket_launch_rounded,
                    label: 'Campanhas',
                    section: NavSection.campaigns,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: onSelect,
                  ),
                  _NavItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chat',
                    section: NavSection.chat,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: onSelect,
                  ),
                  const _SidebarDivider(),
                  _NavItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Conexão',
                    section: NavSection.connection,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: onSelect,
                    trailing: _ConnectionDot(isConnected: connectionVm.isConnected),
                  ),
                  _NavItem(
                    icon: Icons.tune_rounded,
                    label: 'Configurações',
                    section: NavSection.settings,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: onSelect,
                  ),
                ],
              ),
            ),
          ),
          // ── Status ──
          _SidebarFooter(
            collapsed: collapsed,
            isConnected: connectionVm.isConnected,
            isLoading: connectionVm.isLoading,
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.sidebarBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo mark
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Money',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            InkWell(
              onTap: onToggleCollapse,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ] else ...[
            const Spacer(),
            InkWell(
              onTap: onToggleCollapse,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final NavSection section;
  final NavSection selected;
  final bool collapsed;
  final ValueChanged<NavSection> onTap;
  final Widget? trailing;

  bool get _isSelected => section == selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isSelected ? AppColors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(section),
              borderRadius: BorderRadius.circular(8),
              hoverColor: _isSelected ? Colors.transparent : AppColors.sidebarHover,
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : 10,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: _isSelected
                          ? AppColors.primaryLight
                          : AppColors.textSecondary,
                    ),
                    if (!collapsed) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: GoogleFonts.inter(
                            color: _isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: _isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.isConnected});
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isConnected ? AppColors.success : AppColors.warning,
        boxShadow: [
          BoxShadow(
            color: (isConnected ? AppColors.success : AppColors.warning)
                .withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.sidebarBorder,
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.isConnected,
    required this.isLoading,
  });

  final bool collapsed;
  final bool isConnected;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    late final Color dotColor;
    late final String statusLabel;

    if (isLoading) {
      dotColor = AppColors.info;
      statusLabel = 'Verificando...';
    } else if (isConnected) {
      dotColor = AppColors.success;
      statusLabel = 'Conectado';
    } else {
      dotColor = AppColors.warning;
      statusLabel = 'Desconectado';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 16 : 16,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.sidebarBorder, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 8),
            Text(
              'WhatsApp • $statusLabel',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
