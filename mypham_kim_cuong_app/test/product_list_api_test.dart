import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_product_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/screens/product_list_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';

Widget _app(ApiProductRepository repository) {
  return MaterialApp(
    home: Scaffold(body: ProductListScreen(apiRepository: repository)),
  );
}

ApiProductRepository _okRepository() {
  return ApiProductRepository(
    apiClient: ApiClient(
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'wc_active': true,
            'count': 2,
            'data': [
              {
                'id': 101,
                'name': 'Son Kem Lì Satin',
                'sku': 'KC-0001',
                'barcode': '893000000001',
                'price': 189000,
                'stock_quantity': 25,
                'stock_status': 'instock',
                'categories': [
                  {'id': 1, 'name': 'Son', 'slug': 'son'},
                ],
              },
              {
                'id': 102,
                'name': 'Kem Chống Nắng SPF 50',
                'sku': 'KC-0003',
                'barcode': null,
                'price': 210000,
                'stock_quantity': 0,
                'stock_status': 'outofstock',
                'categories': [],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

ApiProductRepository _wcInactiveRepository() {
  return ApiProductRepository(
    apiClient: ApiClient(
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'wc_active': false,
            'count': 0,
            'data': [],
            'message': 'WooCommerce chưa active, không đọc được sản phẩm.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

ApiProductRepository _failingRepository() {
  return ApiProductRepository(
    apiClient: ApiClient(
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

  testWidgets('Bật API mode hiển thị sản phẩm từ API', (tester) async {
    await tester.pumpWidget(_app(_okRepository()));

    expect(find.text('10 sản phẩm'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2 sản phẩm'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsOneWidget);
    expect(find.text('Kem Chống Nắng SPF 50'), findsOneWidget);
    expect(find.text('Hết hàng'), findsWidgets);
  });

  testWidgets('Tắt API mode quay lại dữ liệu mock', (tester) async {
    await tester.pumpWidget(_app(_okRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 sản phẩm'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('10 sản phẩm'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsOneWidget);
  });

  testWidgets('Lỗi API hiển thị thông báo và quay lại mock được',
      (tester) async {
    await tester.pumpWidget(_app(_failingRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Không đọc được dữ liệu API'), findsOneWidget);
    expect(find.text('Không kết nối được máy chủ'), findsOneWidget);

    await tester.tap(find.text('Quay lại dữ liệu mock'));
    await tester.pump();

    expect(find.text('10 sản phẩm'), findsOneWidget);
    expect(find.text('Serum Vitamin C Brightening'), findsOneWidget);
  });

  testWidgets('WooCommerce chưa active hiển thị lỗi rõ ràng', (tester) async {
    await tester.pumpWidget(_app(_wcInactiveRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Không đọc được dữ liệu API'), findsOneWidget);
    expect(
      find.text('WooCommerce chưa active, không đọc được sản phẩm.'),
      findsOneWidget,
    );
  });

  testWidgets('Có nút Thử lại khi API lỗi', (tester) async {
    await tester.pumpWidget(_app(_failingRepository()));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Thử lại'), findsOneWidget);
  });
}