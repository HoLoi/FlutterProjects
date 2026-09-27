import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/main.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

const String _appPassword = 'abcd efgh ijkl mnop';

ApiClient _okClient() {
  return ApiClient(
    httpClient: MockClient((request) async {
      if (request.url.path.contains('/orders')) {
        return http.Response(
          jsonEncode({'wc_active': true, 'count': 0, 'data': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'ok': true, 'plugin': 'mypham-kim-cuong-manager'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Tên đăng nhập'),
    'demo',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Application Password'),
    _appPassword,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppSettings.baseUrl = '';
  });

  testWidgets('App khởi động ở màn hình đăng nhập', (tester) async {
    await tester.pumpWidget(const MyPhamKimCuongApp());

    expect(find.text('Mỹ Phẩm Kim Cương'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
  });

  testWidgets('Đăng nhập thành côông mở màn hình chính', (tester) async {
    final session = AuthSession();
    AppSettings.baseUrl = 'https://demo.local';

    await tester.pumpWidget(
      MyPhamKimCuongApp(authSession: session, apiClient: _okClient()),
    );
    await _signIn(tester);

    expect(session.isSignedIn, isTrue);
    expect(find.text('Bảng điều khiển'), findsOneWidget);
  });

  testWidgets('Điều hướng giữa Sản phẩm, Đơn hàng và POS', (tester) async {
    final session = AuthSession();
    AppSettings.baseUrl = 'https://demo.local';

    await tester.pumpWidget(
      MyPhamKimCuongApp(authSession: session, apiClient: _okClient()),
    );
    await _signIn(tester);

    await tester.tap(find.text('Sản phẩm'));
    await tester.pumpAndSettle();
    expect(find.text('Danh sách sản phẩm'), findsOneWidget);

    await tester.tap(find.text('Đơn hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng'), findsWidgets);

    await tester.tap(find.text('POS'));
    await tester.pumpAndSettle();
    expect(find.text('Màn hình POS'), findsOneWidget);
  });

  testWidgets('Đăng xuất xoá thông tin trong bộ nhớ', (tester) async {
    final session = AuthSession();
    AppSettings.baseUrl = 'https://demo.local';

    await tester.pumpWidget(
      MyPhamKimCuongApp(authSession: session, apiClient: _okClient()),
    );
    await _signIn(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(session.isSignedIn, isFalse);
    expect(find.text('Đã đăng xuất'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('Cài đặt lưu base URL', (tester) async {
    final session = AuthSession();
    AppSettings.baseUrl = 'https://demo.local';

    await tester.pumpWidget(
      MyPhamKimCuongApp(authSession: session, apiClient: _okClient()),
    );
    await _signIn(tester);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Địa chỉ website (Base URL)'),
      'https://demo.local',
    );
    await tester.tap(find.text('Lưu cài đặt'));
    await tester.pump();

    expect(AppSettings.baseUrl, 'https://demo.local');
  });
}
