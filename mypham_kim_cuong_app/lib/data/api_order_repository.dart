import '../models/order.dart';
import '../services/api_client.dart';
import '../services/auth_session.dart';

class ApiOrderException implements Exception {
  const ApiOrderException(
    this.message, {
    this.wcInactive = false,
    this.unauthorized = false,
    this.forbidden = false,
  });

  final String message;
  final bool wcInactive;
  final bool unauthorized;
  final bool forbidden;

  @override
  String toString() => message;
}

class ApiOrderRepository {
  ApiOrderRepository({ApiClient? apiClient, AuthSession? authSession})
    : _apiClient = apiClient ?? ApiClient(authSession: authSession);

  final ApiClient _apiClient;

  /// Danh sách đơn hàng WooCommerce (read-only, cần đăng nhập).
  Future<List<Order>> fetchAll({
    String? search,
    String? status,
    int perPage = 20,
    int page = 1,
  }) async {
    final result = await _apiClient.fetchOrders(
      search: search,
      status: status,
      perPage: perPage,
      page: page,
    );
    if (!result.succeeded) {
      throw ApiOrderException(
        result.message ?? 'Không đọc được đơn hàng',
        wcInactive: result.status == CatalogStatus.wcInactive,
        unauthorized: result.status == CatalogStatus.unauthorized,
        forbidden: result.status == CatalogStatus.forbidden,
      );
    }
    return result.items.map(ApiOrderParser.fromJson).toList();
  }

  /// Chi tiết một đơn hàng (read-only, cần đăng nhập).
  Future<Order> fetchDetail(int orderId) async {
    final result = await _apiClient.fetchOrderDetail(orderId);
    if (!result.succeeded) {
      throw ApiOrderException(
        result.message ?? 'Không đọc được chi tiết đơn hàng',
        wcInactive: result.status == OrderDetailStatus.wcInactive,
        unauthorized: result.status == OrderDetailStatus.unauthorized,
        forbidden: result.status == OrderDetailStatus.forbidden,
      );
    }
    return ApiOrderParser.fromJson(result.data ?? const <String, dynamic>{});
  }
}
