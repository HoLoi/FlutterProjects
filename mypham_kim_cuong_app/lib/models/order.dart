enum OrderStatus {
  pending('Chờ xử lý'),
  processing('Đang xử lý'),
  onHold('Chờ thanh toán'),
  completed('Hoàn tất'),
  cancelled('Đã huỷ'),
  refunded('Đã hoàn'),
  failed('Thất bại'),
  unknown('Không rõ');

  const OrderStatus(this.label);

  final String label;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.subtotal,
    this.sku = '',
  });

  final int id;
  final String name;
  final double quantity;
  final double price;
  final double subtotal;
  final String sku;
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    this.statusLabel = '',
    this.createdAt = '',
    this.customerName = '',
    this.customerPhone = '',
    this.itemsCount = 0,
    this.paymentMethod = '',
    this.paymentMethodLabel = '',
    this.subtotal = 0,
    this.discountTotal = 0,
    this.shippingTotal = 0,
    this.notes = '',
    this.items = const [],
  });

  final int id;
  final String number;
  final OrderStatus status;
  final String statusLabel;
  final String createdAt;
  final String customerName;
  final String customerPhone;
  final int itemsCount;
  final double total;
  final String paymentMethod;
  final String paymentMethodLabel;
  final double subtotal;
  final double discountTotal;
  final double shippingTotal;
  final String notes;
  final List<OrderItem> items;

  String get statusText => statusLabel.isNotEmpty ? statusLabel : status.label;

  String get customerLabel =>
      customerName.isNotEmpty ? customerName : 'Khách lẻ (chưa có tên)';
}

class ApiOrderParser {
  static Order fromJson(Map<String, dynamic> json) {
    return Order(
      id: (json['id'] as num?)?.toInt() ?? 0,
      number: json['number']?.toString() ?? '',
      status: _status(json['status']?.toString() ?? ''),
      statusLabel: json['status_label']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method']?.toString() ?? '',
      paymentMethodLabel: json['payment_method_label']?.toString() ?? '',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
      shippingTotal: (json['shipping_total'] as num?)?.toDouble() ?? 0,
      notes: json['notes']?.toString() ?? '',
      items: _items(json['items']),
    );
  }

  static List<OrderItem> _items(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => OrderItem(
            id: (item['id'] as num?)?.toInt() ?? 0,
            name: item['name']?.toString() ?? 'Sản phẩm chưa có tên',
            sku: item['sku']?.toString() ?? '',
            quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
            price: (item['price'] as num?)?.toDouble() ?? 0,
            subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  static OrderStatus _status(String raw) {
    switch (raw) {
      case 'pending':
        return OrderStatus.pending;
      case 'processing':
        return OrderStatus.processing;
      case 'on-hold':
        return OrderStatus.onHold;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'refunded':
        return OrderStatus.refunded;
      case 'failed':
        return OrderStatus.failed;
      default:
        return OrderStatus.unknown;
    }
  }
}
