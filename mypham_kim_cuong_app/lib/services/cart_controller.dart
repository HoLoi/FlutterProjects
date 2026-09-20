import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';

class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.lineTotal);

  bool add(Product product) {
    if (product.status == ProductStatus.outOfStock) {
      return false;
    }
    final existing = _find(product.id);
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _items.add(CartItem(product: product, quantity: 1));
    }
    notifyListeners();
    return true;
  }

  void increase(int productId) {
    final item = _find(productId);
    if (item == null) {
      return;
    }
    item.quantity += 1;
    notifyListeners();
  }

  void decrease(int productId) {
    final item = _find(productId);
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

  void remove(int productId) {
    _items.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }
    _items.clear();
    notifyListeners();
  }

  CartItem? _find(int productId) {
    for (final item in _items) {
      if (item.product.id == productId) {
        return item;
      }
    }
    return null;
  }
}