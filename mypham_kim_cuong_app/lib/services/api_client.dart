import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import 'auth_session.dart';

/// Thông điệp chuẩn khi server từ chối truy cập endpoint đơn hàng.
class AuthErrorMessages {
  const AuthErrorMessages._();

  static const String unauthorized =
      'Thông tin đăng nhập không hợp lệ hoặc đã hết hạn';
  static const String forbidden = 'Tài khoản không có quyền xem đơn hàng';
  static const String notSignedIn = 'Bạn cần đăng nhập để xem đơn hàng';
}

enum HealthStatus { online, offline, invalidUrl }

/// Kết quả kiểm tra đăng nhập bằng Application Password.
class LoginStatus {
  const LoginStatus({required this.failed, this.message});

  final bool failed;
  final String? message;
}

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

enum CatalogStatus {
  ok,
  wcInactive,
  httpError,
  networkError,
  invalidUrl,
  unauthorized,
  forbidden,
}

class CatalogResult {
  const CatalogResult({
    required this.status,
    this.items = const [],
    this.message,
  });

  final CatalogStatus status;
  final List<Map<String, dynamic>> items;
  final String? message;

  bool get succeeded => status == CatalogStatus.ok;
}

enum OrderDetailStatus {
  ok,
  notFound,
  wcInactive,
  httpError,
  networkError,
  invalidUrl,
  unauthorized,
  forbidden,
}

class OrderDetailResult {
  const OrderDetailResult({required this.status, this.data, this.message});

  final OrderDetailStatus status;
  final Map<String, dynamic>? data;
  final String? message;

  bool get succeeded => status == OrderDetailStatus.ok;
}

class ApiClient {
  ApiClient({http.Client? httpClient, this.authSession})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Session đăng nhập dùng cho endpoint cần xác thực.
  /// Chỉ đọc ở đây; mật khẩu nằm trong [AuthSession], không nằm ở ApiClient.
  final AuthSession? authSession;

  static const Duration _timeout = Duration(seconds: 10);
  static const String _healthPath = '/wp-json/kc/v1/health';
  static const String _productsPath = '/wp-json/kc/v1/products';
  static const String _categoriesPath = '/wp-json/kc/v1/categories';
  static const String _variationsPath = '/wp-json/kc/v1/variations';
  static const String _ordersPath = '/wp-json/kc/v1/orders';

  static const Map<String, String> _publicHeaders = {
    'Accept': 'application/json',
  };

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
          .get(uri, headers: _publicHeaders)
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
    final sortedSearch = (search?.trim().isEmpty ?? true)
        ? null
        : search!.trim();
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
          .get(uri, headers: _publicHeaders)
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
          message: decoded['message']?.toString() ?? 'WooCommerce chưa active',
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

  /// Danh sách danh mục sản phẩm WooCommerce (read-only).
  Future<CatalogResult> fetchCategories({
    String? search,
    int perPage = 50,
    int page = 1,
  }) async {
    final query = <String, String>{'per_page': '$perPage', 'page': '$page'};
    final sortedSearch = (search?.trim().isEmpty ?? true)
        ? null
        : search!.trim();
    if (sortedSearch != null) {
      query['search'] = sortedSearch;
    }
    return _fetchCatalog(path: _categoriesPath, query: query);
  }

  /// Danh sách biến thể của một sản phẩm (read-only).
  Future<CatalogResult> fetchVariations({
    required int productId,
    String? search,
  }) async {
    final query = <String, String>{'product_id': '$productId'};
    final sortedSearch = (search?.trim().isEmpty ?? true)
        ? null
        : search!.trim();
    if (sortedSearch != null) {
      query['search'] = sortedSearch;
    }
    return _fetchCatalog(path: _variationsPath, query: query);
  }

  /// Danh sách đơn hàng WooCommerce (read-only, cần đăng nhập).
  Future<CatalogResult> fetchOrders({
    String? search,
    String? status,
    int perPage = 20,
    int page = 1,
  }) async {
    final query = <String, String>{'per_page': '$perPage', 'page': '$page'};
    final sortedSearch = (search?.trim().isEmpty ?? true)
        ? null
        : search!.trim();
    if (sortedSearch != null) {
      query['search'] = sortedSearch;
    }
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    return _fetchCatalog(path: _ordersPath, query: query, requireAuth: true);
  }

