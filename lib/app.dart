import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'presentation/viewmodels/connection_viewmodel.dart';
import 'presentation/views/connection_page.dart';
import 'presentation/views/dashboard_page.dart';

class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: Consumer<ConnectionViewModel>(
        builder: (context, vm, child) {
          if (vm.isConnected) {
            return const DashboardPage();
          }

          return const ConnectionPage();
        },
      ),
    );
  }
}
