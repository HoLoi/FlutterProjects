/// Cấu hình đơn giản, chỉ lưu trong bộ nhớ.
class AppSettings {
  AppSettings._();

  static String baseUrl = '';

  static bool get hasBaseUrl => baseUrl.trim().isNotEmpty;
}