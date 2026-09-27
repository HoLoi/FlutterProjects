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
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

/// Session đã đăng nhập, chỉ tồn tại trong test. Không dùng thông tin thật.
AuthSession _signedInSession() {
  final session = AuthSession();
  session.signIn(username: 'demo', appPassword: 'abcd efgh ijkl');
  return session;
}

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// JSON lỗi đúng cấu trúc WordPress trả về.
Map<String, Object> _errorBody(String code, String message, int status) {
  return {'code': code, 'message': message, 'data': {'status': status}};
}

/// Một phần tử của `GET /orders` — bám sát JSON đã kiểm tra trên production.
Map<String, Object?> _orderListItem() {
  return {
    'id': 456,
    'number': '456',
    'status': 'processing',
    'status_label': 'Đang xử lý',
    'date_created': '2026-09-20 14:30:00',
    'date_paid': null,
    'payment_method': 'cod',
    'payment_method_label': 'COD',
    'payment_status': 'unpaid',
    'currency': 'VND',
    'total': 398000,
    'customer': {
      'id': 0,
      'is_guest': true,
      'name': 'Nguyễn Thị A',
      'phone': '0900000000',
      'email': 'a@example.com',
    },
    'billing': {
      'first_name': 'Nguyễn Thị',
      'last_name': 'A',
      'address_1': '123 Nguyễn Huệ',
      'address_2': '',
      'city': 'TP. Hồ Chí Minh',
      'state': '',
      'postcode': '700000',
      'country': 'VN',
      'phone': '0900000000',
      'email': 'a@example.com',
    },
    // shipping.email luôn null vì WooCommerce chỉ lưu email ở billing.
    'shipping': {
      'first_name': 'Nguyễn Thị',
      'last_name': 'A',
      'address_1': '123 Nguyễn Huệ',
      'address_2': '',
      'city': 'TP. Hồ Chí Minh',
      'state': '',
      'postcode': '700000',
      'country': 'VN',
      'phone': '0900000000',
      'email': null,
    },
    'line_items': [
      {
        'id': 789,
        'product_id': 123,
        'variation_id': 124,
        'name': 'Son Kem Lì Satin Đỏ',
        'sku': 'KC-0001-RED',
        'quantity': 2,
        'price': 190000,
        'subtotal': 380000,
        'total': 380000,
      },
    ],
  };
}

