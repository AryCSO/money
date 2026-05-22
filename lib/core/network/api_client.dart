import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'dio_config.dart';

class ApiClient {
  ApiClient({required String initialBaseUrl}) {
    dio = Dio(
      BaseOptions(
        baseUrl: initialBaseUrl,
        headers: {
          'Content-Type': 'application/json',
          'apikey': AppConstants.apiKey,
        },
        // O connectTimeout precisa ser curto para que a UI nao
        // congele caso a API Evolution esteja fora do ar.
        // O receiveTimeout segue maior porque o QR code e respostas
        // de envio podem demorar.
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: kIsWeb ? null : const Duration(seconds: 60),
      ),
    );

    setupDioAdapter(dio);
  }

  late final Dio dio;

  void updateBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
  }
}
