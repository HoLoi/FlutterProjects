import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _CheckState { idle, checking, success, failure }

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final ApiClient _apiClient;

  _CheckState _state = _CheckState.idle;
  HealthResult? _result;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: AppSettings.baseUrl);
    _apiClient = widget.apiClient ?? ApiClient();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      AppSettings.baseUrl = _baseUrlController.text.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu cài đặt')),
    );
  }

  Future<void> _checkConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      AppSettings.baseUrl = _baseUrlController.text.trim();
      _state = _CheckState.checking;
      _result = null;
    });

    final result = await _apiClient.checkHealth();

    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      _state = result.status == HealthStatus.online
          ? _CheckState.success
          : _CheckState.failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final checking = _state == _CheckState.checking;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bản demo: chưa gọi dữ liệu thật, không sửa '
                          'WooCommerce. "Kiểm tra kết nối" chỉ xác minh '
                          'endpoint health của plugin.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ website (Base URL)',
                  hintText: 'https://vi-du.com',
                  border: OutlineInputBorder(),
                  helperText: 'Nhập địa chỉ website có cài plugin',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập địa chỉ website';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: checking ? null : _checkConnection,
                icon: Icon(checking
                    ? Icons.hourglass_top
                    : Icons.wifi_tethering),
                label: const Text('Kiểm tra kết nối'),
              ),
              const SizedBox(height: 16),
              _ResultCard(state: _state, result: _result),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: checking ? null : _save,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Lưu cài đặt'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state, required this.result});

  final _CheckState state;
  final HealthResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state) {
      case _CheckState.idle:
        return Text(
          'Nhập địa chỉ website rồi bấm "Kiểm tra kết nối".',
          style: theme.textTheme.bodySmall,
        );
      case _CheckState.checking:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Đang kiểm tra...'),
          ],
        );
      case _CheckState.success:
        final r = result!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text('Kết nối thành công', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (r.plugin != null) Text('Plugin: ${r.plugin}'),
            if (r.version != null) Text('Phiên bản: ${r.version}'),
            if (r.time != null) Text('Thời gian server: ${r.time}'),
            if (r.wordpress != null) Text('WordPress: ${r.wordpress}'),
            Text(
              r.woocommerceActive == true
                  ? 'WooCommerce: có hoạt động'
                  : 'WooCommerce: chưa kích hoạt',
            ),
          ],
        );
      case _CheckState.failure:
        final invalidUrl = result?.status == HealthStatus.invalidUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  invalidUrl ? Icons.warning_amber : Icons.error_outline,
                  color: invalidUrl ? Colors.orange : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  invalidUrl ? 'URL chưa hợp lệ' : 'Không kết nối được',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (result?.message != null) ...[
              const SizedBox(height: 8),
              Text(result!.message!),
            ],
          ],
        );
    }
  }
}