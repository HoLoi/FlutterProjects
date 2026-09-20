import 'package:flutter/material.dart';

import '../data/product_repository.dart';
import '../models/product.dart';
import '../widgets/code_input_dialog.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.repository});

  final ProductRepository? repository;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late final ProductRepository _repository;
  late List<Product> _products;
  late final TextEditingController _searchController;
  String _query = '';
  ProductStatus? _filter;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockProductRepository();
    _products = _repository.getProducts();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    var list = _products;
    if (_filter != null) {
      list = list.where((p) => p.status == _filter).toList();
    }
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(query) ||
              p.sku.toLowerCase().contains(query) ||
              p.barcode.toLowerCase().contains(query))
          .toList();
    }
    return list;
  }

  Future<void> _lookupCode() async {
    final code = await showCodeInputDialog(
      context,
      title: 'Tìm bằng mã',
      label: 'Barcode / SKU',
    );
    if (code == null || code.isEmpty) {
      return;
    }
    final product = _repository.findProductByCode(code);
    if (product == null) {
      _showMessage('Không tìm thấy sản phẩm với mã "$code"');
      return;
    }
    _searchController.text = code;
    setState(() => _query = code);
    _showMessage('Đã tìm thấy: ${product.name}');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Danh sách sản phẩm', style: theme.textTheme.titleLarge),
              Text('${_products.length} sản phẩm', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Tìm tên, SKU, mã vạch',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Tìm bằng mã',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _lookupCode,
              ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                  onSelected: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                ...ProductStatus.values.map(
                  (status) => Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: _FilterChip(
                      label: status.label,
                      selected: _filter == status,
                      onSelected: () => setState(() => _filter = status),
                    ),
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
                    itemBuilder: (context, index) =>
                        _ProductCard(product: filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Không tìm thấy sản phẩm'),
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.spa,
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
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SKU: ${product.sku} · Mã vạch: ${product.barcode}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (product.category != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Danh mục: ${product.category}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Tồn kho: ${product.stockQuantity}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatPrice(product.price),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _statusBadge(product.status),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(ProductStatus status) {
    final (background, foreground) = switch (status) {
      ProductStatus.inStock => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      ProductStatus.lowStock => (const Color(0xFFFFF3E0), const Color(0xFFEF6C00)),
      ProductStatus.outOfStock => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
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