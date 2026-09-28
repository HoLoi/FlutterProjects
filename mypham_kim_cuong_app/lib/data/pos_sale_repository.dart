import '../models/pos_sale.dart';
import '../services/api_client.dart';

/// Thông điệp mặc định khi server không trả `message` tiếng Việt.
class PosSaleMessages {
  const PosSaleMessages._();

  static const String notSignedIn = 'Bạn cần đăng nhập để thanh toán';
  static const String forbidden = 'Tài khoản không có quyền bán hàng';
  static const String outOfStock = 'Một sản phẩm trong giỏ đã hết hàng';
  static const String invalidRequest = 'Giỏ hàng không hợp lệ, hãy kiểm tra lại';
  static const String serverError = 'Máy chủ không tạo được đơn, hãy thử lại';
  static const String saleInProgress =
      'Đơn cùng mã đang được tạo, hãy bấm Gửi lại sau ít giây';

  /// Thông báo cho từng trạng thái, dùng khi server không có message riêng.
  static String defaultFor(PosSaleStatus status) {
    switch (status) {
      case PosSaleStatus.notSignedIn:
        return notSignedIn;
      case PosSaleStatus.unauthorized:
        return 'Thông tin đăng nhập không hợp lệ hoặc đã hết hạn';
      case PosSaleStatus.forbidden:
        return forbidden;
      case PosSaleStatus.invalidRequest:
        return invalidRequest;
      case PosSaleStatus.outOfStock:
        return outOfStock;
      case PosSaleStatus.saleInProgress:
        return saleInProgress;
      case PosSaleStatus.serverError:
        return serverError;
      case PosSaleStatus.insecureUrl:
      case PosSaleStatus.invalidUrl:
        return 'URL chưa hợp lệ';
      case PosSaleStatus.networkError:
        return 'Không kết nối được máy chủ';
      case PosSaleStatus.httpError:
        return 'Máy chủ trả về lỗi không xác định';
      case PosSaleStatus.created:
      case PosSaleStatus.ok:
        return '';
    }
  }
}

/// Lỗi khi bán hàng thất bại.
///
/// Mang theo [status] để POS chọn cách phản hồi: mở màn hình đăng nhập khi
/// [PosSaleStatus.unauthorized], báo người bán khi hết hàng, hay cho gửi lại
/// cùng `request_id` khi lỗi mạng.
class PosSaleException implements Exception {
  const PosSaleException(this.status, {this.message = '', this.code});

  final PosSaleStatus status;

  /// Thông báo tiếng Việt đã sẵn sàng hiển thị.
  final String message;

  /// Mã lỗi gốc của WordPress, ví dụ `kc_out_of_stock`.
  final String? code;

  /// Đơn có thể đã tạo xong ngoài máy mà app chưa nhận được phản hồi.
  ///
  /// Trong trường hợp này phải gửi lại **cùng** `request_id`, không được sinh
  /// khoá mới, nếu không sẽ tạo đơn trùng.
  bool get canRetryWithSameRequestId =>
      status == PosSaleStatus.networkError ||
      status == PosSaleStatus.serverError ||
      status == PosSaleStatus.saleInProgress;

  @override
  String toString() => 'PosSaleException($status, $message)';
}

/// Gọi API bán hàng tại cửa hàng.
///
/// Giữ dạng abstract để POS test được bằng `MockClient` mà không cần chạm
/// mạng, giống cách `ProductRepository` tách mock khỏi API thật.
abstract class PosSaleRepository {
  /// Gửi một lần bán. Ném [PosSaleException] khi server không trả 201/200 hợp lệ.
  Future<PosSaleResult> createPosSale({
    required String requestId,
    required String paymentMethod,
    required int customerId,
    required List<PosSaleItemRequest> items,
    String customerNote = '',
  });
}

/// Cài đặt thật, gọi `POST /wp-json/kc/v1/pos/sales`.
///
/// Mật khẩu ứng dụng nằm trong [ApiClient]'s `AuthSession` và chỉ đọc qua
/// `authorizationHeader`; class này không giữ, không log, không ghi credential
/// ra bất kỳ đâu.
class ApiPosSaleRepository implements PosSaleRepository {
  ApiPosSaleRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  @override
  Future<PosSaleResult> createPosSale({
    required String requestId,
    required String paymentMethod,
    required int customerId,
    required List<PosSaleItemRequest> items,
    String customerNote = '',
  }) async {
    final response = await _apiClient.createPosSale(
      requestId: requestId,
      paymentMethod: paymentMethod,
      customerId: customerId,
      items: items,
      customerNote: customerNote,
    );

    if (!response.succeeded) {
      final serverMessage = response.message?.trim();
      throw PosSaleException(
        response.status,
        message:
            (serverMessage == null || serverMessage.isEmpty)
            ? PosSaleMessages.defaultFor(response.status)
            : serverMessage,
        code: response.code,
      );
    }

    final data = response.data;
    if (data == null) {
      throw const PosSaleException(
        PosSaleStatus.httpError,
        message: 'Máy chủ trả về lỗi không xác định',
      );
    }

    try {
      return PosSaleParser.fromEnvelope(data);
    } on FormatException {
      throw const PosSaleException(
        PosSaleStatus.httpError,
        message: 'Máy chủ trả về dữ liệu không đúng định dạng',
      );
    }
  }
}
