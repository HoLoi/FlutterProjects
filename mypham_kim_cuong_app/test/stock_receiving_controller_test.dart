import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/models/product.dart';
import 'package:mypham_kim_cuong_app/models/stock_receiving.dart';
import 'package:mypham_kim_cuong_app/services/stock_receiving_controller.dart';

void main() {
  const product = Product(
    id: 1,
    name: 'Son Kem Lì Satin',
    sku: 'KC-0001',
    barcode: '893000000001',
    price: 189000,
    stockQuantity: 25,
    status: ProductStatus.inStock,
  );

  test('tạo phiếu nhập kho lưu vào danh sách và tăng id', () {
    final controller = StockReceivingController();
    const item = StockReceivingItem(
      product: product,
      quantity: 5,
      costPrice: 100000,
    );

    final record = controller.create(items: [item], note: 'Nhập lẻ');

    expect(controller.recordCount, 1);
    expect(record.id, 1);
    expect(controller.records.single.note, 'Nhập lẻ');
  });

  test('ghi chú rỗng được lưu là null', () {
    final controller = StockReceivingController();
    const item = StockReceivingItem(
      product: product,
      quantity: 1,
      costPrice: 1000,
    );

    final record = controller.create(items: [item], note: '   ');

    expect(record.note, isNull);
  });

  test('tổng tiền phiếu đúng', () {
    final controller = StockReceivingController();

    final record = controller.create(
      items: const [
        StockReceivingItem(product: product, quantity: 4, costPrice: 1000),
        StockReceivingItem(product: product, quantity: 2, costPrice: 2000),
      ],
    );

    expect(record.total, 8000);
  });

  test('mã lô rỗng hiển thị tự sinh khi triển khai thật', () {
    const emptyLot = StockReceivingItem(
      product: product,
      quantity: 1,
      costPrice: 1,
    );
    const filledLot = StockReceivingItem(
      product: product,
      quantity: 1,
      costPrice: 1,
      batchCode: 'L01',
    );

    expect(emptyLot.batchLabel, 'Tự sinh khi triển khai thật');
    expect(filledLot.batchLabel, 'L01');
  });
}