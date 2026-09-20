import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/screens/stock_receiving_screen.dart';

Widget _stockApp() {
  return const MaterialApp(home: Scaffold(body: StockReceivingScreen()));
}

Future<void> _pumpStock(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_stockApp());
}

Future<void> _selectProduct(WidgetTester tester, String query) async {
  await tester.tap(find.text('Chọn sản phẩm'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump();
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.tap(find.byTooltip('Nhập mã'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    code,
  );
  await tester.tap(find.text('Tìm'));
  await tester.pumpAndSettle();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String? quantity,
  String? cost,
  String? batch,
  String? nsx,
  String? hsd,
  String? note,
}) async {
  if (quantity != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Số lượng'),
      quantity,
    );
  }
  if (cost != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Giá nhập'),
      cost,
    );
  }
  if (batch != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mã lô (tùy chọn)'),
      batch,
    );
  }
  if (nsx != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'NSX — ngày sản xuất (tùy chọn)'),
      nsx,
    );
  }
  if (hsd != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'HSD — hạn sử dụng (tùy chọn)'),
      hsd,
    );
  }
  if (note != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ghi chú (tùy chọn)'),
      note,
    );
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Xác nhận nhập kho demo'));
  await tester.tap(find.text('Xác nhận nhập kho demo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Màn nhập kho hiển thị các trường cơ bản', (tester) async {
    await _pumpStock(tester);

    expect(find.text('Nhập kho'), findsOneWidget);
    expect(find.text('Chọn sản phẩm'), findsOneWidget);
    expect(find.text('Số lượng'), findsOneWidget);
    expect(find.text('Giá nhập'), findsOneWidget);
    expect(find.text('Mã lô (tùy chọn)'), findsOneWidget);
    expect(find.text('NSX — ngày sản xuất (tùy chọn)'), findsOneWidget);
    expect(find.text('HSD — hạn sử dụng (tùy chọn)'), findsOneWidget);
    expect(find.text('Ghi chú (tùy chọn)'), findsOneWidget);
    expect(find.text('Xác nhận nhập kho demo'), findsOneWidget);
  });

  testWidgets('Chọn sản phẩm bằng tìm kiếm trong bộ chọn', (tester) async {
    await _pumpStock(tester);

    await _selectProduct(tester, 'serum');

    expect(find.textContaining('Serum Vitamin C Brightening'), findsOneWidget);
  });

  testWidgets('Xác nhận khi chưa chọn sản phẩm báo lỗi', (tester) async {
    await _pumpStock(tester);

    await _confirm(tester);

    expect(find.text('Vui lòng chọn sản phẩm'), findsOneWidget);
    expect(find.text('Phiếu nhập kho demo'), findsNothing);
  });

  testWidgets('Số lượng phải lớn hơn 0', (tester) async {
    await _pumpStock(tester);

    await _selectProduct(tester, 'serum');
    await _fillForm(tester, quantity: '0', cost: '100000');
    await _confirm(tester);

    expect(find.text('Số lượng phải lớn hơn 0'), findsOneWidget);
    expect(find.text('Phiếu nhập kho demo'), findsNothing);
  });

  testWidgets('Xác nhận nhập kho demo hiển thị tóm tắt và lưu tạm vào bộ nhớ',
      (tester) async {
    await _pumpStock(tester);

    await _selectProduct(tester, 'serum');
    await _fillForm(
      tester,
      quantity: '5',
      cost: '100000',
      note: 'Nhập lẻ đợt mới',
    );
    await _confirm(tester);

    expect(find.text('Phiếu nhập kho demo'), findsOneWidget);
    expect(find.textContaining('Không gọi API'), findsOneWidget);
    expect(find.text('Serum Vitamin C Brightening'), findsOneWidget);
    expect(find.text('Số lượng: 5'), findsOneWidget);
    expect(find.text('Giá nhập: 100.000 đ'), findsOneWidget);
    expect(find.text('Tổng tiền: 500.000 đ'), findsOneWidget);
    expect(find.text('Mã lô: Tự sinh khi triển khai thật'), findsOneWidget);
    expect(find.text('Ghi chú: Nhập lẻ đợt mới'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Phiếu nhập kho demo đã tạo: 1'), findsOneWidget);
    expect(find.text('Chọn sản phẩm'), findsOneWidget);
  });

  testWidgets('Nhập mã lô thì tóm tắt hiển thị mã lô đó', (tester) async {
    await _pumpStock(tester);

    await _selectProduct(tester, 'Kem Chống Nắng');
    await _fillForm(
      tester,
      quantity: '10',
      cost: '120000',
      batch: 'L01',
      nsx: '2026-09-01',
      hsd: '2027-09-01',
    );
    await _confirm(tester);

    expect(find.text('Phiếu nhập kho demo'), findsOneWidget);
    expect(find.text('Mã lô: L01'), findsOneWidget);
    expect(find.text('NSX: 2026-09-01'), findsOneWidget);
    expect(find.text('HSD: 2027-09-01'), findsOneWidget);
  });

  testWidgets('HSD trước NSX bị chặn', (tester) async {
    await _pumpStock(tester);

    await _selectProduct(tester, 'serum');
    await _fillForm(
      tester,
      quantity: '2',
      cost: '50000',
      nsx: '2026-09-20',
      hsd: '2026-09-19',
    );
    await _confirm(tester);

    expect(find.text('HSD không được trước NSX'), findsOneWidget);
    expect(find.text('Phiếu nhập kho demo'), findsNothing);
  });

  testWidgets('Nhập mã nhanh chọn được sản phẩm', (tester) async {
    await _pumpStock(tester);

    await _enterCode(tester, '893000000001');

    expect(find.text('Son Kem Lì Satin — SKU: KC-0001'), findsOneWidget);
    expect(find.textContaining('Đã chọn: Son Kem Lì Satin'), findsOneWidget);
  });

  testWidgets('Chọn NSX bằng lịch điền ngày hôm nay', (tester) async {
    await _pumpStock(tester);

    await tester.tap(find.byTooltip('Chọn NSX'));
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.widgetWithText(
        TextFormField,
        'NSX — ngày sản xuất (tùy chọn)',
      ),
    );
    expect(field.controller!.text, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });
}
