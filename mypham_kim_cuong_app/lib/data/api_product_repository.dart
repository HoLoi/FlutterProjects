import '../models/product.dart';
import '../services/api_client.dart';

class ApiProductException implements Exception {
  const ApiProductException(this.message, {this.wcInactive = false});

  final String message;
  final bool wcInactive;

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
    return result.items.map(ApiProductParser.fromJson).toList();
  }
}

class ApiProductParser {
  static const int lowStockThreshold = 5;

  static Product fromJson(Map<String, dynamic> json) {
    final stockStatus = json['stock_status']?.toString() ?? 'instock';
    final stockQuantity = (json['stock_quantity'] as num?)?.toInt();

    return Product(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      stockQuantity: stockQuantity ?? 0,
      status: _status(stockStatus, stockQuantity),
      imageUrl: json['image_url']?.toString(),
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

  static String? _category(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      return null;
    }
    final first = raw.first;
    if (first is Map<String, dynamic>) {
      return first['name']?.toString();
    }
    return null;
  }
}