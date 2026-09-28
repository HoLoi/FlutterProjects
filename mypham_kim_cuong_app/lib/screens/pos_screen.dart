import 'package:flutter/material.dart';

import '../data/api_product_repository.dart';
import '../data/product_repository.dart';
import '../data/pos_sale_repository.dart';
import '../models/cart_item.dart';
import '../models/pos_sale.dart';
import '../models/product.dart';
import '../models/product_variation.dart';
import '../services/api_client.dart';
import '../services/auth_session.dart';
import '../services/cart_controller.dart';
import '../services/pos_checkout_controller.dart';
import '../widgets/code_input_dialog.dart';
import '../widgets/pos_variation_picker.dart';
import '../widgets/product_image_box.dart';
class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    this.repository,
    this.cart,
    this.apiRepository,
    this.posRepository,
    this.apiClient,
    this.authSession,
    this.checkout,
  });

  final ProductRepository? repository;
  final CartController? cart;

  /// Nguồn sản phẩm thật, dùng khi bật chế độ API.
  final ApiProductRepository? apiRepository;

  /// Cổng gọi `POST /pos/sales`.
  final PosSaleRepository? posRepository;

  final ApiClient? apiClient;
  final AuthSession? authSession;
  final PosCheckoutController? checkout;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late final ProductRepository _repository;
  late final CartController _cart;
  late final PosCheckoutController _checkoutController;
  ApiProductRepository? _apiRepository;
  PosSaleRepository? _posRepository;
  ApiClient? _apiClient;
  AuthSession? _authSession;
  List<Product> _products = const [];
  String _query = '';

  /// Bật tay để dùng dữ liệu thật khi chưa đăng nhập (không thanh toán được).
  bool _apiModeEnabled = false;

  bool _loadingProducts = false;
  PosPaymentMethod _paymentMethod = PosPaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockProductRepository();
    _cart = widget.cart ?? CartController();
    _checkoutController = widget.checkout ?? PosCheckoutController();
    _apiRepository = widget.apiRepository;
    _posRepository = widget.posRepository;
    _apiClient = widget.apiClient;
    _authSession = widget.authSession;
    _products = _repository.getProducts();
    _authSession?.addListener(_onAuthChanged);
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant PosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authSession != widget.authSession) {
      oldWidget.authSession?.removeListener(_onAuthChanged);
      _authSession = widget.authSession;
      _authSession?.addListener(_onAuthChanged);
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _authSession?.removeListener(_onAuthChanged);
    if (widget.cart == null) {
      _cart.dispose();
    }
    if (widget.checkout == null) {
      _checkoutController.dispose();
    }
    super.dispose();
  }

  /// Có dùng dữ liệu và thanh toán thật hay không.
  bool get _useApi => _apiModeEnabled || (_authSession?.isSignedIn ?? false);

  /// Đã đăng nhập thì bắt buộc dùng API, không cho chạy demo song song.
  bool get _canPay => _authSession?.isSignedIn ?? false;

  void _onAuthChanged() {
    _loadProducts();
  }

  /// Nạp danh sách sản phẩm: từ API khi bật chế độ API, ngược lại từ mock.
  Future<void> _loadProducts() async {
    if (!_useApi || _apiRepository == null) {
      if (mounted) {
        setState(() {
          _loadingProducts = false;
          _products = _repository.getProducts();
        });
      }
      return;
    }

    setState(() => _loadingProducts = true);
    try {
      final products = await _apiRepository!.fetchAll(perPage: 50);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProducts = false;
        _products = products;
      });
    } on ApiProductException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProducts = false;
        _products = _repository.getProducts();
      });
      _showMessage(error.message);
    }
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

  Future<void> _addToCart(Product product) async {
    ProductVariation? variation;
    if (product.hasVariations) {
      if (!_useApi) {
        _showMessage(
          'Sản phẩm biến thể cần chọn mẫu, hãy bật chế độ dữ liệu API',
        );
        return;
      }
      variation = await showPosVariationPicker(
        context,
        product: product,
        apiClient: _apiClient ?? ApiClient(),
      );
      if (!mounted || variation == null) {
        return;
      }
    }

    final added = _cart.add(product, variation: variation);
    if (!added) {
      _showMessage('${variation?.name ?? product.name} đã hết hàng');
      return;
    }
    final attributes = variation?.attributeText ?? '';
    final label = attributes.isEmpty
        ? product.name
        : '${product.name} · $attributes';
    _showMessage('Đã thêm "$label" vào giỏ');
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
    final product = _findProductByCode(code);
    if (product == null) {
      _showMessage('Không tìm thấy sản phẩm, có thể tạo mới ở phiên bản sau');
      return;
    }
    if (product.status == ProductStatus.outOfStock) {
      _showMessage('${product.name} đã hết hàng, không thể thêm vào giỏ');
      return;
    }
    await _addToCart(product);
  }

  /// Tìm theo barcode/SKU trong danh sách đang hiển thị.
  Product? _findProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final product in _products) {
      if (product.barcode.toLowerCase() == normalized ||
          product.sku.toLowerCase() == normalized) {
        return product;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkout() async {
    if (_useApi) {
      await _checkoutWithApi();
      return;
    }
    await _checkoutDemo();
  }

  /// POS demo cũ: chỉ xác nhận, không tạo đơn, không gọi mạng.
  Future<void> _checkoutDemo() async {
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

  /// Thanh toán thật qua `POST /pos/sales`.
  Future<void> _checkoutWithApi() async {
    if (!_canPay) {
      _showMessage('Bạn cần đăng nhập để thanh toán');
      return;
    }
    final repository = _posRepository;
    if (repository == null) {
      _showMessage('Chưa cấu hình kết nối thanh toán');
      return;
    }
    if (_cart.isEmpty) {
      return;
    }

    final succeeded = await _checkoutController.submit(
      repository: repository,
      items: _cart.items,
      paymentMethod: _paymentMethod.wire,
    );

    if (!mounted) {
      return;
    }

    if (succeeded) {
      // Chỉ xoá giỏ sau khi server đã xác nhận tạo đơn.
      _cart.clear();
      await _showSaleSuccess(_checkoutController.lastResult!);
      _checkoutController.reset();
      return;
    }

    await _showSaleError(_checkoutController.lastError);
  }

  Future<void> _showSaleSuccess(PosSaleResult result) async {
    if (!mounted) {
      return;
    }
    final order = result.order;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Đơn #${order.number}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng: ${formatPrice(order.total)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Trạng thái: ${order.status.label}'),
            if (order.paymentMethod.isNotEmpty)
              Text('Thanh toán: ${order.paymentMethod}'),
            if (result.replayed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Đơn này đã được tạo từ lần gửi trước, không tạo đơn mới.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSaleError(PosSaleException? error) async {
    if (!mounted) {
      return;
    }
    final repository = _posRepository;
    if (repository == null) {
      return;
    }

    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chưa thanh toán được'),
        content: Text(error?.message ?? PosSaleMessages.invalidRequest),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Đóng'),
          ),
          // Chỉ cho gửi lại khi server chưa chắc đã tạo đơn; lần gửi lại dùng
          // lại đúng `request_id` nên không sinh đơn trùng.
          if (_checkoutController.canRetry)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Gửi lại'),
            ),
        ],
      ),
    );

    if (retry != true || !mounted) {
      return;
    }

    final succeeded = await _checkoutController.submit(
      repository: repository,
      items: _cart.items,
      paymentMethod: _paymentMethod.wire,
    );

    if (!mounted) {
      return;
    }

    if (succeeded) {
      _cart.clear();
      await _showSaleSuccess(_checkoutController.lastResult!);
      _checkoutController.reset();
      return;
    }

    // Vẫn lỗi: đệ quy để hiện lỗi tiếp theo (ví dụ 500 rồi mạng lại lỗi).
    await _showSaleError(_checkoutController.lastError);
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
              if (_loadingProducts)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Text(
                  _useApi ? 'Dữ liệu API' : 'Bản demo local',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chế độ API'),
                  Switch(
                    value: _apiModeEnabled,
                    onChanged: (value) {
                      setState(() => _apiModeEnabled = value);
                      _loadProducts();
                    },
                  ),
                ],
              ),
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
                        Icon(
                          Icons.search_off,
                          color: theme.colorScheme.outline,
                        ),
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
          _CartPanel(
            cart: _cart,
            checkout: _checkoutController,
            paymentMethod: _paymentMethod,
            useApi: _useApi,
            canPay: _canPay,
            onPaymentMethodChanged: (value) {
              setState(() => _paymentMethod = value);
            },
            onCheckout: _checkout,
          ),
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
    final stockText =
        outOfStock ? 'Hết hàng' : 'Tồn kho: ${stockLabel(product)}';
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
            ProductImageBox(imageUrl: product.imageUrl, size: 40),
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
              tooltip: product.hasVariations
                  ? 'Chọn biến thể'
                  : 'Thêm vào giỏ',
              icon: Icon(
                product.hasVariations
                    ? Icons.tune
                    : Icons.add_shopping_cart,
              ),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.checkout,
    required this.paymentMethod,
    required this.useApi,
    required this.canPay,
    required this.onPaymentMethodChanged,
    required this.onCheckout,
  });

  final CartController cart;
  final PosCheckoutController checkout;
  final PosPaymentMethod paymentMethod;
  final bool useApi;
  final bool canPay;
  final ValueChanged<PosPaymentMethod> onPaymentMethodChanged;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListenableBuilder(
          listenable: Listenable.merge([cart, checkout]),
          builder: (context, _) {
            final items = cart.items;
            final isEmpty = items.isEmpty;
            final submitting = checkout.isSubmitting;
            // Khoá nút khi đang gọi mạng để không tạo hai đơn cùng lúc, và khi
            // chế độ API bật mà chưa đăng nhập vì server chắc chắn trả 401.
            final blocked = isEmpty ||
                submitting ||
                (useApi && !canPay);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Giỏ hàng',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${cart.itemCount} món · Tổng: ${formatPrice(cart.subtotal)}',
                      textAlign: TextAlign.end,
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
                if (useApi) ...[
                  SegmentedButton<PosPaymentMethod>(
                    segments: const [
                      ButtonSegment(
                        value: PosPaymentMethod.cash,
                        label: Text('Tiền mặt'),
                      ),
                      ButtonSegment(
                        value: PosPaymentMethod.bacs,
                        label: Text('Chuyển khoản'),
                      ),
                      ButtonSegment(
                        value: PosPaymentMethod.vietqr,
                        label: Text('VietQR'),
                      ),
                    ],
                    selected: {paymentMethod},
                    onSelectionChanged: submitting
                        ? null
                        : (selection) =>
                              onPaymentMethodChanged(selection.first),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: blocked ? null : onCheckout,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(useApi ? Icons.point_of_sale : Icons.payment),
                  label: Text(
                    submitting
                        ? 'Đang tạo đơn...'
                        : useApi
                        ? 'Thanh toán'
                        : 'Thanh toán demo',
                  ),
                ),
                if (useApi && !canPay)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Đăng nhập để thanh toán thật',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
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
    final productId = item.product.id;
    final variationId = item.variationId;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '${formatPrice(item.unitPrice)} x ${item.quantity}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => cart.decrease(productId, variationId: variationId),
          tooltip: 'Giảm số lượng',
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
        Text('${item.quantity}'),
        IconButton(
          onPressed: () => cart.increase(productId, variationId: variationId),
          tooltip: 'Tăng số lượng',
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => cart.remove(productId, variationId: variationId),
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