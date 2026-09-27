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

Widget _listApp(ApiOrderRepository repository) {
  return MaterialApp(
    home: Scaffold(body: OrderListScreen(apiRepository: repository)),
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
  return ApiOrderRepository(
    apiClient: ApiClient(
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

ApiOrderRepository _wcInactiveRepository() {
  return ApiOrderRepository(
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
}

ApiOrderRepository _failingRepository() {
  return ApiOrderRepository(
    apiClient: ApiClient(
      httpClient: MockClient((_) async {
        throw http.ClientException('Connection refused');
      }),
    ),
  );
}

ApiOrderRepository _notFoundRepository() {
  return ApiOrderRepository(
    apiClient: ApiClient(
      httpClient: MockClient((_) async => http.Response('', 404)),
    ),
  );
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  testWidgets('Mặc định hiển thị dữ liệu mock', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository()));

    expect(find.text('1 đơn hàng'), findsOneWidget);
    expect(find.text('#501'), findsOneWidget);
    expect(find.text('Nguyễn Thị A'), findsOneWidget);
  });

  testWidgets('Bật API mode hiển thị đơn hàng từ API', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2 đơn hàng'), findsOneWidget);
    expect(find.text('#501'), findsOneWidget);
    expect(find.text('#502'), findsOneWidget);
    expect(find.text('398.000 đ'), findsOneWidget);
    expect(find.text('Đang xử lý'), findsWidgets);
    expect(find.text('Đã huỷ'), findsWidgets);
  });

  testWidgets('Đơn hàng thiếu tên khách dùng nhãn dự phòng', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Khách lẻ (chưa có tên)'), findsOneWidget);
  });

  testWidgets('Lọc theo trạng thái chỉ hiện đơn tương ứng', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final cancelledChip = find.widgetWithText(FilterChip, 'Đã huỷ');
    await tester.ensureVisible(cancelledChip);
    await tester.pumpAndSettle();
    await tester.tap(cancelledChip);
    await tester.pump();

    expect(find.text('#502'), findsOneWidget);
    expect(find.text('#501'), findsNothing);
  });

  testWidgets('Lỗi API hiển thị thông báo và quay lại mock được', (tester) async {
    await tester.pumpWidget(_listApp(_failingRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Không đọc được đơn hàng'), findsOneWidget);
    expect(find.text('Không kết nối được máy chủ'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);

    await tester.tap(find.text('Quay lại dữ liệu mock'));
    await tester.pump();

    expect(find.text('1 đơn hàng'), findsOneWidget);
  });

  testWidgets('WooCommerce chưa active hiển thị lỗi rõ ràng', (tester) async {
    await tester.pumpWidget(_listApp(_wcInactiveRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('WooCommerce chưa active, không đọc được dữ liệu.'),
      findsOneWidget,
    );
  });

  testWidgets('Mở chi tiết đơn hàng từ danh sách', (tester) async {
    await tester.pumpWidget(_listApp(_okRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('#501'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Son Kem Lì Satin'), findsOneWidget);
    expect(find.text('SKU: KC-0001-RED'), findsOneWidget);
    expect(find.text('Số lượng: 2'), findsOneWidget);
    expect(find.text('Ghi chú'), findsOneWidget);
    expect(find.text('Giao sau 18h'), findsOneWidget);
  });

  testWidgets('Chi tiết đơn không tìm thấy hiển thị lỗi và có nút thử lại',
      (tester) async {
    await tester.pumpWidget(_detailApp(_notFoundRepository(), 999));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
  });
}
