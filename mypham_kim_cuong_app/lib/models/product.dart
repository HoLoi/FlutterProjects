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
    this.regularPrice,
    this.salePrice,
    this.productType = '',
    this.imageUrl,
    this.category,
  });

  final int id;
  final String name;
  final String sku;
  final String barcode;

  /// Giá đang bán (`price` trong JSON).
  final double price;

  /// `regular_price` — có thể `null` khi sản phẩm không có giá dạng chuỗi.
  final double? regularPrice;

  /// `sale_price` — có thể `null` khi sản phẩm không giảm giá.
  final double? salePrice;

  /// `null` khi sản phẩm không bật quản lý kho (API trả `null`, không phải 0).
  final int? stockQuantity;

  final ProductStatus status;

  /// `simple`, `variable`, `grouped` hoặc `external`.
  final String productType;
  final String? imageUrl;
  final String? category;

  /// Sản phẩm cha có biến thể hay không.
  bool get hasVariations => productType == 'variable';

  /// Đang giảm giá khi `sale_price` khác `null` và nhỏ hơn `regular_price`.
  bool get isOnSale {
    final sale = salePrice;
    final regular = regularPrice;
    if (sale == null || regular == null) {
      return false;
    }
    return sale > 0 && sale < regular;
  }
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

/// Nhãn giá gốc, chỉ hiện khi sản phẩm thực sự đang giảm giá.
String regularPriceLabel(Product product) {
  final regular = product.regularPrice;
  if (!product.isOnSale || regular == null) {
    return '';
  }
  return formatPrice(regular);
}
