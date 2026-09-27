import 'package:flutter/material.dart';

import '../data/api_order_repository.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../widgets/product_image_box.dart';

/// Chi tiết đơn hàng, đọc từ `GET /wp-json/kc/v1/orders/{id}` (read-only).
///
/// Màn hình này chỉ hiển thị. Không có nút tạo, sửa, thanh toán hay hoàn đơn.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.apiRepository,
  });

  final int orderId;
  final ApiOrderRepository? apiRepository;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final ApiOrderRepository _apiRepository;
  Order? _order;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiRepository = widget.apiRepository ?? ApiOrderRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await _apiRepository.fetchDetail(widget.orderId);
      if (!mounted) {
        return;
      }
      setState(() {
        _order = order;
        _loading = false;
      });
    } on ApiOrderException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _order = null;
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Đơn #${widget.orderId}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Quay lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final order = _order;
    if (order == null) {
      return const Center(child: Text('Không có dữ liệu đơn hàng'));
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(theme, order),
        const SizedBox(height: 12),
        _customerCard(theme, order),
        if (!order.billing.isEmpty || !order.shipping.isEmpty) ...[
          const SizedBox(height: 12),
          _addressCard(theme, order),
        ],
        const SizedBox(height: 12),
        _itemsSection(theme, order),
        _totalsCard(theme, order),
        if (order.customerNote != null) ...[
          const SizedBox(height: 12),
          _sectionTitle(theme, 'Ghi chú của khách'),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(order.customerNote!),
            ),
          ),
        ],
        if (order.createdVia != null) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _row(theme, 'Kênh đặt hàng', _createdViaLabel(order)),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _summaryCard(ThemeData theme, Order order) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#${order.number}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  order.statusText,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // date_created có thể null với đơn nhập tay trong wp-admin.
            if (order.dateCreated != null)
              _row(theme, 'Ngày tạo', order.dateCreated!),
            // date_paid = null nghĩa là chưa thanh toán.
            _row(
              theme,
              'Ngày thanh toán',
              order.datePaid ?? 'Chưa thanh toán',
            ),
            _row(
              theme,
              'Phương thức',
              order.paymentMethodLabel ?? order.paymentMethod ?? 'Chưa có',
            ),
            _row(theme, 'Trạng thái thanh toán', order.paymentStatus.label),
            if (order.currency.isNotEmpty)
              _row(theme, 'Tiền tệ', order.currency),
          ],
        ),
      ),
    );
  }

  Widget _customerCard(ThemeData theme, Order order) {
    final customer = order.customer;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Khách hàng',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                _guestBadge(theme, customer),
              ],
            ),
            const SizedBox(height: 8),
            _row(theme, 'Tên', customer.nameLabel),
            // phone có thể null khi khách không nhập số điện thoại.
            _row(theme, 'Điện thoại', customer.phone ?? 'Không có'),
            _row(theme, 'Email', customer.email ?? 'Không có'),
            if (customer.id > 0)
              _row(theme, 'Tài khoản', '#${customer.id}'),
          ],
        ),
      ),
    );
  }

  Widget _guestBadge(ThemeData theme, OrderCustomer customer) {
    final (background, foreground) = customer.isGuest
        ? (const Color(0xFFFFF3E0), const Color(0xFFEF6C00))
        : (const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        customer.isGuest ? 'Khách lẻ' : 'Tài khoản',
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _addressCard(ThemeData theme, Order order) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Địa chỉ',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (!order.billing.isEmpty) ...[
              Text('Thanh toán', style: theme.textTheme.bodySmall),
              Text(
                order.billing.fullName.isEmpty
                    ? order.billing.addressLabel
                    : '${order.billing.fullName}\n${order.billing.addressLabel}',
                style: theme.textTheme.bodyMedium,
              ),
              if (order.billing.phone != null)
                Text(
                  order.billing.phone!,
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
            ],
            if (!order.shipping.isEmpty) ...[
              Text('Giao hàng', style: theme.textTheme.bodySmall),
              Text(
                order.shipping.fullName.isEmpty
                    ? order.shipping.addressLabel
                    : '${order.shipping.fullName}\n${order.shipping.addressLabel}',
                style: theme.textTheme.bodyMedium,
              ),
              if (order.shipping.phone != null)
                Text(
                  order.shipping.phone!,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemsSection(ThemeData theme, Order order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, 'Sản phẩm (${order.items.length})'),
        const SizedBox(height: 8),
        if (order.items.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Đơn hàng không có sản phẩm.'),
            ),
          )
        else
          ...order.items.map((item) => _ItemTile(item: item)),
      ],
    );
  }

  Widget _totalsCard(ThemeData theme, Order order) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng tiền',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // Các tổng chi tiết chỉ có ở GET /orders/{id}.
            _row(theme, 'Tạm tính', formatPrice(order.subtotal)),
            if (order.discountTotal > 0)
              _row(theme, 'Giảm giá', '-${formatPrice(order.discountTotal)}'),
            if (order.shippingTotal > 0)
              _row(theme, 'Phí vận chuyển', formatPrice(order.shippingTotal)),
            if (order.feeTotal > 0)
              _row(theme, 'Phí khác', formatPrice(order.feeTotal)),
            if (order.refundedTotal > 0)
              _row(theme, 'Đã hoàn', '-${formatPrice(order.refundedTotal)}'),
            const Divider(height: 16),
            _row(theme, 'Tổng cộng', formatPrice(order.total), bold: true),
          ],
        ),
      ),
    );
  }

  static String _createdViaLabel(Order order) {
    final createdVia = order.createdVia;
    if (createdVia == null) {
      return '';
    }
    return switch (createdVia) {
      'checkout' => 'Trang thanh toán',
      'pos' => 'Cửa hàng (POS)',
      'admin' => 'Quản trị',
      final value => value,
    };
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _row(ThemeData theme, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: bold
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final OrderItem item;

  /// Khung ảnh cố định để card không nhảy khi ảnh tải hoặc lỗi.
  static const double _thumbSize = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ảnh sản phẩm: rỗng/lỗi thì tự hiện Icons.spa.
            ProductImageBox(imageUrl: item.imageUrl, size: _thumbSize),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nameLabel,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.hasVariation)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Biến thể',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                  // sku có thể null khi sản phẩm bị xoá hoặc không có SKU.
                  Text(
                    'SKU: ${item.sku ?? 'Chưa có SKU'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Số lượng: ${item.quantityLabel} · '
                    '${formatPrice(item.price)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPrice(item.total),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
