import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/models/product.dart';
import 'package:mypham_kim_cuong_app/models/stock_receiving.dart';
import 'package:mypham_kim_cuong_app/services/cart_controller.dart';
import 'package:mypham_kim_cuong_app/services/dashboard_summary.dart';
import 'package:mypham_kim_cuong_app/services/stock_receiving_controller.dart';

void main() {
  const inStock = Product(
    id: 1,
    name: 'A',
    sku: 'S1',
    barcode: 'B1',
    price: 100,
    stockQuantity: 5,
    status: ProductStatus.inStock,
  );
  const lowStock = Product(
    id: 2,
    name: 'B',
    sku: 'S2',
    barcode: 'B2',
    price: 200,
    stockQuantity: 2,
    status: ProductStatus.lowStock,
  );
  const outOfStock = Product(
    id: 3,
    name: 'C',
    sku: 'S3',
    barcode: 'B3',
    price: 300,
    stockQuantity: 0,
    status: ProductStatus.outOfStock,
  );

  DashboardSummary build({
    List<Product> products = const [],
    CartController? cart,
    StockReceivingController? stock,
    bool apiConnected = false,
  }) {
    return const DashboardSummaryBuilder().build(
      products: products,
      cart: cart ?? CartController(),
      stock: stock ?? StockReceivingController(),
      apiConnected: apiConnected,
    );
  }

  test('đếm tổng sản phẩm và trạng thái kho đúng', () {
    final summary = build(
      products: [inStock, inStock, lowStock, outOfStock],
      apiConnected: false,
    );

    expect(summary.totalProducts, 4);
    expect(summary.inStock, 2);
    expect(summary.lowStock, 1);
    expect(summary.outOfStock, 1);
    expect(summary.inStockRatio, closeTo(0.5, 0.001));
    expect(summary.hasLowStockWarning, isTrue);
    expect(summary.hasOutOfStockWarning, isTrue);
    expect(summary.apiConnected, isFalse);
  });

  test('phản ánh giỏ POS hiện tại', () {
    final cart = CartController();
    cart.add(inStock);
    cart.add(inStock);

    final summary = build(products: [inStock], cart: cart, apiConnected: true);

    expect(summary.cartItemCount, 2);
    expect(summary.cartSubtotal, 200);
    expect(summary.apiConnected, isTrue);
  });

  test('phản ánh phiếu nhập kho demo', () {
    final stock = StockReceivingController();
    stock.create(
      items: [StockReceivingItem(product: inStock, quantity: 5, costPrice: 1000)],
    );
    stock.create(
      items: [StockReceivingItem(product: inStock, quantity: 2, costPrice: 2000)],
    );

    final summary = build(products: const [], stock: stock);

    expect(summary.stockReceivingCount, 2);
    expect(summary.stockReceivingTotal, 9000);
  });

  test('không có cảnh báo khi mọi thứ đủ hàng và đã kết nối', () {
    final summary = build(
      products: [inStock],
      apiConnected: true,
    );

    expect(summary.hasLowStockWarning, isFalse);
    expect(summary.hasOutOfStockWarning, isFalse);
    expect(summary.inStockRatio, 1);
  });
}