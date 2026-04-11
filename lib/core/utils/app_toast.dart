import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum ToastType { success, error, warning, info }

class AppToast {
  const AppToast._();

  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final (icon, bgColor, fgColor) = switch (type) {
      ToastType.success => (
        Icons.check_circle_rounded,
        AppColors.success.withValues(alpha: 0.16),
        AppColors.success,
      ),
      ToastType.error => (
        Icons.error_rounded,
        AppColors.errorLight.withValues(alpha: 0.16),
        AppColors.errorLight,
      ),
      ToastType.warning => (
        Icons.warning_rounded,
        AppColors.warning.withValues(alpha: 0.16),
        AppColors.warning,
      ),
      ToastType.info => (
        Icons.info_rounded,
        AppColors.info.withValues(alpha: 0.16),
        AppColors.info,
      ),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: fgColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: bgColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: fgColor.withValues(alpha: 0.35)),
          ),
          duration: duration,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }
}
