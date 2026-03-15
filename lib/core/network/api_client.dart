import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'dio_config.dart';

class ApiClient {
  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'apikey': AppConstants.apiKey,
        },
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: kIsWeb ? null : const Duration(seconds: 60),
      ),
    );

    setupDioAdapter(dio);
  }

  late final Dio dio;
}
