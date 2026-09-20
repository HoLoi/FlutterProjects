import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mypham_kim_cuong_app/data/api_product_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/product.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';

void main() {
  setUp(() {
    AppSettings.baseUrl = 'https://demo.local';
  });

  group('ApiProductParser', () {
    test('parse đầy đủ các trường của product', () {
      final product = ApiProductParser.fromJson({
        'id': 101,
        'name': 'Son Kem Lì Satin',
        'sku': 'KC-0001',
        'barcode': null,
        'price': 189000,
        'stock_quantity': 25,
        'stock_status': 'instock',
        'image_url': 'https://demo.local/wp-content/uploads/son.png',
        'categories': [
          {'id': 1, 'name': 'Son', 'slug': 'son'},
        ],
        'type': 'simple',
      });

      expect(product.id, 101);
      expect(product.name, 'Son Kem Lì Satin');
      expect(product.sku, 'KC-0001');
      expect(product.barcode, '');
      expect(product.price, 189000);
      expect(product.stockQuantity, 25);
      expect(product.status, ProductStatus.inStock);
      expect(product.imageUrl, 'https://demo.local/wp-content/uploads/son.png');
      expect(product.category, 'Son');
    });

    test('sản phẩm hết hàng chuyển sang outOfStock', () {
      final product = ApiProductParser.fromJson({
        'id': 102,
        'name': 'Kem Chống Nắng SPF 50',
        'sku': 'KC-0003',
        'stock_quantity': 0,
        'stock_status': 'outofstock',
        'price': 210000,
      });

      expect(product.status, ProductStatus.outOfStock);
    });

    test('sản phẩm còn hàng với tồn kho nhỏ là lowStock', () {
      final product = ApiProductParser.fromJson({
        'id': 9,
        'name': 'Phấn Phủ Kiềm Dầu',
        'sku': 'KC-0009',
        'stock_quantity': 2,
        'stock_status': 'instock',
        'price': 230000,
      });

      expect(product.status, ProductStatus.lowStock);
    });

    test('không có categories thì category là null', () {
      final product = ApiProductParser.fromJson({
        'id': 103,
        'name': 'Sản phẩm không danh mục',
        'sku': 'SKU-X',
        'stock_quantity': 10,
        'stock_status': 'instock',
        'price': 100000,
        'categories': [],
      });

      expect(product.category, isNull);
    });
  });

  group('ApiClient.fetchProducts', () {
    test('trả về ok cùng danh sách product khi wc_active', () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/wp-json/kc/v1/products');
          expect(request.url.queryParameters['per_page'], '50');
          return http.Response(
            jsonEncode({
              'wc_active': true,
              'count': 2,
              'data': [
                {'id': 101, 'name': 'A', 'price': 1000, 'stock_quantity': 10},
                {'id': 102, 'name': 'B', 'price': 2000, 'stock_quantity': 0},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.fetchProducts(perPage: 50);

      expect(result.status, ProductsStatus.ok);
      expect(result.succeeded, isTrue);
      expect(result.items.length, 2);
    });

    test('truyền tham số search khi có từ khóa', () async {
      String? searchParam;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          searchParam = request.url.queryParameters['search'];
          return http.Response(
            jsonEncode({'wc_active': true, 'count': 0, 'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.fetchProducts(search: '  son  ');

      expect(searchParam, 'son');
    });

    test('WooCommerce chưa active thì trả về wcInactive', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'wc_active': false,
              'count': 0,
              'data': [],
              'message': 'WooCommerce chưa active, không đọc được sản phẩm.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.fetchProducts();

      expect(result.status, ProductsStatus.wcInactive);
      expect(result.succeeded, isFalse);
      expect(result.message, contains('chưa active'));
    });

    test('HTTP khác 200 trả về httpError', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchProducts();

      expect(result.status, ProductsStatus.httpError);
      expect(result.message, 'HTTP 500');
    });

    test('lỗi mạng trả về networkError', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );

      final result = await client.fetchProducts();

      expect(result.status, ProductsStatus.networkError);
      expect(result.message, 'Không kết nối được máy chủ');
    });

    test('base URL rỗng trả về invalidUrl', () async {
      AppSettings.baseUrl = '';
      final client = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      final result = await client.fetchProducts();

      expect(result.status, ProductsStatus.invalidUrl);
    });
  });

  group('ApiProductRepository', () {
    test('fetchAll trả về danh sách Product đã parse', () async {
      final repository = ApiProductRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'wc_active': true,
                'count': 1,
                'data': [
                  {
                    'id': 101,
                    'name': 'Son Kem Lì Satin',
                    'sku': 'KC-0001',
                    'barcode': '893000000001',
                    'price': 189000,
                    'stock_quantity': 25,
                    'stock_status': 'instock',
                    'image_url': null,
                    'categories': [
                      {'id': 1, 'name': 'Son', 'slug': 'son'},
                    ],
                    'type': 'simple',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final products = await repository.fetchAll();

      expect(products.single.name, 'Son Kem Lì Satin');
      expect(products.single.price, 189000);
      expect(products.single.status, ProductStatus.inStock);
    });

    test('ném ApiProductException khi WooCommerce chưa active', () async {
      final repository = ApiProductRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'wc_active': false,
                'count': 0,
                'data': [],
                'message': 'WooCommerce chưa active, không đọc được sản phẩm.',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      expect(
        () => repository.fetchAll(),
        throwsA(
          isA<ApiProductException>()
              .having((e) => e.wcInactive, 'wcInactive', isTrue)
              .having((e) => e.message, 'message', contains('chưa active')),
        ),
      );
    });

    test('ném ApiProductException khi lỗi mạng', () async {
      final repository = ApiProductRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            throw http.ClientException('Connection refused');
          }),
        ),
      );

      expect(
        () => repository.fetchAll(),
        throwsA(
          isA<ApiProductException>()
              .having((e) => e.wcInactive, 'wcInactive', isFalse)
              .having((e) => e.message, 'message', contains('Không kết nối')),
        ),
      );
    });
  });
}