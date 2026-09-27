import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_order_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/screens/order_detail_screen.dart';
import 'package:mypham_kim_cuong_app/screens/order_list_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

const String _appPassword = 'abcd efgh ijkl mnop';

Widget _listApp(
  ApiOrderRepository repository,
  AuthSession session, {
  VoidCallback? onRequireSignIn,
}) {
  return MaterialApp(
    home: Scaffold(
      body: OrderListScreen(
        apiRepository: repository,
        authSession: session,
        onRequireSignIn: onRequireSignIn,
      ),
    ),
  );
}

Widget _detailApp(ApiOrderRepository repository, int orderId) {
  return MaterialApp(
    home: OrderDetailScreen(orderId: orderId, apiRepository: repository),
  );
}

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

AuthSession _signedIn() {
  final session = AuthSession();
  session.signIn(username: 'demo', appPassword: _appPassword);
  return session;
}

List<Map<String, dynamic>> _orderFixtures() {
  return [
    {
      'id': 501,
      'number': '501',
      'status': 'processing',
      'status_label': 'Đang xử lý',
      'created_at': '2026-09-20 14:30:00',
      'customer_name': 'Nguyễn Thị A',
      'customer_phone': '0900000000',
      'items_count': 2,
      'total': 398000,
      'payment_method_label': 'COD',
    },
    {
      'id': 502,
      'number': '502',
      'status': 'cancelled',
      'status_label': 'Đã huỷ',
      'customer_name': '',
      'items_count': 1,
      'total': 189000,
      'payment_method_label': '',
    },
  ];
}

ApiOrderRepository _okRepository() {
  final session = _signedIn();
  return ApiOrderRepository(
    authSession: session,
    apiClient: ApiClient(
      authSession: session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/501')) {
          return _jsonResponse({
            'wc_active': true,
            'id': 501,
            'number': '501',
            'status': 'processing',
            'status_label': 'Đang xử lý',
            'customer_name': 'Nguyễn Thị A',
            'customer_phone': '0900000000',
            'created_at': '2026-09-20 14:30:00',
            'total': 398000,
            'payment_method_label': 'COD',
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
        }
        return _jsonResponse({
          'wc_active': true,
          'count': 2,
          'data': _orderFixtures(),
        });
      }),
    ),
  );
}

ApiOrderRepository _repositoryReturning(int status, {String body = ''}) {
  final session = _signedIn();
  return ApiOrderRepository(
    authSession: session,
    apiClient: ApiClient(
      authSession: session,
      httpClient: MockClient((_) async => http.Response(body, status)),
    ),
  );
}

