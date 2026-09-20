import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() {
  runApp(const MyPhamKimCuongApp());
}

class MyPhamKimCuongApp extends StatelessWidget {
  const MyPhamKimCuongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mỹ Phẩm Kim Cương',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LoginScreen(),
    );
  }
}