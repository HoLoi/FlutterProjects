enum ProductStatus {
  inStock('Còn hàng'),
  lowStock('Sắp hết'),
  outOfStock('Hết hàng');

  const ProductStatus(this.label);

  final String label;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.price,
    required this.stockQuantity,
    required this.status,
    this.imageUrl,
    this.category,
  });

  final int id;
  final String name;
  final String sku;
  final String barcode;
  final double price;
  final int stockQuantity;
  final ProductStatus status;
  final String? imageUrl;
  final String? category;
}

String formatPrice(double price) {
  final digits = price.toStringAsFixed(0);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  buffer.write(' đ');
  return buffer.toString();
}