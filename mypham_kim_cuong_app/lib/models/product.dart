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
  final int? stockQuantity;
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

String nameLabel(Product product) =>
    product.name.trim().isEmpty ? 'Sản phẩm chưa có tên' : product.name;

String skuLabel(Product product) =>
    product.sku.trim().isEmpty ? 'Chưa có SKU' : product.sku;

String barcodeLabel(Product product) =>
    product.barcode.trim().isEmpty ? 'Chưa có mã' : product.barcode;

String stockLabel(Product product) =>
    product.stockQuantity == null ? 'Không quản lý số lượng' : '${product.stockQuantity}';

String priceLabel(Product product) =>
    product.price <= 0 ? 'Chưa có giá' : formatPrice(product.price);