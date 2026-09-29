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

Từ MVP-13 có **hai** endpoint ghi: `POST /pos/sales` (tạo đơn hàng) và
`POST /products` (tạo sản phẩm). Cả hai đều yêu cầu
`manage_woocommerce`. Xem [POS_API_SPECIFICATION](POS_API_SPECIFICATION.md) và
mục 4. Cả hai endpoint này mới chỉ có mã trong plugin, **chưa upload lên
production**.

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

### POST `/products` — **yêu cầu xác thực**
Tạo **một sản phẩm đơn giản (simple)**. Phục vụ luồng "quét mã lạ → nhập nhanh
thành sản phẩm mới" của app POS.

Phạm vi cố ý hẹp, nhằm giữ cho endpoint an toàn và dễ kiểm chứng:

| Ngoài phạm vi | Lý do |
|---|---|
| Không tạo biến thể / sản phẩm nhóm / sản phẩm ngoài | Sản phẩm biến thể phải tạo trước trong trang quản trị WooCommerce |
| Không upload ảnh | Ảnh được đặt sau trong trang quản trị |
| Không chỉnh sửa, không xoá sản phẩm đã có | Chỉ tạo, không sửa |
| Không quản lý lô hàng / nhiều kho / nhập kho | Ngoài phạm vi POS |

| Mục | Quy tắc |
|---|---|
| Xác thực | Application Password qua HTTPS, bắt buộc |
| Capability | `manage_woocommerce` |
| Content-Type | `application/json` |
| Mặc định | `status: "draft"` — người dùng rà soát trước khi đăng bán |
| Idempotency | Không có. Tạo hai lần là tạo hai sản phẩm. App tự khoá nút. |

Request:

```json
{
  "name": "Son Kem Lì Satin 30ml",
  "barcode": "893000000123",
  "sku": "KC-0123",
  "regular_price": 189000,
  "sale_price": 159000,
  "stock_quantity": 12,
  "manage_stock": true,
  "stock_status": "instock",
  "status": "draft",
  "short_description": "Son lì satin mềm mại, giữ màu 8 giờ.",
  "description": ""
}
```

| Trường | Bắt buộc | Kiểu | Quy tắc |
|---|---|---|---|
| `name` | Có | string | Bắt buộc, không rỗng sau khi làm sạch, tối đa 200 ký tự. |
| `barcode` | Có | string | 1–64 ký tự, chỉ `A–Z a–z 0–9 . _ -`. Phải duy nhất. |
| `sku` | Không | string | Tối đa 100 ký tự, cùng bộ ký tự. Phải duy nhất. Bỏ trống thì không đặt SKU. |
| `regular_price` | Có | number \| string | Số không âm, tối đa 999999999. Chấp nhận chuỗi số. |
| `sale_price` | Không | number \| string | Mặc định không giảm giá. Nếu > 0 thì phải nhỏ hơn `regular_price`. |
| `stock_quantity` | Không | int | Mặc định `0`. Số nguyên không âm, tối đa 999999. Số thập phân và số âm bị từ chối. |
| `manage_stock` | Không | bool | Mặc định `true`. Chấp nhận `"true"`/`"false"` và `0`/`1`. |
| `stock_status` | Không | string | Mặc định suy ra từ `stock_quantity`: `> 0` → `instock`, `0` → `outofstock`. Chỉ nhận `instock`, `outofstock`, `onbackorder`. |
| `status` | Không | string | Mặc định `draft`. Chỉ nhận `draft`, `publish`. |
| `short_description` | Không | string | Cắt còn tối đa 500 ký tự. |
| `description` | Không | string | Cắt còn tối đa 5000 ký tự. |

Sản phẩm trả về dùng chung model với `GET /products/barcode/{barcode}`:

```json
{
  "success": true,
  "product": {
    "id": 712,
    "product_id": 712,
    "variation_id": 0,
    "name": "Son Kem Lì Satin 30ml",
    "sku": "KC-0123",
    "barcode": "893000000123",
    "price": 159000,
    "regular_price": 189000,
    "sale_price": 159000,
    "stock_quantity": 12,
    "stock_status": "instock",
    "image_url": null,
    "type": "simple",
    "status": "draft",
    "created_via": null
  }
}
```

HTTP `201`. Barcode ghi vào meta `_mkc_barcode` — đúng key mà
`GET /products/barcode/{barcode}` đọc, nên sản phẩm vừa tạo tra cứu được
ngay. `price` là giá thực tế sau giảm giá.

