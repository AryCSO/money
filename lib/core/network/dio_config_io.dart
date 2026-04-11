import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

void setupDioAdapter(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      // Apenas aceita certificados inválidos em modo debug.
      // Em release, a validação SSL padrão é mantida.
      if (kDebugMode) {
        client.badCertificateCallback = (cert, host, port) => true;
      }
      return client;
    };
  }
}
