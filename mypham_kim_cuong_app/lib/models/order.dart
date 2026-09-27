import 'api_value.dart';

/// Trạng thái đơn hàng. Giá trị `wire` là slug gửi lên API `?status=`.
enum OrderStatus {
  pending('pending', 'Chờ xử lý'),
  processing('processing', 'Đang xử lý'),
  onHold('on-hold', 'Chờ thanh toán'),
  completed('completed', 'Hoàn tất'),
  cancelled('cancelled', 'Đã huỷ'),
  refunded('refunded', 'Đã hoàn'),
  failed('failed', 'Thất bại'),
  unknown('', 'Không rõ');

  const OrderStatus(this.wire, this.label);

  /// Slug API; rỗng với [OrderStatus.unknown] để không gửi tham số.
  final String wire;

  /// Nhãn tiếng Việt hiển thị trên UI.
  final String label;
}

/// Trạng thái thanh toán mà WooCommerce trả về.
enum PaymentStatus {
  paid('paid', 'Đã thanh toán'),
  unpaid('unpaid', 'Chưa thanh toán'),
  refunded('refunded', 'Đã hoàn tiền'),
  unknown('', 'Không rõ');

  const PaymentStatus(this.wire, this.label);

  final String wire;
  final String label;
}

/// Khách hàng của đơn hàng.
///
/// `GET /orders` trả `customer` là object, không phải hai trường phẳng:
/// `{ "id": 0, "is_guest": true, "name": ..., "phone": ..., "email": ... }`
class OrderCustomer {
  const OrderCustomer({
    this.id = 0,
    this.isGuest = true,
    this.name,
    this.phone,
    this.email,
  });

  final int id;

  /// `true` khi đơn đặt không cần tài khoản (`id` = 0).
  final bool isGuest;

  final String? name;
  final String? phone;
  final String? email;

  /// Tên hiển thị, có nhãn thay thế cho đơn guest chưa có tên.
  String get nameLabel => name ?? (isGuest ? 'Khách lẻ' : 'Khách hàng');
}

/// Địa chỉ `billing` hoặc `shipping`.
///
/// Mọi trường đều có thể `null`: WooCommerce chỉ lưu những gì khách nhập, và
/// `shipping.email` luôn `null` vì WooCommerce chỉ lưu email ở billing.
class OrderAddress {
  const OrderAddress({
    this.firstName,
    this.lastName,
    this.address1,
    this.address2,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.phone,
    this.email,
  });

  final String? firstName;
  final String? lastName;
  final String? address1;
  final String? address2;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  final String? phone;
  final String? email;

  /// Họ + tên, hoặc chuỗi rỗng nếu không có.
  String get fullName =>
      [firstName, lastName].whereType<String>().join(' ').trim();

  /// Địa chỉ nhiều dòng đã ghép, bỏ qua dòng rỗng.
  List<String> get lines => [
    if (address1 != null && address1!.isNotEmpty) address1!,
    if (address2 != null && address2!.isNotEmpty) address2!,
    if (city != null && city!.isNotEmpty) city!,
    if (state != null && state!.isNotEmpty) state!,
    if (country != null && country!.isNotEmpty) country!,
  ];

  String get addressLabel => lines.join(', ');

  /// Địa chỉ có ít nhất một trường đã điền hay không.
  bool get isEmpty =>
      fullName.isEmpty && lines.isEmpty && (phone ?? '').isEmpty;
}

/// Sản phẩm trong đơn hàng (`line_items`).
class OrderItem {
  const OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.total,
    required this.productId,
    this.variationId = 0,
    this.sku,
  });

  final int id;
  final String? name;

  /// `variation_id` = `0` nghĩa là sản phẩm đơn, không phải biến thể.
  final int variationId;
  final int productId;

  /// Có thể `null` khi sản phẩm đã bị xoá hoặc không có SKU.
  final String? sku;

  final double quantity;
  final double price;
  final double subtotal;
  final double total;

  bool get hasVariation => variationId > 0;

  String get nameLabel => name ?? 'Sản phẩm chưa có tên';

  /// Số lượng bỏ phần thập phân thừa khi là số nguyên.
  String get quantityLabel {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity.toString();
  }
}

/// Đơn hàng WooCommerce, đọc từ `GET /orders` và `GET /orders/{id}`.
class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.customer,
    required this.billing,
    required this.shipping,
    required this.items,
    this.statusLabel = '',
    this.dateCreated,
    this.datePaid,
    this.paymentMethod,
    this.paymentMethodLabel,
    this.paymentStatus = PaymentStatus.unknown,
    this.currency = '',
    this.customerNote,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.shippingTotal = 0,
    this.feeTotal = 0,
    this.refundedTotal = 0,
    this.createdVia,
  });

  final int id;
  final String number;
  final OrderStatus status;
  final String statusLabel;

  /// `date_created` theo giờ website, định dạng `YYYY-MM-DD HH:mm:ss`.
  final String? dateCreated;

  /// `null` khi đơn chưa thanh toán.
  final String? datePaid;

  final String? paymentMethod;
  final String? paymentMethodLabel;
  final PaymentStatus paymentStatus;
  final String currency;
  final double total;
  final OrderCustomer customer;
  final OrderAddress billing;
  final OrderAddress shipping;
  final List<OrderItem> items;

  /// `customer_note`: chỉ có trong `GET /orders/{id}`.
  final String? customerNote;

  /// Các tổng tiền chi tiết: chỉ có trong `GET /orders/{id}`.
  final double subtotal;
  final double discountTotal;
  final double shippingTotal;
  final double feeTotal;
  final double refundedTotal;
  final String? createdVia;

  /// Ưu tiên nhãn tiếng Việt từ API, fallback sang nhãn cục bộ.
  String get statusText => statusLabel.isNotEmpty ? statusLabel : status.label;

  /// Tên khách kèm nhãn rõ ràng cho đơn guest.
  String get customerLabel {
    final name = customer.name;
    if (name == null) {
      return customer.isGuest ? 'Khách lẻ (chưa có tên)' : 'Khách hàng (chưa có tên)';
    }
    return customer.isGuest ? '$name (khách lẻ)' : name;
  }

  /// Số sản phẩm. API `GET /orders` không có `items_count`, nên tính từ
  /// `line_items` (danh sách luôn có trong response).
  int get itemsCount => items.length;

  /// Tổng số lượng, dùng cho tiêu đề.
  double get totalQuantity =>
      items.fold<double>(0, (sum, item) => sum + item.quantity);

  bool get isRefunded => paymentStatus == PaymentStatus.refunded;

  /// Có thông tin chi tiết (chỉ `GET /orders/{id}` mới có) hay không.
  bool get hasDetailTotals => createdVia != null || customerNote != null;
}

