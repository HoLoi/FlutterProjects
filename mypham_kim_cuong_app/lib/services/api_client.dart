import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';

enum HealthStatus { online, offline, invalidUrl }

class HealthResult {
  const HealthResult({
    required this.status,
    this.message,
    this.plugin,
    this.version,
    this.time,
    this.wordpress,
    this.woocommerceActive,
  });

  final HealthStatus status;
  final String? message;
  final String? plugin;
  final String? version;
  final String? time;
  final String? wordpress;
  final bool? woocommerceActive;
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _timeout = Duration(seconds: 10);
  static const String _healthPath = '/wp-json/kc/v1/health';

  Future<HealthResult> checkHealth() async {
    final uri = _healthUri(AppSettings.baseUrl);
    if (uri == null) {
      return const HealthResult(
        status: HealthStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    try {
      final response = await _httpClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return HealthResult(
          status: HealthStatus.offline,
          message: 'HTTP ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['ok'] == true) {
        return HealthResult(
          status: HealthStatus.online,
          plugin: body['plugin']?.toString(),
          version: body['version']?.toString(),
          time: body['time']?.toString(),
          wordpress: body['wordpress']?.toString(),
          woocommerceActive: body['woocommerce_active'] == true,
        );
      }

      return const HealthResult(
        status: HealthStatus.offline,
        message: 'Phản hồi không hợp lệ',
      );
    } on TimeoutException {
      return const HealthResult(
        status: HealthStatus.offline,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const HealthResult(
        status: HealthStatus.offline,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  Uri? _healthUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse('$normalized$_healthPath');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    return uri;
  }
}