  /// Chi tiết một đơn hàng (read-only, cần đăng nhập).
  Future<OrderDetailResult> fetchOrderDetail(int orderId) async {
    final uri = _apiUri(AppSettings.baseUrl, '$_ordersPath/$orderId');
    if (uri == null) {
      return const OrderDetailResult(
        status: OrderDetailStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    if (!(authSession?.isSignedIn ?? false)) {
      return const OrderDetailResult(
        status: OrderDetailStatus.unauthorized,
        message: AuthErrorMessages.notSignedIn,
      );
    }

    try {
      final response = await _httpClient
          .get(uri, headers: _authHeaders())
          .timeout(_timeout);

      if (response.statusCode == 401) {
        return const OrderDetailResult(
          status: OrderDetailStatus.unauthorized,
          message: AuthErrorMessages.unauthorized,
        );
      }

      if (response.statusCode == 403) {
        return const OrderDetailResult(
          status: OrderDetailStatus.forbidden,
          message: AuthErrorMessages.forbidden,
        );
      }

      if (response.statusCode == 404) {
        return const OrderDetailResult(
          status: OrderDetailStatus.notFound,
          message: 'Không tìm thấy đơn hàng',
        );
      }

      if (response.statusCode != 200) {
        return OrderDetailResult(
          status: OrderDetailStatus.httpError,
          message: 'HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const OrderDetailResult(
          status: OrderDetailStatus.httpError,
          message: 'Phản hồi không hợp lệ',
        );
      }

      if (decoded['wc_active'] != true) {
        return OrderDetailResult(
          status: OrderDetailStatus.wcInactive,
          message: decoded['message']?.toString() ?? 'WooCommerce chưa active',
        );
      }

      return OrderDetailResult(status: OrderDetailStatus.ok, data: decoded);
    } on TimeoutException {
      return const OrderDetailResult(
        status: OrderDetailStatus.networkError,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const OrderDetailResult(
        status: OrderDetailStatus.networkError,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  /// Kiểm tra thông tin đăng nhập bằng cách gọi endpoint đơn hàng (read-only).
  ///
  /// Dùng `per_page=1` để không tải dữ liệu thừa và không thay đổi dữ liệu nào.
  /// Trả về [LoginStatus] để màn hình đăng nhập hiển thị thông báo tương ứng.
  Future<LoginStatus> verifyLogin({
    required String username,
    required String appPassword,
  }) async {
    final uri = _apiUri(
      AppSettings.baseUrl,
      _ordersPath,
      query: const {'per_page': '1', 'page': '1'},
    );
    if (uri == null) {
      return const LoginStatus(failed: true, message: 'URL chưa hợp lệ');
    }

    final header = BasicAuthHeader.build(username, appPassword);
    if (header == null) {
      return const LoginStatus(
        failed: true,
        message: 'Vui lòng nhập tên đăng nhập và Application Password',
      );
    }

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: {'Accept': 'application/json', 'Authorization': header},
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        return const LoginStatus(
          failed: true,
          message: AuthErrorMessages.unauthorized,
        );
      }

      if (response.statusCode == 403) {
        return const LoginStatus(
          failed: true,
          message: AuthErrorMessages.forbidden,
        );
      }

      if (response.statusCode != 200) {
        return LoginStatus(
          failed: true,
          message: 'Không đăng nhập được (HTTP ${response.statusCode})',
        );
      }

      return const LoginStatus(failed: false);
    } on TimeoutException {
      return const LoginStatus(
        failed: true,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const LoginStatus(
        failed: true,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  /// Header cho request cần xác thực. Chỉ dùng cho endpoint đơn hàng.
  Map<String, String> _authHeaders() {
    final header = authSession?.authorizationHeader;
    if (header == null) {
      return _publicHeaders;
    }
    return <String, String>{..._publicHeaders, 'Authorization': header};
  }

  /// Gọi GET một endpoint danh sách read-only và chuẩn hoá lỗi.
  Future<CatalogResult> _fetchCatalog({
    required String path,
    Map<String, String>? query,
    bool requireAuth = false,
  }) async {
    final uri = _apiUri(AppSettings.baseUrl, path, query: query);
    if (uri == null) {
      return const CatalogResult(
        status: CatalogStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    if (requireAuth && !(authSession?.isSignedIn ?? false)) {
      return const CatalogResult(
        status: CatalogStatus.unauthorized,
        message: AuthErrorMessages.notSignedIn,
      );
    }

    final headers = requireAuth ? _authHeaders() : _publicHeaders;

    try {
      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(_timeout);

      if (requireAuth && response.statusCode == 401) {
        return const CatalogResult(
          status: CatalogStatus.unauthorized,
          message: AuthErrorMessages.unauthorized,
        );
      }

      if (requireAuth && response.statusCode == 403) {
        return const CatalogResult(
          status: CatalogStatus.forbidden,
          message: AuthErrorMessages.forbidden,
        );
      }

      if (response.statusCode != 200) {
        return CatalogResult(
          status: CatalogStatus.httpError,
          message: 'HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const CatalogResult(
          status: CatalogStatus.httpError,
          message: 'Phản hồi không hợp lệ',
        );
      }

      if (decoded['wc_active'] != true) {
        return CatalogResult(
          status: CatalogStatus.wcInactive,
          message: decoded['message']?.toString() ?? 'WooCommerce chưa active',
        );
      }

      final rawItems = decoded['data'];
      if (rawItems is! List) {
        return const CatalogResult(
          status: CatalogStatus.httpError,
          message: 'Thiếu danh sách dữ liệu',
        );
      }

      return CatalogResult(
        status: CatalogStatus.ok,
        items: rawItems.whereType<Map<String, dynamic>>().toList(),
      );
    } on TimeoutException {
      return const CatalogResult(
        status: CatalogStatus.networkError,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const CatalogResult(
        status: CatalogStatus.networkError,
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
    final query = <String, String>{'per_page': '$perPage', 'page': '$page'};
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
