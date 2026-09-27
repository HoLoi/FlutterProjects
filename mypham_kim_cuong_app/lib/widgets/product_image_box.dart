import 'package:flutter/material.dart';

/// Khung ảnh sản phẩm dùng chung cho danh sách và chi tiết đơn hàng.
///
/// Kích thước cố định nên layout không nhảy khi ảnh tải xong hoặc tải lỗi:
/// - `imageUrl` hợp lệ (http/https) thì hiện `Image.network` phủ kín khung.
/// - Chưa tải xong frame nào thì hiện spinner nhỏ, vẫn nằm gọn trong khung.
/// - Thiếu URL hoặc tải lỗi thì hiện `Icons.spa` (không crash).
class ProductImageBox extends StatelessWidget {
  const ProductImageBox({
    super.key,
    required this.imageUrl,
    this.size = 56,
    this.borderRadius = 10,
  });

  /// URL ảnh từ API; `null` hoặc rỗng nghĩa là sản phẩm chưa có ảnh.
  final String? imageUrl;

  /// Cạnh của khung vuông, ví dụ 56 cho chi tiết đơn, 40 cho danh sách.
  final double size;

  /// Bán kính bo góc nhẹ, khớp phong cách card hiện có.
  final double borderRadius;

  static const double _spinnerSize = 18;
  static const double _spinnerStroke = 2;

  /// URL có thể hiển thị hay không.
  ///
  /// Chỉ nhận `http`/`https` có host để không đưa nhầm đường dẫn filesystem hay
  /// scheme lạ vào `NetworkImage`.
  static bool isRenderable(String? url) {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      // Cắt ảnh theo bo góc giống placeholder bên trong.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: _content(theme),
    );
  }

  Widget _content(ThemeData theme) {
    final placeholder = _placeholder(theme);
    final url = imageUrl?.trim() ?? '';
    if (!isRenderable(url)) {
      return placeholder;
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return _loading(theme);
        }
        return child;
      },
      // Ảnh hỏng hoặc URL không tồn tại: về lại icon, không crash.
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Center(
      child: Icon(Icons.spa, color: theme.colorScheme.onPrimaryContainer),
    );
  }

  Widget _loading(ThemeData theme) {
    return Center(
      child: SizedBox(
        width: _spinnerSize,
        height: _spinnerSize,
        child: CircularProgressIndicator(
          strokeWidth: _spinnerStroke,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
