# 03 · Đặc Tả API

## 1. Phạm vi

Tất cả endpoint thuộc namespace `kc/v1` của plugin `mypham-kim-cuong-manager`.

```text
Base URL: https://{host}/wp-json/kc/v1
```

Giai đoạn MVP-10 → MVP-12 **chỉ dùng GET** — read-only.

Từ MVP-12, endpoint đơn hàng (`/orders`, `/orders/{id}`) **yêu cầu xác thực**;
endpoint catalog vẫn public. Chi tiết ở mục 6.

Ngoại lệ so với "catalog public": `GET /products/barcode/{barcode}` cũng yêu
cầu xác thực vì trả cả sản phẩm nháp. Chi tiết ở mục 4.

Từ MVP-13 có **một** endpoint ghi duy nhất: `POST /pos/sales`. Xem
[POS_API_SPECIFICATION](POS_API_SPECIFICATION.md). Endpoint này mới chỉ có mã
trong plugin, **chưa upload lên production**.

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

## 4. Endpoint MVP-11/MVP-12 (chỉ đọc)

`/categories`, `/variations` còn public. `/orders`, `/orders/{id}` yêu cầu
xác thực từ MVP-12 (mục 6).

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

### GET `/products/barcode/{barcode}` — **yêu cầu xác thực**
Tra cứu đúng một sản phẩm hoặc biến thể theo barcode, phục vụ luồng quét
mã của app POS. Barcode lấy từ path, không có tham số query.

| Mục | Quy tắc |
|---|---|
| Xác thực | Application Password qua HTTPS, bắt buộc |
| Capability | `manage_woocommerce`, hoặc `edit_shop_products`, hoặc `edit_products` |
| Định dạng barcode | 1–64 ký tự, chỉ gồm `A–Z a–z 0–9 . _ -` |
| Nguồn dữ liệu | meta `_mkc_barcode` (chính), fallback `_barcode` |
| Bao gồm sản phẩm nháp | Có (`draft`, `private`) — vì sao phải xác thực |

Sản phẩm simple:

```json
{
  "found": true,
  "type": "simple",
  "product_id": 101,
  "variation_id": 0,
  "name": "Son Kem Lì Satin",
  "parent": null,
  "sku": "KC-0001",
  "barcode": "893000000001",
  "price": 189000,
  "regular_price": 189000,
  "sale_price": null,
  "stock_quantity": 25,
  "stock_status": "instock",
  "status": "publish",
  "manage_stock": true,
  "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son.png",
  "attributes": [],
  "ambiguous": false
}
```

Biến thể (`type: "variation"`) khác ở chỗ `product_id` là id sản phẩm cha,
`variation_id` là id biến thể, `name` là tên đầy đủ đã ghép option, `parent`
mô tả sản phẩm cha và `attributes` liệt kê option:

```json
{
  "found": true,
  "type": "variation",
  "product_id": 101,
  "variation_id": 88,
  "name": "Son Kem Lì Satin - Dung lượng: 30ml",
  "parent": { "id": 101, "name": "Son Kem Lì Satin", "sku": "KC-0001", "status": "publish" },
  "sku": "KC-0001-30",
  "barcode": "893000000001",
  "price": 189000,
  "regular_price": 189000,
  "sale_price": null,
  "stock_quantity": 10,
  "stock_status": "instock",
  "status": "publish",
  "manage_stock": true,
  "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son.png",
  "attributes": [{ "name": "Dung lượng", "option": "30ml" }],
  "ambiguous": false
}
```

`ambiguous: true` nghĩa là barcode trùng ở nhiều sản phẩm; response trả về
sản phẩm có id nhỏ nhất. App nên cảnh báo người dùng thay vì âm thầm bán.

Mã lỗi:

| Tình huống | HTTP | `code` |
|---|---|---|
| Chưa xác thực | `401` | `kc_not_authenticated` |
| Không phải HTTPS | `403` | `kc_https_required` |
| Thiếu capability | `403` | `kc_cannot_view_products` |
| WooCommerce chưa active | `503` | `kc_woocommerce_unavailable` |
| Barcode rỗng / sai định dạng / quá dài | `400` | `kc_invalid_barcode` |
| Không có sản phẩm nào khớp | `404` | `kc_not_found` |

