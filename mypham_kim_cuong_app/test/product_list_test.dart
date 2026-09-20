import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/screens/product_list_screen.dart';

Widget _productApp() {
  return const MaterialApp(home: Scaffold(body: ProductListScreen()));
}

void main() {
  testWidgets('Hiển thị danh sách sản phẩm mẫu', (WidgetTester tester) async {
    await tester.pumpWidget(_productApp());

    expect(find.text('Danh sách sản phẩm'), findsOneWidget);
    expect(find.text('10 sản phẩm'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsOneWidget);
  });

  testWidgets('Tìm kiếm theo tên', (WidgetTester tester) async {
    await tester.pumpWidget(_productApp());

    await tester.enterText(find.byType(TextField), 'serum');
    await tester.pump();

    expect(find.text('Serum Vitamin C Brightening'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsNothing);
  });

  testWidgets('Tìm kiếm theo mã vạch', (WidgetTester tester) async {
    await tester.pumpWidget(_productApp());

    await tester.enterText(find.byType(TextField), '893000000003');
    await tester.pump();

    expect(find.text('Kem Chống Nắng SPF 50'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsNothing);
  });

  testWidgets('Lọc sản phẩm hết hàng', (WidgetTester tester) async {
    await tester.pumpWidget(_productApp());

    await tester.tap(find.widgetWithText(FilterChip, 'Hết hàng'));
    await tester.pump();

    expect(find.text('Kem Chống Nắng SPF 50'), findsOneWidget);
    expect(find.text('Nước Hoa Hồng Cân Bằng Da'), findsOneWidget);
    expect(find.text('Son Kem Lì Satin'), findsNothing);
  });

  testWidgets('Tìm không ra sản phẩm thì hiển thị trạng thái rỗng',
      (WidgetTester tester) async {
    await tester.pumpWidget(_productApp());

    await tester.enterText(find.byType(TextField), 'không tồn tại');
    await tester.pump();

    expect(find.text('Không tìm thấy sản phẩm'), findsOneWidget);
  });
}