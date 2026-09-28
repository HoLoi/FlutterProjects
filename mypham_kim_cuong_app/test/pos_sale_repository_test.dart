import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mypham_kim_cuong_app/data/pos_sale_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/order.dart';
import 'package:mypham_kim_cuong_app/models/pos_sale.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://pos.example.com';
  });

  AuthSession signedInSession() {
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');
    return session;
  }

  /// Envelope thành công đúng shape server trả về.
  String successBody({
    bool replayed = false,
    int orderId = 900,
    int total = 189000,
  }) {
    return jsonEncode({
      'success': true,
      'replayed': replayed,
      'order': {
        'id': orderId,
        'number': 'POS-900',
        'status': 'processing',
        'created_via': 'kc_pos',
        'payment_method': 'cash',
        'currency': 'VND',
        'total': total,
        'request_id': 'pos-test-1',
        'line_items': [
          {
            'id': 12,
            'product_id': 651,
            'variation_id': 0,
            'name': 'Serum Vitamin C',
            'sku': 'VC-30',
            'quantity': 1,
            'price': 189000,
            'subtotal': 189000,
            'total': 189000,
            'image_url': 'https://cdn.example.com/vc.jpg',
          },
        ],
      },
    });
  }

  String errorBody(String code, String message, int status) {
    return jsonEncode({
      'code': code,
      'message': message,
      'data': {'status': status},
    });
  }

  /// `http.Response` mặc định encode body theo Latin-1, nên thêm charset UTF-8
  /// để body tiếng Việt không làm `MockClient` ném lỗi trước khi app kịp đọc.
  http.Response jsonResponse(String body, int statusCode) {
    return http.Response(
      body,
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  PosSaleRepository repositoryReturning(
    http.Response Function(http.Request request) handler, {
    AuthSession? session,
  }) {
    final client = MockClient((request) async => handler(request));
    return ApiPosSaleRepository(
      apiClient: ApiClient(
        httpClient: client,
        authSession: session ?? signedInSession(),
      ),
    );
  }

  const simpleItem = PosSaleItemRequest(productId: 651, quantity: 2);

  group('ApiClient.createPosSale gửi đúng body', () {
    test('chỉ gửi product_id, variation_id, quantity và không gửi giá', () async {
      late http.Request captured;
      final repository = repositoryReturning((request) {
        captured = request;
        return http.Response(successBody(), 201);
      });

      await repository.createPosSale(
        requestId: 'pos-abc',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/wp-json/kc/v1/pos/sales');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['request_id'], 'pos-abc');
      expect(body['payment_method'], 'cash');
      expect(body['customer_id'], 0);
      expect(body['customer_note'], '');
      expect(body.containsKey('total'), isFalse);
      expect(body.containsKey('price'), isFalse);

      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item.keys, containsAll(['product_id', 'variation_id', 'quantity']));
      expect(item['product_id'], 651);
      expect(item['variation_id'], 0, reason: 'sản phẩm simple dùng variation 0');
      expect(item['quantity'], 2);
    });

    test('gửi variation_id dương cho sản phẩm biến thể', () async {
      late http.Request captured;
      final repository = repositoryReturning((request) {
        captured = request;
        return http.Response(successBody(), 201);
      });

      await repository.createPosSale(
        requestId: 'pos-var',
        paymentMethod: PosPaymentMethod.vietqr.wire,
        customerId: 0,
        items: const [
          PosSaleItemRequest(productId: 652, variationId: 9001, quantity: 1),
        ],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item['variation_id'], 9001);
    });

    test('gửi customer_id và customer_note khi có', () async {
      late http.Request captured;
      final repository = repositoryReturning((request) {
        captured = request;
        return http.Response(successBody(), 201);
      });

      await repository.createPosSale(
        requestId: 'pos-note',
        paymentMethod: PosPaymentMethod.bacs.wire,
        customerId: 42,
        items: const [simpleItem],
        customerNote: 'Giao sau 17h',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['customer_id'], 42);
      expect(body['customer_note'], 'Giao sau 17h');
    });

    test('gửi Authorization header và Accept', () async {
      late http.Request captured;
      final repository = repositoryReturning((request) {
        captured = request;
        return http.Response(successBody(), 201);
      });

      await repository.createPosSale(
        requestId: 'pos-auth',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );

      expect(captured.headers['Authorization'], isNotNull);
      expect(captured.headers['Accept'], 'application/json');
      expect(captured.headers['Content-Type'], contains('application/json'));
    });
  });

  group('HTTP 201 tạo đơn mới', () {
    test('parse đủ thông tin đơn và line item', () async {
      final repository = repositoryReturning(
        (_) => http.Response(successBody(), 201),
      );

      final result = await repository.createPosSale(
        requestId: 'pos-test-1',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );

      expect(result.replayed, isFalse);
      final order = result.order;
      expect(order.id, 900);
      expect(order.number, 'POS-900');
      expect(order.status, OrderStatus.processing);
      expect(order.createdVia, 'kc_pos');
      expect(order.paymentMethod, 'cash');
      expect(order.currency, 'VND');
      expect(order.total, 189000);
      expect(order.requestId, 'pos-test-1');

      expect(order.lineItems, hasLength(1));
      final line = order.lineItems.first;
      expect(line.productId, 651);
      expect(line.variationId, 0);
      expect(line.name, 'Serum Vitamin C');
      expect(line.quantity, 1);
      expect(line.total, 189000);
      expect(line.imageUrl, 'https://cdn.example.com/vc.jpg');
    });
  });

  group('HTTP 200 replay cùng request_id', () {
    test('báo replayed và không tạo đơn mới', () async {
      final repository = repositoryReturning(
        (_) => http.Response(successBody(replayed: true), 200),
      );

      final result = await repository.createPosSale(
        requestId: 'pos-test-1',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );

      expect(result.replayed, isTrue);
      expect(result.order.number, 'POS-900');
    });

    test('gửi lại cùng request_id hai lần đều trả cùng đơn', () async {
      final seen = <String>[];
      final repository = repositoryReturning((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final requestId = body['request_id'] as String;
        seen.add(requestId);
        // Lần đầu tạo mới (201), lần sau server trả lại đơn cũ (200).
        final isFirst = seen.length == 1;
        return http.Response(
          successBody(replayed: !isFirst, orderId: 901),
          isFirst ? 201 : 200,
        );
      });

      final first = await repository.createPosSale(
        requestId: 'pos-idempotent',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );
      final second = await repository.createPosSale(
        requestId: 'pos-idempotent',
        paymentMethod: PosPaymentMethod.cash.wire,
        customerId: 0,
        items: const [simpleItem],
      );

      expect(seen, ['pos-idempotent', 'pos-idempotent']);
      expect(first.order.id, 901);
      expect(second.order.id, 901);
      expect(second.replayed, isTrue);
    });
  });

  group('Phân loại lỗi', () {
    Future<PosSaleException> expectFailure(
      http.Response Function(http.Request) handler,
    ) async {
      final repository = repositoryReturning(handler);
      try {
        await repository.createPosSale(
          requestId: 'pos-err',
          paymentMethod: PosPaymentMethod.cash.wire,
          customerId: 0,
          items: const [simpleItem],
        );
      } on PosSaleException catch (error) {
        return error;
      }
      fail('phải ném PosSaleException');
    }

    test('400 invalid request', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('kc_invalid_cart', 'Giỏ hàng không hợp lệ', 400),
          400,
        ),
      );
      expect(error.status, PosSaleStatus.invalidRequest);
      expect(error.code, 'kc_invalid_cart');
      expect(error.message, 'Giỏ hàng không hợp lệ');
    });

    test('401 unauthorized', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('rest_not_logged_in', 'Chưa đăng nhập', 401),
          401,
        ),
      );
      expect(error.status, PosSaleStatus.unauthorized);
      expect(error.canRetryWithSameRequestId, isFalse);
    });

    test('403 forbidden', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('rest_forbidden', 'Không có quyền', 403),
          403,
        ),
      );
      expect(error.status, PosSaleStatus.forbidden);
    });

    test('409 hết tồn kho không cho gửi lại', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('kc_out_of_stock', 'Sản phẩm đã hết hàng', 409),
          409,
        ),
      );
      expect(error.status, PosSaleStatus.outOfStock);
      expect(error.code, 'kc_out_of_stock');
      // Hết hàng là lỗi chắc chắn chưa tạo đơn, gửi lại vô ích.
      expect(error.canRetryWithSameRequestId, isFalse);
    });

    test('409 đang tạo đơn thì cho gửi lại cùng khoá', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody(
            'kc_sale_in_progress',
            'Đơn đang được tạo, thử lại',
            409,
          ),
          409,
        ),
      );
      expect(error.status, PosSaleStatus.saleInProgress);
      expect(error.canRetryWithSameRequestId, isTrue);
    });

    test('500 server error cho gửi lại cùng khoá', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('internal_server_error', 'Lỗi máy chủ', 500),
          500,
        ),
      );
      expect(error.status, PosSaleStatus.serverError);
      // Có thể đơn đã tạo xong mà app chưa nhận phản hồi.
      expect(error.canRetryWithSameRequestId, isTrue);
    });

    test('503 WooCommerce chưa kích hoạt', () async {
      final error = await expectFailure(
        (_) => jsonResponse(
          errorBody('rest_no_route', 'REST API không khả dụng', 404),
          404,
        ),
      );
      expect(error.status, PosSaleStatus.httpError);
    });

    test('lỗi mạng cho gửi lại cùng khoá', () async {
      final client = MockClient((_) async {
        throw const SocketExceptionStub();
      });
      final repository = ApiPosSaleRepository(
        apiClient: ApiClient(
          httpClient: client,
          authSession: signedInSession(),
        ),
      );

      try {
        await repository.createPosSale(
          requestId: 'pos-net',
          paymentMethod: PosPaymentMethod.cash.wire,
          customerId: 0,
          items: const [simpleItem],
        );
        fail('phải ném PosSaleException');
      } on PosSaleException catch (error) {
        expect(error.status, PosSaleStatus.networkError);
        expect(error.canRetryWithSameRequestId, isTrue);
      }
    });

    test('200 nhưng body sai format thì báo lỗi client', () async {
      final error = await expectFailure(
        (_) => jsonResponse(jsonEncode({'success': false}), 200),
      );
      expect(error.status, PosSaleStatus.httpError);
    });
  });

  group('Chặn trước khi gọi mạng', () {
    test('chưa đăng nhập thì không gửi request', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(successBody(), 201);
      });
      final repository = ApiPosSaleRepository(
        apiClient: ApiClient(httpClient: client, authSession: AuthSession()),
      );

      try {
        await repository.createPosSale(
          requestId: 'pos-noauth',
          paymentMethod: PosPaymentMethod.cash.wire,
          customerId: 0,
          items: const [simpleItem],
        );
        fail('phải ném PosSaleException');
      } on PosSaleException catch (error) {
        expect(error.status, PosSaleStatus.notSignedIn);
        expect(called, isFalse, reason: 'không được gửi Basic auth khi chưa đăng nhập');
      }
    });

    test('base URL dùng http thì không gửi Application Password', () async {
      AppSettings.baseUrl = 'http://pos.example.com';
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(successBody(), 201);
      });
      final repository = ApiPosSaleRepository(
        apiClient: ApiClient(
          httpClient: client,
          authSession: signedInSession(),
        ),
      );

      try {
        await repository.createPosSale(
          requestId: 'pos-http',
          paymentMethod: PosPaymentMethod.cash.wire,
          customerId: 0,
          items: const [simpleItem],
        );
        fail('phải ném PosSaleException');
      } on PosSaleException catch (error) {
        expect(error.status, PosSaleStatus.insecureUrl);
        expect(called, isFalse, reason: 'không gửi credential qua http thường');
      }
    });

    test('giỏ rỗng thì không gửi request', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(successBody(), 201);
      });
      final repository = ApiPosSaleRepository(
        apiClient: ApiClient(
          httpClient: client,
          authSession: signedInSession(),
        ),
      );

      try {
        await repository.createPosSale(
          requestId: 'pos-empty',
          paymentMethod: PosPaymentMethod.cash.wire,
          customerId: 0,
          items: const [],
        );
        fail('phải ném PosSaleException');
      } on PosSaleException catch (error) {
        expect(error.status, PosSaleStatus.invalidRequest);
        expect(called, isFalse);
      }
    });
  });

  group('PosPaymentMethod', () {
    test('ba giá trị khớp hợp đồng với server', () {
      expect(PosPaymentMethod.cash.wire, 'cash');
      expect(PosPaymentMethod.bacs.wire, 'bacs');
      expect(PosPaymentMethod.vietqr.wire, 'vietqr');
    });

    test('fromWire đọc được cả ba và mặc định về tiền mặt', () {
      expect(PosPaymentMethod.fromWire('cash'), PosPaymentMethod.cash);
      expect(PosPaymentMethod.fromWire('bacs'), PosPaymentMethod.bacs);
      expect(PosPaymentMethod.fromWire('vietqr'), PosPaymentMethod.vietqr);
      expect(PosPaymentMethod.fromWire('unknown'), PosPaymentMethod.cash);
    });
  });
}

/// Ném lỗi giống `SocketException` để nhánh network error chạy đúng.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
