import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variation.dart';

/// Giỏ hàng POS.
///
/// Khoá của một dòng là `productId:variationId` để sản phẩm variable bán được
/// nhiều biến thể trong cùng một lần bán, đúng với ràng buộc chống trùng mà
/// server kiểm tra.
class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount =>
      _items.fold<int>(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  bool get isEmpty => _items.isEmpty;

  bool add(Product product, {ProductVariation? variation}) {
    if (product.status == ProductStatus.outOfStock) {
      return false;
    }
    if (variation != null && variation.isOutOfStock) {
      return false;
    }
    final existing = _find(product.id, variation?.id ?? 0);
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _items.add(
        CartItem(product: product, quantity: 1, variation: variation),
      );
    }
    notifyListeners();
    return true;
  }

  void increase(int productId, {int variationId = 0}) {
    final item = _find(productId, variationId);
    if (item == null) {
      return;
    }
    item.quantity += 1;
    notifyListeners();
  }

  void decrease(int productId, {int variationId = 0}) {
    final item = _find(productId, variationId);
    if (item == null) {
      return;
    }
    if (item.quantity <= 1) {
      _items.remove(item);
    } else {
      item.quantity -= 1;
    }
    notifyListeners();
  }

  void remove(int productId, {int variationId = 0}) {
    _items.removeWhere(
      (item) =>
          item.product.id == productId && item.variationId == variationId,
    );
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }
    _items.clear();
    notifyListeners();
  }

  CartItem? _find(int productId, int variationId) {
    for (final item in _items) {
      if (item.product.id == productId && item.variationId == variationId) {
        return item;
      }
    }
    return null;
  }
}
