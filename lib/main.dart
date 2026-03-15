import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'data/datasources/evolution_api_service.dart';
import 'data/repositories/evolution_repository_impl.dart';
import 'domain/usecases/check_connection_usecase.dart';
import 'domain/usecases/ensure_money_instance_usecase.dart';
import 'domain/usecases/get_qr_code_usecase.dart';
import 'domain/usecases/send_bulk_messages_usecase.dart';
import 'presentation/viewmodels/connection_viewmodel.dart';
import 'presentation/viewmodels/template_viewmodel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1360, 850),
        minimumSize: Size(1100, 700),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final apiClient = ApiClient();
  final apiService = EvolutionApiService(apiClient);
  final repository = EvolutionRepositoryImpl(apiService);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: repository),
        ChangeNotifierProvider(
          create: (_) => ConnectionViewModel(
            ensureMoneyInstanceUseCase: EnsureMoneyInstanceUseCase(repository),
            getQrCodeUseCase: GetQrCodeUseCase(repository),
            checkConnectionUseCase: CheckConnectionUseCase(repository),
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => TemplateViewModel(
            sendBulkMessagesUseCase: SendBulkMessagesUseCase(repository),
          ),
        ),
      ],
      child: const MoneyApp(),
    ),
  );
}
