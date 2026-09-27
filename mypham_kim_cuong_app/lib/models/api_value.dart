/// Đọc giá trị từ JSON của API `kc/v1` một cách an toàn.
///
/// Plugin PHP dùng `text_or_null()` nên **chuỗi rỗng trở thành `null`**, và
/// mọi số đều được ép sang JSON number. Tuy nhiên các helper ở đây vẫn chấp nhận
/// cả hai dạng (number và string) để không vỡ nếu WooCommerce đổi cách Serialize
/// giá trị. Mọi parser trong app đều đi qua đây để xử lý null thống nhất.
class ApiValue {
  const ApiValue._();

  /// Chuỗi đã trim, rỗng hoặc `null` thành `null`.
  static String? text(Object? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw is String ? raw.trim() : raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  /// Chuỗi đã trim, rỗng hoặc `null` thành chuỗi rỗng.
  static String textOrEmpty(Object? raw) => text(raw) ?? '';

  /// Số thực, `null` hoặc không đọc được thành `null`.
  ///
  /// Chấp nhận `190000`, `"190000.00"` và `"190.000,00"` không được hỗ trợ vì
  /// API luôn trả JSON number hoặc chuỗi dấu chấm thập phân kiểu WooCommerce.
  static double? number(Object? raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw.trim());
    }
    return null;
  }

  /// Số thực, `null` hoặc không đọc được thành `0`.
  static double numberOrZero(Object? raw) => number(raw) ?? 0;

  /// Số nguyên, `null` hoặc không đọc được thành `null`.
  ///
  /// Giữ `null` thay vì ép về 0 để phân biệt "không quản lý tồn kho"
  /// (`stock_quantity`) với "tồn kho bằng 0".
  static int? integer(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim()) ??
          double.tryParse(raw.trim())?.toInt();
    }
    return null;
  }

  /// Số nguyên, `null` hoặc không đọc được thành `0`.
  static int integerOrZero(Object? raw) => integer(raw) ?? 0;

  /// Đọc một object con; trả `null` nếu không phải object.
  static Map<String, dynamic>? object(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  /// Đọc một mảng object; trả `const []` nếu không phải mảng.
  static List<Map<String, dynamic>> objectList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .map(object)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
}
