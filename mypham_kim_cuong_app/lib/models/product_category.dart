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
  final int parent;
  final int count;
}

class ApiCategoryParser {
  static ProductCategory fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Danh mục chưa có tên',
      slug: json['slug']?.toString() ?? '',
      parent: (json['parent'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
