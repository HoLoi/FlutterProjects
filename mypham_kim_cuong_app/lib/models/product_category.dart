import 'api_value.dart';

/// Danh mục sản phẩm WooCommerce.
///
/// JSON thật: `{ "id": 3, "name": "Son", "slug": "son", "parent": 0, "count": 12 }`
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.count,
    this.slug = '',
    this.parent = 0,
  });

  final int id;
  final String name;
  final String slug;

  /// `parent` = `0` nghĩa là danh mục cấp cao nhất.
  final int parent;

  /// Số sản phẩm trong danh mục, có thể `0` vì API trả cả danh mục rỗng.
  final int count;

  bool get isTopLevel => parent == 0;
}

class ApiCategoryParser {
  static ProductCategory fromJson(Map<String, dynamic> json) {
    final name = ApiValue.text(json['name']);
    return ProductCategory(
      id: ApiValue.integerOrZero(json['id']),
      name: name ?? 'Danh mục chưa có tên',
      slug: ApiValue.textOrEmpty(json['slug']),
      parent: ApiValue.integerOrZero(json['parent']),
      count: ApiValue.integerOrZero(json['count']),
    );
  }
}