/// Đọc JSON thật của `GET /orders` và `GET /orders/{id}`.
///
/// Danh sách và chi tiết dùng chung một shape; chi tiết chỉ bổ sung thêm
/// `wc_active`, `customer_note`, `subtotal`, `discount_total`, `shipping_total`,
/// `fee_total`, `refunded_total` và `created_via`. Vì vậy cùng một parser dùng
/// được cho cả hai, và các trường chỉ có ở chi tiết sẽ là giá trị mặc định khi
/// đọc từ danh sách.
class ApiOrderParser {
  static Order fromJson(Map<String, dynamic> json) {
    return Order(
      id: ApiValue.integerOrZero(json['id']),
      number: ApiValue.textOrEmpty(json['number']),
      status: _status(json['status']),
      statusLabel: ApiValue.textOrEmpty(json['status_label']),
      dateCreated: ApiValue.text(json['date_created']),
      datePaid: ApiValue.text(json['date_paid']),
      paymentMethod: ApiValue.text(json['payment_method']),
      paymentMethodLabel: ApiValue.text(json['payment_method_label']),
      paymentStatus: _paymentStatus(json['payment_status']),
      currency: ApiValue.textOrEmpty(json['currency']),
      total: ApiValue.numberOrZero(json['total']),
      customer: _customer(json['customer']),
      billing: _address(json['billing']),
      shipping: _address(json['shipping']),
      items: _items(json['line_items']),
      customerNote: ApiValue.text(json['customer_note']),
      subtotal: ApiValue.numberOrZero(json['subtotal']),
      discountTotal: ApiValue.numberOrZero(json['discount_total']),
      shippingTotal: ApiValue.numberOrZero(json['shipping_total']),
      feeTotal: ApiValue.numberOrZero(json['fee_total']),
      refundedTotal: ApiValue.numberOrZero(json['refunded_total']),
      createdVia: ApiValue.text(json['created_via']),
    );
  }

  static OrderStatus _status(Object? raw) {
    return switch (ApiValue.textOrEmpty(raw)) {
      'pending' => OrderStatus.pending,
      'processing' => OrderStatus.processing,
      'on-hold' => OrderStatus.onHold,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      'refunded' => OrderStatus.refunded,
      'failed' => OrderStatus.failed,
      _ => OrderStatus.unknown,
    };
  }

  static PaymentStatus _paymentStatus(Object? raw) {
    return switch (ApiValue.textOrEmpty(raw)) {
      'paid' => PaymentStatus.paid,
      'unpaid' => PaymentStatus.unpaid,
      'refunded' => PaymentStatus.refunded,
      _ => PaymentStatus.unknown,
    };
  }

  static OrderCustomer _customer(Object? raw) {
    final customer = ApiValue.object(raw);
    if (customer == null) {
      return const OrderCustomer();
    }
    // `is_guest` luôn khớp với `id == 0`; nếu thiếu thì suy ra từ `id`.
    final id = ApiValue.integerOrZero(customer['id']);
    return OrderCustomer(
      id: id,
      isGuest: customer['is_guest'] is bool
          ? customer['is_guest']! as bool
          : id == 0,
      name: ApiValue.text(customer['name']),
      phone: ApiValue.text(customer['phone']),
      email: ApiValue.text(customer['email']),
    );
  }

  static OrderAddress _address(Object? raw) {
    final address = ApiValue.object(raw);
    if (address == null) {
      return const OrderAddress();
    }
    return OrderAddress(
      firstName: ApiValue.text(address['first_name']),
      lastName: ApiValue.text(address['last_name']),
      address1: ApiValue.text(address['address_1']),
      address2: ApiValue.text(address['address_2']),
      city: ApiValue.text(address['city']),
      state: ApiValue.text(address['state']),
      postcode: ApiValue.text(address['postcode']),
      country: ApiValue.text(address['country']),
      phone: ApiValue.text(address['phone']),
      email: ApiValue.text(address['email']),
    );
  }

  static List<OrderItem> _items(Object? raw) {
    return ApiValue.objectList(raw)
        .map(
          (item) => OrderItem(
            id: ApiValue.integerOrZero(item['id']),
            name: ApiValue.text(item['name']),
            productId: ApiValue.integerOrZero(item['product_id']),
            variationId: ApiValue.integerOrZero(item['variation_id']),
            sku: ApiValue.text(item['sku']),
            quantity: ApiValue.numberOrZero(item['quantity']),
            price: ApiValue.numberOrZero(item['price']),
            subtotal: ApiValue.numberOrZero(item['subtotal']),
            total: ApiValue.numberOrZero(item['total']),
          ),
        )
        .toList(growable: false);
  }
}
