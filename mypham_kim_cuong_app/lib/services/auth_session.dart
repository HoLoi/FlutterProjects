import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Tạo header `Authorization: Basic base64(username:application-password)`.
///
/// Application Password của WordPress dùng đúng cơ chế HTTP Basic nên
/// không cần token riêng, refresh token hay bảng user riêng.
@immutable
class BasicAuthHeader {
  const BasicAuthHeader._();

  /// Trả về giá trị header, hoặc null nếu thiếu thông tin đăng nhập.
  ///
  /// Không ghi log, không throw: mật khẩu chỉ tồn tại trong giá trị trả về
  /// và chỉ được dùng để tạo request.
  static String? build(String? username, String? appPassword) {
    final user = username?.trim() ?? '';
    if (user.isEmpty) {
      return null;
    }
    if (appPassword == null || appPassword.isEmpty) {
      return null;
    }
    final encoded = base64Encode(utf8.encode('$user:$appPassword'));
    return 'Basic $encoded';
  }
}

/// Thông tin đăng nhập của phiên hiện tại, chỉ nằm trong bộ nhớ.
///
/// MVP-12 không lưu xuống đĩa: tắt app là mất, không có secret nào nằm trong
/// SharedPreferences hay file. Mật khẩu không có getter để UI không vô tình
/// hiển thị, và `toString()` cố tình không chứa cả mật khẩu lẫn tên đăng nhập
/// để không rò thông tin nếu object bị in ra log.
class AuthSession extends ChangeNotifier {
  AuthSession();

  String _username = '';
  String _appPassword = '';

  bool get isSignedIn => _username.isNotEmpty && _appPassword.isNotEmpty;

  /// Chỉ trả về tên đăng nhập. Không có getter cho application password.
  String get username => _username;

  /// Header cho các request cần xác thực, null khi chưa đăng nhập.
  String? get authorizationHeader =>
      BasicAuthHeader.build(_username, _appPassword);

  void signIn({required String username, required String appPassword}) {
    _username = username.trim();
    _appPassword = appPassword;
    notifyListeners();
  }

  void signOut() {
    _username = '';
    _appPassword = '';
    notifyListeners();
  }

  @override
  String toString() => 'AuthSession(isSignedIn: $isSignedIn)';
}
