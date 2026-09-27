import 'api_value.dart';

/// Biến thể sản phẩm WooCommerce.
///
/// JSON thật:
/// ```json
/// {
///   "id": 124, "product_id": 123, "name": "Son Kem Lì Satin Đỏ - Màu đỏ",
///   "sku": "KC-0001-RED", "barcode": null, "price": 190000,
///   "regular_price": 220000, "sale_price": 190000,
///   "stock_quantity": 5, "stock_status": "instock",
///   "image_url": "https://.../son-do.jpg",
///   "attributes": [ { "name": "Màu sắc", "option": "Đỏ" } ]
/// }
/// ```
class ProductVariation {
  const ProductVariation({
    required this.id,
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    this.barcode = '',
    this.regularPrice,
    this.salePrice,
    this.stockQuantity,
    this.stockStatus = '',
    this.imageUrl,
    this.attributes = const [],
  });

  final int id;
  final int productId;
  final String name;
  final String sku;
  final String barcode;
  final double price;
  final double? regularPrice;
  final double? salePrice;

  /// `null` khi biến thể không bật quản lý kho.
  final int? stockQuantity;

  /// `instock`, `outofstock` hoặc `onbackorder`.
  final String stockStatus;
  final String? imageUrl;

  /// Đã ghép thành chuỗi `"Màu sắc: Đỏ"`.
  final List<String> attributes;

  String get attributeText => attributes.isEmpty ? '' : attributes.join(', ');

  bool get isOutOfStock => stockStatus == 'outofstock';
}

class ApiVariationParser {
  static ProductVariation fromJson(Map<String, dynamic> json) {
    final name = ApiValue.text(json['name']);
    return ProductVariation(
      id: ApiValue.integerOrZero(json['id']),
      productId: ApiValue.integerOrZero(json['product_id']),
      name: name ?? 'Biến thể chưa có tên',
      sku: ApiValue.textOrEmpty(json['sku']),
      barcode: ApiValue.textOrEmpty(json['barcode']),
      price: ApiValue.numberOrZero(json['price']),
      regularPrice: ApiValue.number(json['regular_price']),
      salePrice: ApiValue.number(json['sale_price']),
      // Giữ null: API trả null khi biến thể không bật quản lý kho.
      stockQuantity: ApiValue.integer(json['stock_quantity']),
      stockStatus: ApiValue.textOrEmpty(json['stock_status']),
      imageUrl: ApiValue.text(json['image_url']),
      attributes: _attributes(json['attributes']),
    );
  }

  /// `attributes` là mảng `{name, option}`; bỏ qua phần tử thiếu `option`
  /// vì chỉ có tên thuộc tính thì không mô tả được biến thể.
  static List<String> _attributes(Object? raw) {
    return ApiValue.objectList(raw)
        .map((item) {
          final name = ApiValue.textOrEmpty(item['name']);
          final option = ApiValue.textOrEmpty(item['option']);
          if (name.isEmpty || option.isEmpty) {
            return '';
          }
          return '$name: $option';
        })
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }
}
