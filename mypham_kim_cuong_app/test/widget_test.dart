import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mypham_kim_cuong_app/main.dart';
import 'package:mypham_kim_cuong_app/models/app_settings.dart';

void main() {
  setUp(() {
    AppSettings.baseUrl = '';
  });

  testWidgets('App khởi động ở màn hình đăng nhập', (tester) async {
    await tester.pumpWidget(const MyPhamKimCuongApp());

    expect(find.text('Mỹ Phẩm Kim Cương'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });

  testWidgets('Đăng nhập demo mở màn hình chính', (tester) async {
    await tester.pumpWidget(const MyPhamKimCuongApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên đăng nhập'),
      'admin',
    );
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Bảng điều khiển'), findsOneWidget);
  });

  testWidgets('Điều hướng giữa Sản phẩm và POS', (tester) async {
    await tester.pumpWidget(const MyPhamKimCuongApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên đăng nhập'),
      'admin',
    );
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sản phẩm'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có dữ liệu'), findsOneWidget);

    await tester.tap(find.text('POS'));
    await tester.pumpAndSettle();
    expect(find.text('Màn hình POS'), findsOneWidget);
  });

  testWidgets('Cài đặt lưu base URL', (tester) async {
    await tester.pumpWidget(const MyPhamKimCuongApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên đăng nhập'),
      'admin',
    );
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Địa chỉ website (Base URL)'),
      'https://demo.local',
    );
    await tester.tap(find.text('Lưu cài đặt'));
    await tester.pump();

    expect(AppSettings.baseUrl, 'https://demo.local');
  });
}