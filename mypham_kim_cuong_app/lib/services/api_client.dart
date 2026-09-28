import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_value.dart';
import '../models/app_settings.dart';
import '../models/pos_sale.dart';
import 'auth_session.dart';

/// Thông điệp chuẩn khi server từ chối truy cập endpoint đơn hàng.
class AuthErrorMessages {
  const AuthErrorMessages._();

  static const String unauthorized =
      'Thông tin đăng nhập không hợp lệ hoặc đã hết hạn';
  static const String forbidden = 'Tài khoản không có quyền xem đơn hàng';
  static const String notSignedIn = 'Bạn cần đăng nhập để xem đơn hàng';
}

/// Trạng thái của `POST /wp-json/kc/v1/pos/sales`.
///
/// Tách riêng từng nhóm lỗi vì POS cần hành động khác nhau: [unauthorized] thì
/// mở màn hình đăng nhập, [outOfStock] thì báo người bán, còn [networkError] và
/// [saleInProgress] thì **gửi lại cùng `request_id`** để server idempotency
/// trả về đúng đơn đó.
enum PosSaleStatus {
  /// HTTP 201: vừa tạo đơn mới.
  created,

  /// HTTP 200: server trả lại đơn đã tạo từ request trước (`replayed: true`).
  ok,

  /// Chưa đăng nhập, chặn trước khi gọi mạng.
  notSignedIn,

  /// HTTP 401.
  unauthorized,

  /// HTTP 403, gồm cả khi gọi bằng `http` thay vì `https`.
  forbidden,

  /// HTTP 400: giỏ hàng không hợp lệ theo server.
  invalidRequest,

  /// HTTP 409 `kc_out_of_stock`.
  outOfStock,

  /// HTTP 409 `kc_sale_in_progress`: đơn cùng `request_id` đang được tạo.
  saleInProgress,

  /// HTTP 5xx, gồm cả 503 khi WooCommerce chưa active.
  serverError,

  /// Lỗi HTTP khác, hoặc body không đúng contract.
  httpError,

  /// Timeout hoặc không kết nối được máy chủ.
  networkError,

  /// Chưa cấu hình base URL.
  invalidUrl,

  /// Base URL dùng `http`; không gửi Basic Authorization qua kênh không mã hoá.
  insecureUrl,
}

/// Kết quả thô của `POST /pos/sales` trước khi parse thành [PosSaleResult].
class PosSaleResponse {
  const PosSaleResponse({required this.status, this.data, this.message, this.code});

  final PosSaleStatus status;

  /// Envelope thành công nguyên bản; `null` khi có lỗi.
  final Map<String, dynamic>? data;

  /// Thông báo tiếng Việt từ server, hoặc thông báo mặc định của client.
  final String? message;

  /// Mã lỗi của WordPress, ví dụ `kc_out_of_stock`.
  final String? code;

  bool get succeeded =>
      status == PosSaleStatus.created || status == PosSaleStatus.ok;

  /// Có nên cho người bán bấm "Gửi lại" cùng `request_id` hay không.
  ///
  /// Chỉ khi server **chưa chắc** đã tạo đơn. Lỗi 400/409 tồn kho thì chắc chắn
  /// chưa tạo, gửi lại vô ích; còn lỗi mạng và 500 thì có thể đơn đã tạo xong
  /// mà app chưa nhận được phản hồi, nên phải gửi lại đúng khoá cũ.
  bool get canRetryWithSameRequestId =>
      status == PosSaleStatus.networkError ||
      status == PosSaleStatus.serverError ||
      status == PosSaleStatus.saleInProgress;
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

enum ProductDetailStatus {
  ok,
  notFound,
  wcInactive,
  httpError,
  networkError,
  invalidUrl,
}

/// Kết quả `GET /products/{id}`: trả thẳng object sản phẩm, không có envelope.
class ProductDetailResult {
  const ProductDetailResult({required this.status, this.data, this.message});

  final ProductDetailStatus status;
  final Map<String, dynamic>? data;
  final String? message;

  bool get succeeded => status == ProductDetailStatus.ok;
}

/// Thông điệp lỗi do server trả về trong JSON lỗi của WordPress.
///
/// Mọi lỗi của API có cùng cấu trúc:
/// `{ "code": "kc_not_found", "message": "...", "data": { "status": 404 } }`
/// Ngoại lệ đã kiểm tra trên production: khoảng ngày ngược trả
/// `kc_invalid_date_range`; mọi lỗi tham số cấp khác trả `rest_invalid_param`.
/// App bắt lỗi theo HTTP status nên không cần phân nhánh theo `code`.
class ApiErrorBody {
  const ApiErrorBody({this.code, this.message, this.status});

