import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/qr_code_response.dart';
import '../../domain/usecases/check_connection_usecase.dart';
import '../../domain/usecases/ensure_money_instance_usecase.dart';
import '../../domain/usecases/get_qr_code_usecase.dart';

class ConnectionViewModel extends ChangeNotifier {
  ConnectionViewModel({
    required EnsureMoneyInstanceUseCase ensureMoneyInstanceUseCase,
    required GetQrCodeUseCase getQrCodeUseCase,
    required CheckConnectionUseCase checkConnectionUseCase,
  }) : _ensureMoneyInstanceUseCase = ensureMoneyInstanceUseCase,
       _getQrCodeUseCase = getQrCodeUseCase,
       _checkConnectionUseCase = checkConnectionUseCase;

  final EnsureMoneyInstanceUseCase _ensureMoneyInstanceUseCase;
  final GetQrCodeUseCase _getQrCodeUseCase;
  final CheckConnectionUseCase _checkConnectionUseCase;

  bool isLoading = true;
  bool isConnected = false;
  bool isRefreshingQr = false;
  bool _isCheckingConnection = false;
  String? errorMessage;
  QrCodeResponse? qrCode;
  DateTime? lastQrRefreshAt;
  Timer? _poller;

  Future<void> initialize() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      try {
        await _ensureMoneyInstanceUseCase();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Falha ao garantir instancia money: $e');
        }
      }

      await refreshQrCode(showLoader: false);
      await checkConnection();
      _startPolling();
    } catch (e) {
      errorMessage = 'Falha ao inicializar a instancia money: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshQrCode({bool showLoader = true}) async {
    if (showLoader) {
      isRefreshingQr = true;
      notifyListeners();
    }

    try {
      qrCode = await _getQrCodeUseCase();
      lastQrRefreshAt = DateTime.now();
      errorMessage = null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) {
        try {
          await _ensureMoneyInstanceUseCase();
          qrCode = await _getQrCodeUseCase();
          lastQrRefreshAt = DateTime.now();
          errorMessage = null;
        } catch (retryError) {
          errorMessage = 'Nao foi possivel carregar o QR Code: $retryError';
        }
      } else {
        errorMessage = 'Nao foi possivel carregar o QR Code: $e';
      }
    } catch (e) {
      errorMessage = 'Nao foi possivel carregar o QR Code: $e';
    } finally {
      isRefreshingQr = false;
      notifyListeners();
    }
  }

  Future<void> checkConnection() async {
    if (_isCheckingConnection || isConnected) {
      return;
    }

    _isCheckingConnection = true;
    try {
      final result = await _checkConnectionUseCase();
      isConnected = result.isOpen;
      if (isConnected) {
        _poller?.cancel();
      }
    } catch (_) {
      isConnected = false;
    } finally {
      _isCheckingConnection = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(AppConstants.connectionPollInterval, (_) async {
      await checkConnection();

      if (isConnected || isRefreshingQr) {
        return;
      }

      final refreshedAt = lastQrRefreshAt;
      final shouldRefresh =
          refreshedAt == null ||
          DateTime.now().difference(refreshedAt) >= const Duration(seconds: 20);

      if (shouldRefresh) {
        await refreshQrCode(showLoader: false);
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }
}
