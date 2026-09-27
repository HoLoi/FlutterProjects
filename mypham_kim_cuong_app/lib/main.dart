import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_session.dart';

void main() {
  runApp(const MyPhamKimCuongApp());
}

class MyPhamKimCuongApp extends StatefulWidget {
  const MyPhamKimCuongApp({super.key, this.authSession, this.apiClient});

  /// Cho phép test tiêm session và API client giả lập.
  final AuthSession? authSession;
  final ApiClient? apiClient;

  @override
  State<MyPhamKimCuongApp> createState() => _MyPhamKimCuongAppState();
}

class _MyPhamKimCuongAppState extends State<MyPhamKimCuongApp> {
  late final AuthSession _authSession;

  @override
  void initState() {
    super.initState();
    _authSession = widget.authSession ?? AuthSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mỹ Phẩm Kim Cương',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: LoginScreen(
        authSession: _authSession,
        apiClient: widget.apiClient ?? ApiClient(authSession: _authSession),
      ),
    );
  }
}
