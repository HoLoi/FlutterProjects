import 'package:flutter/material.dart';

import '../data/product_repository.dart';
import '../models/app_settings.dart';
import '../models/product.dart';
import '../services/cart_controller.dart';
import '../services/dashboard_summary.dart';
import '../services/stock_receiving_controller.dart';
import 'pos_screen.dart';
import 'product_list_screen.dart';
import 'settings_screen.dart';
import 'stock_receiving_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.repository,
    this.cart,
    this.stockController,
  });

  final ProductRepository? repository;
  final CartController? cart;
  final StockReceivingController? stockController;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  late final ProductRepository _repository;
  late final CartController _cart;
  late final StockReceivingController _stockController;

  bool get _ownsCart => widget.cart == null;
  bool get _ownsStock => widget.stockController == null;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockProductRepository();
    _cart = widget.cart ?? CartController();
    _stockController = widget.stockController ?? StockReceivingController();
    _screens = <Widget>[
      _DashboardHomePage(
        products: _repository.getProducts(),
        cart: _cart,
        stock: _stockController,
      ),
      ProductListScreen(repository: _repository),
      PosScreen(repository: _repository, cart: _cart),
      StockReceivingScreen(controller: _stockController),
    ];
  }

  @override
  void dispose() {
    if (_ownsCart) {
      _cart.dispose();
    }
    if (_ownsStock) {
      _stockController.dispose();
    }
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mỹ Phẩm Kim Cương'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Cài đặt',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Sản phẩm',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'POS',
          ),
          NavigationDestination(
            icon: Icon(Icons.warehouse_outlined),
            selectedIcon: Icon(Icons.warehouse),
            label: 'Nhập kho',
          ),
        ],
      ),
    );
  }
}

class _DashboardHomePage extends StatelessWidget {
  const _DashboardHomePage({
    required this.products,
    required this.cart,
    required this.stock,
  });

  final List<Product> products;
  final CartController cart;
  final StockReceivingController stock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([cart, stock]),
      builder: (context, _) {
        final summary = const DashboardSummaryBuilder().build(
          products: products,
          cart: cart,
          stock: stock,
          apiConnected: AppSettings.hasBaseUrl,
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Bảng điều khiển', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Dữ liệu demo local — chờ kết nối thật',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Tổng sản phẩm',
                    value: '${summary.totalProducts}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.check_circle_outline,
                    label: 'Còn hàng',
                    value: '${summary.inStock}',
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.warning_amber_outlined,
                    label: 'Sắp hết',
                    value: '${summary.lowStock}',
                    color: const Color(0xFFEF6C00),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.error_outline,
                    label: 'Hết hàng',
                    value: '${summary.outOfStock}',
                    color: const Color(0xFFC62828),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.point_of_sale_outlined,
                    label: 'Giá trị giỏ POS',
                    value: formatPrice(summary.cartSubtotal),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Trong giỏ',
                    value: '${summary.cartItemCount} món',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.warehouse_outlined,
                    label: 'Phiếu nhập kho',
                    value: '${summary.stockReceivingCount} phiếu',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Tổng tiền nhập',
                    value: formatPrice(summary.stockReceivingTotal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Cảnh báo nhanh',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (!summary.apiConnected) ...[
              _WarningTile(
                icon: Icons.cloud_off,
                color: theme.colorScheme.error,
                title: 'Chưa kết nối API',
                subtitle: 'Vào Cài đặt để nhập địa chỉ website',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            if (summary.hasOutOfStockWarning) ...[
              _WarningTile(
                icon: Icons.error_outline,
                color: const Color(0xFFC62828),
                title: 'Có ${summary.outOfStock} sản phẩm hết hàng',
                subtitle: 'Cần nhập kho bổ sung',
              ),
              const SizedBox(height: 8),
            ],
            if (summary.hasLowStockWarning) ...[
              _WarningTile(
                icon: Icons.warning_amber_outlined,
                color: const Color(0xFFEF6C00),
                title: 'Có ${summary.lowStock} sản phẩm sắp hết hàng',
                subtitle: 'Cân nhắc nhập kho sớm',
              ),
              const SizedBox(height: 8),
            ],
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tồn kho khả dụng',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '${summary.inStock}/${summary.totalProducts}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: summary.inStockRatio,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24, color: color ?? theme.colorScheme.primary),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  const _WarningTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        onTap: onTap,
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }
}