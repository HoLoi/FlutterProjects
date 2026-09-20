import 'product.dart';

class StockReceivingItem {
  const StockReceivingItem({
    required this.product,
    required this.quantity,
    required this.costPrice,
    this.batchCode,
    this.productionDate,
    this.expiryDate,
  });

  final Product product;
  final int quantity;
  final double costPrice;
  final String? batchCode;
  final DateTime? productionDate;
  final DateTime? expiryDate;

  double get total => costPrice * quantity;

  String get batchLabel {
    final code = batchCode?.trim() ?? '';
    return code.isEmpty ? 'Tự sinh khi triển khai thật' : code;
  }
}

class StockReceiving {
  const StockReceiving({
    required this.id,
    required this.createdAt,
    required this.items,
    this.note,
  });

  final int id;
  final DateTime createdAt;
  final List<StockReceivingItem> items;
  final String? note;

  double get total => items.fold(0, (sum, item) => sum + item.total);
}