/// `GET /orders/{id}`: giống hệt phần tử của danh sách, cộng 8 trường chi tiết.
Map<String, Object?> _orderDetail() {
  return {
    ..._orderListItem(),
    'wc_active': true,
    'customer_note': 'Giao sau 18h',
    'subtotal': 380000,
    'discount_total': 0,
    'shipping_total': 18000,
    'fee_total': 0,
    'refunded_total': 0,
    'created_via': 'checkout',
  };
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  group('ApiOrderParser - JSON thật của GET /orders', () {
    test('parse đầy đủ trường của một đơn trong danh sách', () {
      final order = ApiOrderParser.fromJson(_orderListItem());

      expect(order.id, 456);
      expect(order.number, '456');
      expect(order.status, OrderStatus.processing);
      expect(order.statusText, 'Đang xử lý');
      expect(order.dateCreated, '2026-09-20 14:30:00');
      expect(order.datePaid, isNull);
      expect(order.paymentMethod, 'cod');
      expect(order.paymentMethodLabel, 'COD');
      expect(order.paymentStatus, PaymentStatus.unpaid);
      expect(order.currency, 'VND');
      expect(order.total, 398000);
    });

    test('parse customer dạng object, không phải trường phẳng', () {
      final order = ApiOrderParser.fromJson(_orderListItem());

      expect(order.customer.id, 0);
      expect(order.customer.isGuest, isTrue);
      expect(order.customer.name, 'Nguyễn Thị A');
      expect(order.customer.phone, '0900000000');
      expect(order.customer.email, 'a@example.com');
      // Nhãn hiển thị ghi rõ đây là đơn khách lẻ.
      expect(order.customerLabel, 'Nguyễn Thị A (khách lẻ)');
    });

    test('parse billing và shipping, bỏ qua trường rỗng', () {
      final order = ApiOrderParser.fromJson(_orderListItem());

      expect(order.billing.fullName, 'Nguyễn Thị A');
      expect(order.billing.city, 'TP. Hồ Chí Minh');
      expect(order.billing.country, 'VN');
      // address_2 và state là chuỗi rỗng nên bị loại khỏi dòng địa chỉ.
      expect(order.billing.addressLabel, '123 Nguyễn Huệ, TP. Hồ Chí Minh, VN');
      // shipping.email luôn null trong WooCommerce.
      expect(order.shipping.email, isNull);
      expect(order.shipping.isEmpty, isFalse);
    });

    test('parse line_items kèm variation_id', () {
      final order = ApiOrderParser.fromJson(_orderListItem());

      expect(order.items.length, 1);
      // API không có items_count nên phải tính từ line_items.
      expect(order.itemsCount, 1);
      expect(order.totalQuantity, 2);

      final item = order.items.single;
      expect(item.id, 789);
      expect(item.name, 'Son Kem Lì Satin Đỏ');
      expect(item.productId, 123);
      expect(item.variationId, 124);
      expect(item.hasVariation, isTrue);
      expect(item.sku, 'KC-0001-RED');
      expect(item.quantity, 2);
      expect(item.price, 190000);
      expect(item.total, 380000);
    });

    test('variation_id = 0 nghĩa là sản phẩm đơn', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'line_items': [
          {
            'id': 1,
            'product_id': 9,
            'variation_id': 0,
            'name': 'Kem Chống Nắng',
            'sku': 'KC-0003',
            'quantity': 1,
            'price': 210000,
            'subtotal': 210000,
            'total': 210000,
          },
        ],
      });

      expect(order.items.single.hasVariation, isFalse);
      expect(order.items.single.variationId, 0);
    });

    test('đơn của tài khoản đăng ký không phải khách lẻ', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'customer': {
          'id': 42,
          'is_guest': false,
          'name': 'Trần Thị B',
          'phone': '0912345678',
          'email': 'b@example.com',
        },
      });

      expect(order.customer.isGuest, isFalse);
      expect(order.customer.id, 42);
      expect(order.customerLabel, 'Trần Thị B');
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
          ..._orderListItem(),
          'status': raw,
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

    test('status_label thiếu thì fallback sang label của enum', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'status': 'completed',
        'status_label': null,
      });

      expect(order.statusText, 'Hoàn tất');
    });

    test('slug gửi lên API đúng với từng trạng thái', () {
      expect(OrderStatus.onHold.wire, 'on-hold');
      expect(OrderStatus.processing.wire, 'processing');
      // unknown không có slug nên không được gửi lên `?status=`.
      expect(OrderStatus.unknown.wire, isEmpty);
    });
  });

  group('ApiOrderParser - trường chỉ có ở GET /orders/{id}', () {
    test('parse đủ 8 trường chi tiết', () {
      final order = ApiOrderParser.fromJson(_orderDetail());

      expect(order.customerNote, 'Giao sau 18h');
      expect(order.subtotal, 380000);
      expect(order.discountTotal, 0);
      expect(order.shippingTotal, 18000);
      expect(order.feeTotal, 0);
      expect(order.refundedTotal, 0);
      expect(order.createdVia, 'checkout');
      expect(order.hasDetailTotals, isTrue);
    });

    test('đọc danh sách thì các trường chi tiết là giá trị mặc định', () {
      final order = ApiOrderParser.fromJson(_orderListItem());

      expect(order.customerNote, isNull);
      expect(order.createdVia, isNull);
      expect(order.subtotal, 0);
      expect(order.hasDetailTotals, isFalse);
    });
  });

  group('ApiOrderParser - null fields', () {
    test('sku null và tên thiếu vẫn trả item hợp lệ', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'line_items': [
          {'id': 1, 'product_id': 9, 'variation_id': 0, 'quantity': 1},
        ],
      });

      final item = order.items.single;
      expect(item.name, isNull);
      expect(item.nameLabel, 'Sản phẩm chưa có tên');
      expect(item.sku, isNull);
      expect(item.price, 0);
      expect(item.total, 0);
    });

    test('customer thiếu toàn bộ thì dùng giá trị mặc định khách lẻ', () {
      final order = ApiOrderParser.fromJson({
        'id': 3,
        'number': '3',
        'status': 'pending',
        'total': 1000,
      });

      expect(order.customer.id, 0);
      expect(order.customer.isGuest, isTrue);
      expect(order.customer.name, isNull);
      expect(order.customer.phone, isNull);
      expect(order.customerLabel, 'Khách lẻ (chưa có tên)');
    });

    test('thiếu is_guest thì suy ra từ customer.id', () {
      final guest = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'customer': {'id': 0, 'name': 'Khách vãng lai'},
      });
      final member = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'customer': {'id': 7, 'name': 'Thành viên'},
      });

      expect(guest.customer.isGuest, isTrue);
      expect(member.customer.isGuest, isFalse);
    });

    test('date_paid null nghĩa là chưa thanh toán', () {
      final unpaid = ApiOrderParser.fromJson(_orderListItem());
      final paid = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'date_paid': '2026-09-20 15:00:00',
        'payment_status': 'paid',
      });

      expect(unpaid.datePaid, isNull);
      expect(unpaid.paymentStatus, PaymentStatus.unpaid);
      expect(paid.datePaid, '2026-09-20 15:00:00');
      expect(paid.paymentStatus, PaymentStatus.paid);
    });

    test('payment_status lạ thì về unknown', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'payment_status': 'on-hold',
      });

      expect(order.paymentStatus, PaymentStatus.unknown);
      expect(order.paymentStatus.label, 'Không rõ');
    });

    test('billing và shipping thiếu hoặc sai kiểu thì không lỗi', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'billing': 'không phải object',
        'shipping': null,
      });

      expect(order.billing.isEmpty, isTrue);
      expect(order.shipping.isEmpty, isTrue);
      expect(order.billing.fullName, isEmpty);
      expect(order.billing.addressLabel, isEmpty);
    });

    test('line_items thiếu hoặc sai kiểu thì trả danh sách rỗng', () {
      final missing = ApiOrderParser.fromJson({'id': 6, 'total': 0});
      final wrongType = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'line_items': 'không phải danh sách',
      });

      expect(missing.items, isEmpty);
      expect(missing.itemsCount, 0);
      expect(wrongType.items, isEmpty);
    });

    test('bỏ qua phần tử line_items không phải object', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'line_items': [
          'không phải object',
          {'id': 1, 'product_id': 2, 'variation_id': 0, 'quantity': 1},
        ],
      });

      expect(order.items.length, 1);
      expect(order.items.single.id, 1);
    });

    test('số dạng chuỗi vẫn parse được như WooCommerce hay trả về', () {
      final order = ApiOrderParser.fromJson({
        ..._orderListItem(),
        'total': '398000.00',
        'id': '456',
        'line_items': [
          {
            'id': '789',
            'product_id': '123',
            'variation_id': '124',
            'quantity': '2',
            'price': '190000.00',
            'subtotal': '380000.00',
            'total': '380000.00',
          },
        ],
      });

      expect(order.id, 456);
      expect(order.total, 398000);
      expect(order.items.single.id, 789);
      expect(order.items.single.variationId, 124);
      expect(order.items.single.quantity, 2);
      expect(order.items.single.price, 190000);
    });
  });

  group('ApiClient.fetchOrders', () {
    test('gọi đúng path và trả về danh sách', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/orders');
          expect(request.url.queryParameters['per_page'], '20');
          expect(request.url.queryParameters['page'], '1');
          // Endpoint đơn hàng phải gửi Authorization.
          expect(request.headers['Authorization'], startsWith('Basic '));
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'page': 1,
            'per_page': 20,
            'data': [_orderListItem()],
          });
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.ok);
      expect(result.items.length, 1);
    });

    test('truyền search, status và khoảng ngày khi có', () async {
      String? searchParam;
      String? statusParam;
      String? dateFromParam;
      String? dateToParam;
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          searchParam = request.url.queryParameters['search'];
          statusParam = request.url.queryParameters['status'];
          dateFromParam = request.url.queryParameters['date_from'];
          dateToParam = request.url.queryParameters['date_to'];
          return _jsonResponse({
            'wc_active': true,
            'count': 0,
            'data': [],
          });
        }),
      );

      await client.fetchOrders(
        search: '  An  ',
        status: 'processing',
        dateFrom: '2026-01-01',
        dateTo: '2026-12-31',
      );

      expect(searchParam, 'An');
      expect(statusParam, 'processing');
      expect(dateFromParam, '2026-01-01');
      expect(dateToParam, '2026-12-31');
    });

    test('tham số rỗng thì không gửi lên URL', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(query.containsKey('search'), isFalse);
          expect(query.containsKey('status'), isFalse);
          expect(query.containsKey('date_from'), isFalse);
          expect(query.containsKey('date_to'), isFalse);
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      await client.fetchOrders(search: '   ', status: '  ');

      expect(client, isNotNull);
    });

    test('chưa đăng nhập thì không gọi mạng, trả unauthorized', () async {
      var called = false;
      final client = ApiClient(
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      final result = await client.fetchOrders();

      expect(called, isFalse, reason: 'phải chặn trước khi gọi HTTP');
      expect(result.status, CatalogStatus.unauthorized);
      expect(result.message, AuthErrorMessages.notSignedIn);
    });

    test('HTTP 401 trả unauthorized kèm message của server', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async {
          return _jsonResponse(
            _errorBody(
              'kc_not_authenticated',
              'Cần đăng nhập để xem đơn hàng.',
              401,
            ),
            status: 401,
          );
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.unauthorized);
      expect(result.message, AuthErrorMessages.unauthorized);
    });

    test('HTTP 403 trả forbidden', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async {
          return _jsonResponse(
            _errorBody(
              'kc_cannot_view_orders',
              'Tài khoản không có quyền xem đơn hàng.',
              403,
            ),
            status: 403,
          );
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.forbidden);
      expect(result.message, AuthErrorMessages.forbidden);
    });

    test('khoảng ngày ngược trả 400 kc_invalid_date_range', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async {
          return _jsonResponse(
            _errorBody(
              'kc_invalid_date_range',
              'date_from phải nhỏ hơn hoặc bằng date_to.',
              400,
            ),
            status: 400,
          );
        }),
      );

      final result = await client.fetchOrders(
        dateFrom: '2026-12-31',
        dateTo: '2026-01-01',
      );

      expect(result.status, CatalogStatus.httpError);
      // Ngoại lệ đã kiểm tra production: code ở cấp ngoài là
      // kc_invalid_date_range, HTTP status vẫn là 400.
      expect(result.message, 'date_from phải nhỏ hơn hoặc bằng date_to.');
    });

    test('WooCommerce chưa active thì trả wcInactive', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
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

    test('HTTP 500 trả httpError và lấy message trong JSON lỗi', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async {
          return _jsonResponse(
            _errorBody('kc_internal', 'Lỗi máy chủ.', 500),
            status: 500,
          );
        }),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.httpError);
      expect(result.message, 'Lỗi máy chủ.');
    });

    test('HTTP 500 với body rỗng vẫn fallback về HTTP status', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.httpError);
      expect(result.message, 'HTTP 500');
    });

    test('lỗi mạng trả networkError', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
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
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.invalidUrl);
    });
  });

  group('ApiClient.fetchOrderDetail', () {
    test('gọi đúng path có id và parse dữ liệu', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/orders/456');
          expect(request.headers['Authorization'], startsWith('Basic '));
          return _jsonResponse(_orderDetail());
        }),
      );

      final result = await client.fetchOrderDetail(456);

      expect(result.status, OrderDetailStatus.ok);
      expect(result.data?['number'], '456');
      expect(result.data?['wc_active'], true);
    });

    test('HTTP 404 trả notFound', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async {
          return _jsonResponse(
            _errorBody('kc_not_found', 'Không tìm thấy đơn hàng.', 404),
            status: 404,
          );
        }),
      );

      final result = await client.fetchOrderDetail(99999999);

      expect(result.status, OrderDetailStatus.notFound);
      expect(result.message, 'Không tìm thấy đơn hàng');
    });

    test('chưa đăng nhập thì không gọi mạng', () async {
      var called = false;
      final client = ApiClient(
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse(_orderDetail());
        }),
      );

      final result = await client.fetchOrderDetail(456);

      expect(called, isFalse);
      expect(result.status, OrderDetailStatus.unauthorized);
    });

    test('HTTP 401 trả unauthorized', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      final result = await client.fetchOrderDetail(456);

      expect(result.status, OrderDetailStatus.unauthorized);
    });

    test('HTTP 403 trả forbidden', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 403)),
      );

      final result = await client.fetchOrderDetail(456);

      expect(result.status, OrderDetailStatus.forbidden);
    });

    test('HTTP 500 trả httpError', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrderDetail(456);

      expect(result.status, OrderDetailStatus.httpError);
      expect(result.message, 'HTTP 500');
    });

    test('base URL rỗng trả invalidUrl', () async {
      AppSettings.baseUrl = '';
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchOrderDetail(456);

      expect(result.status, OrderDetailStatus.invalidUrl);
    });
  });

  group('ApiClient.fetchCategories', () {
    test('gọi đúng path và parse danh mục', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/categories');
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'page': 1,
            'per_page': 50,
            'data': [
              {'id': 3, 'name': 'Son', 'slug': 'son', 'parent': 0, 'count': 12},
            ],
          });
        }),
      );

      final result = await client.fetchCategories();

      expect(result.status, CatalogStatus.ok);
      final category = ApiCategoryParser.fromJson(result.items.single);
      expect(category.id, 3);
      expect(category.name, 'Son');
      expect(category.slug, 'son');
      expect(category.parent, 0);
      expect(category.isTopLevel, isTrue);
      expect(category.count, 12);
    });

    test('danh mục thiếu tên thì dùng nhãn dự phòng', () {
      final category = ApiCategoryParser.fromJson({'id': 2});

      expect(category.name, 'Danh mục chưa có tên');
      expect(category.count, 0);
      expect(category.isTopLevel, isTrue);
    });

    test('danh mục con có parent khác 0', () {
      final category = ApiCategoryParser.fromJson({
        'id': 4,
        'name': 'Son đỏ',
        'parent': 3,
      });

      expect(category.parent, 3);
      expect(category.isTopLevel, isFalse);
    });
  });

  group('ApiClient.fetchVariations', () {
    test('gọi đúng path kèm product_id', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/variations');
          expect(request.url.queryParameters['product_id'], '123');
          return _jsonResponse({
            'wc_active': true,
            'count': 1,
            'page': 1,
            'per_page': 50,
            'data': [
              {
                'id': 124,
                'product_id': 123,
                'name': 'Son Kem Lì Satin Đỏ - Màu đỏ',
                'sku': 'KC-0001-RED',
                'barcode': null,
                'price': 190000,
                'regular_price': 220000,
                'sale_price': 190000,
                'stock_quantity': 5,
                'stock_status': 'instock',
                'image_url': 'https://example.com/son-do.jpg',
                'attributes': [
                  {'name': 'Màu sắc', 'option': 'Đỏ'},
                ],
              },
            ],
          });
        }),
      );

      final result = await client.fetchVariations(productId: 123);

      expect(result.status, CatalogStatus.ok);
      final variation = ApiVariationParser.fromJson(result.items.single);
      expect(variation.id, 124);
      expect(variation.productId, 123);
      expect(variation.sku, 'KC-0001-RED');
      // barcode null vì shop chưa nhập mã vạch.
      expect(variation.barcode, '');
      expect(variation.price, 190000);
      expect(variation.regularPrice, 220000);
      expect(variation.salePrice, 190000);
      expect(variation.stockQuantity, 5);
      expect(variation.stockStatus, 'instock');
      expect(variation.isOutOfStock, isFalse);
      expect(variation.attributeText, 'Màu sắc: Đỏ');
    });

    test('bỏ trống product_id thì không gửi tham số', () async {
      final client = ApiClient(
        authSession: _signedInSession(),
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('product_id'), isFalse);
          return _jsonResponse({
            'wc_active': true,
            'count': 0,
            'data': [],
          });
        }),
      );

      final result = await client.fetchVariations();

      expect(result.status, CatalogStatus.ok);
    });

    test('biến thể không quản lý tồn kho giữ null', () {
      final variation = ApiVariationParser.fromJson({
        'id': 1002,
        'product_id': 102,
        'name': 'Kem Chống Nắng',
        'price': 210000,
        'stock_quantity': null,
        'stock_status': 'outofstock',
        'attributes': [],
      });

      expect(variation.stockQuantity, isNull);
      expect(variation.attributeText, '');
      expect(variation.isOutOfStock, isTrue);
    });

    test('bỏ qua thuộc tính thiếu option', () {
      final variation = ApiVariationParser.fromJson({
        'id': 1,
        'product_id': 2,
        'attributes': [
          {'name': 'Màu sắc', 'option': ''},
          {'name': 'Dung tích', 'option': '30ml'},
        ],
      });

      expect(variation.attributes, ['Dung tích: 30ml']);
    });
  });

  group('ApiOrderRepository', () {
    test('fetchAll trả về danh sách Order đã parse', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          authSession: _signedInSession(),
          httpClient: MockClient((_) async {
            return _jsonResponse({
              'wc_active': true,
              'count': 1,
              'page': 1,
              'per_page': 20,
              'data': [
                {
                  ..._orderListItem(),
                  'status': 'completed',
                  'status_label': 'Hoàn tất',
                  'customer': {
                    'id': 42,
                    'is_guest': false,
                    'name': 'Trần Thị B',
                    'phone': '0912345678',
                    'email': 'b@example.com',
                  },
                  'line_items': [
                    {
                      'id': 1,
                      'product_id': 101,
                      'variation_id': 0,
                      'name': 'Son',
                      'sku': null,
                      'quantity': 3,
                      'price': 150000,
                      'subtotal': 450000,
                      'total': 450000,
                    },
                  ],
                },
              ],
            });
          }),
        ),
      );

      final orders = await repository.fetchAll();

      final order = orders.single;
      expect(order.id, 456);
      expect(order.status, OrderStatus.completed);
      expect(order.total, 398000);
      expect(order.customer.isGuest, isFalse);
      expect(order.customerLabel, 'Trần Thị B');
      expect(order.itemsCount, 1);
      expect(order.items.single.sku, isNull);
      expect(order.items.single.hasVariation, isFalse);
    });

    test('fetchDetail trả về Order đủ trường chi tiết', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          authSession: _signedInSession(),
          httpClient: MockClient((_) async => _jsonResponse(_orderDetail())),
        ),
      );

      final order = await repository.fetchDetail(456);

      expect(order.number, '456');
      expect(order.status, OrderStatus.processing);
      expect(order.customerNote, 'Giao sau 18h');
      expect(order.subtotal, 380000);
      expect(order.shippingTotal, 18000);
      expect(order.createdVia, 'checkout');
      expect(order.items.single.quantity, 2);
    });

    test('ném ApiOrderException khi đơn không tồn tại', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          authSession: _signedInSession(),
          httpClient: MockClient((_) async {
            return _jsonResponse(
              _errorBody('kc_not_found', 'Không tìm thấy đơn hàng.', 404),
              status: 404,
            );
          }),
        ),
      );

      expect(
        () => repository.fetchDetail(99999999),
        throwsA(
          isA<ApiOrderException>()
              .having((e) => e.notFound, 'notFound', isTrue)
              .having((e) => e.message, 'message', 'Không tìm thấy đơn hàng'),
        ),
      );
    });

    test('ném ApiOrderException khi thiếu quyền', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          authSession: _signedInSession(),
          httpClient: MockClient((_) async {
            return _jsonResponse(
              _errorBody(
                'kc_cannot_view_orders',
                'Tài khoản không có quyền xem đơn hàng.',
                403,
              ),
              status: 403,
            );
          }),
        ),
      );

      expect(
        () => repository.fetchAll(),
        throwsA(
          isA<ApiOrderException>()
              .having((e) => e.forbidden, 'forbidden', isTrue)
              .having((e) => e.unauthorized, 'unauthorized', isFalse),
        ),
      );
    });

    test('ném ApiOrderException khi WooCommerce chưa active', () async {
      final repository = ApiOrderRepository(
        apiClient: ApiClient(
          authSession: _signedInSession(),
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
          authSession: _signedInSession(),
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

  group('ApiClient.parseErrorBody', () {
    test('đọc được code, message và status từ JSON lỗi', () {
      final body = ApiClient.parseErrorBody(
        jsonEncode(
          _errorBody(
            'kc_invalid_date_range',
            'date_from phải nhỏ hơn hoặc bằng date_to.',
            400,
          ),
        ),
      );

      expect(body.code, 'kc_invalid_date_range');
      expect(body.message, 'date_from phải nhỏ hơn hoặc bằng date_to.');
      expect(body.status, 400);
    });

    test('body rỗng hoặc không phải JSON thì trả giá trị rỗng', () {
      expect(ApiClient.parseErrorBody('').code, isNull);
      expect(ApiClient.parseErrorBody('<html>500</html>').message, isNull);
      expect(ApiClient.parseErrorBody('[1,2]').status, isNull);
    });
  });
}