### GET `/orders` — **yêu cầu xác thực**
Danh sách đơn hàng WooCommerce (HPOS-safe, đọc bằng `wc_get_orders()`), mới nhất trước.
Tham số: `page`, `per_page`, `status`, `search`, `date_from`, `date_to`.

Trả `401` nếu chưa xác thực, `403` nếu tài khoản thiếu quyền xem đơn.

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

### GET `/orders/{id}` — **yêu cầu xác thực**
Chi tiết một đơn hàng. Trả `404` với mã lỗi `kc_not_found` nếu không tồn tại.
Trả `401`/`403` theo cùng quy tắc của `/orders`.

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
| `GET /inventory/receivings` | MVP-14 | Nhập kho |
| `POST /returns` | MVP-15 | Trả hàng |

> `POST /pos/sales` (MVP-13) đã có mã trong `includes/class-pos.php` nhưng
> **chưa upload production**: xem
> [POS_API_SPECIFICATION](POS_API_SPECIFICATION.md).

> MVP-12 **không** thêm endpoint `POST /auth/login`. Xác thực dùng sẵn cơ chế
> Application Password của WordPress, xem mục 6.

## 6. Quy tắc bảo mật API

### 6.1. Phân quyền theo endpoint (từ MVP-12)

| Endpoint | Xác thực | Mức quyền |
|---|---|---|
| `GET /health` | Public | Không |
| `GET /products` | Public | Không |
| `GET /categories` | Public | Không |
| `GET /variations` | Public | Không |
| `GET /products/barcode/{barcode}` | **Bắt buộc** | Xem sản phẩm |
| `GET /orders` | **Bắt buộc** | Xem đơn hàng |
| `GET /orders/{id}` | **Bắt buộc** | Xem đơn hàng |
| `POST /pos/sales` | **Bắt buộc** | `manage_woocommerce` |

"Xem đơn hàng" = `manage_woocommerce`, hoặc `edit_shop_orders`, hoặc
`read_private_shop_orders` (theo thứ tự ưu tiên).

"Xem sản phẩm" = `manage_woocommerce`, hoặc `edit_shop_products`, hoặc
`edit_products` (theo thứ tự ưu tiên). Endpoint này cần quyền này vì trả cả
sản phẩm nháp.

Mã lỗi trả về:

| Tình huống | HTTP | Body |
|---|---|---|
| Chưa xác thực (thiếu/sai Application Password) | `401` | `{"code":"kc_not_authenticated","message":"Cần đăng nhập để xem đơn hàng."}` |
| Đã xác thực nhưng thiếu capability | `403` | `{"code":"kc_cannot_view_orders","message":"Tài khoản không có quyền xem đơn hàng."}` |

### 6.2. Cách xác thực

- HTTP Basic theo chuẩn **WordPress Application Password**:
  `Authorization: Basic base64(username:application-password)`.
- Bắt buộc truyền qua **HTTPS**. Không dùng HTTP vì Basic header gửi thẳng
  username + mật khẩu (chỉ base64, không mã hoá).
- WordPress tự xác thực và dựng `current_user`; plugin chỉ kiểm tra
  `is_user_logged_in()` và capability, không tự parse header.
- Không có endpoint trả secret, token hay mật khẩu về app.
- Endpoint ghi duy nhất là `POST /pos/sales` (`manage_woocommerce`, HTTPS bắt
  buộc, có idempotency theo `request_id`). Chi tiết ở
  [POS_API_SPECIFICATION](POS_API_SPECIFICATION.md).
- Xem [05_SECURITY](05_SECURITY.md).

## 7. Tài liệu liên quan

[02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md) · [04_DATA_MODEL](04_DATA_MODEL.md) · [05_SECURITY](05_SECURITY.md) · [DECISIONS](DECISIONS.md)
