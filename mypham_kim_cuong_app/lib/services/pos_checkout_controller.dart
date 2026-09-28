import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/pos_sale_repository.dart';
import '../models/cart_item.dart';
import '../models/pos_sale.dart';

/// Sinh `request_id` cho mỗi lần thanh toán.
///
/// Server chấp nhận `^[A-Za-z0-9._:-]{1,64}$` nên chỉ dùng ký tự an toàn.
/// Dùng `Random.secure()` vì đây là khoá chống tạo đơn trùng, không phải bí mật,
/// nhưng cũng không cần thiết phải đoán được.
class PosRequestId {
  const PosRequestId._();

  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const int _randomLength = 8;

  /// Ví dụ `pos-1780123456789-a1b2c3d4` (26 ký tự, dưới giới hạn 64).
  static String generate({Random? random, DateTime? now}) {
    final source = random ?? Random.secure();
    final suffix = List.generate(
      _randomLength,
      (_) => _alphabet[source.nextInt(_alphabet.length)],
    ).join();
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return 'pos-$stamp-$suffix';
  }

  /// Có đúng định dạng server chấp nhận không.
  static bool isValid(String value) {
    return RegExp(r'^[A-Za-z0-9._:-]{1,64}$').hasMatch(value);
  }
}

/// Điều khiển một lần thanh toán POS.
///
/// Giữ `request_id` xuyên suốt các lần gửi lại: nếu app không chắc đơn đã
/// tạo hay chưa (lỗi mạng, 500) thì phải gửi lại **cùng** khoá để server
/// trả về đúng đơn cũ. Sinh khoá mới ở lần gửi lại sẽ tạo đơn trùng.
///
/// `request_id` bị huỷ khi giỏ hàng thay đổi: nếu người bán sửa giỏ rồi gửi
/// lại, nội dung đơn đã khác nên khoá cũ không còn ý nghĩa.
class PosCheckoutController extends ChangeNotifier {
  PosCheckoutController({this.random, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Nguồn ngẫu nhiên để test được khoá idempotency một cách tất định.
  final Random? random;
  final DateTime Function() _clock;

  bool _isSubmitting = false;
  String? _pendingRequestId;
  String? _pendingSignature;
  PosSaleResult? _lastResult;
  PosSaleException? _lastError;

  /// Đang gọi API: UI phải khoá nút thanh toán để không bấm hai lần.
  bool get isSubmitting => _isSubmitting;

  /// Đơn đã tạo thành công, giữ lại để UI hiển thị mã đơn.
  PosSaleResult? get lastResult => _lastResult;

  PosSaleException? get lastError => _lastError;

  /// Khoá đang dùng cho lần bán chưa hoàn tất.
  String? get pendingRequestId => _pendingRequestId;

  /// Đã có một lần gửi thất bại nhưng server chưa chắc là chưa tạo đơn.
  bool get canRetry =>
      !_isSubmitting &&
      _pendingRequestId != null &&
      (_lastError?.canRetryWithSameRequestId ?? false);

  /// Gửi giỏ hàng lên server.
  ///
  /// Trả `true` khi server trả 201 hoặc 200 hợp lệ. Giỏ hàng **không** bị xoá
  /// ở đây: chỉ UI mới xoá, và chỉ sau khi nhận `true`, để lần gửi lại vẫn còn
  /// hàng để bán.
  Future<bool> submit({
    required PosSaleRepository repository,
    required List<CartItem> items,
    required String paymentMethod,
    int customerId = 0,
    String customerNote = '',
  }) async {
    if (_isSubmitting || items.isEmpty) {
      return false;
    }

    final signature = _signatureOf(items);

    if (_pendingSignature != signature || _pendingRequestId == null) {
      _pendingRequestId = PosRequestId.generate(
        random: random,
        now: _clock(),
      );
      _pendingSignature = signature;
    }

    final requestId = _pendingRequestId!;
    _isSubmitting = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await repository.createPosSale(
        requestId: requestId,
        paymentMethod: paymentMethod,
        customerId: customerId,
        items: [
          for (final item in items)
            PosSaleItemRequest(
              productId: item.product.id,
              variationId: item.variationId,
              quantity: item.quantity,
            ),
        ],
        customerNote: customerNote,
      );

      _lastResult = result;
      _lastError = null;
      // Đã tạo xong: khoá cũ không dùng lại được nữa, lần bán sau cần khoá mới.
      _pendingRequestId = null;
      _pendingSignature = null;
      return true;
    } on PosSaleException catch (error) {
      // Giữ nguyên `requestId` để gửi lại cùng khoá.
      _lastError = error;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Xoá trạng thái sau khi UI đã hiển thị kết quả.
  void reset() {
    _lastResult = null;
    _lastError = null;
    _pendingRequestId = null;
    _pendingSignature = null;
    notifyListeners();
  }

  /// Dấu vết của nội dung giỏ: đổi giỏ thì phải sinh `request_id` mới.
  static String _signatureOf(List<CartItem> items) {
    return items
        .map(
          (item) => '${item.product.id}:${item.variationId}x${item.quantity}',
        )
        .join('|');
  }
}
