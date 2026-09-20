import '../models/product.dart';
import 'cart_controller.dart';
import 'stock_receiving_controller.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalProducts,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.cartItemCount,
    required this.cartSubtotal,
    required this.stockReceivingCount,
    required this.stockReceivingTotal,
    required this.apiConnected,
  });

  final int totalProducts;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final int cartItemCount;
  final double cartSubtotal;
  final int stockReceivingCount;
  final double stockReceivingTotal;
  final bool apiConnected;

  bool get hasLowStockWarning => lowStock > 0;

  bool get hasOutOfStockWarning => outOfStock > 0;

  double get inStockRatio =>
      totalProducts == 0 ? 0 : inStock / totalProducts;
}

class DashboardSummaryBuilder {
  const DashboardSummaryBuilder();

  DashboardSummary build({
    required List<Product> products,
    required CartController cart,
    required StockReceivingController stock,
    required bool apiConnected,
  }) {
    var inStock = 0;
    var lowStock = 0;
    var outOfStock = 0;
    for (final product in products) {
      switch (product.status) {
        case ProductStatus.inStock:
          inStock++;
        case ProductStatus.lowStock:
          lowStock++;
        case ProductStatus.outOfStock:
          outOfStock++;
      }
    }
    final records = stock.records;
    final stockReceivingTotal = records.fold<double>(
      0,
      (sum, record) => sum + record.total,
    );
    return DashboardSummary(
      totalProducts: products.length,
      inStock: inStock,
      lowStock: lowStock,
      outOfStock: outOfStock,
      cartItemCount: cart.itemCount,
      cartSubtotal: cart.subtotal,
      stockReceivingCount: records.length,
      stockReceivingTotal: stockReceivingTotal,
      apiConnected: apiConnected,
    );
  }
}