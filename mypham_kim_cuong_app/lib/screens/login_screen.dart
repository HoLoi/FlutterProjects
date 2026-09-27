import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_session.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authSession, this.apiClient});

  final AuthSession? authSession;
  final ApiClient? apiClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _appPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  late final AuthSession _authSession;
  late final ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    _authSession = widget.authSession ?? AuthSession();
    final session = widget.authSession;
    _apiClient =
        widget.apiClient ?? ApiClient(authSession: session ?? _authSession);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _appPasswordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final status = await _apiClient.verifyLogin(
      username: _usernameController.text,
      appPassword: _appPasswordController.text,
    );

    if (!mounted) {
      return;
    }

    if (status.failed) {
      setState(() {
        _loading = false;
        _error = status.message;
      });
      return;
    }

    _authSession.signIn(
      username: _usernameController.text,
      appPassword: _appPasswordController.text,
    );

    // Xoá ngay khỏi ô nhập để mật khẩu không còn trong cây widget.
    _appPasswordController.clear();
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    _openDashboard();
  }

  void _openDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DashboardScreen(authSession: _authSession),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.storefront,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mỹ Phẩm Kim Cương',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đăng nhập bằng tài khoản WordPress',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_loading,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                      hintText: 'username WordPress',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập tên đăng nhập';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _appPasswordController,
                    enabled: !_loading,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Application Password',
                      helperText: 'Lấy tại WordPress: Hồ sơ người dùng → Application Passwords.',
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Hiện Application Password'
                            : 'Ẩn Application Password',
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập Application Password';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Đăng nhập'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : _openDashboard,
                    child: const Text('Bỏ qua, dùng chế độ demo'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chỉ dùng để xem đơn hàng. Sản phẩm và POS vẫn xem được '
                    'khi bỏ qua đăng nhập.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
