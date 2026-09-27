import 'package:flutter/material.dart';

import '../data/api_order_repository.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../services/auth_session.dart';
import '../widgets/product_image_box.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({
    super.key,
    this.apiRepository,
    this.authSession,
    this.onRequireSignIn,
  });

  final ApiOrderRepository? apiRepository;
  final AuthSession? authSession;
  final VoidCallback? onRequireSignIn;

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  late final AuthSession _authSession;
  late final ApiOrderRepository _apiRepository;
  List<Order> _orders = const [];
  String? _error;
  bool _authError = false;
  bool _loading = false;
  String _query = '';
  OrderStatus? _filter;

  @override
  void initState() {
    super.initState();
    _authSession = widget.authSession ?? AuthSession();
    _apiRepository =
        widget.apiRepository ??
        ApiOrderRepository(authSession: widget.authSession);
    _authSession.addListener(_onAuthChanged);
    if (_authSession.isSignedIn) {
      _reload();
    }
  }

  @override
  void dispose() {
    _authSession.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) {
      return;
    }
    if (_authSession.isSignedIn) {
      _reload();
      return;
    }
    setState(() {
      _orders = const [];
      _error = null;
      _authError = false;
      _loading = false;
    });
  }

  List<Order> get _filteredOrders {
    final list = _orders;
    if (_filter == null) {
      return list;
    }
    return list.where((order) => order.status == _filter).toList();
  }

  Future<void> _reload() async {
    if (!_authSession.isSignedIn) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _authError = false;
    });
    try {
      final orders = await _apiRepository.fetchAll(
        search: _query.trim().isEmpty ? null : _query.trim(),
        // Lọc trạng thái do server xử lý, đúng tham số `?status=` của API.
        status: _filter?.wire,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } on ApiOrderException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _orders = const [];
        _error = error.message;
        _authError = error.unauthorized || error.forbidden;
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OrderDetailScreen(orderId: order.id, apiRepository: _apiRepository),
      ),
    );
    if (_authSession.isSignedIn) {
      await _reload();
    }
  }

  void _selectFilter(OrderStatus? status) {
    setState(() => _filter = status);
    _reload();
  }

  void _requireSignIn() {
    if (widget.onRequireSignIn != null) {
      widget.onRequireSignIn!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AuthErrorMessages.notSignedIn)),
    );
  }

  String get _countLabel {
    if (!_authSession.isSignedIn) {
      return 'Cần đăng nhập';
    }
    if (_loading) {
      return 'Đang tải...';
    }
    return '${_orders.length} đơn hàng';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredOrders;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Đơn hàng', style: theme.textTheme.titleLarge),
              Text(_countLabel, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          if (_authSession.isSignedIn)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(
                  _authSession.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Đang đọc đơn hàng thật từ WooCommerce (read-only)',
                ),
                trailing: IconButton(
                  tooltip: 'Tải lại',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _reload,
                ),
              ),
            ),
          if (_authSession.isSignedIn) const SizedBox(height: 12),
          if (!_authSession.isSignedIn)
            Expanded(child: _signInRequired(theme))
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: _errorState(theme))
          else ...[
            TextField(
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) => _reload(),
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên khách hoặc số đơn',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Tất cả',
                    selected: _filter == null,
                    onSelected: () => _selectFilter(null),
                  ),
                  // Bỏ `unknown`: không có slug để gửi lên API.
                  ...OrderStatus.values
                      .where((status) => status != OrderStatus.unknown)
                      .map(
                        (status) => _FilterChip(
                          label: status.label,
                          selected: _filter == status,
                          onSelected: () => _selectFilter(status),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? _emptyState(theme)
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final order = filtered[index];
                        return _OrderCard(
                          order: order,
                          onTap: () => _openDetail(order),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signInRequired(ThemeData theme) {
    return Center(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              const Text(
                AuthErrorMessages.notSignedIn,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Đơn hàng cần đăng nhập bằng tài khoản WordPress để bảo vệ dữ liệu.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _requireSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState(ThemeData theme) {
    return Center(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _authError ? Icons.lock_outline : Icons.cloud_off,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'Không đọc được đơn hàng',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _error ?? 'Lỗi không xác định',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (_authError)
                    FilledButton.tonalIcon(
                      onPressed: _requireSignIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Đăng nhập lại'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Tải lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('Chưa có đơn hàng'),
          const SizedBox(height: 4),
          const Text(
            'Thử điều chỉnh từ khóa hoặc bộ lọc',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  /// Khung ảnh nhỏ hơn chi tiết đơn vì card ở đây là ListTile một dòng.
  static const double _thumbSize = 40;

  /// Sản phẩm đầu tiên của đơn, `null` khi đơn không có sản phẩm.
  OrderItem? get _firstItem => order.items.isEmpty ? null : order.items.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstItem = _firstItem;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        // Ảnh sản phẩm đầu tiên trong đơn; thiếu ảnh thì tự hiện Icons.spa.
        leading: firstItem == null
            ? null
            : ProductImageBox(imageUrl: firstItem.imageUrl, size: _thumbSize),
        title: Row(
          children: [
            // Số đơn co lại được để badge trạng thái không đẩy ra ngoài khi
            // màn hình hẹp (ảnh leading đã chiếm 40px).
            Expanded(
              child: Text(
                '#${order.number}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Badge co lại được để màn hình hẹp không tràn dòng tiêu đề.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _statusBadge(theme, order.status),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(order.customerLabel, style: theme.textTheme.bodySmall),
            Text(
              // itemsCount tính từ line_items vì API không có items_count.
              '${order.itemsCount} sản phẩm'
              '${(order.paymentMethodLabel ?? '').isEmpty ? '' : ' · ${order.paymentMethodLabel}'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Text(
          formatPrice(order.total),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ThemeData theme, OrderStatus status) {
    final (background, foreground) = switch (status) {
      OrderStatus.completed => (
        const Color(0xFFE8F5E9),
        const Color(0xFF2E7D32),
      ),
      OrderStatus.processing => (
        const Color(0xFFE3F2FD),
        const Color(0xFF1565C0),
      ),
      OrderStatus.pending => (const Color(0xFFFFF3E0), const Color(0xFFEF6C00)),
      OrderStatus.onHold => (const Color(0xFFFFF8E1), const Color(0xFFF9A825)),
      OrderStatus.cancelled => (
        const Color(0xFFFFEBEE),
        const Color(0xFFC62828),
      ),
      OrderStatus.refunded => (
        const Color(0xFFECEFF1),
        const Color(0xFF546E7A),
      ),
      OrderStatus.failed => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      OrderStatus.unknown => (const Color(0xFFECEFF1), const Color(0xFF546E7A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
