import 'product.dart';
import 'product_variation.dart';

/// Một dòng trong giỏ hàng POS.
///
/// Giá hiển thị lấy từ [variation] khi có, vì sản phẩm variable không có giá
/// riêng ở sản phẩm cha. Giá này **chỉ để hiển thị**: server luôn tự lấy lại
/// giá hiện tại trong WooCommerce khi bán.
class CartItem {
  CartItem({required this.product, required this.quantity, this.variation});

  final Product product;
  int quantity;

  /// Biến thể đã chọn; `null` với sản phẩm simple.
  final ProductVariation? variation;

  /// Id gửi lên API. `0` nghĩa là bán chính sản phẩm.
  int get variationId => variation?.id ?? 0;

  /// Đơn giá hiển thị: giá biến thể nếu có, nếu không giá sản phẩm.
  double get unitPrice => variation?.price ?? product.price;

  /// Tên hiển thị kèm thuộc tính biến thể, ví dụ `Son - Màu sắc: Đỏ`.
  String get label {
    final attributeText = variation?.attributeText ?? '';
    if (attributeText.isEmpty) {
      return product.name;
    }
    return '${product.name} · $attributeText';
  }

  double get lineTotal => unitPrice * quantity;
}