  final String? code;
  final String? message;
  final int? status;
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
  static const String _posSalesPath = '/wp-json/kc/v1/pos/sales';

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

  /// Danh sách biến thể (read-only).
  ///
  /// Bỏ trống [productId] để lấy biến thể của **mọi** sản phẩm đang publish.
  /// Khi có [productId] trỏ tới sản phẩm cha chưa publish, API trả `404`.
  Future<CatalogResult> fetchVariations({
    int? productId,
    String? search,
    int perPage = 50,
    int page = 1,
  }) async {
    final query = <String, String>{'per_page': '$perPage', 'page': '$page'};
    if (productId != null && productId > 0) {
      query['product_id'] = '$productId';
    }
    final sortedSearch = (search?.trim().isEmpty ?? true)
        ? null
        : search!.trim();
    if (sortedSearch != null) {
      query['search'] = sortedSearch;
    }
    return _fetchCatalog(path: _variationsPath, query: query);
  }

  /// Chi tiết một sản phẩm (read-only, public).
  Future<ProductDetailResult> fetchProductDetail(int productId) async {
    final uri = _apiUri(AppSettings.baseUrl, '$_productsPath/$productId');
    if (uri == null) {
      return const ProductDetailResult(
        status: ProductDetailStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    try {
      final response = await _httpClient
          .get(uri, headers: _publicHeaders)
          .timeout(_timeout);

      if (response.statusCode == 404) {
        return const ProductDetailResult(
          status: ProductDetailStatus.notFound,
          message: 'Không tìm thấy sản phẩm',
        );
      }

      if (response.statusCode != 200) {
        return ProductDetailResult(
          status: ProductDetailStatus.httpError,
          message: _errorMessage(response, 'HTTP ${response.statusCode}'),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ProductDetailResult(
          status: ProductDetailStatus.httpError,
          message: 'Phản hồi không hợp lệ',
        );
      }

      if (decoded['wc_active'] != true) {
        return ProductDetailResult(
          status: ProductDetailStatus.wcInactive,
          message: decoded['message']?.toString() ?? 'WooCommerce chưa active',
        );
      }

      return ProductDetailResult(
        status: ProductDetailStatus.ok,
        data: decoded,
      );
    } on TimeoutException {
      return const ProductDetailResult(
        status: ProductDetailStatus.networkError,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const ProductDetailResult(
        status: ProductDetailStatus.networkError,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  /// Danh sách đơn hàng WooCommerce (read-only, cần đăng nhập).
  ///
  /// [dateFrom] / [dateTo] theo định dạng `YYYY-MM-DD`. Khoảng ngày ngược sẽ bị
  /// API từ chối bằng HTTP `400` với mã `kc_invalid_date_range`.
  Future<CatalogResult> fetchOrders({
    String? search,
    String? status,
    String? dateFrom,
    String? dateTo,
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
    if (dateFrom != null && dateFrom.trim().isNotEmpty) {
      query['date_from'] = dateFrom.trim();
    }
    if (dateTo != null && dateTo.trim().isNotEmpty) {
      query['date_to'] = dateTo.trim();
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
          message: _errorMessage(response, 'HTTP ${response.statusCode}'),
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

  /// `POST /wp-json/kc/v1/pos/sales` — bán hàng tại cửa hàng.
  ///
  /// Đây là endpoint ghi đầu tiên của app nên có thêm ba lớp chặn trước khi gọi
  /// mạng: chưa đăng nhập thì không gửi, base URL không phải `https` thì không
  /// gửi (tránh rò Basic Authorization qua kênh không mã hoá), và
  /// `items` rỗng thì không gửi.
  ///
  /// [requestId] là khoá idempotency do app sinh ra. Gửi lại **cùng** [requestId]
  /// sẽ không tạo đơn thứ hai: server trả HTTP 200 kèm `replayed: true`.
  ///
  /// Không gửi giá: body chỉ có `product_id`, `variation_id`, `quantity`.
  Future<PosSaleResponse> createPosSale({
    required String requestId,
    required String paymentMethod,
    required int customerId,
    required List<PosSaleItemRequest> items,
    String customerNote = '',
  }) async {
    final uri = _apiUri(AppSettings.baseUrl, _posSalesPath);

    if (uri == null) {
      return const PosSaleResponse(
        status: PosSaleStatus.invalidUrl,
        message: 'URL chưa hợp lệ',
      );
    }

    if (uri.scheme != 'https') {
      return const PosSaleResponse(
        status: PosSaleStatus.insecureUrl,
        message:
            'Chỉ thanh toán qua kết nối HTTPS. Đổi địa chỉ website sang https '
            'trong Cài đặt rồi thử lại.',
      );
    }

    if (!(authSession?.isSignedIn ?? false)) {
      return const PosSaleResponse(
        status: PosSaleStatus.notSignedIn,
        message: 'Bạn cần đăng nhập để thanh toán',
      );
    }

    if (items.isEmpty) {
      return const PosSaleResponse(
        status: PosSaleStatus.invalidRequest,
        message: 'Giỏ hàng đang trống',
      );
    }

    final body = jsonEncode({
      'request_id': requestId,
      'payment_method': paymentMethod,
      'customer_id': customerId,
      'customer_note': customerNote,
      'items': items.map((item) => item.toJson()).toList(),
    });

    final headers = <String, String>{
      ..._authHeaders(),
      'Content-Type': 'application/json',
    };

    try {
      final response = await _httpClient
          .post(uri, headers: headers, body: body)
          .timeout(_timeout);

      return _parsePosSaleResponse(response);
    } on TimeoutException {
      return const PosSaleResponse(
        status: PosSaleStatus.networkError,
        message: 'Hết thời gian chờ phản hồi',
      );
    } catch (_) {
      return const PosSaleResponse(
        status: PosSaleStatus.networkError,
        message: 'Không kết nối được máy chủ',
      );
    }
  }

  /// Chuyển HTTP response thành [PosSaleResponse].
  ///
  /// Cố ý bắt lỗi theo **HTTP status** thay vì theo `code` của WordPress, giống
  /// các endpoint GET: `code` có thể đổi, còn status thì ổn định.
  PosSaleResponse _parsePosSaleResponse(http.Response response) {
    final statusCode = response.statusCode;

    if (statusCode == 200 || statusCode == 201) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          return const PosSaleResponse(
            status: PosSaleStatus.httpError,
            message: 'Phản hồi không hợp lệ',
          );
        }
        if (decoded['success'] != true || ApiValue.object(decoded['order']) == null) {
          return const PosSaleResponse(
            status: PosSaleStatus.httpError,
            message: 'Phản hồi không hợp lệ',
          );
        }
        return PosSaleResponse(
          status: statusCode == 201
              ? PosSaleStatus.created
              : PosSaleStatus.ok,
          data: decoded,
        );
      } catch (_) {
        return const PosSaleResponse(
          status: PosSaleStatus.httpError,
          message: 'Phản hồi không hợp lệ',
        );
      }
    }

    final error = parseErrorBody(response.body);
    final message = _errorMessage(response, 'HTTP $statusCode');

    if (statusCode == 401) {
      return PosSaleResponse(
        status: PosSaleStatus.unauthorized,
        message: AuthErrorMessages.unauthorized,
        code: error.code,
      );
    }

    if (statusCode == 403) {
      return PosSaleResponse(
        status: PosSaleStatus.forbidden,
        message: message,
        code: error.code,
      );
    }

    if (statusCode == 400) {
      return PosSaleResponse(
        status: PosSaleStatus.invalidRequest,
        message: message,
        code: error.code,
      );
    }

    if (statusCode == 409) {
      return PosSaleResponse(
        status: error.code == 'kc_sale_in_progress'
            ? PosSaleStatus.saleInProgress
            : PosSaleStatus.outOfStock,
        message: message,
        code: error.code,
      );
    }

    if (statusCode >= 500) {
      return PosSaleResponse(
        status: PosSaleStatus.serverError,
        message: message,
        code: error.code,
      );
    }

    return PosSaleResponse(
      status: PosSaleStatus.httpError,
      message: message,
      code: error.code,
    );
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
          message: _errorMessage(response, 'HTTP ${response.statusCode}'),
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

  /// Đọc `message` tiếng Việt trong JSON lỗi của WordPress, fallback về [fallback].
  ///
  /// Body lỗi có dạng `{ "code": ..., "message": ..., "data": { "status": ... } }`.
  /// Body rỗng hoặc không phải JSON vẫn phải trả về [fallback] thay vì ném lỗi.
  String _errorMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Body không phải JSON: dùng fallback.
    }
    return fallback;
  }

  /// Đọc toàn bộ JSON lỗi (code + message + status) của WordPress.
  static ApiErrorBody parseErrorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final data = decoded['data'];
        return ApiErrorBody(
          code: decoded['code']?.toString(),
          message: decoded['message']?.toString(),
          status: data is Map ? _asInt(data['status']) : null,
        );
      }
    } catch (_) {
      // Không phải JSON: trả về body rỗng.
    }
    return const ApiErrorBody();
  }

  static int? _asInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
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
