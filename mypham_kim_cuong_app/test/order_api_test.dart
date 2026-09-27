import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_order_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/order.dart';
import 'package:mypham_kim_cuong_app/models/product_category.dart';
import 'package:mypham_kim_cuong_app/models/product_variation.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  group('ApiOrderParser', () {
    test('parse đầy đủ các trường của order', () {
      final order = ApiOrderParser.fromJson({
        'id': 501,
        'number': '501',
        'status': 'processing',
        'status_label': 'Đang xử lý',
        'created_at': '2026-09-20 14:30:00',
        'customer_name': 'Nguyễn Thị A',
        'customer_phone': '0900000000',
        'items_count': 2,
        'total': 398000,
        'payment_method': 'cod',
        'payment_method_label': 'COD',
      });

      expect(order.id, 501);
      expect(order.number, '501');
      expect(order.status, OrderStatus.processing);
      expect(order.statusText, 'Đang xử lý');
      expect(order.createdAt, '2026-09-20 14:30:00');
      expect(order.customerLabel, 'Nguyễn Thị A');
      expect(order.customerPhone, '0900000000');
      expect(order.itemsCount, 2);
      expect(order.total, 398000);
      expect(order.paymentMethodLabel, 'COD');
    });

    test('mọi status của WooCommerce đều map đúng', () {
      const mapping = {
        'pending': OrderStatus.pending,
        'processing': OrderStatus.processing,
        'on-hold': OrderStatus.onHold,
        'completed': OrderStatus.completed,
        'cancelled': OrderStatus.cancelled,
        'refunded': OrderStatus.refunded,
        'failed': OrderStatus.failed,
      };

      mapping.forEach((raw, expected) {
        final order = ApiOrderParser.fromJson({
          'id': 1,
          'number': '1',
          'status': raw,
          'total': 0,
        });
        expect(order.status, expected, reason: 'status "$raw"');
      });
    });

    test('status lạ hoặc thiếu thì về unknown và dùng nhãn tiếng Việt', () {
      final order = ApiOrderParser.fromJson({
        'id': 2,
        'number': '2',
        'total': 0,
      });

      expect(order.status, OrderStatus.unknown);
      expect(order.statusText, 'Không rõ');
    });

    test('thiếu tên khách thì dùng nhãn khách lẻ', () {
      final order = ApiOrderParser.fromJson({
        'id': 3,
        'number': '3',
        'status': 'pending',
        'total': 1000,
      });

      expect(order.customerName, '');
      expect(order.customerLabel, 'Khách lẻ (chưa có tên)');
    });

    test('status_label thiếu thì fallback sang label của enum', () {
      final order = ApiOrderParser.fromJson({
        'id': 4,
        'number': '4',
        'status': 'completed',
        'total': 1000,
      });

      expect(order.statusText, 'Hoàn tất');
    });

    test('parse items của chi tiết đơn hàng', () {
      final order = ApiOrderParser.fromJson({
        'id': 5,
        'number': '5',
        'status': 'completed',
        'total': 398000,
        'subtotal': 400000,
        'discount_total': 2000,
        'shipping_total': 0,
        'notes': 'Giao sau 18h',
        'items': [
          {
            'id': 11,
            'product_id': 101,
            'variation_id': 1001,
            'name': 'Son Kem Lì Satin',
            'sku': 'KC-0001-RED',
            'quantity': 2,
            'price': 190000,
            'subtotal': 380000,
          },
        ],
      });

      expect(order.subtotal, 400000);
      expect(order.discountTotal, 2000);
      expect(order.notes, 'Giao sau 18h');
      expect(order.items.length, 1);

      final item = order.items.single;
      expect(item.id, 11);
      expect(item.name, 'Son Kem Lì Satin');
      expect(item.sku, 'KC-0001-RED');
      expect(item.quantity, 2);
      expect(item.subtotal, 380000);
    });

    test('items thiếu hoặc sai kiểu thì trả danh sách rỗng', () {
      final order = ApiOrderParser.fromJson({
        'id': 6,
        'number': '6',
        'total': 0,
        'items': 'không phải danh sách',
      });

      expect(order.items, isEmpty);
    });

    test('item thiếu tên thì dùng nhãn dự phòng', () {
      final order = ApiOrderParser.fromJson({
        'id': 7,
        'number': '7',
        'total': 0,
        'items': [
          {'id': 1, 'quantity': 1},
        ],
      });

      expect(order.items.single.name, 'Sản phẩm chưa có tên');
      expect(order.items.single.sku, '');
    });
  });

  group('ApiClient.fetchOrders', () {
    test('gọi đúng path và trả về danh sách', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/orders');
          expect(request.url.queryParameters['per_page'], '20');
          expect(request.url.queryParameters['page'], '1');
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'data': [
              {'id': 501, 'number': '501', 'status': 'pending', 'total': 1000},
            ],
          });
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.ok);
      expect(result.items.length, 1);
    });

    test('truyền search và status khi có', () async {
      String? searchParam;
      String? statusParam;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          searchParam = request.url.queryParameters['search'];
          statusParam = request.url.queryParameters['status'];
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      await client.fetchOrders(search: '  An  ', status: 'processing');

      expect(searchParam, 'An');
      expect(statusParam, 'processing');
    });

    test('search rỗng thì không gửi tham số', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('search'), isFalse);
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      await client.fetchOrders(search: '   ');

      expect(client, isNotNull);
    });

    test('WooCommerce chưa active thì trả wcInactive', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async {
          return _jsonResponse({
            'wc_active': false,
            'count': 0,
            'data': [],
            'message': 'WooCommerce chưa active, không đọc được dữ liệu.',
          });
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.wcInactive);
      expect(result.succeeded, isFalse);
      expect(result.message, contains('chưa active'));
    });

    test('HTTP 500 trả httpError', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.httpError);
      expect(result.message, 'HTTP 500');
    });

    test('lỗi mạng trả networkError', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.networkError);
      expect(result.message, 'Không kết nối được máy chủ');
    });

    test('base URL rỗng trả invalidUrl', () async {
      AppSettings.baseUrl = '';
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.invalidUrl);
    });
  });

  group('ApiClient.fetchOrderDetail', () {
    test('gọi đúng path có id và parse dữ liệu', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/orders/501');
          return _jsonResponse({
            'wc_active': true,
            'id': 501,
            'number': '501',
            'status': 'completed',
            'total': 398000,
            'items': [
              {'id': 1, 'name': 'Son', 'quantity': 1, 'subtotal': 398000},
            ],
          });
        }),
      );

      final result = await client.fetchOrderDetail(501);

      expect(result.status, OrderDetailStatus.ok);
      expect(result.data?['number'], '501');
    });

    test('HTTP 404 trả notFound', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      );

      final result = await client.fetchOrderDetail(999);

      expect(result.status, OrderDetailStatus.notFound);
      expect(result.message, 'Không tìm thấy đơn hàng');
    });

    test('HTTP 500 trả httpError', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrderDetail(501);

      expect(result.status, OrderDetailStatus.httpError);
      expect(result.message, 'HTTP 500');
    });

    test('base URL rỗng trả invalidUrl', () async {
      AppSettings.baseUrl = '';
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrderDetail(501);

      expect(result.status, OrderDetailStatus.invalidUrl);
    });
  });

  group('ApiClient.fetchCategories', () {
    test('gọi đúng path và parse danh mục', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/categories');
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'data': [
              {'id': 1, 'name': 'Son', 'slug': 'son', 'parent': 0, 'count': 5},
            ],
          });
        }),
      );

      final result = await client.fetchCategories();

      expect(result.status, CatalogStatus.ok);
      final category = ApiCategoryParser.fromJson(result.items.single);
      expect(category.id, 1);
      expect(category.name, 'Son');
      expect(category.count, 5);
    });

    test('danh mục thiếu tên thì dùng nhãn dự phòng', () {
      final category = ApiCategoryParser.fromJson({'id': 2});

      expect(category.name, 'Danh mục chưa có tên');
      expect(category.count, 0);
    });
  });

  group('ApiClient.fetchVariations', () {
    test('gọi đúng path kèm product_id', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/variations');
          expect(request.url.queryParameters['product_id'], '101');
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'data': [
              {
                'id': 1001,
                'product_id': 101,
                'name': 'Son Kem Lì Satin - Đỏ',
                'sku': 'KC-0001-RED',
                'barcode': '893000000001',
                'price': 189000,
                'stock_quantity': 5,
                'attributes': [
                  {'name': 'Màu', 'option': 'Đỏ'},
                ],
              },
            ],
          });
        }),
      );

      final result = await client.fetchVariations(productId: 101);

      expect(result.status, CatalogStatus.ok);
      final variation = ApiVariationParser.fromJson(result.items.single);
      expect(variation.id, 1001);
      expect(variation.productId, 101);
      expect(variation.sku, 'KC-0001-RED');
      expect(variation.price, 189000);
      expect(variation.stockQuantity, 5);
      expect(variation.attributeText, 'Màu: Đỏ');
    });

    test('biến thể không quản lý tồn kho giữ null', () {
      final variation = ApiVariationParser.fromJson({
        'id': 1002,
        'product_id': 102,
        'name': 'Kem Chống Nắng',
        'price': 210000,
        'stock_quantity': null,
        'attributes': [],
      });

      expect(variation.stockQuantity, isNull);
      expect(variation.attributeText, '');
    });
  });

  group('ApiOrderRepository', () {
    test('fetchAll trả về danh sách Order đã parse', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            return _jsonResponse({
              'wc_active': true,
              'count': 1,
              'data': [
                {
                  'id': 501,
                  'number': '501',
                  'status': 'completed',
                  'status_label': 'Hoàn tất',
                  'customer_name': 'Trần Thị B',
                  'items_count': 3,
                  'total': 512000,
                  'payment_method_label': 'COD',
                },
              ],
            });
          }),
        ),
      );

      final orders = await repository.fetchAll();

      expect(orders.single.id, 501);
      expect(orders.single.status, OrderStatus.completed);
      expect(orders.single.total, 512000);
      expect(orders.single.customerLabel, 'Trần Thị B');
    });

    test('fetchDetail trả về Order đã parse', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            return _jsonResponse({
              'wc_active': true,
              'id': 501,
              'number': '501',
              'status': 'processing',
              'total': 398000,
              'items': [
                {'id': 1, 'name': 'Son', 'quantity': 2, 'subtotal': 380000},
              ],
            });
          }),
        ),
      );

      final order = await repository.fetchDetail(501);

      expect(order.number, '501');
      expect(order.status, OrderStatus.processing);
      expect(order.items.single.quantity, 2);
    });

    test('ném ApiOrderException khi WooCommerce chưa active', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            return _jsonResponse({
              'wc_active': false,
              'count': 0,
              'data': [],
              'message': 'WooCommerce chưa active, không đọc được dữ liệu.',
            });
          }),
        ),
      );

      expect(
        () => repository.fetchAll(),
        throwsA(
          isA<ApiOrderException>()
              .having((e) => e.wcInactive, 'wcInactive', isTrue)
              .having((e) => e.message, 'message', contains('chưa active')),
        ),
      );
    });

    test('ném ApiOrderException khi lỗi mạng', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            throw http.ClientException('Connection refused');
          }),
        ),
      );

      expect(
        () => repository.fetchAll(),
        throwsA(
          isA<ApiOrderException>()
              .having((e) => e.wcInactive, 'wcInactive', isFalse)
              .having((e) => e.message, 'message', contains('Không kết nối')),
        ),
      );
    });
  });

  group('MockOrderRepository', () {
    test('trả về đơn hàng mẫu để dùng khi chưa bật API', () {
      final orders = const MockOrderRepository().getOrders();

      expect(orders.length, 1);
      expect(orders.single.status, OrderStatus.processing);
    });
  });
}
