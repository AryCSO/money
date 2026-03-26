import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/app_config_controller.dart';
import 'core/network/api_client.dart';
import 'data/datasources/auto_reply_service.dart';
import 'data/datasources/database_service.dart';
import 'data/datasources/evolution_api_service.dart';
import 'data/datasources/send_history_service.dart';
import 'data/repositories/evolution_repository_impl.dart';
import 'domain/usecases/check_connection_usecase.dart';
import 'domain/usecases/disconnect_instance_usecase.dart';
import 'domain/usecases/ensure_money_instance_usecase.dart';
import 'domain/usecases/get_qr_code_usecase.dart';
import 'domain/usecases/send_bulk_messages_usecase.dart';
import 'presentation/viewmodels/auto_reply_viewmodel.dart';
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

  // ── Inicializar banco de dados ──
  try {
    await DatabaseService.instance.database;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Aviso: Falha ao inicializar banco de dados: $e');
    }
  }

  final appConfig = AppConfigController();
  final apiClient = ApiClient(initialBaseUrl: appConfig.baseUrl);
  appConfig.addListener(() {
    apiClient.updateBaseUrl(appConfig.baseUrl);
  });

  final apiService = EvolutionApiService(apiClient);
  final sendHistoryService = SendHistoryService(
    evolutionApiService: apiService,
  );
  final repository = EvolutionRepositoryImpl(apiService, sendHistoryService);

  // ── Serviço de Auto-Reply ──
  final autoReplyService = AutoReplyService(
    evolutionApiService: apiService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appConfig),
        Provider.value(value: repository),
        ChangeNotifierProvider(
          create: (_) => ConnectionViewModel(
            ensureMoneyInstanceUseCase: EnsureMoneyInstanceUseCase(repository),
            getQrCodeUseCase: GetQrCodeUseCase(repository),
            checkConnectionUseCase: CheckConnectionUseCase(repository),
            disconnectInstanceUseCase: DisconnectInstanceUseCase(repository),
          )..initialize(),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => AutoReplyViewModel(
            autoReplyService: autoReplyService,
          ),
        ),
        ChangeNotifierProxyProvider<AutoReplyViewModel, TemplateViewModel>(
          create: (_) => TemplateViewModel(
            sendBulkMessagesUseCase: SendBulkMessagesUseCase(repository),
          ),
          update: (_, autoReplyVm, templateVm) {
            templateVm!.autoReplyViewModel = autoReplyVm;
            return templateVm;
          },
        ),
      ],
      child: const MoneyApp(),
    ),
  );
}
