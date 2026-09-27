import '../models/api_value.dart';
import '../models/product.dart';
import '../services/api_client.dart';

class ApiProductException implements Exception {
  const ApiProductException(
    this.message, {
    this.wcInactive = false,
    this.notFound = false,
  });

  final String message;
  final bool wcInactive;

  /// `GET /products/{id}` trả `404` khi sản phẩm không tồn tại.
  final bool notFound;

  @override
  String toString() => message;
}

class ApiProductRepository {
  ApiProductRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<Product>> fetchAll({String? search, int perPage = 50}) async {
    final result = await _apiClient.fetchProducts(search: search, perPage: perPage);
    if (!result.succeeded) {
      throw ApiProductException(
        result.message ?? 'Không đọc được sản phẩm',
        wcInactive: result.status == ProductsStatus.wcInactive,
      );
    }
    return result.items.map(ApiProductParser.fromJson).toList(growable: false);
  }

  /// Chi tiết một sản phẩm (read-only).
  Future<Product> fetchDetail(int productId) async {
    final result = await _apiClient.fetchProductDetail(productId);
    if (!result.succeeded) {
      throw ApiProductException(
        result.message ?? 'Không đọc được chi tiết sản phẩm',
        wcInactive: result.status == ProductDetailStatus.wcInactive,
        notFound: result.status == ProductDetailStatus.notFound,
      );
    }
    return ApiProductParser.fromJson(
      ApiValue.object(result.data) ?? const <String, dynamic>{},
    );
  }
}

class ApiProductParser {
  static const int lowStockThreshold = 5;

  static Product fromJson(Map<String, dynamic> json) {
    final stockStatus = ApiValue.textOrEmpty(json['stock_status']);
    // Giữ null: API trả null khi sản phẩm không bật quản lý kho.
    final stockQuantity = ApiValue.integer(json['stock_quantity']);

    return Product(
      id: ApiValue.integerOrZero(json['id']),
      name: ApiValue.textOrEmpty(json['name']),
      sku: ApiValue.textOrEmpty(json['sku']),
      barcode: ApiValue.textOrEmpty(json['barcode']),
      price: ApiValue.numberOrZero(json['price']),
      regularPrice: ApiValue.number(json['regular_price']),
      salePrice: ApiValue.number(json['sale_price']),
      stockQuantity: stockQuantity,
      status: _status(stockStatus, stockQuantity),
      productType: ApiValue.textOrEmpty(json['type']),
      imageUrl: ApiValue.text(json['image_url']),
      category: _category(json['categories']),
    );
  }

  static ProductStatus _status(String stockStatus, int? stockQuantity) {
    if (stockStatus == 'outofstock') {
      return ProductStatus.outOfStock;
    }
    final quantity = stockQuantity;
    if (quantity != null && quantity <= lowStockThreshold) {
      return ProductStatus.lowStock;
    }
    return ProductStatus.inStock;
  }

  /// `categories` là mảng `{id, name, slug}`; lấy tên danh mục đầu tiên.
  static String? _category(Object? raw) {
    final categories = ApiValue.objectList(raw);
    if (categories.isEmpty) {
      return null;
    }
    return ApiValue.text(categories.first['name']);
  }
}
