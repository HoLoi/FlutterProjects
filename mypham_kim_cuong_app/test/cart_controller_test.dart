import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/models/product.dart';
import 'package:mypham_kim_cuong_app/services/cart_controller.dart';

const _inStock = Product(
  id: 1,
  name: 'Son Kem Lì Satin',
  sku: 'KC-0001',
  barcode: '893000000001',
  price: 189000,
  stockQuantity: 25,
  status: ProductStatus.inStock,
);

const _lowStock = Product(
  id: 2,
  name: 'Serum Vitamin C Brightening',
  sku: 'KC-0002',
  barcode: '893000000002',
  price: 295000,
  stockQuantity: 3,
  status: ProductStatus.lowStock,
);

const _outOfStock = Product(
  id: 3,
  name: 'Kem Chống Nắng SPF 50',
  sku: 'KC-0003',
  barcode: '893000000003',
  price: 210000,
  stockQuantity: 0,
  status: ProductStatus.outOfStock,
);

void main() {
  test('add sản phẩm cùng loại gộp số lượng và tính tổng đúng', () {
    final cart = CartController();

    expect(cart.add(_inStock), isTrue);
    expect(cart.add(_inStock), isTrue);

    expect(cart.items.length, 1);
    expect(cart.items.first.quantity, 2);
    expect(cart.itemCount, 2);
    expect(cart.subtotal, 189000 * 2);
  });

  test('không thêm được sản phẩm hết hàng', () {
    final cart = CartController();

    expect(cart.add(_outOfStock), isFalse);
    expect(cart.items, isEmpty);
    expect(cart.subtotal, 0);
  });

  test('tăng và giảm số lượng', () {
    final cart = CartController();
    cart.add(_inStock);

    cart.increase(_inStock.id);
    cart.increase(_inStock.id);
    expect(cart.items.first.quantity, 3);
    expect(cart.itemCount, 3);

    cart.decrease(_inStock.id);
    cart.decrease(_inStock.id);
    expect(cart.items.first.quantity, 1);
    expect(cart.itemCount, 1);
  });

  test('giảm về 0 sẽ xóa khỏi giỏ', () {
    final cart = CartController();
    cart.add(_inStock);

    cart.decrease(_inStock.id);

    expect(cart.items, isEmpty);
    expect(cart.subtotal, 0);
  });

  test('remove sản phẩm khỏi giỏ', () {
    final cart = CartController();
    cart.add(_inStock);
    cart.add(_lowStock);

    cart.remove(_inStock.id);

    expect(cart.items.length, 1);
    expect(cart.items.first.product.id, _lowStock.id);
  });

  test('tổng tiền nhiều sản phẩm cộng đúng', () {
    final cart = CartController();
    cart.add(_inStock);
    cart.add(_inStock);
    cart.add(_lowStock);

    expect(cart.subtotal, 189000 + 189000 + 295000);
  });

  test('clear cart xóa toàn bộ giỏ', () {
    final cart = CartController();
    cart.add(_inStock);
    cart.add(_lowStock);

    cart.clear();

    expect(cart.items, isEmpty);
    expect(cart.itemCount, 0);
    expect(cart.subtotal, 0);
  });
}