import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/anti_ban_controller.dart';
import 'core/config/app_config_controller.dart';
import 'core/config/google_config_controller.dart';
import 'core/config/window_behavior_controller.dart';
import 'core/network/api_client.dart';
import 'core/theme/theme_controller.dart';
import 'data/datasources/auto_reply_service.dart';
import 'data/datasources/google_auth_service.dart';
import 'data/datasources/database_service.dart';
import 'data/datasources/evolution_api_service.dart';
import 'data/datasources/send_history_service.dart';
import 'data/datasources/system_tray_service.dart';
import 'data/repositories/evolution_repository_impl.dart';
import 'domain/usecases/check_connection_usecase.dart';
import 'domain/usecases/disconnect_instance_usecase.dart';
import 'domain/usecases/ensure_money_instance_usecase.dart';
import 'domain/usecases/get_qr_code_usecase.dart';
import 'domain/usecases/send_bulk_messages_usecase.dart';
import 'presentation/viewmodels/auth_viewmodel.dart';
import 'presentation/viewmodels/auto_reply_viewmodel.dart';
import 'presentation/viewmodels/connection_viewmodel.dart';
import 'presentation/viewmodels/google_viewmodel.dart';
import 'presentation/viewmodels/overview_viewmodel.dart';
import 'presentation/viewmodels/pending_clients_viewmodel.dart';
import 'presentation/viewmodels/template_viewmodel.dart';

const _kDesktopInitialSize = Size(1360, 850);
const _kDesktopMinimumSize = Size(820, 640);

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Inicializar banco de dados (apenas desktop) ──
  // Disparado o mais cedo possivel, em paralelo com o setup da janela,
  // para que o arquivo .fdb seja criado/conectado assim que o app abre,
  // independente do estado do WhatsApp. Awaitamos antes de runApp com
  // timeout duro para nao travar caso o Firebird esteja inacessivel.
  final dbInit = !kIsWeb
      ? () async {
          try {
            await DatabaseService.instance.database.timeout(
              const Duration(seconds: 15),
            );
          } catch (e) {
            // Sempre logar (em release tambem) — se a criacao do banco
            // falhar, o usuario precisa enxergar nos logs do app por que.
            debugPrint('Aviso: Falha ao inicializar banco de dados: $e');
          }
        }()
      : Future<void>.value();

  final windowBehavior = WindowBehaviorController();
  if (_isDesktop) {
    await windowBehavior.load();
  }

  final antiBan = AntiBanController();
  await antiBan.load();

  final googleConfig = GoogleConfigController();
  await googleConfig.load();
  final googleAuthService = GoogleAuthService();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: _kDesktopInitialSize,
        minimumSize: _kDesktopMinimumSize,
        center: true,
      ),
      () async {
        await windowManager.setMinimumSize(_kDesktopMinimumSize);
        // Sempre interceptamos o close — o listener decide entre esconder ou destruir.
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      },
    );

    windowManager.addListener(_AppWindowListener(windowBehavior));
    await SystemTrayService.instance.initialize();
  }

  // Garante que o banco esteja criado/aberto (ou falhou com log) antes
  // de subir as ViewModels que dependem dele.
  await dbInit;

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
  final autoReplyService = AutoReplyService(evolutionApiService: apiService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => AuthViewModel()..restore()),
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider.value(value: windowBehavior),
        ChangeNotifierProvider.value(value: antiBan),
        ChangeNotifierProvider.value(value: googleConfig),
        Provider.value(value: repository),
        ChangeNotifierProvider(
          create: (_) => GoogleViewModel(
            authService: googleAuthService,
            config: googleConfig,
          )..initialize(),
        ),
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
          create: (_) => AutoReplyViewModel(autoReplyService: autoReplyService),
        ),
        ChangeNotifierProvider(
          create: (_) => OverviewViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              PendingClientsViewModel(autoReplyService: autoReplyService),
        ),
        ChangeNotifierProxyProvider2<AutoReplyViewModel, AntiBanController,
            TemplateViewModel>(
          create: (_) => TemplateViewModel(
            sendBulkMessagesUseCase: SendBulkMessagesUseCase(repository),
            sendHistoryService: sendHistoryService,
          ),
          update: (_, autoReplyVm, antiBanCtrl, templateVm) {
            templateVm!.autoReplyViewModel = autoReplyVm;
            templateVm.antiBan = antiBanCtrl;
            return templateVm;
          },
        ),
      ],
      child: const MoneyApp(),
    ),
  );
}

/// Intercepta o evento de fechamento da janela:
/// - Se "fechar para a bandeja" estiver habilitado, esconde a janela.
/// - Caso contrário, destrói a janela e encerra o processo.
class _AppWindowListener extends WindowListener {
  _AppWindowListener(this._behavior);

  final WindowBehaviorController _behavior;

  @override
  void onWindowClose() async {
    if (_behavior.closeToTray) {
      await windowManager.hide();
      return;
    }
    await SystemTrayService.instance.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
