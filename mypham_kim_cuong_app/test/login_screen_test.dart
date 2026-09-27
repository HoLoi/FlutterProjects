import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/screens/login_screen.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

const String _appPassword = 'abcd efgh ijkl mnop';

Widget _app(AuthSession session, ApiClient client) {
  return MaterialApp(
    home: LoginScreen(authSession: session, apiClient: client),
  );
}

ApiClient _clientReturning(int status, {Object? body}) {
  return ApiClient(
    httpClient: MockClient((_) async {
      final payload = body ?? <String, dynamic>{};
      return http.Response(
        jsonEncode(payload),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

ApiClient _failingClient() {
  return ApiClient(
    httpClient: MockClient((_) async {
      throw http.ClientException('Connection refused');
    }),
  );
}

Future<void> _fillCredentials(
  WidgetTester tester, {
  String username = 'demo',
  String password = _appPassword,
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Tên đăng nhập'),
    username,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Application Password'),
    password,
  );
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  testWidgets('Đăng nhập thành công lưu session trong bộ nhớ', (tester) async {
    final session = AuthSession();

    await tester.pumpWidget(
      _app(
        session,
        _clientReturning(
          200,
          body: {'wc_active': true, 'count': 0, 'data': []},
        ),
      ),
    );
    await _fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(session.isSignedIn, isTrue);
    expect(session.username, 'demo');
    expect(find.text('Bảng điều khiển'), findsOneWidget);
  });

  testWidgets('Đăng nhập thất bại khi 401 và không lưu session', (
    tester,
  ) async {
    final session = AuthSession();

    await tester.pumpWidget(_app(session, _clientReturning(401)));
    await _fillCredentials(tester, password: 'sai-mat-khau');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(
      find.text('Thông tin đăng nhập không hợp lệ hoặc đã hết hạn'),
      findsOneWidget,
    );
    expect(session.isSignedIn, isFalse);
    expect(find.text('Bảng điều khiển'), findsNothing);
  });

  testWidgets('Đăng nhập thất bại khi 403 báo thiếu quyền', (tester) async {
    final session = AuthSession();

    await tester.pumpWidget(_app(session, _clientReturning(403)));
    await _fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Tài khoản không có quyền xem đơn hàng'), findsOneWidget);
    expect(session.isSignedIn, isFalse);
  });

  testWidgets('Lỗi mạng hiển thị thông báo kết nối', (tester) async {
    final session = AuthSession();

    await tester.pumpWidget(_app(session, _failingClient()));
    await _fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Không kết nối được máy chủ'), findsOneWidget);
    expect(session.isSignedIn, isFalse);
  });

  testWidgets('Bỏ trống thì không gọi API, hiện lỗi validate', (tester) async {
    final session = AuthSession();
    var called = false;
    final client = ApiClient(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );

    await tester.pumpWidget(_app(session, client));
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Vui lòng nhập tên đăng nhập'), findsOneWidget);
    expect(find.text('Vui lòng nhập Application Password'), findsOneWidget);
  });

  testWidgets('Bỏ qua đăng nhập vẫn vào được bảng điều khiển', (tester) async {
    final session = AuthSession();
    var called = false;
    final client = ApiClient(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );

    await tester.pumpWidget(_app(session, client));
    await tester.tap(find.text('Bỏ qua, dùng chế độ demo'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(session.isSignedIn, isFalse);
    expect(find.text('Bảng điều khiển'), findsOneWidget);
  });

  testWidgets('Application Password được hiển thị dạng che (obscureText)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(AuthSession(), _clientReturning(200, body: {})),
    );
    await _fillCredentials(tester);
    await tester.pump();

    // Ô mật khẩu phải ẩn ký tự, nên mật khẩu không bị render ra màn hình.
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Application Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.obscureText, isTrue);
  });

  testWidgets('Application Password bị xoá khỏi ô nhập sau khi đăng nhập', (
    tester,
  ) async {
    final session = AuthSession();

    await tester.pumpWidget(
      _app(
        session,
        _clientReturning(
          200,
          body: {'wc_active': true, 'count': 0, 'data': []},
        ),
      ),
    );
    await _fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(session.isSignedIn, isTrue);
    expect(find.text(_appPassword), findsNothing);
  });
}
