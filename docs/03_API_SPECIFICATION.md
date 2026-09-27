# 03 · Đặc Tả API

## 1. Phạm vi

Tất cả endpoint thuộc namespace `kc/v1` của plugin `mypham-kim-cuong-manager`.

```text
Base URL: https://{host}/wp-json/kc/v1
```

Giai đoạn hiện tại (MVP-10, MVP-11) **chỉ dùng GET** — read-only.

## 2. Quy ước chung

| Vấn đề | Quy ước |
|---|---|
| Giao thức | HTTPS bắt buộc, `Accept: application/json` |
| Timeout | 10 giây (phía app) |
| Phân trang | `page` (≥1, mặc định 1), `per_page` (tối đa 50) |
| Tìm kiếm | `search` |
| WooCommerce chưa active | Trả `wc_active: false` + `message` thay vì lỗi 500 |
| Lỗi mạng/HTTP | App tự hiển thị thông báo, không retry tự động |

Cấu trúc response thành công (danh sách):

```json
{
  "wc_active": true,
  "count": 2,
  "page": 1,
  "per_page": 20,
  "data": [ ... ]
}
```

## 3. Endpoint đang có

Tất cả endpoint dưới đây đã được cài đặt trong plugin và chỉ nhận `GET`.

### GET `/health`
Kiểm tra kết nối. Public, không cần xác thực.

```json
{
  "ok": true,
  "plugin": "mypham-kim-cuong-manager",
  "version": "1.0.0",
  "time": "2026-09-27 10:00:00",
  "wordpress": "7.1.1",
  "woocommerce_active": true
}
```

### GET `/products`
Danh sách sản phẩm WooCommerce. Tham số: `search`, `page`, `per_page`.

```json
{
  "wc_active": true,
  "count": 1,
  "page": 1,
  "per_page": 20,
  "data": [
    {
      "id": 101,
      "name": "Son Kem Lì Satin",
      "sku": "KC-0001",
      "barcode": "893000000001",
      "price": 189000,
      "regular_price": 189000,
      "sale_price": null,
      "stock_quantity": 25,
      "stock_status": "instock",
      "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son.png",
      "categories": [{ "id": 3, "name": "Son", "slug": "son" }],
      "type": "simple"
    }
  ]
}
```

Lưu ý: `stock_quantity` có thể là `null` khi WooCommerce không quản lý tồn kho cho sản phẩm đó.

## 4. Endpoint MVP-11 (chỉ đọc)

### GET `/categories`
Danh sách danh mục sản phẩm, sắp xếp theo tên. Tham số: `search`, `page`, `per_page`.

```json
{
  "wc_active": true,
  "count": 1,
  "page": 1,
  "per_page": 50,
  "data": [
    { "id": 3, "name": "Son", "slug": "son", "parent": 0, "count": 12 }
  ]
}
```

### GET `/variations`
Biến thể của một sản phẩm. Tham số: `product_id` (bắt buộc, chấp nhận cả `parent_id`), `search`.

Endpoint trả về **toàn bộ** biến thể của sản phẩm nên `page` luôn bằng `1` và `per_page` bằng số phần tử thực tế. `search` được lọc phía máy chủ theo tên và SKU.

```json
{
  "wc_active": true,
  "count": 1,
  "page": 1,
  "per_page": 1,
  "data": [
    {
      "id": 88,
      "product_id": 101,
      "name": "Son Kem Lì Satin - 30ml",
      "sku": "KC-0001-30",
      "barcode": "893000000001",
      "price": 189000,
      "regular_price": 189000,
      "sale_price": null,
      "stock_quantity": 10,
      "stock_status": "instock",
      "image_url": null,
      "attributes": [{ "name": "Dung lượng", "option": "30ml" }]
    }
  ]
}
```

`stock_quantity` có thể là `null`. `image_url` lấy ảnh biến thể, nếu không có thì lấy ảnh sản phẩm cha.

### GET `/orders`
Danh sách đơn hàng WooCommerce (HPOS-safe, đọc bằng `wc_get_orders()`), mới nhất trước.
Tham số: `page`, `per_page`, `status`, `search`, `date_from`, `date_to`.

`status`: `any` hoặc bỏ trống (mặc định), `pending`, `processing`, `on-hold`, `completed`, `cancelled`, `refunded`, `failed`.

```json
{
  "wc_active": true,
  "count": 1,
  "page": 1,
  "per_page": 20,
  "data": [
    {
      "id": 501,
      "number": "501",
      "status": "processing",
      "status_label": "Đang xử lý",
      "created_at": "2026-09-20 14:30:00",
      "customer_name": "Nguyễn Thị A",
      "customer_phone": "0900000000",
      "items_count": 2,
      "total": 398000,
      "payment_method": "cod",
      "payment_method_label": "COD",
      "payment_status": "unpaid"
    }
  ]
}
```

Nhãn tiếng Việt của `status` do plugin trả sẵn trong `status_label`. `payment_status` là `paid` khi đơn đã ghi nhận thời điểm thanh toán, ngược lại `unpaid`.

### GET `/orders/{id}`
Chi tiết một đơn hàng. Trả `404` với mã lỗi `kc_not_found` nếu không tồn tại.

Ngoài các trường của `/orders`, response có thêm `subtotal`, `discount_total`, `shipping_total`, `notes` và danh sách `items`.

```json
{
  "wc_active": true,
  "id": 501,
  "number": "501",
  "status": "processing",
  "status_label": "Đang xử lý",
  "created_at": "2026-09-20 14:30:00",
  "customer_name": "Nguyễn Thị A",
  "customer_phone": "0900000000",
  "subtotal": 398000,
  "discount_total": 0,
  "shipping_total": 0,
  "total": 398000,
  "payment_method": "cod",
  "payment_method_label": "COD",
  "payment_status": "unpaid",
  "items": [
    {
      "id": 900,
      "product_id": 101,
      "variation_id": 0,
      "name": "Son Kem Lì Satin",
      "sku": "KC-0001",
      "quantity": 2,
      "price": 199000,
      "subtotal": 398000
    }
  ],
  "notes": ""
}
```

## 5. Endpoint dự kiến (chưa làm)

Chỉ ghi để nhớ hướng, **không phải kế hoạch bắt buộc**:

| Đường dẫn | MVP | Ghi chú |
|---|---|---|
| `POST /auth/login` | MVP-12 | Auth tối thiểu |
| `POST /pos/sales` | MVP-13 | Tạo WooCommerce order, có `Idempotency-Key` |
| `GET /inventory/receivings` | MVP-14 | Nhập kho |
| `POST /returns` | MVP-15 | Trả hàng |

## 6. Quy tắc bảo mật API

- Giai đoạn thử nghiệm (MVP-10, MVP-11): endpoint đọc **public** — chấp nhận được tạm thời.
- **Trước khi tạo/sửa/xóa dữ liệu thật** (bắt đầu MVP-13) phải bổ sung authentication + permission tối thiểu.
- Không bao giờ trả secret qua API cho app.
- Xem [05_SECURITY](05_SECURITY.md).

## 7. Tài liệu liên quan

[02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md) · [04_DATA_MODEL](04_DATA_MODEL.md) · [05_SECURITY](05_SECURITY.md) · [DECISIONS](DECISIONS.md)
