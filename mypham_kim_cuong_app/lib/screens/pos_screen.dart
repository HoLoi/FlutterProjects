import 'package:flutter/material.dart';

import '../data/product_repository.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/cart_controller.dart';
import '../widgets/code_input_dialog.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.repository});

  final ProductRepository? repository;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late final ProductRepository _repository;
  late final CartController _cart;
  late List<Product> _products;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockProductRepository();
    _cart = CartController();
    _products = _repository.getProducts();
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _products;
    }
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query) ||
            p.barcode.toLowerCase().contains(query))
        .toList();
  }

  void _addToCart(Product product) {
    final added = _cart.add(product);
    if (!added) {
      _showMessage('${product.name} đã hết hàng, không thể thêm vào giỏ');
    }
  }

  Future<void> _lookupCode() async {
    final code = await showCodeInputDialog(
      context,
      title: 'Nhập mã sản phẩm',
      label: 'Barcode / SKU',
    );
    if (code == null || code.isEmpty) {
      return;
    }
    final product = _repository.findProductByCode(code);
    if (product == null) {
      _showMessage('Không tìm thấy sản phẩm, có thể tạo mới ở phiên bản sau');
      return;
    }
    if (product.status == ProductStatus.outOfStock) {
      _showMessage('${product.name} đã hết hàng, không thể thêm vào giỏ');
      return;
    }
    _cart.add(product);
    _showMessage('Đã thêm "${product.name}" vào giỏ');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thanh toán demo'),
        content: const Text(
          'Thanh toán demo thành công.\n\nKhông tạo đơn hàng, không trừ kho thật.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _cart.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredProducts;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Màn hình POS',
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('Bản demo local', style: theme.textTheme.bodySmall),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Nhập mã',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _lookupCode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Tìm sản phẩm, SKU, mã vạch',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, color: theme.colorScheme.outline),
                        const SizedBox(height: 8),
                        const Text('Không tìm thấy sản phẩm'),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _PosProductTile(
                      product: filtered[index],
                      onAdd: () => _addToCart(filtered[index]),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _CartPanel(cart: _cart, onCheckout: _checkout),
        ],
      ),
    );
  }
}

class _PosProductTile extends StatelessWidget {
  const _PosProductTile({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outOfStock = product.status == ProductStatus.outOfStock;
    final stockText = outOfStock ? 'Hết hàng' : 'Tồn kho: ${product.stockQuantity}';
    final stockStyle = outOfStock
        ? theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFFC62828),
            fontWeight: FontWeight.w600,
          )
        : theme.textTheme.bodySmall;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.spa,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: outOfStock ? theme.disabledColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SKU: ${product.sku} · ${formatPrice(product.price)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(stockText, style: stockStyle),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Thêm vào giỏ',
              icon: const Icon(Icons.add_shopping_cart),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.cart, required this.onCheckout});

  final CartController cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListenableBuilder(
          listenable: cart,
          builder: (context, _) {
            final items = cart.items;
            final isEmpty = items.isEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Giỏ hàng',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${cart.itemCount} món · Tổng: ${formatPrice(cart.subtotal)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'Giỏ hàng trống',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _CartItemRow(
                        item: items[index],
                        cart: cart,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: isEmpty ? null : onCheckout,
                  icon: const Icon(Icons.payment),
                  label: const Text('Thanh toán demo'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  const _CartItemRow({required this.item, required this.cart});

  final CartItem item;
  final CartController cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '${formatPrice(product.price)} x ${item.quantity}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => cart.decrease(product.id),
          tooltip: 'Giảm số lượng',
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
        Text('${item.quantity}'),
        IconButton(
          onPressed: () => cart.increase(product.id),
          tooltip: 'Tăng số lượng',
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => cart.remove(product.id),
          tooltip: 'Xóa khỏi giỏ',
          icon: const Icon(Icons.delete_outline),
          iconSize: 20,
          color: theme.colorScheme.error,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}