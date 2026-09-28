import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypham_kim_cuong_app/data/pos_sale_repository.dart';
import 'package:mypham_kim_cuong_app/models/cart_item.dart';
import 'package:mypham_kim_cuong_app/models/order.dart';
import 'package:mypham_kim_cuong_app/models/pos_sale.dart';
import 'package:mypham_kim_cuong_app/models/product.dart';
import 'package:mypham_kim_cuong_app/models/product_variation.dart';
import 'package:mypham_kim_cuong_app/services/api_client.dart';
import 'package:mypham_kim_cuong_app/services/cart_controller.dart';
import 'package:mypham_kim_cuong_app/services/pos_checkout_controller.dart';

/// Ghi lại request và trả kết quả theo kịch bản.
class RecordingPosRepository implements PosSaleRepository {
  RecordingPosRepository({this.succeed = true, this.statusOnFailure});

  bool succeed;
  final PosSaleStatus? statusOnFailure;
  final List<PosSaleItemRequest> sentItems = [];
  final List<String> sentRequestIds = [];
  final List<String> sentPaymentMethods = [];
  int callCount = 0;

  @override
  Future<PosSaleResult> createPosSale({
    required String requestId,
    required String paymentMethod,
    required int customerId,
    required List<PosSaleItemRequest> items,
    String customerNote = '',
  }) async {
    callCount += 1;
    sentRequestIds.add(requestId);
    sentPaymentMethods.add(paymentMethod);
    sentItems.addAll(items);

    if (!succeed) {
      throw PosSaleException(
        statusOnFailure ?? PosSaleStatus.serverError,
        message: 'Lỗi giả lập',
        code: 'kc_test',
      );
    }

    return PosSaleResult(
      success: true,
      order: PosSaleOrder(
        id: 900 + callCount,
        number: 'POS-$callCount',
        status: OrderStatus.processing,
        createdVia: 'kc_pos',
        paymentMethod: paymentMethod,
        currency: 'VND',
        total: 189000,
        requestId: requestId,
        lineItems: const [],
      ),
      replayed: false,
    );
  }
}

ProductVariation variationOf({
  required int id,
  required int productId,
  String color = 'Đỏ',
  double price = 250000,
  bool inStock = true,
}) {
  return ProductVariation(
    id: id,
    productId: productId,
    name: 'Son Kem · $color',
    sku: 'KC-$id',
    price: price,
    stockQuantity: inStock ? 5 : 0,
    stockStatus: inStock ? 'instock' : 'outofstock',
    attributes: ['Màu sắc: $color'],
  );
}

Product simpleProduct({int id = 651, double price = 189000}) {
  return Product(
    id: id,
    name: 'Serum Vitamin C',
    sku: 'VC-30',
    barcode: '893000000001',
    price: price,
    status: ProductStatus.inStock,
    stockQuantity: 10,
  );
}