`created_via` luôn là `null`. Trường này là thuộc tính của **order** và
**customer** trong WooCommerce, **không phải của product** — sản phẩm không có
field đó. Khóa vẫn được giữ trong response để app không phải đổi model. Nếu sau
này cần biết sản phẩm nào tạo từ POS, phải dùng meta riêng (ví dụ
`_mkc_created_via`), tuyệt đối không gọi `set_created_via()` trên product.

Mã lỗi:

| Tình huống | HTTP | `code` |
|---|---|---|
| Chưa xác thực | `401` | `kc_not_authenticated` |
| Không phải HTTPS | `403` | `kc_https_required` |
| Thiếu capability | `403` | `kc_cannot_create_product` |
| WooCommerce chưa active | `503` | `kc_woocommerce_unavailable` |
| Body rỗng hoặc JSON hỏng | `400` | `kc_invalid_json` |
| Body không phải JSON object | `400` | `kc_invalid_request` |
| `name` rỗng / quá dài / sai kiểu | `400` | `kc_invalid_name` |
| `barcode` sai định dạng | `400` | `kc_invalid_barcode` |
| `sku` sai định dạng | `400` | `kc_invalid_sku` |
| `regular_price` sai | `400` | `kc_invalid_price` |
| `sale_price` sai | `400` | `kc_invalid_sale_price` |
| Tồn kho sai | `400` | `kc_invalid_stock` |
| `status` không hợp lệ | `400` | `kc_invalid_status` |
| SKU đã tồn tại | `400` | `kc_duplicate_sku` |
| Barcode đã tồn tại | `400` | `kc_duplicate_barcode` |
| Không kiểm tra được trùng lặp | `500` | `kc_product_check_failed` |
| Lỗi WooCommerce khi lưu | `500` | `kc_product_create_failed` |

Kiểm tra trùng lặp chạy **trước** khi tạo: SKU bằng
`wc_get_product_id_by_sku()` (tra cả sản phẩm và biến thể, an toàn với HPOS),
barcode bằng `get_posts()` + `meta_query` trên `product` + `product_variation`,
bao gồm cả key dự phòng `_barcode`. Nếu không tra được thì trả `500` chứ không
tạo, để không sinh sản phẩm trùng mà app không biết.

Ghi dữ liệu bằng WooCommerce CRUD chính thức (`new WC_Product_Simple()` +
setter + `save()`). Không `wp_insert_post()`, không SQL, không bảng riêng. Tồn
kho đi qua `set_manage_stock()` / `set_stock_quantity()` / `set_stock_status()`
nên WooCommerce tự đồng bộ `_stock` và `_stock_status`.

Route `GET /products` và `POST /products` được đăng ký trong **một** lệnh gọi
`register_rest_route()` duy nhất (dạng danh sách endpoint), nên `args` phân
trang của GET không bị mất.

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
>
> `POST /products` cũng đã có mã trong `includes/class-product-create.php` và
> **chưa upload production**: xem mục 4.

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
| `POST /products` | **Bắt buộc** | `manage_woocommerce` |
| `GET /orders` | **Bắt buộc** | Xem đơn hàng |
| `GET /orders/{id}` | **Bắt buộc** | Xem đơn hàng |
| `POST /pos/sales` | **Bắt buộc** | `manage_woocommerce` |

"Xem đơn hàng" = `manage_woocommerce`, hoặc `edit_shop_orders`, hoặc
`read_private_shop_orders` (theo thứ tự ưu tiên).

"Xem sản phẩm" = `manage_woocommerce`, hoặc `edit_shop_products`, hoặc
`edit_products` (theo thứ tự ưu tiên). Endpoint này cần quyền này vì trả cả
sản phẩm nháp.

`POST /products` và `POST /pos/sales` đều là endpoint ghi, nên yêu cầu
`manage_woocommerce` — quyền cao nhất, không nới như endpoint đọc.

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
- Có hai endpoint ghi, cả hai đều `manage_woocommerce` + HTTPS bắt buộc:
  - `POST /pos/sales` — tạo đơn hàng, có idempotency theo `request_id`. Chi tiết ở
    [POS_API_SPECIFICATION](POS_API_SPECIFICATION.md).
  - `POST /products` — tạo sản phẩm simple, không idempotent, mặc định `draft`.
    Chi tiết ở mục 4.
- `GET /products/barcode/{barcode}` yêu cầu quyền xem sản phẩm vì trả cả sản
  phẩm nháp, dù không ghi dữ liệu.
- Xem [05_SECURITY](05_SECURITY.md).

## 7. Tài liệu liên quan

[02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md) · [04_DATA_MODEL](04_DATA_MODEL.md) · [05_SECURITY](05_SECURITY.md) · [DECISIONS](DECISIONS.md)
