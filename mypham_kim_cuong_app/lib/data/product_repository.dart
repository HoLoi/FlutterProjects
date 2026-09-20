import '../models/product.dart';

abstract class ProductRepository {
  List<Product> getProducts();

  Product? findProductByCode(String code);
}

class MockProductRepository implements ProductRepository {
  static const List<Product> _products = [
    Product(
      id: 1,
      name: 'Son Kem Lì Satin',
      sku: 'KC-0001',
      barcode: '893000000001',
      price: 189000,
      stockQuantity: 25,
      status: ProductStatus.inStock,
      category: 'Son',
    ),
    Product(
      id: 2,
      name: 'Serum Vitamin C Brightening',
      sku: 'KC-0002',
      barcode: '893000000002',
      price: 295000,
      stockQuantity: 3,
      status: ProductStatus.lowStock,
      category: 'Dưỡng da',
    ),
    Product(
      id: 3,
      name: 'Kem Chống Nắng SPF 50',
      sku: 'KC-0003',
      barcode: '893000000003',
      price: 210000,
      stockQuantity: 0,
      status: ProductStatus.outOfStock,
      category: 'Chống nắng',
    ),
    Product(
      id: 4,
      name: 'Sữa Rửa Mặt Dịu Nhẹ',
      sku: 'KC-0004',
      barcode: '893000000004',
      price: 95000,
      stockQuantity: 40,
      status: ProductStatus.inStock,
      category: 'Làm sạch',
    ),
    Product(
      id: 5,
      name: 'Nước Tẩy Trang Cho Da Nhạy Cảm',
      sku: 'KC-0005',
      barcode: '893000000005',
      price: 125000,
      stockQuantity: 5,
      status: ProductStatus.lowStock,
      category: 'Làm sạch',
    ),
    Product(
      id: 6,
      name: 'Kem Dưỡng Ẩm Cấp Nước',
      sku: 'KC-0006',
      barcode: '893000000006',
      price: 165000,
      stockQuantity: 60,
      status: ProductStatus.inStock,
      category: 'Dưỡng da',
    ),
    Product(
      id: 7,
      name: 'Nước Hoa Hồng Cân Bằng Da',
      sku: 'KC-0007',
      barcode: '893000000007',
      price: 85000,
      stockQuantity: 0,
      status: ProductStatus.outOfStock,
      category: 'Dưỡng da',
    ),
    Product(
      id: 8,
      name: 'Mặt Nạ Giấy Trà Xanh',
      sku: 'KC-0008',
      barcode: '893000000008',
      price: 45000,
      stockQuantity: 100,
      status: ProductStatus.inStock,
      category: 'Mặt nạ',
    ),
    Product(
      id: 9,
      name: 'Phấn Phủ Kiềm Dầu',
      sku: 'KC-0009',
      barcode: '893000000009',
      price: 230000,
      stockQuantity: 2,
      status: ProductStatus.lowStock,
      category: 'Trang điểm',
    ),
    Product(
      id: 10,
      name: 'Kẻ Mắt Nước Siêu Bền',
      sku: 'KC-0010',
      barcode: '893000000010',
      price: 145000,
      stockQuantity: 30,
      status: ProductStatus.inStock,
      category: 'Trang điểm',
    ),
  ];

  @override
  List<Product> getProducts() => _products;

  @override
  Product? findProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final product in _products) {
      if (product.barcode.toLowerCase() == normalized ||
          product.sku.toLowerCase() == normalized) {
        return product;
      }
    }
    return null;
  }
}