void main() {
  group('PosRequestId', () {
    test('sinh khoá hợp lệ theo regex của server', () {
      final id = PosRequestId.generate(
        random: Random(1),
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(id, startsWith('pos-1700000000000-'));
      expect(PosRequestId.isValid(id), isTrue);
      expect(id.length, lessThanOrEqualTo(64));
    });

    test('mỗi lần sinh cho khoá khác nhau', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(PosRequestId.generate());
      }
      expect(ids.length, 200);
    });

    test('chỉ dùng ký tự an toàn cho server', () {
      for (var i = 0; i < 100; i++) {
        expect(PosRequestId.isValid(PosRequestId.generate()), isTrue);
      }
    });

    test('từ chối khoá chứa ký tự server không chấp nhận', () {
      expect(PosRequestId.isValid('pos có dấu'), isFalse);
      expect(PosRequestId.isValid('pos/slash'), isFalse);
      expect(PosRequestId.isValid(''), isFalse);
      expect(PosRequestId.isValid('a' * 65), isFalse);
      expect(PosRequestId.isValid('a' * 64), isTrue);
    });
  });

  group('PosCheckoutController giữ request_id qua các lần gửi lại', () {
    late CartController cart;
    late List<CartItem> items;

    setUp(() {
      cart = CartController()..add(simpleProduct());
      items = cart.items;
    });

    tearDown(() {
      cart.dispose();
    });

    test('lần đầu sinh khoá mới', () async {
      final repository = RecordingPosRepository();
      final controller = PosCheckoutController(random: Random(7));

      final ok = await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );

      expect(ok, isTrue);
      expect(repository.sentRequestIds, hasLength(1));
      expect(controller.pendingRequestId, isNull, reason: 'đã tạo xong thì bỏ khoá');
      controller.dispose();
    });

    test('lỗi mạng rồi gửi lại thì dùng đúng khoá cũ', () async {
      final repository = RecordingPosRepository(
        succeed: false,
        statusOnFailure: PosSaleStatus.networkError,
      );
      final controller = PosCheckoutController(random: Random(7));

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      expect(controller.canRetry, isTrue);

      repository.succeed = true;
      final ok = await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );

      expect(ok, isTrue);
      expect(repository.sentRequestIds, hasLength(2));
      expect(
        repository.sentRequestIds[0],
        repository.sentRequestIds[1],
        reason: 'phải gửi lại cùng khoá để không tạo đơn trùng',
      );
      controller.dispose();
    });

    test('lỗi 500 rồi gửi lại thì dùng đúng khoá cũ', () async {
      final repository = RecordingPosRepository(
        succeed: false,
        statusOnFailure: PosSaleStatus.serverError,
      );
      final controller = PosCheckoutController(random: Random(7));

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      repository.succeed = true;
      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );

      expect(repository.sentRequestIds[0], repository.sentRequestIds[1]);
      controller.dispose();
    });

    test('lỗi hết hàng thì không cho gửi lại', () async {
      final repository = RecordingPosRepository(
        succeed: false,
        statusOnFailure: PosSaleStatus.outOfStock,
      );
      final controller = PosCheckoutController(random: Random(7));

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );

      expect(controller.canRetry, isFalse);
      controller.dispose();
    });

    test('giỏ đổi nội dung thì sinh khoá mới', () async {
      final repository = RecordingPosRepository(
        succeed: false,
        statusOnFailure: PosSaleStatus.networkError,
      );
      final controller = PosCheckoutController(random: Random(7));

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      final firstKey = repository.sentRequestIds.first;

      // Người bán sửa giỏ rồi gửi lại: nội dung đơn đã khác nên cần khoá mới.
      cart.add(simpleProduct(id: 652, price: 250000));
      repository.succeed = true;
      await controller.submit(
        repository: repository,
        items: cart.items,
        paymentMethod: 'cash',
      );

      expect(repository.sentRequestIds[1], isNot(firstKey));
      controller.dispose();
    });

    test('đơn thành công rồi bán lại thì dùng khoá khác', () async {
      final repository = RecordingPosRepository();
      final controller = PosCheckoutController(random: Random(7));

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      cart.add(simpleProduct(id: 652, price: 250000));
      await controller.submit(
        repository: repository,
        items: cart.items,
        paymentMethod: 'cash',
      );

      expect(repository.sentRequestIds[0], isNot(repository.sentRequestIds[1]));
      controller.dispose();
    });

    test('không gửi khi giỏ rỗng', () async {
      final repository = RecordingPosRepository();
      final controller = PosCheckoutController();

      final ok = await controller.submit(
        repository: repository,
        items: const [],
        paymentMethod: 'cash',
      );

      expect(ok, isFalse);
      expect(repository.callCount, 0);
      controller.dispose();
    });

    test('bỏ qua lần gọi thứ hai khi đang gửi', () async {
      final repository = RecordingPosRepository();
      final controller = PosCheckoutController();

      final first = controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      final second = controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );

      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(repository.callCount, 1, reason: 'không tạo hai đơn cùng lúc');
      controller.dispose();
    });

    test('gửi đúng product_id, variation_id, quantity từ giỏ', () async {
      final repository = RecordingPosRepository();
      final controller = PosCheckoutController();
      final variation = variationOf(id: 9001, productId: 652);
      cart.add(simpleProduct(id: 652, price: 250000), variation: variation);

      await controller.submit(
        repository: repository,
        items: cart.items,
        paymentMethod: 'vietqr',
      );

      expect(repository.sentItems, hasLength(2));
      expect(repository.sentItems[0].productId, 651);
      expect(repository.sentItems[0].variationId, 0);
      expect(repository.sentItems[0].quantity, 1);
      expect(repository.sentItems[1].productId, 652);
      expect(repository.sentItems[1].variationId, 9001);
      expect(repository.sentPaymentMethods.single, 'vietqr');
      controller.dispose();
    });

    test('reset xoá khoá và kết quả cũ', () async {
      final repository = RecordingPosRepository(
        succeed: false,
        statusOnFailure: PosSaleStatus.networkError,
      );
      final controller = PosCheckoutController();

      await controller.submit(
        repository: repository,
        items: items,
        paymentMethod: 'cash',
      );
      expect(controller.lastError, isNotNull);

      controller.reset();
      expect(controller.lastError, isNull);
      expect(controller.lastResult, isNull);
      expect(controller.pendingRequestId, isNull);
      controller.dispose();
    });
  });

  group('CartController phân biệt biến thể', () {
    test('cùng sản phẩm khác biến thể là hai dòng riêng', () {
      final cart = CartController();
      final product = simpleProduct(id: 652);
      final red = variationOf(id: 1, productId: 652, color: 'Đỏ', price: 250000);
      final blue = variationOf(id: 2, productId: 652, color: 'Xanh', price: 260000);

      cart.add(product, variation: red);
      cart.add(product, variation: blue);

      expect(cart.items, hasLength(2));
      expect(cart.subtotal, 510000);
      cart.dispose();
    });

    test('tăng giảm đúng biến thể được chọn', () {
      final cart = CartController();
      final product = simpleProduct(id: 652);
      final red = variationOf(id: 1, productId: 652, color: 'Đỏ');

      cart.add(product, variation: red);
      cart.increase(652, variationId: 1);
      cart.add(simpleProduct(id: 651));

      expect(cart.items, hasLength(2));
      expect(cart.items.first.quantity, 2);
      expect(cart.items.first.variationId, 1);

      cart.decrease(652, variationId: 1);
      expect(cart.items.first.quantity, 1);
      cart.dispose();
    });

    test('từ chối biến thể hết hàng', () {
      final cart = CartController();
      final soldOut = variationOf(id: 3, productId: 652, inStock: false);

      expect(cart.add(simpleProduct(id: 652), variation: soldOut), isFalse);
      expect(cart.isEmpty, isTrue);
      cart.dispose();
    });

    test('giá dòng giỏ lấy theo biến thể', () {
      final cart = CartController();
      final variation = variationOf(id: 1, productId: 652, color: 'Đỏ');

      cart.add(simpleProduct(id: 652, price: 189000), variation: variation);
      cart.add(simpleProduct(id: 652, price: 189000), variation: variation);

      final item = cart.items.single;
      expect(item.unitPrice, 250000, reason: 'giá biến thể thay giá sản phẩm');
      expect(item.lineTotal, 500000);
      expect(item.label, contains('Đỏ'));
      cart.dispose();
    });
  });
}
