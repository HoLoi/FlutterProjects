import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/screens/settings_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';

Widget _settingsApp(ApiClient client) {
  return MaterialApp(home: SettingsScreen(apiClient: client));
}

void main() {
  setUp(() {
    AppSettings.baseUrl = '';
  });

  testWidgets('Settings có ô base URL và nút Kiểm tra kết nối',
      (WidgetTester tester) async {
    final client = ApiClient(
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    await tester.pumpWidget(_settingsApp(client));

    expect(find.text('Địa chỉ website (Base URL)'), findsOneWidget);
    expect(find.text('Kiểm tra kết nối'), findsOneWidget);
  });

  testWidgets('Không gọi API khi base URL rỗng', (WidgetTester tester) async {
    var called = false;
    final client = ApiClient(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('', 500);
      }),
    );
    await tester.pumpWidget(_settingsApp(client));

    await tester.tap(find.text('Kiểm tra kết nối'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Vui lòng nhập địa chỉ website'), findsOneWidget);
    expect(find.text('Đang kiểm tra...'), findsNothing);
  });

  testWidgets('Kiểm tra kết nối thành công', (WidgetTester tester) async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/wp-json/kc/v1/health');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response(
          jsonEncode({
            'ok': true,
            'plugin': 'mypham-kim-cuong-manager',
            'version': '1.0.0',
            'time': '2026-09-20 10:30:00',
            'wordpress': '7.1.1',
            'woocommerce_active': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(_settingsApp(client));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Địa chỉ website (Base URL)'),
      'https://demo.local',
    );
    await tester.pump();
    await tester.tap(find.text('Kiểm tra kết nối'));
    await tester.pump();

    expect(find.text('Đang kiểm tra...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Kết nối thành công'), findsOneWidget);
    expect(find.text('Phiên bản: 1.0.0'), findsOneWidget);
    expect(find.text('WooCommerce: có hoạt động'), findsOneWidget);
  });

  testWidgets('Kiểm tra kết nối thất bại', (WidgetTester tester) async {
    final client = ApiClient(
      httpClient: MockClient((_) async {
        throw http.ClientException('Connection refused');
      }),
    );
    await tester.pumpWidget(_settingsApp(client));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Địa chỉ website (Base URL)'),
      'https://demo.local',
    );
    await tester.pump();
    await tester.tap(find.text('Kiểm tra kết nối'));
    await tester.pump();

    expect(find.text('Không kết nối được'), findsOneWidget);
  });
}