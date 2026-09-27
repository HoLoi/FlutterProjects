# 04 · Mô Hình Dữ Liệu

## 1. Nguyên tắc

1. **Không tạo database sản phẩm riêng cho Flutter.**
2. **Không viết SQL trực tiếp để sửa tồn kho.**
3. Chỉ tạo dữ liệu riêng **khi WooCommerce thật sự không có**.
4. Plugin không sửa core WordPress/WooCommerce.

## 2. Nguồn dữ liệu theo nhóm

| Nhóm | Nơi lưu | Ví dụ |
|---|---|---|
| Dữ liệu bán hàng chính | WooCommerce | Sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng, danh mục, media |
| Nghiệp vụ mở rộng (khi cần) | Custom table `wp_kc_*` | Lô hàng/HSD, nhà cung cấp, lịch sử nhập kho, giao dịch POS |
| Cấu hình nhẹ | `wp_options` (prefix `kc_`) | Cài đặt, tham số chung |

## 3. Trạng thái database hiện tại

**MVP-10 và MVP-11 không tạo bảng nào.** Toàn bộ dữ liệu đọc được đến từ WooCommerce.

Lý do: các trường đọc trong giai đoạn này (sản phẩm, biến thể, danh mục, đơn hàng) WooCommerce đã có sẵn.

## 4. Dữ liệu WooCommerce được dùng

### Sản phẩm (`WC_Product`)
| Trường app | Nguồn WooCommerce |
|---|---|
| `id` | `get_id()` |
| `name` | `get_name()` |
| `sku` | `get_sku()` |
| `barcode` | post meta `_mkc_barcode`, fallback `_barcode` |
| `price` | `get_price()` |
| `regular_price` | `get_regular_price()` |
| `sale_price` | `get_sale_price()` |
| `stock_quantity` | `get_stock_quantity()` — có thể `null` |
| `stock_status` | `get_stock_status()` |
| `image_url` | ảnh đại diện qua `wp_get_attachment_image_url()` |
| `categories` | `get_category_ids()` |
| `type` | `get_type()` |

### Biến thể (`WC_Product_Variation`)
Dùng chung bộ trường với sản phẩm, thêm `product_id` và `attributes`.

### Danh mục (`WP_Term`)
`id`, `name`, `slug`, `parent`, `count`.

### Đơn hàng (`WC_Order`)
> WooCommerce 10.4.4 dùng HPOS (High-Performance Order Storage) → đơn nằm ở `wp_wc_orders`.
> **Phải đọc đơn bằng `wc_get_order()` / `wc_get_orders()` — không SQL tay vào bảng đơn hàng.**

Trường dùng: `id`, `number`, `status`, `date_created`, `customer`, `payment_method`, `payment_status`, tổng tiền, và các line item.

## 5. Bảng riêng — khi nào mới tạo

Chỉ tạo khi WooCommerce không đáp ứng được, và tạo **tối thiểu**:

| Nghiệp vụ | Bảng đề xuất | MVP |
|---|---|---|
| Lô hàng + hạn sử dụng | `kc_lots`, `kc_lot_ledger` | MVP-16 (chỉ khi cửa hàng xác nhận cần) |
| Nhà cung cấp | `kc_suppliers` | MVP-14 |
| Lịch sử nhập kho | `kc_receivings`, `kc_receiving_items` | MVP-14 |
| Giao dịch POS | `kc_pos_transactions` | MVP-13 (nếu cần mã riêng) |
| Chống tạo đơn trùng | `kc_idempotency_keys` | MVP-13 |

Quy tắc khi tạo bảng:
- Prefix `{wpdb->prefix}kc_` → `wp_kc_*`
- Phiên bản schema lưu trong option `kc_db_version`
- Dùng `dbDelta()` để tạo/cập nhật
- Deactivate plugin **không** xóa dữ liệu
- Không tạo hàng chục bảng; mỗi bảng phải phục vụ một nghiệp vụ đã xác nhận

## 6. Xử lý dữ liệu thiếu ở phía app

WooCommerce có thể trả trường rỗng. App hiển thị fallback thay vì lỗi:

| Trường rỗng | Hiển thị |
|---|---|
| Tên | "Sản phẩm chưa có tên" |
| SKU | "Chưa có SKU" |
| Barcode | "Chưa có mã" |
| Tồn kho (`null`) | "Không quản lý số lượng" |
| Giá `0` | "Chưa có giá" |

Được khóa bằng test trong `test/product_api_test.dart`.

## 7. Tài liệu liên quan

[02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md) · [03_API_SPECIFICATION](03_API_SPECIFICATION.md) · [DECISIONS](DECISIONS.md)
