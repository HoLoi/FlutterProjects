import 'api_value.dart';
import 'order.dart';

/// Phương thức thanh toán được server cho phép.
///
/// Whitelist này phải khớp `allowed_payment_methods()` trong
/// `includes/class-pos.php` (`cash`, `bacs`, `vietqr`). Server tự loại các
/// phương thức khác, app chỉ cần gửi đúng slug.
enum PosPaymentMethod {
  cash('cash', 'Tiền mặt'),
  bacs('bacs', 'Chuyển khoản'),
  vietqr('vietqr', 'VietQR');

  const PosPaymentMethod(this.wire, this.label);

  /// Slug gửi lên `POST /wp-json/kc/v1/pos/sales`.
  final String wire;

  /// Nhãn tiếng Việt cho UI.
  final String label;

  /// Slug không nằm trong whitelist thì về mặc định an toàn nhất.
  static PosPaymentMethod fromWire(String? wire) {
    for (final method in values) {
      if (method.wire == wire) {
        return method;
      }
    }
    return PosPaymentMethod.cash;
  }
}

/// Một dòng sản phẩm gửi lên server.
///
/// **Không có trường giá**: server tự lấy giá hiện tại trong WooCommerce và tự
/// kiểm tra tồn kho, nên client không được gửi `price`/`subtotal`/`total`.
///
/// JSON thật:
/// ```json
/// { "product_id": 651, "variation_id": 0, "quantity": 1 }
/// ```
class PosSaleItemRequest {
  const PosSaleItemRequest({
    required this.productId,
    this.variationId = 0,
    required this.quantity,
  });

  final int productId;

  /// `0` nghĩa là bán chính sản phẩm (sản phẩm simple). Sản phẩm variable bắt
  /// buộc phải có `variation_id > 0`, nếu không server trả `kc_invalid_variation`.
  final int variationId;

  final int quantity;

  Map<String, Object> toJson() {
    return {
      'product_id': productId,
      'variation_id': variationId,
      'quantity': quantity,
    };
  }
}

/// Một dòng trong `order.line_items` mà server trả về sau khi bán.
class PosSaleLineItem {
  const PosSaleLineItem({
    required this.id,
    required this.productId,
    required this.variationId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.total,
    this.sku,
    this.imageUrl,
  });

  final int id;
  final int productId;
  final int variationId;
  final String name;
  final String? sku;
  final double quantity;
  final double price;
  final double subtotal;
  final double total;

  /// Ảnh sản phẩm. Variation chưa có ảnh thì server đã fallback sang ảnh sản
  /// phẩm cha; `null` khi sản phẩm không có ảnh.
  final String? imageUrl;

  bool get hasVariation => variationId > 0;
}

/// Phần `order` trong response của `POST /pos/sales`.
///
/// Đây là payload tối thiểu do server tự dựng, không phải `GET /orders/{id}`.
class PosSaleOrder {
  const PosSaleOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.createdVia,
    required this.paymentMethod,
    required this.currency,
    required this.total,
    required this.requestId,
    required this.lineItems,
  });

  final int id;

  /// Mã đơn hiển thị cho thu ngân, ví dụ `675`.
  final String number;

  final OrderStatus status;
  final String createdVia;

  /// Gateway thực sự dùng. Khi yêu cầu `vietqr` mà site chưa bật gateway đó,
  /// server dùng `bacs` nên giá trị này có thể khác phương thức đã chọn.
  final String paymentMethod;

  final String currency;
  final double total;

  /// `request_id` mà server lưu lại; giống khoá app gửi lên.
  final String requestId;

  final List<PosSaleLineItem> lineItems;
}

/// Kết quả thanh toán thành công.
class PosSaleResult {
  const PosSaleResult({
    required this.success,
    required this.replayed,
    required this.order,
  });

  final bool success;

  /// `true` nghĩa là server trả lại đơn đã tạo từ request trước cùng
  /// `request_id` (idempotency), **không** phải đơn vừa tạo.
  final bool replayed;

  final PosSaleOrder order;
}

/// Đọc JSON trả về của `POST /wp-json/kc/v1/pos/sales`.
///
/// JSON thật đã kiểm tra trên production:
/// ```json
/// {
///   "success": true,
///   "replayed": false,
///   "order": {
///     "id": 675, "number": "675", "status": "on-hold",
///     "created_via": "kc_pos", "payment_method": "bacs",
///     "currency": "VND", "total": 189000,
///     "request_id": "pos-1-1",
///     "line_items": [
///       { "id": 12, "product_id": 651, "variation_id": 0,
///         "name": "Son Kem", "sku": "KC-0001", "quantity": 1,
///         "price": 189000, "subtotal": 189000, "total": 189000,
///         "image_url": "https://.../son.jpg" }
///     ]
///   }
/// }
/// ```
class PosSaleParser {
  const PosSaleParser._();

  /// Tham số [json] là `order` đã tách riêng, không phải cả envelope.
  static PosSaleOrder order(Map<String, dynamic> json) {
    return PosSaleOrder(
      id: ApiValue.integerOrZero(json['id']),
      number: ApiValue.textOrEmpty(json['number']),
      status: _status(json['status']),
      createdVia: ApiValue.textOrEmpty(json['created_via']),
      paymentMethod: ApiValue.textOrEmpty(json['payment_method']),
      currency: ApiValue.textOrEmpty(json['currency']),
      total: ApiValue.numberOrZero(json['total']),
      requestId: ApiValue.textOrEmpty(json['request_id']),
      lineItems: _lineItems(json['line_items']),
    );
  }

  static PosSaleResult fromEnvelope(Map<String, dynamic> json) {
    final orderJson = ApiValue.object(json['order']);
    if (orderJson == null) {
      throw const FormatException('Thiếu dữ liệu đơn POS');
    }
    return PosSaleResult(
      success: json['success'] == true,
      replayed: json['replayed'] == true,
      order: order(orderJson),
    );
  }

  static List<PosSaleLineItem> _lineItems(Object? raw) {
    return ApiValue.objectList(raw).map(_lineItem).toList(growable: false);
  }

  static PosSaleLineItem _lineItem(Map<String, dynamic> json) {
    return PosSaleLineItem(
      id: ApiValue.integerOrZero(json['id']),
      productId: ApiValue.integerOrZero(json['product_id']),
      variationId: ApiValue.integerOrZero(json['variation_id']),
      name: ApiValue.textOrEmpty(json['name']),
      sku: ApiValue.text(json['sku']),
      quantity: ApiValue.numberOrZero(json['quantity']),
      price: ApiValue.numberOrZero(json['price']),
      subtotal: ApiValue.numberOrZero(json['subtotal']),
      total: ApiValue.numberOrZero(json['total']),
      imageUrl: ApiValue.text(json['image_url']),
    );
  }

  static OrderStatus _status(Object? raw) {
    final wire = ApiValue.text(raw);
    for (final status in OrderStatus.values) {
      if (status.wire == wire) {
        return status;
      }
    }
    return OrderStatus.unknown;
  }
}
