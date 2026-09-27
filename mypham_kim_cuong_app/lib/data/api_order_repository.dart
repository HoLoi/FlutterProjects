import '../models/order.dart';
import '../services/api_client.dart';

class ApiOrderException implements Exception {
  const ApiOrderException(this.message, {this.wcInactive = false});

  final String message;
  final bool wcInactive;

  @override
  String toString() => message;
}

class ApiOrderRepository {
  ApiOrderRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Danh sách đơn hàng WooCommerce (read-only).
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
      );
    }
    return result.items.map(ApiOrderParser.fromJson).toList();
  }

  /// Chi tiết một đơn hàng (read-only).
  Future<Order> fetchDetail(int orderId) async {
    final result = await _apiClient.fetchOrderDetail(orderId);
    if (!result.succeeded) {
      throw ApiOrderException(
        result.message ?? 'Không đọc được chi tiết đơn hàng',
        wcInactive: result.status == OrderDetailStatus.wcInactive,
      );
    }
    return ApiOrderParser.fromJson(result.data ?? const <String, dynamic>{});
  }
}

class MockOrderRepository {
  const MockOrderRepository();

  List<Order> getOrders() {
    return <Order>[
      const Order(
        id: 501,
        number: '501',
        status: OrderStatus.processing,
        statusLabel: 'Đang xử lý',
        createdAt: '2026-09-20 14:30:00',
        customerName: 'Nguyễn Thị A',
        customerPhone: '0900000000',
        itemsCount: 2,
        total: 398000,
        paymentMethod: 'cod',
        paymentMethodLabel: 'COD',
      ),
    ];
  }
}
