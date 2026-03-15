import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

void setupDioAdapter(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }
}
