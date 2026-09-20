import 'package:flutter/material.dart';

import '../data/product_repository.dart';
import '../models/product.dart';
import '../models/stock_receiving.dart';
import '../services/stock_receiving_controller.dart';
import '../widgets/code_input_dialog.dart';
import '../widgets/product_picker_dialog.dart';

class StockReceivingScreen extends StatefulWidget {
  const StockReceivingScreen({super.key, this.repository, this.controller});

  final ProductRepository? repository;
  final StockReceivingController? controller;

  @override
  State<StockReceivingScreen> createState() => _StockReceivingScreenState();
}

class _StockReceivingScreenState extends State<StockReceivingScreen> {
  late final ProductRepository _repository;
  late final StockReceivingController _controller;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;
  late final TextEditingController _batchController;
  late final TextEditingController _productionController;
  late final TextEditingController _expiryController;
  late final TextEditingController _noteController;

  Product? _product;
  String? _dateError;

  bool get _ownsController => widget.controller == null;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockProductRepository();
    _controller = widget.controller ?? StockReceivingController();
    _quantityController = TextEditingController();
    _costController = TextEditingController();
    _batchController = TextEditingController();
    _productionController = TextEditingController();
    _expiryController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    _quantityController.dispose();
    _costController.dispose();
    _batchController.dispose();
    _productionController.dispose();
    _expiryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  String? _validateDates() {
    final nsxText = _productionController.text.trim();
    final hsdText = _expiryController.text.trim();
    DateTime? nsx;
    DateTime? hsd;
    if (nsxText.isNotEmpty) {
      nsx = _parseDate(nsxText);
      if (nsx == null) {
        return 'NSX sai định dạng, vui lòng dùng YYYY-MM-DD';
      }
    }
    if (hsdText.isNotEmpty) {
      hsd = _parseDate(hsdText);
      if (hsd == null) {
        return 'HSD sai định dạng, vui lòng dùng YYYY-MM-DD';
      }
    }
    if (nsx != null && hsd != null && hsd.isBefore(nsx)) {
      return 'HSD không được trước NSX';
    }
    return null;
  }

  Future<void> _lookupCode() async {
    final code = await showCodeInputDialog(
      context,
      title: 'Nhập mã sản phẩm',
      label: 'Barcode / SKU',
    );
    if (code == null || code.isEmpty) {
      return;
    }
    final product = _repository.findProductByCode(code);
    if (product == null) {
      _showMessage('Không tìm thấy sản phẩm với mã "$code"');
      return;
    }
    setState(() => _product = product);
    _showMessage('Đã chọn: ${product.name}');
  }

