import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/pos_sale_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/pos_sale.dart';
import 'package:mypham_kim_cuong_app/screens/pos_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';
import 'package:mypham_kim_cuong_app/services/cart_controller.dart';
import 'package:mypham_kim_cuong_app/services/pos_checkout_controller.dart';

/// Nháp lệnh POST để test khẳng định đúng body và khoá idempotency.
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.body, this.headers);

  final String method;
  final String path;
  final Map<String, dynamic> body;
  final Map<String, String> headers;

  Map<String, dynamic> get firstItem =>
      (body['items'] as List).first as Map<String, dynamic>;
}

PosSaleRepository repositoryRecording(
  List<RecordedRequest> log, {
  int statusCode = 201,
  bool replayed = false,
  String? orderNumber,
}) {
  final client = MockClient((request) async {
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    log.add(
      RecordedRequest(
        request.method,
        request.url.path,
        body,
        request.headers,
      ),
    );
    return http.Response(
      jsonEncode({
        'success': true,
        'replayed': replayed,
        'order': {
          'id': 901,
          'number': orderNumber ?? 'POS-901',
          'status': 'processing',
          'created_via': 'kc_pos',
          'payment_method': body['payment_method'],
          'currency': 'VND',
          'total': 189000,
          'request_id': body['request_id'],
          'line_items': [
            {
              'id': 1,
              'product_id': 651,
              'variation_id': 0,
              'name': 'Serum Vitamin C',
              'sku': 'VC-30',
              'quantity': 1,
              'price': 189000,
              'subtotal': 189000,
              'total': 189000,
            },
          ],
        },
      }),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  final session = AuthSession();
  session.signIn(username: 'pos', appPassword: 'test-pass');
  return ApiPosSaleRepository(
    apiClient: ApiClient(httpClient: client, authSession: session),
  );
}

PosSaleRepository failingRepository(PosSaleStatus status) {
  return _ThrowingRepository(status);
}

class _ThrowingRepository implements PosSaleRepository {
  _ThrowingRepository(this.status);

  final PosSaleStatus status;

  @override
  Future<PosSaleResult> createPosSale({
    required String requestId,
    required String paymentMethod,
    required int customerId,
    required List<PosSaleItemRequest> items,
    String customerNote = '',
  }) async {
    throw PosSaleException(status, message: 'Lỗi kiểm thử');
  }
}

Widget _apiPosApp({
  required PosSaleRepository repository,
  CartController? cart,
  AuthSession? authSession,
}) {
  final session = authSession ?? AuthSession();
  return MaterialApp(
    home: Scaffold(
      body: PosScreen(
        cart: cart,
        posRepository: repository,
        authSession: session,
        checkout: PosCheckoutController(),
      ),
    ),
  );
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://pos.example.com';
  });

  testWidgets('Đăng nhập rồi bấm thanh toán thì gọi API và xoá giỏ', (
    tester,
  ) async {
    final log = <RecordedRequest>[];
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');

    await tester.pumpWidget(
      _apiPosApp(
        repository: repositoryRecording(log),
        authSession: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    expect(log, hasLength(1));
    expect(log.first.method, 'POST');
    expect(log.first.path, '/wp-json/kc/v1/pos/sales');
    expect(log.first.headers['Authorization'], isNotNull);

    // Dialog thành công hiện mã đơn và tổng tiền từ server.
    expect(find.text('Đơn #POS-901'), findsOneWidget);
    expect(find.textContaining('189.000'), findsWidgets);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ hàng trống'), findsOneWidget);
  });

  testWidgets('Gửi đúng customer_id 0 và variation_id 0 cho sản phẩm simple', (
    tester,
  ) async {
    final log = <RecordedRequest>[];
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');

    await tester.pumpWidget(
      _apiPosApp(
        repository: repositoryRecording(log),
        authSession: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    final body = log.first.body;
    expect(body['customer_id'], 0);
    expect(body['payment_method'], 'cash');
    expect(log.first.firstItem['variation_id'], 0);
    expect(log.first.firstItem.containsKey('price'), isFalse);
  });

  testWidgets('Chọn VietQR thì gửi payment_method tương ứng', (tester) async {
    final log = <RecordedRequest>[];
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');

    await tester.pumpWidget(
      _apiPosApp(
        repository: repositoryRecording(log),
        authSession: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    await tester.tap(find.text('VietQR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    expect(log.first.body['payment_method'], 'vietqr');
  });

  testWidgets('HTTP 200 replay hiện thông báo không tạo đơn mới', (tester) async {
    final log = <RecordedRequest>[];
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');

    await tester.pumpWidget(
      _apiPosApp(
        repository: repositoryRecording(log, statusCode: 200, replayed: true),
        authSession: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    expect(find.textContaining('không tạo đơn mới'), findsOneWidget);
  });

  testWidgets('Lỗi hết hàng thì giữ giỏ và không có nút Gửi lại', (tester) async {
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');

    await tester.pumpWidget(
      _apiPosApp(
        repository: failingRepository(PosSaleStatus.outOfStock),
        authSession: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    expect(find.text('Chưa thanh toán được'), findsOneWidget);
    expect(find.text('Lỗi kiểm thử'), findsOneWidget);
    // Hết hàng là lỗi chắc chắn chưa tạo đơn, gửi lại vô ích.
    expect(find.text('Gửi lại'), findsNothing);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ hàng trống'), findsNothing);
  });

  testWidgets('Lỗi mạng thì cho gửi lại và giữ nguyên request_id', (
    tester,
  ) async {
    final log = <RecordedRequest>[];
    var attempts = 0;
    final client = MockClient((request) async {
      attempts += 1;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      log.add(
        RecordedRequest(request.method, request.url.path, body, request.headers),
      );
      if (attempts == 1) {
        throw StateError('mất mạng');
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'replayed': true,
          'order': {
            'id': 902,
            'number': 'POS-902',
            'status': 'processing',
            'created_via': 'kc_pos',
            'payment_method': body['payment_method'],
            'currency': 'VND',
            'total': 189000,
            'request_id': body['request_id'],
            'line_items': const [],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');
    final repository = ApiPosSaleRepository(
      apiClient: ApiClient(httpClient: client, authSession: session),
    );

    await tester.pumpWidget(
      _apiPosApp(repository: repository, authSession: session),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();

    // Lỗi mạng: server có thể đã tạo đơn, nên phải cho gửi lại cùng khoá.
    expect(find.text('Gửi lại'), findsOneWidget);
    await tester.tap(find.text('Gửi lại'));
    await tester.pumpAndSettle();

    expect(log, hasLength(2));
    expect(
      log[0].body['request_id'],
      log[1].body['request_id'],
      reason: 'phải gửi lại cùng khoá để không tạo đơn trùng',
    );
    expect(find.text('Đơn #POS-902'), findsOneWidget);
  });

  testWidgets('Chưa đăng nhập thì khoá nút thanh toán', (tester) async {
    final log = <RecordedRequest>[];

    await tester.pumpWidget(
      _apiPosApp(
        repository: repositoryRecording(log),
        cart: CartController(),
      ),
    );
    await tester.pumpAndSettle();

    // Bật chế độ API để xem trạng thái chưa đăng nhập.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    expect(find.text('Đăng nhập để thanh toán thật'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Thanh toán'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull, reason: 'không cho gọi API khi chưa đăng nhập');
    expect(log, isEmpty);
  });

  testWidgets('Chế độ demo giữ nguyên hành vi cũ, không gọi API', (tester) async {
    final log = <RecordedRequest>[];

    await tester.pumpWidget(
      _apiPosApp(repository: repositoryRecording(log)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    // Chưa đăng nhập và không bật chế độ API: vẫn là POS demo.
    expect(find.text('Thanh toán demo'), findsOneWidget);
    await tester.tap(find.text('Thanh toán demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();

    expect(log, isEmpty, reason: 'POS demo không được gọi mạng');
    expect(find.text('Giỏ hàng trống'), findsOneWidget);
  });

  testWidgets('Trong lúc gọi API thì nút thanh toán bị khoá', (tester) async {
    final session = AuthSession();
    session.signIn(username: 'pos', appPassword: 'test-pass');
    final completer = Completer<http.Response>();

    final client = MockClient((_) async => await completer.future);
    final repository = ApiPosSaleRepository(
      apiClient: ApiClient(httpClient: client, authSession: session),
    );

    await tester.pumpWidget(
      _apiPosApp(repository: repository, authSession: session),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    await tester.tap(find.text('Thanh toán'));
    await tester.pump();

    expect(find.text('Đang tạo đơn...'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Đang tạo đơn...'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull, reason: 'chặn bấm hai lần tạo đơn');

    completer.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'replayed': false,
          'order': {
            'id': 903,
            'number': 'POS-903',
            'status': 'processing',
            'created_via': 'kc_pos',
            'payment_method': 'cash',
            'currency': 'VND',
            'total': 189000,
            'request_id': 'x',
            'line_items': const [],
          },
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đơn #POS-903'), findsOneWidget);
  });
}
