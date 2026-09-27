import 'package:flutter/material.dart';

import '../data/api_order_repository.dart';
import '../models/order.dart';
import '../models/product.dart';

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
        Card(
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
                _row(theme, 'Khách hàng', order.customerLabel),
                if (order.customerPhone.isNotEmpty)
                  _row(theme, 'Điện thoại', order.customerPhone),
                if (order.createdAt.isNotEmpty)
                  _row(theme, 'Ngày tạo', order.createdAt),
                if (order.paymentMethodLabel.isNotEmpty)
                  _row(theme, 'Thanh toán', order.paymentMethodLabel),
                _row(theme, 'Tổng cộng', formatPrice(order.total)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sản phẩm (${order.items.length})',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
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
        if (order.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Ghi chú',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(order.notes),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
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
              style: theme.textTheme.bodyMedium,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.sku.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('SKU: ${item.sku}', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 2),
                  Text('Số lượng: $quantity', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              formatPrice(item.subtotal),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
