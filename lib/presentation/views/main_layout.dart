import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../widgets/app_sidebar.dart';
import 'campaigns_page.dart';
import 'chat_page.dart';
import 'connection_page.dart';
import 'developer_options_page.dart';
import 'overview_page.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  NavSection _section = NavSection.overview;
  bool _sidebarCollapsed = false;

  static const _pageTitles = {
    NavSection.overview: 'Visão Geral',
    NavSection.campaigns: 'Campanhas',
    NavSection.chat: 'Chat',
    NavSection.connection: 'Conexão WhatsApp',
    NavSection.settings: 'Configurações',
  };

  static const _pageSubtitles = {
    NavSection.overview: 'Monitore o desempenho das suas campanhas',
    NavSection.campaigns: 'Crie e dispare mensagens em massa',
    NavSection.chat: 'Histórico de conversas e auto-resposta',
    NavSection.connection: 'Gerencie sua instância WhatsApp',
    NavSection.settings: 'Opções avançadas do desenvolvedor',
  };

  Widget _buildPage() {
    return switch (_section) {
      NavSection.overview => const OverviewPage(),
      NavSection.campaigns => const CampaignsPage(),
      NavSection.chat => const ChatPage(),
      NavSection.connection => const ConnectionPage(),
      NavSection.settings => const DeveloperOptionsPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile) {
      return _MobileLayout(
        section: _section,
        onSectionChanged: (s) => setState(() => _section = s),
        child: _buildPage(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          AppSidebar(
            selected: _section,
            onSelect: (s) => setState(() => _section = s),
            collapsed: _sidebarCollapsed,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _pageTitles[_section]!,
                  subtitle: _pageSubtitles[_section]!,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_section),
                      child: _buildPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final connectionVm = context.watch<ConnectionViewModel>();
    final themeCtrl = context.watch<ThemeController>();

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),

          // Connection chip
          _ConnectionChip(
            isConnected: connectionVm.isConnected,
            isLoading: connectionVm.isLoading,
          ),
          const SizedBox(width: 8),

          // Theme toggle
          IconButton(
            onPressed: themeCtrl.toggle,
            tooltip: themeCtrl.isDark ? 'Modo claro' : 'Modo escuro',
            icon: Icon(
              themeCtrl.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 18,
            ),
          ),

          // User avatar
          const SizedBox(width: 4),
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
            child: Center(
              child: Text(
                'M',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.isConnected, required this.isLoading});
  final bool isConnected;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final IconData icon;

    if (isLoading) {
      color = AppColors.info;
      label = 'Verificando';
      icon = Icons.sync_rounded;
    } else if (isConnected) {
      color = AppColors.success;
      label = 'Online';
      icon = Icons.wifi_rounded;
    } else {
      color = AppColors.warning;
      label = 'Offline';
      icon = Icons.wifi_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout mobile com BottomNavigationBar
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.section,
    required this.onSectionChanged,
    required this.child,
  });

  final NavSection section;
  final ValueChanged<NavSection> onSectionChanged;
  final Widget child;

  int get _index => NavSection.values.indexOf(section).clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.sidebarBg,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) =>
              onSectionChanged([NavSection.overview, NavSection.campaigns, NavSection.chat][i]),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.primaryLight,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded, size: 22),
              label: 'Visão Geral',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rocket_launch_rounded, size: 22),
              label: 'Campanhas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 22),
              label: 'Chat',
            ),
          ],
        ),
      ),
    );
  }
}
