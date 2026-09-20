import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/screens/pos_screen.dart';

Widget _posApp() {
  return const MaterialApp(home: Scaffold(body: PosScreen()));
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

void main() {
  testWidgets('Thêm sản phẩm vào giỏ và tổng tiền đúng', (tester) async {
    await tester.pumpWidget(_posApp());

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    expect(find.text('1 món · Tổng: 189.000 đ'), findsOneWidget);

    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();
    expect(find.text('2 món · Tổng: 378.000 đ'), findsOneWidget);
  });

  testWidgets('Tăng và giảm số lượng trong giỏ', (tester) async {
    await tester.pumpWidget(_posApp());
    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    await tester.tap(find.byTooltip('Tăng số lượng'));
    await tester.pump();
    expect(find.text('2 món · Tổng: 378.000 đ'), findsOneWidget);

    await tester.tap(find.byTooltip('Giảm số lượng'));
    await tester.pump();
    expect(find.text('1 món · Tổng: 189.000 đ'), findsOneWidget);
  });

  testWidgets('Xóa sản phẩm khỏi giỏ', (tester) async {
    await tester.pumpWidget(_posApp());
    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    await tester.tap(find.byTooltip('Xóa khỏi giỏ'));
    await tester.pump();
    expect(find.text('Giỏ hàng trống'), findsOneWidget);
  });

  testWidgets('Không thêm được sản phẩm hết hàng', (tester) async {
    await tester.pumpWidget(_posApp());

    await tester.enterText(find.byType(TextField), 'Chống Nắng');
    await tester.pump();

    await tester.tap(find.byTooltip('Thêm vào giỏ'));
    await tester.pump();

    expect(find.textContaining('đã hết hàng'), findsOneWidget);
    expect(find.text('Giỏ hàng trống'), findsOneWidget);
  });

  testWidgets('Tìm kiếm sản phẩm trong POS', (tester) async {
    await tester.pumpWidget(_posApp());

    await tester.enterText(find.byType(TextField), 'serum');
    await tester.pump();

    expect(find.text('Serum Vitamin C Brightening'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsNothing);
  });

  testWidgets('Thanh toán demo xác nhận sẽ xóa giỏ', (tester) async {
    await tester.pumpWidget(_posApp());
    await tester.tap(find.byTooltip('Thêm vào giỏ').first);
    await tester.pump();

    await tester.tap(find.text('Thanh toán demo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thanh toán demo thành công'), findsOneWidget);

    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();

    expect(find.text('Giỏ hàng trống'), findsOneWidget);
  });

  testWidgets('POS nhập barcode còn hàng thì thêm vào giỏ', (tester) async {
    await tester.pumpWidget(_posApp());

    await _enterCode(tester, '893000000001');

    expect(find.text('1 món · Tổng: 189.000 đ'), findsOneWidget);
    expect(find.textContaining('Đã thêm'), findsOneWidget);
  });

  testWidgets('POS nhập barcode hết hàng thì báo và không thêm', (tester) async {
    await tester.pumpWidget(_posApp());

    await _enterCode(tester, '893000000003');

    expect(find.text('Giỏ hàng trống'), findsOneWidget);
    expect(find.textContaining('đã hết hàng'), findsOneWidget);
  });

  testWidgets('POS nhập mã không tồn tại thì có thông báo', (tester) async {
    await tester.pumpWidget(_posApp());

    await _enterCode(tester, '999999999');

    expect(find.text('Giỏ hàng trống'), findsOneWidget);
    expect(
      find.textContaining('Không tìm thấy sản phẩm, có thể tạo mới'),
      findsOneWidget,
    );
  });
}