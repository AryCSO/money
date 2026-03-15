import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../models/instance_connection_state.dart';
import '../models/qr_code_response.dart';

class EvolutionApiService {
  EvolutionApiService(this._apiClient);

  final dynamic _apiClient;

  Future<void> createMoneyInstance() async {
    if (await _instanceExists()) {
      return;
    }

    try {
      await _apiClient.dio.post(
        '/instance/create',
        data: {
          'instanceName': AppConstants.instanceName,
          'integration': AppConstants.integration,
          'qrcode': true,
        },
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final text = body?.toString().toLowerCase() ?? '';
      final status = e.response?.statusCode ?? 0;

      final maybeAlreadyExists =
          status == 403 ||
          status == 409 ||
          text.contains('already') ||
          text.contains('exist');

      if (maybeAlreadyExists && await _instanceExists()) {
        return;
      }

      rethrow;
    }
  }

  Future<QrCodeResponse> getQrCode() async {
    final instanceName = AppConstants.instanceName;
    final requests = <Future<Response<dynamic>> Function()>[
      () => _apiClient.dio.get('/instance/connect/$instanceName'),
      () => _apiClient.dio.post('/instance/connect/$instanceName'),
      () => _apiClient.dio.get('/instance/qrcode/$instanceName'),
      () => _apiClient.dio.post('/instance/qrcode/$instanceName'),
    ];

    DioException? lastNotFound;

    for (final request in requests) {
      try {
        final response = await request();
        return _parseQrCodeResponse(response.data);
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final canTryNext = status == 404 || status == 405;
        if (canTryNext) {
          lastNotFound = e;
          continue;
        }
        rethrow;
      }
    }

    if (lastNotFound != null) {
      throw lastNotFound;
    }

    throw StateError('Nao foi possivel obter QR Code da instancia.');
  }

  Future<InstanceConnectionState> getConnectionState() async {
    final response = await _apiClient.dio.get(
      '/instance/connectionState/${AppConstants.instanceName}',
    );

    return InstanceConnectionState.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> sendText({
    required String number,
    required String text,
    int delay = AppConstants.defaultPresenceDelayMs,
  }) async {
    await _apiClient.dio.post(
      '/message/sendText/${AppConstants.instanceName}',
      data: {
        'number': number,
        'text': text,
        'delay': delay,
        'linkPreview': false,
      },
    );
  }

  QrCodeResponse _parseQrCodeResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Resposta de QR Code invalida.');
    }

    final nestedQr = data['qrcode'];
    final payload = nestedQr is Map<String, dynamic> ? nestedQr : data;

    final pairingCode = (payload['pairingCode'] ??
            payload['pairing'] ??
            data['pairingCode'] ??
            '')
        .toString();
    final code = (payload['code'] ??
            payload['qr'] ??
            data['code'] ??
            '')
        .toString();
    final base64 = (payload['base64'] ?? data['base64'] ?? '').toString();
    final count = int.tryParse(
          (payload['count'] ?? data['count'] ?? 0).toString(),
        ) ??
        0;

    return QrCodeResponse(
      pairingCode: pairingCode,
      code: code,
      base64: base64,
      count: count,
    );
  }

  Future<bool> _instanceExists() async {
    try {
      final response = await _apiClient.dio.get(
        '/instance/connectionState/${AppConstants.instanceName}',
      );
      return _hasInstance(response.data);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) {
        return false;
      }
      rethrow;
    }
  }

  bool _hasInstance(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return false;
    }

    final instance = data['instance'];
    final payload = instance is Map<String, dynamic> ? instance : data;
    final instanceName = (payload['instanceName'] ?? '').toString();
    final state = (payload['state'] ?? '').toString();

    return instanceName.isNotEmpty || state.isNotEmpty;
  }
}