  Future<void> _pickProduct() async {
    final product = await showProductPickerDialog(context, _repository);
    if (product != null && mounted) {
      setState(() => _product = product);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final initial = _parseDate(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = _formatDate(picked);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirm() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final dateError = _validateDates();
    setState(() => _dateError = dateError);
    if (_product == null) {
      _showMessage('Vui lòng chọn sản phẩm');
    }
    if (!formValid || dateError != null || _product == null) {
      return;
    }
    final quantity = int.parse(_quantityController.text.trim());
    final cost = double.parse(_costController.text.trim());
    final nsxText = _productionController.text.trim();
    final hsdText = _expiryController.text.trim();
    final item = StockReceivingItem(
      product: _product!,
      quantity: quantity,
      costPrice: cost,
      batchCode: _batchController.text.trim(),
      productionDate: nsxText.isEmpty ? null : _parseDate(nsxText),
      expiryDate: hsdText.isEmpty ? null : _parseDate(hsdText),
    );
    final record = _controller.create(
      items: [item],
      note: _noteController.text.trim(),
    );
    await _showSummary(record);
    if (mounted) {
      _clearForm();
    }
  }

  void _clearForm() {
    setState(() {
      _product = null;
      _dateError = null;
      _quantityController.clear();
      _costController.clear();
      _batchController.clear();
      _productionController.clear();
      _expiryController.clear();
      _noteController.clear();
    });
  }

  Future<void> _showSummary(StockReceiving record) async {
    final item = record.items.single;
    final product = item.product;
    final rows = <String>[
      'Số lượng: ${item.quantity}',
      'Giá nhập: ${formatPrice(item.costPrice)}',
      'Tổng tiền: ${formatPrice(item.total)}',
      'Mã lô: ${item.batchLabel}',
    ];
    if (item.productionDate != null) {
      rows.add('NSX: ${_formatDate(item.productionDate!)}');
    }
    if (item.expiryDate != null) {
      rows.add('HSD: ${_formatDate(item.expiryDate!)}');
    }
    if (record.note != null) {
      rows.add('Ghi chú: ${record.note}');
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Phiếu nhập kho demo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Đã lưu tạm trong bộ nhớ.\nKhông gọi API, không sửa WooCommerce.'),
                const SizedBox(height: 12),
                Text(
                  product.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'SKU: ${product.sku} · Mã vạch: ${product.barcode}',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 16),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(row),
                  ),
                const Divider(height: 16),
                Text('Phiếu #${record.id}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nhập kho',
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('Bản demo local', style: theme.textTheme.bodySmall),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Nhập mã',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _lookupCode,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  InkWell(
                    onTap: _pickProduct,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sản phẩm *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: _product == null
                            ? const Icon(Icons.arrow_drop_down)
                            : IconButton(
                                tooltip: 'Bỏ chọn',
                                icon: const Icon(Icons.close),
                                onPressed: _clearFormProduct,
                              ),
                      ),
                      child: _product == null
                          ? const Text(
                              'Chọn sản phẩm',
                              style: TextStyle(color: Colors.grey),
                            )
                          : Text(
                              '${_product!.name} — SKU: ${_product!.sku}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Số lượng',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Vui lòng nhập số lượng';
                      }
                      final quantity = int.tryParse(text);
                      if (quantity == null || quantity <= 0) {
                        return 'Số lượng phải lớn hơn 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Giá nhập',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Vui lòng nhập giá nhập';
                      }
                      final cost = double.tryParse(text);
                      if (cost == null || cost < 0) {
                        return 'Giá nhập phải >= 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _batchController,
                    decoration: InputDecoration(
                      labelText: 'Mã lô (tùy chọn)',
                      hintText: 'Để trống sẽ tự sinh khi triển khai thật',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    controller: _productionController,
                    label: 'NSX — ngày sản xuất (tùy chọn)',
                    tooltip: 'Chọn NSX',
                    onPick: () => _pickDate(_productionController),
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    controller: _expiryController,
                    label: 'HSD — hạn sử dụng (tùy chọn)',
                    tooltip: 'Chọn HSD',
                    onPick: () => _pickDate(_expiryController),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Ghi chú (tùy chọn)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_dateError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dateError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phiếu nhập kho demo đã tạo: ${_controller.recordCount}',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (_controller.records.isEmpty)
                          Text(
                            'Chưa có phiếu nào — dữ liệu tạm trong bộ nhớ',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          )
                        else
                          ..._controller.records.take(5).map(
                                (record) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ReceiptTile(record: record),
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.warehouse),
              label: const Text('Xác nhận nhập kho demo'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearFormProduct() {
    setState(() => _product = null);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.tooltip,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final String tooltip;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          tooltip: tooltip,
          icon: const Icon(Icons.calendar_month),
          onPressed: onPick,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.record});

  final StockReceiving record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String subtitle = '${record.items.length} dòng · Tổng: ${formatPrice(record.total)}';
    if (record.note != null) {
      subtitle = '$subtitle · ${record.note}';
    }
    String formatDate(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.warehouse_outlined),
        title: Text('Phiếu #${record.id} · ${formatDate(record.createdAt)}'),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          'Demo',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.disabledColor),
        ),
      ),
    );
  }
}