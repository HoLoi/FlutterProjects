import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/data/product_repository.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';
import 'package:mypham_kim_cuong_app/models/stock_receiving.dart';
import 'package:mypham_kim_cuong_app/screens/dashboard_screen.dart';
import 'package:mypham_kim_cuong_app/services/cart_controller.dart';
import 'package:mypham_kim_cuong_app/services/stock_receiving_controller.dart';

Future<void> _pumpDashboard(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
}

void main() {
  setUp(() {
    AppSettings.baseUrl = '';
  });

  testWidgets('Dashboard hiển thị tổng sản phẩm và trạng thái kho',
      (tester) async {
    await _pumpDashboard(tester, const DashboardScreen());

    expect(find.text('Bảng điều khiển'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Dashboard hiển thị cảnh báo chưa kết nối API khi base URL rỗng',
      (tester) async {
    AppSettings.baseUrl = '';

    await _pumpDashboard(tester, const DashboardScreen());

    expect(find.text('Chưa kết nối API'), findsOneWidget);
  });

  testWidgets('Dashboard không hiện cảnh báo kết nối khi đã có base URL',
      (tester) async {
    AppSettings.baseUrl = 'https://demo.local';

    await _pumpDashboard(tester, const DashboardScreen());

    expect(find.text('Chưa kết nối API'), findsNothing);
  });

  testWidgets('Dashboard cập nhật số phiếu và tổng tiền nhập kho',
      (tester) async {
    final stock = StockReceivingController();
    final product = MockProductRepository().getProducts().first;
    stock.create(
      items: [
        StockReceivingItem(product: product, quantity: 5, costPrice: 100000),
      ],
    );

    await _pumpDashboard(
      tester,
      DashboardScreen(stockController: stock),
    );

    expect(find.text('1 phiếu'), findsOneWidget);
    expect(find.text('500.000 đ'), findsOneWidget);

    stock.create(
      items: [
        StockReceivingItem(product: product, quantity: 3, costPrice: 20000),
      ],
    );
    await tester.pump();

    expect(find.text('2 phiếu'), findsOneWidget);
    expect(find.text('560.000 đ'), findsOneWidget);
  });

  testWidgets('Dashboard phản ánh giỏ POS hiện tại', (tester) async {
    final cart = CartController();
    cart.add(MockProductRepository().getProducts().first);

    await _pumpDashboard(tester, DashboardScreen(cart: cart));

    expect(find.text('1 món'), findsOneWidget);
    expect(find.text('189.000 đ'), findsOneWidget);
  });
}