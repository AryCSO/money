import 'package:flutter/material.dart';

/// Nova paleta de cores do Money — design SaaS moderno.
/// Inspirado em Linear, Vercel e Raycast.
class AppColors {
  const AppColors._();

  // ── Marca ──
  static const Color primary = Color(0xFF6366F1);       // Indigo 500
  static const Color primaryLight = Color(0xFF818CF8);  // Indigo 400
  static const Color primaryDim = Color(0xFF312E81);    // Indigo 900
  static const Color accent = Color(0xFF22D3EE);        // Cyan 400
  static const Color accentDim = Color(0xFF164E63);     // Cyan 900

  // Compat aliases (código existente usa essas constantes)
  static const Color gold = primary;
  static const Color goldLight = primaryLight;

  // ── Fundos ──
  static const Color background = Color(0xFF070A13);
  static const Color surface = Color(0xFF0D1117);
  static const Color surfaceAlt = Color(0xFF161C2D);
  static const Color cardHover = Color(0xFF1E2A45);
  static const Color border = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0xFF0F172A);

  // Compat aliases
  static const Color gradientTop = Color(0xFF0D1117);
  static const Color gradientBottom = Color(0xFF070A13);
  static const Color settingsGradientTop = Color(0xFF0D1117);
  static const Color settingsGradientBottom = Color(0xFF070A13);

  // ── Sidebar ──
  static const Color sidebarBg = Color(0xFF050811);
  static const Color sidebarActive = Color(0xFF1A1F35);
  static const Color sidebarBorder = Color(0xFF0F1525);
  static const Color sidebarHover = Color(0xFF11172A);

  // ── Texto ──
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);
  static const Color textHint = Color(0xFF64748B);
  static const Color textLabel = Color(0xFFCBD5E1);
  static const Color textOnDark = Color(0xFFF8FAFC);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnGold = Colors.white;

  // ── Status ──
  static const Color success = Color(0xFF10B981);
  static const Color successDim = Color(0xFF064E3B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFCA5A5);
  static const Color errorText = Color(0xFFFCA5A5);
  static const Color errorDim = Color(0xFF450A0A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningAlt = Color(0xFFD97706);
  static const Color warningDim = Color(0xFF451A03);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoDim = Color(0xFF1E3A5F);

  // ── Chat (WhatsApp-like — mantido) ──
  static const Color chatSidebar = Color(0xFF0D1117);
  static const Color chatHeader = Color(0xFF161C2D);
  static const Color chatBackground = Color(0xFF070A13);
  static const Color chatIncomingBubble = Color(0xFF161C2D);
  static const Color chatOutgoingBubble = Color(0xFF1E3A5F);
  static const Color chatAccent = Color(0xFF22D3EE);
  static const Color chatTick = Color(0xFF818CF8);
  static const Color chatInputSurface = Color(0xFF161C2D);
  static const Color chatDivider = Color(0xFF1E293B);
  static const Color chatDateChip = Color(0xFF0D1117);

  // ── Componentes ──
  static const Color snackBarBackground = Color(0xFF161C2D);
  static const Color cardBorder = Color(0xFF1E293B);
  static const Color chipChatButton = Color(0xFF1A1F35);
  static const Color chipChatText = Color(0xFF818CF8);
  static const Color dialogDark = Color(0xFF0D1117);

  // ── Attachments ──
  static const Color attachDocument = Color(0xFF7C3AED);
  static const Color attachImage = Color(0xFF059669);
  static const Color attachVideo = Color(0xFFD97706);
  static const Color attachLocation = Color(0xFF0891B2);
  static const Color attachPlace = Color(0xFFDC2626);

  // ── Light Theme ──
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // ── Gráficos / Métricas ──
  static const Color chartBar1 = Color(0xFF6366F1);
  static const Color chartBar2 = Color(0xFF22D3EE);
  static const Color chartLine = Color(0xFF818CF8);
  static const Color metricSent = Color(0xFF6366F1);
  static const Color metricPending = Color(0xFFF59E0B);
  static const Color metricUnread = Color(0xFF22D3EE);
  static const Color metricReturn = Color(0xFF10B981);
}
