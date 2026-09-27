import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/auth_session.dart';

const String _username = 'demo';
const String _appPassword = 'abcd efgh ijkl mnop';

/// Base64 của "demo:abcd efgh ijkl mnop".
const String _expectedBasic = 'Basic ZGVtbzphYmNkIGVmZ2ggaWprbCBtbm9w';

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

AuthSession _signedIn() {
  final session = AuthSession();
  session.signIn(username: _username, appPassword: _appPassword);
  return session;
}

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  group('BasicAuthHeader', () {
    test('tạo đúng header Basic base64(username:appPassword)', () {
      expect(BasicAuthHeader.build(_username, _appPassword), _expectedBasic);
    });

    test('bỏ khoảng trắng thừa ở username', () {
      expect(BasicAuthHeader.build('  demo  ', _appPassword), _expectedBasic);
    });

    test('thiếu username hoặc mật khẩu thì trả null', () {
      expect(BasicAuthHeader.build(null, _appPassword), isNull);
      expect(BasicAuthHeader.build('', _appPassword), isNull);
      expect(BasicAuthHeader.build('   ', _appPassword), isNull);
      expect(BasicAuthHeader.build(_username, null), isNull);
      expect(BasicAuthHeader.build(_username, ''), isNull);
    });
  });

  group('AuthSession', () {
    test('mặc định chưa đăng nhập và không có header', () {
      final session = AuthSession();

      expect(session.isSignedIn, isFalse);
      expect(session.authorizationHeader, isNull);
      expect(session.username, isEmpty);
    });

    test('đăng nhập lưu username trong bộ nhớ và tạo header', () {
      final session = _signedIn();

      expect(session.isSignedIn, isTrue);
      expect(session.username, _username);
      expect(session.authorizationHeader, _expectedBasic);
    });

    test('đăng xuất xoá thông tin đăng nhập trong bộ nhớ', () {
      final session = _signedIn();

      session.signOut();

      expect(session.isSignedIn, isFalse);
      expect(session.authorizationHeader, isNull);
      expect(session.username, isEmpty);
    });

    test('toString không lộ username, mật khẩu hay header', () {
      final session = _signedIn();

      final text = session.toString();

      expect(text, contains('isSignedIn: true'));
      expect(text, isNot(contains(_username)));
      expect(text, isNot(contains(_appPassword)));
      expect(text, isNot(contains('efgh')));
      expect(text, isNot(contains(_expectedBasic)));
    });

    test('báo cho listener biết khi đăng nhập và đăng xuất', () {
      final session = AuthSession();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.signIn(username: _username, appPassword: _appPassword);
      session.signOut();

      expect(notifications, 2);
    });
  });

  group('Header trên request', () {
    test('gọi orders có Authorization header', () async {
      String? authHeader;
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          expect(request.url.path, '/wp-json/kc/v1/orders');
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      await client.fetchOrders();

      expect(authHeader, _expectedBasic);
    });

    test('gọi chi tiết đơn có Authorization header', () async {
      String? authHeader;
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          return _jsonResponse({
            'wc_active': true,
            'id': 501,
            'number': '501',
            'status': 'pending',
            'total': 1000,
            'items': [],
          });
        }),
      );

      await client.fetchOrderDetail(501);

      expect(authHeader, _expectedBasic);
    });

    test('gọi products KHÔNG gửi Authorization header', () async {
      String? authHeader;
      var headerSeen = false;
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((request) async {
          headerSeen = true;
          authHeader = request.headers['Authorization'];
          return _jsonResponse({
            'wc_active': true,
            'count': 0,
            'data': <Map<String, dynamic>>[],
          });
        }),
      );

      await client.fetchProducts();

      expect(headerSeen, isTrue);
      expect(authHeader, isNull, reason: 'endpoint catalog vẫn public');
    });

    test('gọi health KHÔNG gửi Authorization header', () async {
      String? authHeader;
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          return _jsonResponse({'ok': true, 'plugin': 'test'});
        }),
      );

      await client.checkHealth();

      expect(authHeader, isNull);
    });

    test('gọi categories KHÔNG gửi Authorization header', () async {
      String? authHeader;
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      await client.fetchCategories();

      expect(authHeader, isNull);
    });

    test('không đăng nhập thì không gọi API orders', () async {
      var called = false;
      final client = ApiClient(
        authSession: AuthSession(),
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse({'wc_active': true, 'count': 0, 'data': []});
        }),
      );

      final result = await client.fetchOrders();

      expect(called, isFalse);
      expect(result.status, CatalogStatus.unauthorized);
      expect(result.message, AuthErrorMessages.notSignedIn);
    });

    test('không đăng nhập thì không gọi API chi tiết đơn', () async {
      var called = false;
      final client = ApiClient(
        authSession: AuthSession(),
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse({}, status: 200);
        }),
      );

      final result = await client.fetchOrderDetail(501);

      expect(called, isFalse);
      expect(result.status, OrderDetailStatus.unauthorized);
    });
  });

  group('HTTP 401 và 403', () {
    test('orders trả 401 thì báo đăng nhập không hợp lệ', () async {
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.unauthorized);
      expect(result.message, AuthErrorMessages.unauthorized);
    });

    test('orders trả 403 thì báo thiếu quyền', () async {
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((_) async => http.Response('', 403)),
      );

      final result = await client.fetchOrders();

      expect(result.status, CatalogStatus.forbidden);
      expect(result.message, AuthErrorMessages.forbidden);
    });

    test('chi tiết đơn trả 401 thì báo đăng nhập không hợp lệ', () async {
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      final result = await client.fetchOrderDetail(501);

      expect(result.status, OrderDetailStatus.unauthorized);
      expect(result.message, AuthErrorMessages.unauthorized);
    });

    test('chi tiết đơn trả 403 thì báo thiếu quyền', () async {
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((_) async => http.Response('', 403)),
      );

      final result = await client.fetchOrderDetail(501);

      expect(result.status, OrderDetailStatus.forbidden);
      expect(result.message, AuthErrorMessages.forbidden);
    });

    test('401 trên orders không bị coi như lỗi HTTP chung', () async {
      final client = ApiClient(
        authSession: _signedIn(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      final result = await client.fetchOrders();

      expect(result.status, isNot(CatalogStatus.httpError));
    });
  });

  group('verifyLogin', () {
    test('đăng nhập thành công khi server trả 200', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], _expectedBasic);
          expect(request.url.queryParameters['per_page'], '1');
          return _jsonResponse({'wc_active': true, 'count': 1, 'data': []});
        }),
      );

      final status = await client.verifyLogin(
        username: _username,
        appPassword: _appPassword,
      );

      expect(status.failed, isFalse);
      expect(status.message, isNull);
    });

    test('đăng nhập thất bại khi 401', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      final status = await client.verifyLogin(
        username: _username,
        appPassword: 'sai mat khau',
      );

      expect(status.failed, isTrue);
      expect(status.message, AuthErrorMessages.unauthorized);
    });

    test('đăng nhập thất bại khi 403', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 403)),
      );

      final status = await client.verifyLogin(
        username: _username,
        appPassword: _appPassword,
      );

      expect(status.failed, isTrue);
      expect(status.message, AuthErrorMessages.forbidden);
    });

    test('đăng nhập thất bại khi lỗi mạng', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );

      final status = await client.verifyLogin(
        username: _username,
        appPassword: _appPassword,
      );

      expect(status.failed, isTrue);
      expect(status.message, 'Không kết nối được máy chủ');
    });

    test('thiếu thông tin thì không gọi mạng', () async {
      var called = false;
      final client = ApiClient(
        httpClient: MockClient((_) async {
          called = true;
          return _jsonResponse({}, status: 200);
        }),
      );

      final status = await client.verifyLogin(username: '', appPassword: '');

      expect(called, isFalse);
      expect(status.failed, isTrue);
    });

    test('base URL rỗng thì báo URL chưa hợp lệ', () async {
      AppSettings.baseUrl = '';
      final client = ApiClient(
        httpClient: MockClient((_) async => _jsonResponse({}, status: 200)),
      );

      final status = await client.verifyLogin(
        username: _username,
        appPassword: _appPassword,
      );

      expect(status.failed, isTrue);
      expect(status.message, 'URL chưa hợp lệ');
    });
  });
}