ApiOrderRepository _failingRepository() {
  final session = _signedIn();
  return ApiOrderRepository(
    authSession: session,
    apiClient: ApiClient(
      authSession: session,
      httpClient: MockClient((_) async {
        throw http.ClientException('Connection refused');
      }),
    ),
  );
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  testWidgets('Chưa đăng nhập thì không gọi API và yêu cầu đăng nhập', (
    tester,
  ) async {
    var called = false;
    final session = AuthSession();
    final repository = ApiOrderRepository(
      authSession: session,
      apiClient: ApiClient(
        authSession: session,
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      ),
    );
    var askedToSignIn = false;

    await tester.pumpWidget(
      _listApp(
        repository,
        session,
        onRequireSignIn: () => askedToSignIn = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      called,
      isFalse,
      reason: 'không được gọi API orders trước khi đăng nhập',
    );
    expect(find.text('Bạn cần đăng nhập để xem đơn hàng'), findsOneWidget);
    expect(find.text('Cần đăng nhập'), findsOneWidget);

    await tester.tap(find.text('Đăng nhập'));
    await tester.pump();

    expect(askedToSignIn, isTrue);
  });

  testWidgets('Đã đăng nhập thì tải và hiển thị đơn hàng', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository(), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text('2 đơn hàng'), findsOneWidget);
    expect(find.text('#501'), findsOneWidget);
    expect(find.text('#502'), findsOneWidget);
    expect(find.text('398.000 đ'), findsOneWidget);
    expect(find.text('Nguyễn Thị A'), findsOneWidget);
  });

  testWidgets('Đơn hàng thiếu tên khách dùng nhãn dự phòng', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository(), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text('Khách lẻ (chưa có tên)'), findsOneWidget);
  });

  testWidgets('Lọc theo trạng thái chỉ hiện đơn tương ứng', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository(), _signedIn()));
    await tester.pumpAndSettle();

    final cancelledChip = find.widgetWithText(FilterChip, 'Đã huỷ');
    await tester.ensureVisible(cancelledChip);
    await tester.pumpAndSettle();
    await tester.tap(cancelledChip);
    await tester.pump();

    expect(find.text('#502'), findsOneWidget);
    expect(find.text('#501'), findsNothing);
  });

  testWidgets('HTTP 401 hiển thị thông báo đăng nhập không hợp lệ', (
    tester,
  ) async {
    await tester.pumpWidget(_listApp(_repositoryReturning(401), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text('Không đọc được đơn hàng'), findsOneWidget);
    expect(
      find.text('Thông tin đăng nhập không hợp lệ hoặc đã hết hạn'),
      findsOneWidget,
    );
    expect(find.text('Đăng nhập lại'), findsOneWidget);
  });

  testWidgets('HTTP 403 hiển thị thông báo thiếu quyền', (tester) async {
    await tester.pumpWidget(_listApp(_repositoryReturning(403), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text('Tài khoản không có quyền xem đơn hàng'), findsOneWidget);
    expect(find.text('Đăng nhập lại'), findsOneWidget);
  });

  testWidgets('Lỗi mạng hiển thị thông báo kết nối', (tester) async {
    await tester.pumpWidget(_listApp(_failingRepository(), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text('Không đọc được đơn hàng'), findsOneWidget);
    expect(find.text('Không kết nối được máy chủ'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('Mở chi tiết đơn hàng từ danh sách', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository(), _signedIn()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#501'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Son Kem Lì Satin'), findsOneWidget);
    expect(find.text('SKU: KC-0001-RED'), findsOneWidget);
    expect(find.text('Số lượng: 2'), findsOneWidget);
    expect(find.text('Ghi chú'), findsOneWidget);
    expect(find.text('Giao sau 18h'), findsOneWidget);
  });

  testWidgets('Chi tiết đơn 404 hiển thị lỗi và có nút thử lại', (
    tester,
  ) async {
    await tester.pumpWidget(_detailApp(_repositoryReturning(404), 999));
    await tester.pumpAndSettle();

    expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
  });

  testWidgets('Chi tiết đơn 401 hiển thị thông báo đăng nhập', (tester) async {
    await tester.pumpWidget(_detailApp(_repositoryReturning(401), 501));
    await tester.pumpAndSettle();

    expect(
      find.text('Thông tin đăng nhập không hợp lệ hoặc đã hết hạn'),
      findsOneWidget,
    );
  });

  testWidgets('Chi tiết đơn 403 hiển thị thông báo thiếu quyền', (
    tester,
  ) async {
    await tester.pumpWidget(_detailApp(_repositoryReturning(403), 501));
    await tester.pumpAndSettle();

    expect(find.text('Tài khoản không có quyền xem đơn hàng'), findsOneWidget);
  });

  testWidgets('Mật khẩu không xuất hiện trên giao diện', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository(), _signedIn()));
    await tester.pumpAndSettle();

    expect(find.text(_appPassword), findsNothing);
    expect(find.textContaining(_appPassword), findsNothing);
  });

  testWidgets('Đăng xuất thì quay về màn hình yêu cầu đăng nhập', (
    tester,
  ) async {
    final session = _signedIn();
    final repository = _okRepository();

    await tester.pumpWidget(_listApp(repository, session));
    await tester.pumpAndSettle();
    expect(find.text('#501'), findsOneWidget);

    session.signOut();
    await tester.pumpAndSettle();

    expect(find.text('#501'), findsNothing);
    expect(find.text('Bạn cần đăng nhập để xem đơn hàng'), findsOneWidget);
  });
}
