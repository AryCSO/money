import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'presentation/views/main_layout.dart';

class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return MaterialApp(
      title: 'Money',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildLight(),
      darkTheme: AppTheme.buildDark(),
      themeMode: themeController.mode,
      home: const MainLayout(),
    );
  }
}
