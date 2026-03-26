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

  Future<void> disconnectInstance() async {
    final instanceName = AppConstants.instanceName;
    final requests = <Future<Response<dynamic>> Function()>[
      () => _apiClient.dio.delete('/instance/logout/$instanceName'),
      () => _apiClient.dio.post('/instance/logout/$instanceName'),
      () => _apiClient.dio.get('/instance/logout/$instanceName'),
      () => _apiClient.dio.delete('/instance/disconnect/$instanceName'),
      () => _apiClient.dio.post('/instance/disconnect/$instanceName'),
      () => _apiClient.dio.get('/instance/disconnect/$instanceName'),
    ];

    DioException? lastNotSupported;

    for (final request in requests) {
      try {
        await request();
        return;
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final canTryNext = status == 404 || status == 405;
        if (canTryNext) {
          lastNotSupported = e;
          continue;
        }
        rethrow;
      }
    }

    if (lastNotSupported != null) {
      throw lastNotSupported;
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

  /// Dispara o evento "composing" (digitando...) para o número indicado.
  /// Compatível com múltiplas versões da Evolution API.
  Future<void> sendPresence({
    required String number,
    String presence = 'composing',
  }) async {
    final instanceName = AppConstants.instanceName;
    final requests = <Future<Response<dynamic>> Function()>[
      // v2 – endpoint preferido
      () => _apiClient.dio.post(
            '/chat/sendPresence/$instanceName',
            data: {'number': number, 'presence': presence},
          ),
      // v2 alternativo
      () => _apiClient.dio.put(
            '/chat/sendPresence/$instanceName',
            data: {'number': number, 'presence': presence},
          ),
      // v1 / outras distribuições
      () => _apiClient.dio.post(
            '/chat/presence/$instanceName',
            data: {'number': number, 'presence': presence},
          ),
    ];

    for (final request in requests) {
      try {
        await request();
        return;
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final canTryNext = status == 404 || status == 405;
        if (canTryNext) continue;
        // Se não for erro de rota, ignora silenciosamente
        // para não travar o fluxo de envio por causa de presença.
        return;
      }
    }
    // Se nenhum endpoint funcionou, segue sem presença (fail-safe).
  }

  Future<void> sendText({
    required String number,
    required String text,
    int delay = AppConstants.defaultPresenceDelayMs,
  }) async {
    try {
      await _apiClient.dio.post(
        '/message/sendText/${AppConstants.instanceName}',
        data: {
          'number': number,
          'text': text,
          'delay': delay,
          'linkPreview': false,
        },
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final details = _describeDioError(e.response?.data);
      final statusText = status != null ? 'HTTP $status' : 'HTTP erro';

      if (details.isNotEmpty) {
        throw Exception('Falha ao enviar mensagem ($statusText): $details');
      }

      throw Exception('Falha ao enviar mensagem ($statusText).');
    }
  }

  Future<List<Map<String, dynamic>>> findChats() async {
    final instanceName = AppConstants.instanceName;
    final requests = <Future<Response<dynamic>> Function()>[
      () => _apiClient.dio.post(
            '/chat/findChats/$instanceName',
            data: {'page': 1, 'limit': 2000},
          ),
      () => _apiClient.dio.post(
            '/chat/findChats/$instanceName',
            data: {},
          ),
      () => _apiClient.dio.get('/chat/findChats/$instanceName'),
    ];

    for (final request in requests) {
      try {
        final response = await request();
        final chats = _extractMapList(
          response.data,
          preferredKeys: const ['chats', 'data', 'result'],
        );
        if (chats.isNotEmpty) {
          return chats;
        }
      } on DioException catch (e) {
        if (_canTryAlternativeHistoryRequest(e)) {
          continue;
        }
      } catch (_) {
        continue;
      }
    }

    return const [];
  }

  Future<List<Map<String, dynamic>>> findMessages({
    required String remoteJid,
    int limit = 60,
  }) async {
    final instanceName = AppConstants.instanceName;
    final requests = <Future<Response<dynamic>> Function()>[
      () => _apiClient.dio.post(
            '/chat/findMessages/$instanceName',
            data: {
              'where': {
                'key': {'remoteJid': remoteJid},
              },
              'page': 1,
              'limit': limit,
            },
          ),
      () => _apiClient.dio.post(
            '/chat/findMessages/$instanceName',
            data: {
              'where': {'key.remoteJid': remoteJid},
              'page': 1,
              'limit': limit,
            },
          ),
      () => _apiClient.dio.post(
            '/chat/findMessages/$instanceName',
            data: {'remoteJid': remoteJid, 'limit': limit},
          ),
      () => _apiClient.dio.post(
            '/chat/findMessages/$instanceName',
            data: {'jid': remoteJid, 'limit': limit},
          ),
    ];

    for (final request in requests) {
      try {
        final response = await request();
        final messages = _extractMapList(
          response.data,
          preferredKeys: const ['messages', 'data', 'result'],
        );
        if (messages.isNotEmpty) {
          return messages;
        }
      } on DioException catch (e) {
        if (_canTryAlternativeHistoryRequest(e)) {
          continue;
        }
      } catch (_) {
        continue;
      }
    }

    return const [];
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

  bool _canTryAlternativeHistoryRequest(DioException exception) {
    final status = exception.response?.statusCode ?? 0;
    return status == 400 || status == 404 || status == 405 || status == 422;
  }

  List<Map<String, dynamic>> _extractMapList(
    dynamic data, {
    required List<String> preferredKeys,
  }) {
    if (data is List) {
      return data.whereType<Map>().map(_toStringDynamicMap).toList();
    }

    if (data is! Map) {
      return const [];
    }

    final mapData = _toStringDynamicMap(data);

    for (final key in preferredKeys) {
      final extracted = _extractNestedMapList(mapData[key]);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    for (final value in mapData.values) {
      final extracted = _extractNestedMapList(value);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    if (mapData.isNotEmpty) {
      return [mapData];
    }

    return const [];
  }

  Map<String, dynamic> _toStringDynamicMap(Map value) {
    return value.map(
      (key, dynamic val) => MapEntry(key.toString(), val),
    );
  }

  List<Map<String, dynamic>> _extractNestedMapList(dynamic value) {
    if (value is List) {
      return value.whereType<Map>().map(_toStringDynamicMap).toList();
    }

    if (value is! Map) {
      return const [];
    }

    final nestedMap = _toStringDynamicMap(value);
    for (final nestedValue in nestedMap.values) {
      final extracted = _extractNestedMapList(nestedValue);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    return const [];
  }

  String _describeDioError(dynamic data) {
    if (data == null) {
      return '';
    }

    if (data is String) {
      return data.trim();
    }

    if (data is List) {
      final parts = data
          .map(_describeDioError)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return parts.join(' | ');
    }

    if (data is Map) {
      final preferredKeys = <String>[
        'message',
        'error',
        'response',
        'details',
        'detail',
        'cause',
      ];

      final mapped = _toStringDynamicMap(data);
      final parts = <String>[];

      for (final key in preferredKeys) {
        final value = mapped[key];
        final description = _describeDioError(value);
        if (description.isNotEmpty) {
          parts.add(description);
        }
      }

      if (parts.isNotEmpty) {
        return parts.join(' | ');
      }

      for (final entry in mapped.entries) {
        final description = _describeDioError(entry.value);
        if (description.isNotEmpty) {
          parts.add('${entry.key}: $description');
        }
      }

      return parts.join(' | ');
    }

    return data.toString().trim();
  }
}
