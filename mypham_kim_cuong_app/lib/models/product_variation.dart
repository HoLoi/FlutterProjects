class ProductVariation {
  const ProductVariation({
    required this.id,
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    this.barcode = '',
    this.stockQuantity,
    this.attributes = const [],
  });

  final int id;
  final int productId;
  final String name;
  final String sku;
  final String barcode;
  final double price;
  final int? stockQuantity;
  final List<String> attributes;

  String get attributeText => attributes.isEmpty ? '' : attributes.join(', ');
}

class ApiVariationParser {
  static ProductVariation fromJson(Map<String, dynamic> json) {
    return ProductVariation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Biến thể chưa có tên',
      sku: json['sku']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
      attributes: _attributes(json['attributes']),
    );
  }

  static List<String> _attributes(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => [
            item['name']?.toString() ?? '',
            item['option']?.toString() ?? '',
          ].where((part) => part.isNotEmpty).join(': '),
        )
        .where((text) => text.isNotEmpty)
        .toList();
  }
}
