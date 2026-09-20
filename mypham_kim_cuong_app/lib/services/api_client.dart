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

enum ProductsStatus { ok, wcInactive, httpError, networkError, invalidUrl }

class ProductsResult {
  const ProductsResult({
    required this.status,
    this.items = const [],
    this.message,
  });

  final ProductsStatus status;
  final List<Map<String, dynamic>> items;
  final String? message;

  bool get succeeded => status == ProductsStatus.ok;
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _timeout = Duration(seconds: 10);
  static const String _healthPath = '/wp-json/kc/v1/health';
  static const String _productsPath = '/wp-json/kc/v1/products';

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

  Future<ProductsResult> fetchProducts({
    String? search,
    int perPage = 20,
    int page = 1,
  }) async {
    final sortedSearch = (search?.trim().isEmpty ?? true) ? null : search!.trim();
    final uri = _productsUri(
      AppSettings.baseUrl,
      search: sortedSearch,
      perPage: perPage,
      page: page,
    );
    if (uri == null) {
      return const ProductsResult(
        status: ProductsStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    try {
      final response = await _httpClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return ProductsResult(
          status: ProductsStatus.httpError,
          message: 'HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ProductsResult(
          status: ProductsStatus.httpError,
          message: 'Phản hồi không hợp lệ',
        );
      }

      if (decoded['wc_active'] != true) {
        return ProductsResult(
          status: ProductsStatus.wcInactive,
          message:
              decoded['message']?.toString() ?? 'WooCommerce chưa active',
        );
      }

      final rawItems = decoded['data'];
      if (rawItems is! List) {
        return const ProductsResult(
          status: ProductsStatus.httpError,
          message: 'Thiếu danh sách sản phẩm',
        );
      }

      final items = rawItems.whereType<Map<String, dynamic>>().toList();
      return ProductsResult(status: ProductsStatus.ok, items: items);
    } on TimeoutException {
      return const ProductsResult(
        status: ProductsStatus.networkError,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const ProductsResult(
        status: ProductsStatus.networkError,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  Uri? _healthUri(String baseUrl) => _apiUri(baseUrl, _healthPath);

  Uri? _productsUri(
    String baseUrl, {
    required String? search,
    required int perPage,
    required int page,
  }) {
    final query = <String, String>{
      'per_page': '$perPage',
      'page': '$page',
    };
    if (search != null) {
      query['search'] = search;
    }
    return _apiUri(baseUrl, _productsPath, query: query);
  }

  Uri? _apiUri(String baseUrl, String path, {Map<String, String>? query}) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse('$normalized$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    if (query != null && query.isNotEmpty) {
      return uri.replace(queryParameters: query);
    }
    return uri;
  }
}