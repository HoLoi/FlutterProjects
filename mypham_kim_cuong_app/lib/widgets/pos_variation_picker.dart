import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/product_variation.dart';
import '../services/api_client.dart';
import 'product_image_box.dart';

/// Chọn biến thể cho sản phẩm variable trước khi thêm vào giỏ.
///
/// Sản phẩm variable bắt buộc gửi `variation_id > 0`; sửa ở `class-pos.php` sẽ
/// trả `400 kc_invalid_variation` nếu thiếu. Nên POS phải chọn biến thể thật
/// thay vì đoán.
///
/// Danh sách biến thể lấy từ `GET /wp-json/kc/v1/variations?product_id=` (public).
/// Trả `null` khi người dùng đóng hộp thoại.
Future<ProductVariation?> showPosVariationPicker(
  BuildContext context, {
  required Product product,
  required ApiClient apiClient,
}) {
  return showDialog<ProductVariation>(
    context: context,
    builder: (context) => _PosVariationPickerDialog(
      product: product,
      apiClient: apiClient,
    ),
  );
}

class _PosVariationPickerDialog extends StatefulWidget {
  const _PosVariationPickerDialog({
    required this.product,
    required this.apiClient,
  });

  final Product product;
  final ApiClient apiClient;

  @override
  State<_PosVariationPickerDialog> createState() =>
      _PosVariationPickerDialogState();
}

class _PosVariationPickerDialogState
    extends State<_PosVariationPickerDialog> {
  late final Future<List<ProductVariation>> _future = _load();

  Future<List<ProductVariation>> _load() async {
    final result = await widget.apiClient.fetchVariations(
      productId: widget.product.id,
      perPage: 50,
    );
    if (result.status != CatalogStatus.ok) {
      throw StateError(result.message ?? 'Không tải được danh sách biến thể');
    }
    return result.items
        .map(ApiVariationParser.fromJson)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Chọn biến thể · ${widget.product.name}'),
      content: SizedBox(
        width: 320,
        child: FutureBuilder<List<ProductVariation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '${snapshot.error}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              );
            }
            final variations = snapshot.data ?? const <ProductVariation>[];
            if (variations.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Sản phẩm này chưa có biến thể nào'),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: variations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final variation = variations[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ProductImageBox(
                    imageUrl: variation.imageUrl ?? widget.product.imageUrl,
                    size: 40,
                  ),
                  title: Text(
                    variation.attributeText.isEmpty
                        ? variation.name
                        : variation.attributeText,
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    '${formatPrice(variation.price)}'
                    '${variation.isOutOfStock ? ' · Hết hàng' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.add_shopping_cart),
                  onTap: () => Navigator.of(context).pop(variation),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
      ],
    );
  }
}
