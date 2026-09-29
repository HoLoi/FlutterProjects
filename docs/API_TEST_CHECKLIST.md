# API Test Checklist — MyPham Kim Cuong Manager

Tài liệu này dùng để **kiểm tra từng endpoint** của plugin `mypham-kim-cuong-manager`
sau khi upload lên website. Toàn bộ endpoint đều **chỉ đọc (GET)**.

> Quy trình theo thứ tự: **hoàn thiện và xác minh API PHP trước → app Flutter viết sau
> dựa trên JSON thực tế trả về.** Không viết app dựa trên giả định.

---

## 1. Thông tin môi trường

| Mục | Giá trị |
|---|---|
| Base URL | `https://myphamkimcuong.id.vn` |
| Namespace | `kc/v1` |
| Prefix đầy đủ | `https://myphamkimcuong.id.vn/wp-json/kc/v1` |
| WordPress | 7.1.2 |
| PHP | 8.1 |
| WooCommerce | 10.4.4 |
| Phiên bản plugin | 1.0.0 |

---

## 2. Bảng tổng quan

| Endpoint | Method | Auth | Parameters | Expected response | How to test |
|---|---|---|---|---|---|
| `/health` | GET | **Public** | — | `200` — `ok`, `plugin`, `version`, `wordpress`, `woocommerce_active` | Mở trực tiếp trên trình duyệt, hoặc `curl` (mục 4.1) |
| `/products` | GET | **Public** | `page`, `per_page` (1–50), `search` | `200` — `{wc_active, count, page, per_page, data[]}` | Mục 4.2 |
| `/products/{id}` | GET | **Public** | `id` (số nguyên > 0) | `200` — payload sản phẩm + `description`, `attributes`, `permalink`…; `404` nếu không có | Mục 4.3 |
| `/categories` | GET | **Public** | `page`, `per_page` (1–50), `search` | `200` — danh sách `{id, name, slug, parent, count}` | Mục 4.4 |
| `/variations` | GET | **Public** | `page`, `per_page` (1–50), `search`, `product_id` | `200` — danh sách biến thể `{id, product_id, name, sku, …, attributes[]}` | Mục 4.5 |
| `/orders` | GET | **Application Password** | `page`, `per_page` (1–50), `search`, `status`, `date_from`, `date_to` | `200` — danh sách đơn có `line_items`; `401` nếu chưa xác thực; `403` nếu thiếu quyền | Mục 4.6 |
| `/orders/{id}` | GET | **Application Password** | `id` (số nguyên > 0) | `200` — chi tiết đơn; `401` / `403` / `404` | Mục 4.7 |
| `/products/barcode/{barcode}` | GET | **Application Password** | `barcode` trong path (1–64 ký tự, `A–Z a–z 0–9 . _ -`) | `200` — sản phẩm hoặc biến thể; `400` / `401` / `403` / `404` | Mục 4.8 |
| `/products` | POST | **Application Password** + `manage_woocommerce` | JSON body: `name`, `barcode`, `regular_price` bắt buộc | `201` — `{success, product}`; `400` khi dữ liệu sai hoặc trùng; `500` xem mục 4.10 | Mục 4.9 |

### Phân loại endpoint

- **Public** (không cần đăng nhập): `/health`, `/products` (GET), `/products/{id}`, `/categories`, `/variations`
- **Cần Application Password**: `/orders`, `/orders/{id}`, `/products/barcode/{barcode}` (GET), `/products` (POST)

---

## 3. Chuẩn bị trước khi test

### 3.1. Kiểm tra nền tảng

1. Website đang chạy **HTTPS** (không phải HTTP).
2. WooCommerce đã cài và **đang active**.
3. Plugin `mypham-kim-cuong-manager` đã cài và **đang active**.
4. Website có ít nhất vài sản phẩm, danh mục và đơn hàng thật để kiểm tra dữ liệu.

### 3.2. Tạo Application Password (cần cho `/orders`, `/products/barcode`, `POST /products`)

1. Đăng nhập WordPress Admin.
2. Vào **Hồ sơ người dùng** (`wp-admin/profile.php`).
3. Kéo xuống mục **Application Passwords** → **Create New Application Password**.
4. Đặt tên, ví dụ `MKC App`, rồi bấm **Create**.
5. WordPress hiển thị mật khẩu ứng dụng dạng 4 nhóm, ví dụ:

   ```text
   abcd efgh ijkl mnop qrst uvwx
   ```

**Lưu ý quan trọng:**

- WordPress **chỉ cho tạo Application Password khi website chạy HTTPS**. Nếu thấy thông báo không tạo được, hãy kiểm tra lại HTTPS trước.
- Mật khẩu này **chỉ hiển thị một lần**. Không lưu vào file, không commit lên Git, không gửi qua chat/email.
- Tài khoản phải có ít nhất một trong các quyền sau:
  `manage_woocommerce`, `edit_shop_orders`, `read_private_shop_orders`.
  Tài khoản Subscriber sẽ nhận `403`.
- Có thể thu hồi bất cứ lúc nào trong chính trang Hồ sơ người dùng.

### 3.3. Lưu ý khi dùng `curl`

- Không gõ mật khẩu thật vào lịch sử lệnh trên máy dùng chung. Có thể dùng biến môi trường tạm:

  ```bash
  # PowerShell
  $env:MKC_APP = "abcd efgh ijkl mnop qrst uvwx"
  curl.exe -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?per_page=1"
  Remove-Item Env:\MKC_APP
  ```

- Kết quả `curl` trả về là **JSON gọn một dòng**. Muốn dễ đọc thì pipe qua `python -m json.tool` hoặc dán vào [jsonformatter.org](https://jsonformatter.org), hoặc mở trực tiếp URL trên trình duyệt (trình duyệt tự format JSON).

---

## 4. Kiểm tra từng endpoint

> Mọi lệnh ví dụ dưới đây đều là **GET**. Tuyệt đối không dùng
> **POST / PUT / PATCH / DELETE** đối với bất kỳ endpoint nào.

### 4.1. `GET /health`

- **Auth:** Public
- **URL:** <https://myphamkimcuong.id.vn/wp-json/kc/v1/health>
- **Trình duyệt:** mở URL trên, hoặc
- **curl:**

  ```bash
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/health"
  ```

**HTTP mong đợi:** `200`

**JSON mong đợi:**

```json
{
  "ok": true,
  "plugin": "mypham-kim-cuong-manager",
  "version": "1.0.0",
  "wordpress": "7.1.2",
  "woocommerce_active": true
}
```

**Cách kiểm tra:**

- `ok` = `true`
- `plugin` = `mypham-kim-cuong-manager`
- `version` = `1.0.0`
- `wordpress` = `7.1.2`
- `woocommerce_active` = `true` → nếu là `false` thì **dừng lại**, các endpoint còn lại sẽ trả `503`.

---

### 4.2. `GET /products`

- **Auth:** Public
- **Tham số:**

  | Tham số | Kiểu | Mặc định | Ràng buộc |
  |---|---|---|---|
  | `page` | integer | `1` | ≥ 1; sai (0, số âm, thập phân, chuỗi) sẽ trả `400 rest_invalid_param` |
  | `per_page` | integer | `20` | 1–50; sai (0, số âm, thập phân, chuỗi, > 50) sẽ trả `400 rest_invalid_param` |
  | `search` | string | — | tối đa 200 ký tự |

- **curl:**

  ```bash
  # Trang đầu, 20 sản phẩm
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/products"

  # Giới hạn 5 sản phẩm, trang 2
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?page=2&per_page=5"

  # Tìm theo tên
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?search=son"
  ```

**HTTP mong đợi:** `200`

**JSON mong đợi:**

```json
{
  "wc_active": true,
  "count": 2,
  "page": 1,
  "per_page": 20,
  "data": [
    {
      "id": 123,
      "name": "Son Kem Lì Satin Đỏ",
      "sku": "KC-0001-RED",
      "barcode": null,
      "price": 190000,
      "regular_price": 220000,
      "sale_price": 190000,
      "stock_quantity": 12,
      "stock_status": "instock",
      "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son.jpg",
      "categories": [
        { "id": 3, "name": "Son", "slug": "son" }
      ],
      "type": "simple"
    }
  ]
}
```

**Cách kiểm tra:**

- `wc_active` = `true`
- `count` = **số item trong trang này** (không phải tổng số sản phẩm trong shop)
- `page`, `per_page` phản ánh đúng tham số gửi lên
- Mỗi phần tử trong `data` có đủ: `id`, `name`, `sku`, `barcode`, `price`, `regular_price`, `sale_price`, `stock_quantity`, `stock_status`, `image_url`, `categories`, `type`
- **Chỉ sản phẩm `simple` / `variable` / `grouped` / `external`**, không có biến thể lẫn vào
- **Chỉ sản phẩm đang publish** (sản phẩm nháp sẽ không xuất hiện)
- `price` = giá đang bán; `regular_price` và `sale_price` có thể `null` nếu sản phẩm không có giá dạng chuỗi
- `barcode` có thể `null` nếu shop chưa nhập mã vạch
- `image_url` có thể `null` nếu sản phẩm chưa có ảnh

**Kiểm tra lỗi mong đợi:**

```bash
# per_page vượt giới hạn → 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=100"
```

---

### 4.3. `GET /products/{id}`

- **Auth:** Public
- **URL:** <https://myphamkimcuong.id.vn/wp-json/kc/v1/products/123>
  (thay `123` bằng `id` thật lấy từ `/products`)
- **curl:**

  ```bash
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/123"
  ```

**HTTP mong đợi:** `200` với id tồn tại, `404` nếu không tồn tại.

**JSON mong đợi (rút gọn, ngoài ra vẫn có đủ 12 trường như `/products`):**

```json
{
  "id": 123,
  "name": "Son Kem Lì Satin Đỏ",
  "sku": "KC-0001-RED",
  "barcode": null,
  "price": 190000,
  "regular_price": 220000,
  "sale_price": 190000,
  "stock_quantity": 12,
  "stock_status": "instock",
  "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son.jpg",
  "categories": [{ "id": 3, "name": "Son", "slug": "son" }],
  "type": "variable",
  "wc_active": true,
  "permalink": "https://myphamkimcuong.id.vn/san-pham/son-kem-li-satin-do/",
  "date_created": "2026-01-15 09:20:00",
  "date_modified": "2026-03-02 14:05:11",
  "description": "<p>Mô tả sản phẩm</p>",
  "short_description": "<p>Mô tả ngắn</p>",
  "virtual": false,
  "downloadable": false,
  "manage_stock": true,
  "attributes": [
    {
      "id": 0,
      "name": "Màu sắc",
      "options": ["Đỏ", "Hồng"],
      "visible": true,
      "variation": true
    }
  ]
}
```

**Cách kiểm tra:**

- Trả về đủ các trường giống `/products`, **cộng thêm** `permalink`, `date_created`, `date_modified`, `description`, `short_description`, `virtual`, `downloadable`, `manage_stock`, `attributes`
- `description` / `short_description` là **HTML**, app tự quyết định có render hay không

**Kiểm tra lỗi mong đợi:**

```bash
# id không tồn tại → 404
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/99999999"

# id không hợp lệ → 404
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/0"
```

JSON lỗi mong đợi:

```json
{
  "code": "kc_not_found",
  "message": "Không tìm thấy sản phẩm.",
  "data": { "status": 404 }
}
```

---

### 4.4. `GET /categories`

- **Auth:** Public
- **Tham số:** giống `/products` (`page`, `per_page` 1–50, `search`)
- **curl:**

  ```bash
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/categories?per_page=50"
  ```

**HTTP mong đợi:** `200`

**JSON mong đợi:**

```json
{
  "wc_active": true,
  "count": 2,
  "page": 1,
  "per_page": 50,
  "data": [
    { "id": 3, "name": "Son", "slug": "son", "parent": 0, "count": 12 },
    { "id": 5, "name": "Kem dưỡng", "slug": "kem-duong", "parent": 0, "count": 7 }
  ]
}
```

**Cách kiểm tra:**

- Mỗi phần tử có `id`, `name`, `slug`, `count`
- `parent` = `0` nghĩa là danh mục cấp cao nhất
- `count` = số sản phẩm trong danh mục (có thể `0` vì API trả cả danh mục rỗng)
- Danh mục được sắp xếp theo tên A–Z

---

### 4.5. `GET /variations`

- **Auth:** Public
- **Tham số:**

  | Tham số | Kiểu | Mặc định | Ràng buộc |
  |---|---|---|---|
  | `page` | integer | `1` | ≥ 1; sai sẽ trả `400 rest_invalid_param` |
  | `per_page` | integer | `20` | 1–50; sai sẽ trả `400 rest_invalid_param` |
  | `product_id` | integer | — | số nguyên > 0; bỏ trống thì lấy biến thể của tất cả sản phẩm **đang publish** |
  | `search` | string | — | tối đa 200 ký tự |

- **curl:**

  ```bash
  # Biến thể của một sản phẩm
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?product_id=123&per_page=50"

  # Tìm biến thể theo tên / SKU / thuộc tính
  curl "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?search=do&per_page=50"
  ```

> **Chỉ trả biến thể của sản phẩm cha đang `publish`.** Endpoint này lọc theo
> trạng thái của *sản phẩm cha*, không phải trạng thái của chính biến thể (mọi
> biến thể đều có `post_status` riêng là `publish`, nên lọc sai chỗ sẽ làm lộ
> biến thể của sản phẩm nháp). Cụ thể:
>
> - Không truyền `product_id`: chỉ trả biến thể có cha đang `publish`.
> - Truyền `product_id` của sản phẩm cha `draft`/`private`/`pending`, hoặc
>   không tồn tại: trả `404 kc_not_found`.
> - Không bao giờ lộ tên, SKU, giá, tồn kho hay thuộc tính của biến thể thuộc
>   sản phẩm chưa publish.

**HTTP mong đợi:** `200`

**JSON mong đợi:**

```json
{
  "wc_active": true,
  "count": 2,
  "page": 1,
  "per_page": 50,
  "data": [
    {
      "id": 124,
      "product_id": 123,
      "name": "Son Kem Lì Satin Đỏ - Màu đỏ",
      "sku": "KC-0001-RED",
      "barcode": null,
      "price": 190000,
      "regular_price": 220000,
      "sale_price": 190000,
      "stock_quantity": 5,
      "stock_status": "instock",
      "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son-do.jpg",
      "attributes": [
        { "name": "Màu sắc", "option": "Đỏ" }
      ]
    }
  ]
}
```

**Cách kiểm tra:**

- Mỗi phần tử có đủ: `id`, `product_id`, `name`, `sku`, `barcode`, `price`, `regular_price`, `sale_price`, `stock_quantity`, `stock_status`, `image_url`, `attributes`
- `product_id` luôn trỏ về sản phẩm cha
- `attributes` là mảng `{name, option}`
- `image_url` lấy ảnh của biến thể, nếu biến thể không có ảnh thì lấy ảnh sản phẩm cha
- `stock_quantity` = `null` nếu biến thể không bật quản lý kho

> **Lưu ý về `search`:** WooCommerce không hỗ trợ tìm kiếm chuẩn cho biến thể, nên
> plugin lọc `search` **sau khi lấy dữ liệu từ database**. Vì vậy khi dùng `search`
> hãy đặt `per_page=50` để giảm khả năng kết quả bị lọc mất. `search` khớp trên
> `name`, `sku` và giá trị thuộc tính.

**Kiểm tra lỗi mong đợi:**

```bash
# product_id không hợp lệ → 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?product_id=abc"
```

---

### 4.6. `GET /orders` — **CẦN APPLICATION PASSWORD**

- **Auth:** Bắt buộc. Không có Application Password thì luôn nhận `401`.
- **Tham số:**

  | Tham số | Kiểu | Mặc định | Ràng buộc |
  |---|---|---|---|
  | `page` | integer | `1` | ≥ 1; sai sẽ trả `400 rest_invalid_param` |
  | `per_page` | integer | `20` | 1–50; sai sẽ trả `400 rest_invalid_param` |
  | `search` | string | — | tối đa 200 ký tự |
  | `status` | string | tất cả | chỉ nhận `any`, `pending`, `processing`, `on-hold`, `completed`, `cancelled`, `refunded`, `failed` |
  | `date_from` | date | — | định dạng `YYYY-MM-DD` |
  | `date_to` | date | — | định dạng `YYYY-MM-DD`, phải ≥ `date_from` |

- **curl (PowerShell):**

  ```powershell
  $env:MKC_APP = "abcd efgh ijkl mnop qrst uvwx"

  # Danh sách 1 đơn
  curl.exe -u "ten_dang_nhap:$env:MKC_APP" `
    "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?per_page=1"

  # Lọc theo trạng thái
  curl.exe -u "ten_dang_nhap:$env:MKC_APP" `
    "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?status=processing&per_page=20"

  # Lọc theo khoảng ngày
  curl.exe -u "ten_dang_nhap:$env:MKC_APP" `
    "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?date_from=2026-01-01&date_to=2026-12-31"

  Remove-Item Env:\MKC_APP
  ```

- **curl (macOS / Linux):**

  ```bash
  curl -u "ten_dang_nhap:abcd efgh ijkl mnop qrst uvwx" \
    "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?per_page=1"
  ```

**HTTP mong đợi:** `200` khi thông tin đúng.

**JSON mong đợi (một phần tử trong `data`):**

```json
{
  "id": 456,
  "number": "456",
  "status": "processing",
  "status_label": "Đang xử lý",
  "date_created": "2026-09-20 14:30:00",
  "date_paid": null,
  "payment_method": "cod",
  "payment_method_label": "COD",
  "payment_status": "unpaid",
  "currency": "VND",
  "total": 398000,
  "customer": {
    "id": 0,
    "is_guest": true,
    "name": "Nguyễn Thị A",
    "phone": "0900000000",
    "email": "a@example.com"
  },
  "billing": {
    "first_name": "Nguyễn Thị",
    "last_name": "A",
    "address_1": "123 Nguyễn Huệ",
    "address_2": "",
    "city": "TP. Hồ Chí Minh",
    "state": "",
    "postcode": "700000",
    "country": "VN",
    "phone": "0900000000",
    "email": "a@example.com"
  },
  "shipping": {
    "first_name": "Nguyễn Thị",
    "last_name": "A",
    "address_1": "123 Nguyễn Huệ",
    "address_2": "",
    "city": "TP. Hồ Chí Minh",
    "state": "",
    "postcode": "700000",
    "country": "VN",
    "phone": "0900000000",
    "email": null
  },
  "line_items": [
    {
      "id": 789,
      "product_id": 123,
      "variation_id": 124,
      "name": "Son Kem Lì Satin Đỏ",
      "sku": "KC-0001-RED",
      "quantity": 2,
      "price": 190000,
      "subtotal": 380000,
      "total": 380000
    }
  ]
}
```

**Cách kiểm tra:**

- Mỗi đơn có đủ: `id`, `number`, `status`, `date_created`, `date_paid`, `payment_method`, `payment_status`, `currency`, `total`, `customer`, `billing`, `shipping`, `line_items`
- `status` là slug (`processing`), `status_label` là nhãn tiếng Việt
- `payment_status` là `paid`, `unpaid` hoặc `refunded`
- `date_created` / `date_paid` theo múi giờ của website, định dạng `YYYY-MM-DD HH:mm:ss`. `date_paid` = `null` nếu chưa thanh toán
- `customer.id` = `0` và `customer.is_guest` = `true` nếu đơn đặt không cần tài khoản
- `shipping.email` luôn là `null` (WooCommerce chỉ lưu email ở billing)
- **JSON không chứa** password, secret, token, ghi chú nội bộ hay dữ liệu quản trị
- Đơn mới nhất lên đầu

**Kiểm tra lỗi mong đợi:**

```bash
# Không gửi Authorization → 401
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders"

# Sai mật khẩu → 401
curl -i -u "ten_dang_nhap:sai-mat-khau-hoi" "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders"

# Đúng mật khẩu nhưng tài khoản không có quyền → 403
```

---

### 4.7. `GET /orders/{id}` — **CẦN APPLICATION PASSWORD**

- **Auth:** Giống hệt `/orders`.
- **URL:** <https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/456>
  (thay `456` bằng `id` thật lấy từ `/orders`)
- **curl (PowerShell):**

  ```powershell
  $env:MKC_APP = "abcd efgh ijkl mnop qrst uvwx"
  curl.exe -u "ten_dang_nhap:$env:MKC_APP" `
    "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/456"
  Remove-Item Env:\MKC_APP
  ```

**HTTP mong đợi:** `200` với id tồn tại, `404` nếu không tồn tại.

**JSON mong đợi:** giống hệt một phần tử của `/orders`, **cộng thêm**:

```json
{
  "wc_active": true,
  "customer_note": "Giao sau 18h",
  "subtotal": 380000,
  "discount_total": 0,
  "shipping_total": 18000,
  "fee_total": 0,
  "refunded_total": 0,
  "created_via": "checkout"
}
```

**Cách kiểm tra:**

- So sánh với `/orders`: phần `id`, `number`, `line_items`… phải **giống hệt**
- Kiểm tra `subtotal`, `discount_total`, `shipping_total`, `fee_total` khớp với tổng tiền trên trang quản trị WooCommerce

**Kiểm tra lỗi mong đợi:**

```powershell
# Không xác thực → 401
curl.exe -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/456"

# Đơn không tồn tại → 404
curl.exe -i -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/99999999"
```

### 4.8. `GET /products/barcode/{barcode}` — **CẦN APPLICATION PASSWORD**

> Endpoint này trả cả sản phẩm nháp, nên yêu cầu quyền xem sản phẩm
> (`manage_woocommerce`, hoặc `edit_shop_products`, hoặc `edit_products`).

**Sản phẩm đơn giản:**

```powershell
# → 200, found=true, type=simple, variation_id=0, product_id = id sản phẩm
curl.exe -s -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/893000000001"
```

**Biến thể:**

```powershell
# → 200, type=variation, product_id = id sản phẩm cha, variation_id = id biến thể,
#    parent không null, attributes có ít nhất 1 phần tử
curl.exe -s -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/893000000099"
```

**Kiểm tra lỗi mong đợi:**

```powershell
# Không xác thực → 401 kc_not_authenticated
curl.exe -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/893000000001"

# Barcode không tồn tại → 404 kc_not_found
curl.exe -i -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/99999999999999"

# Barcode rỗng → 400 kc_invalid_barcode (route vẫn khớp, không phải 404)
curl.exe -i -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/"

# Barcode sai ký tự (có dấu cách) → 400 kc_invalid_barcode
curl.exe -i -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/893%20000"
```

**Kiểm tra bổ sung:**

- Barcode của sản phẩm `draft` vẫn trả `200` (đây là lý do endpoint cần xác thực)
- `GET /products/barcode/...` không làm hỏng `GET /products?page=1&per_page=10&search=son` (route dùng chung prefix)
- `price` bằng `sale_price` nếu đang giảm giá, ngược lại bằng `regular_price`

### 4.9. `POST /products` — **CẦN APPLICATION PASSWORD + `manage_woocommerce`**

> **Endpoint này GHI dữ liệu thật.** Chỉ chạy trên staging hoặc với sản phẩm
> thử có tên dễ nhận ra. Mặc định `status` là `draft` nên sản phẩm không hiện
> trên website.

**Tạo thành công:**

```powershell
$body = @'
{
  "name": "SPAM TEST barcode 20260928",
  "barcode": "TEST-BC-20260928-01",
  "sku": "TEST-SKU-20260928-01",
  "regular_price": 100000,
  "sale_price": 80000,
  "stock_quantity": 5,
  "status": "draft"
}
'@

# → 201, success=true, product.barcode = "TEST-BC-20260928-01",
#    product.price = 80000, product.status = "draft", product.created_via = null
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" `
  -H "Content-Type: application/json" `
  -d $body
```

**Sản phẩm tạo xong phải tra cứu lại được ngay:**

```powershell
# → 200, trùng đúng product.id vừa tạo
curl.exe -s -u "ten_dang_nhap:$env:MKC_APP" "https://myphamkimcuong.id.vn/wp-json/kc/v1/products/barcode/TEST-BC-20260928-01"
```

**Kiểm tra lỗi mong đợi:**

```powershell
# Không xác thực → 401
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -H "Content-Type: application/json" -d '{"name":"x","barcode":"TEST-X","regular_price":1}'

# Trùng barcode với lần tạo trước → 400 kc_duplicate_barcode
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" -H "Content-Type: application/json" `
  -d '{"name":"x","barcode":"TEST-BC-20260928-01","regular_price":1}'

# Thiếu name → 400 kc_invalid_name
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" -H "Content-Type: application/json" `
  -d '{"barcode":"TEST-BC-NEW-01","regular_price":1}'

# sale_price >= regular_price → 400 kc_invalid_sale_price
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" -H "Content-Type: application/json" `
  -d '{"name":"x","barcode":"TEST-BC-NEW-02","regular_price":100,"sale_price":100}'

# stock_quantity âm → 400 kc_invalid_stock
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" -H "Content-Type: application/json" `
  -d '{"name":"x","barcode":"TEST-BC-NEW-03","regular_price":1,"stock_quantity":-5}'

# Body không phải JSON → 400 kc_invalid_json
curl.exe -i -X POST "https://myphamkimcuong.id.vn/wp-json/kc/v1/products" `
  -u "ten_dang_nhap:$env:MKC_APP" -H "Content-Type: application/json" -d 'not json'
```

**Kiểm tra bổ sung:**

- `GET /products?page=1&per_page=10` vẫn phân trang đúng sau khi thêm route POST
  (route GET+POST phải dùng chung một lệnh `register_rest_route`)
- Sản phẩm tạo ra hiện đúng tên, giá, tồn kho trong trang quản trị WooCommerce
- `product.created_via` trả `null` (product không có trường này — đó là thuộc tính
  của order; xem mục 4 của `03_API_SPECIFICATION.md`)
- Tạo lại cùng barcode → `400`, KHÔNG tạo ra sản phẩm thứ hai

### 4.10. Nếu `POST /products` trả 500

Response chỉ có mã lỗi chung, **không** có stack trace. Sự thật nằm trong log máy
chủ. Kiểm tra theo thứ tự:

1. WooCommerce log: **WooCommerce → Status → Logs**, chọn nguồn
   `mkc-product-create`.
2. Nếu không có, xem PHP error log của hosting (thường ở
   `wp-content/debug.log` nếu bật `WP_DEBUG_LOG`, hoặc log của Apache/PHP-FPM).

Mỗi dòng log có dạng:

```
MKC product create: stage=<giai_doan> exception=<ten_class> code=<ma> origin=<file>:<dong> message=<thong_diep>
```

`stage` cho biết hỏng ở bước nào:

| `stage` | Ý nghĩa |
|---|---|
| `instantiate` | Không khởi tạo được `WC_Product_Simple` — thường do WooCommerce chưa active đầy đủ |
| `set_props` | Một setter của WooCommerce ném exception — thường do dùng prop không tồn tại trên product |
| `save` | WooCommerce lưu xuống database thất bại — kiểm tra quyền ghi, HPOS, giá trị tồn kho |
| `read_back` / `serialize` | Sản phẩm **đã tạo thành công**, chỉ lỗi khi đọc lại. Endpoint vẫn trả `201` |

Lưu ý an toàn: log KHÔNG chứa body request, header `Authorization`, mật khẩu ứng
dụng hay dữ liệu khách hàng. Chỉ có tên giai đoạn, tên class exception, mã
exception, file:dòng và thông điệp của exception.

---

## 5. Nhận biết JSON lỗi

Mọi lỗi của WordPress REST API đều trả về **cùng một cấu trúc**:

```json
{
  "code": "mã_lỗi",
  "message": "thông báo tiếng Việt",
  "data": { "status": 401 }
}
```

**Mã lỗi chuẩn của API: hầu hết lỗi tham số đều trả HTTP `400` với `code` là
`rest_invalid_param`.** Đây là hành vi của WordPress: mọi lỗi phát ra từ
`validate_callback` cấp tham số (kể cả `WP_Error` có mã custom) đều bị WordPress
bọc lại thành `rest_invalid_param`. Vì vậy `code` ở cấp ngoài **luôn** là
`rest_invalid_param`, và mã chi tiết hơn chỉ xuất hiện tại
`data.details[tên_tham_số].code`. App Flutter nên bắt lỗi theo **HTTP status**,
không cần phân nhánh theo `code`.

> **Ngoại lệ đã kiểm tra trên production: khoảng ngày ngược.**
> `validate_orders_date_range()` là `validate_callback` **cấp route**, không phải
> cấp tham số, nên WordPress **không** bọc lại mã lỗi của nó. Vì vậy
> `GET /orders?date_from=2026-12-31&date_to=2026-01-01` trả:
>
> ```json
> {
>   "code": "kc_invalid_date_range",
>   "message": "date_from phải nhỏ hơn hoặc bằng date_to.",
>   "data": { "status": 400 }
> }
> ```
>
> HTTP status vẫn là `400` như mọi lỗi tham số khác, nên app bắt theo status là
> đúng. Chỉ khác ở `code`.

| HTTP | `code` (cấp ngoài) | `message` | Nguyên nhân |
|---|---|---|---|
| `400` | `rest_invalid_param` | Tham số phải là số nguyên từ 1 đến 50. | `per_page` = 0, số âm, thập phân, chuỗi không phải số, hoặc > 50 |
| `400` | `rest_invalid_param` | Tham số phải là số nguyên từ 1 đến 9223372036854775807. | `page` = 0, số âm, thập phân, hoặc chuỗi không phải số |
| `400` | `rest_invalid_param` | Tham số phải là số nguyên từ 1 đến 9223372036854775807. | `product_id` sai định dạng, bằng 0 hoặc số âm |
| `400` | `rest_invalid_param` | Định dạng ngày phải là YYYY-MM-DD, ví dụ 2026-09-01. | `date_from` / `date_to` sai định dạng |
| `400` | **`kc_invalid_date_range`** | date_from phải nhỏ hơn hoặc bằng date_to. | **Khoảng ngày bị ngược** (ngoại lệ cấp route, xem khối trên) |
| `400` | `rest_invalid_param` | Trạng thái "xxx" không hợp lệ. Chỉ nhận: any, pending, … | `status` không nằm trong whitelist |
| `401` | `kc_not_authenticated` | Cần đăng nhập để xem đơn hàng. | Thiếu/sai Application Password trên `/orders` |
| `403` | `kc_cannot_view_orders` | Tài khoản không có quyền xem đơn hàng. | Đã xác thực nhưng thiếu capability |
| `404` | `kc_not_found` | Không tìm thấy sản phẩm. / Không tìm thấy đơn hàng. | id không tồn tại, hoặc sản phẩm cha của biến thể không publish |
| `404` | `rest_no_route` | No route was found matching the URL and request method. | Sai đường dẫn, hoặc gửi sai method (ví dụ POST) |
| `500` | `kc_terms_error` | Không đọc được danh mục sản phẩm. | Lỗi truy vấn danh mục |
| `500` | `kc_order_detail_failed` | Không đọc được chi tiết đơn hàng. | Lỗi khi dựng payload chi tiết đơn (luôn trả JSON, không trả trang HTML) |
| `503` | `kc_woocommerce_unavailable` | WooCommerce chưa active nên không đọc được dữ liệu. | WooCommerce đã bị deactivate |

> Lưu ý thứ tự kiểm tra: WordPress kiểm tra tính hợp lệ tham số **trước**
> `permission_callback`. Vì vậy `/orders?status=xxx` trả `400` (không phải
> `401`) ngay cả khi chưa xác thực.

**Phân biệt lỗi:** response thành công luôn có `wc_active: true` (trừ `/health` dùng
`ok` và `woocommerce_active`). Nếu response không có `data` mà có `code` + `message`
+ `data.status` thì đó **là lỗi**, xem `data.status` để biết HTTP status.

---

## 6. Quy tắc an toàn khi kiểm tra

1. **Chỉ dùng GET.** Tuyệt đối không gọi **POST, PUT, PATCH, DELETE** đến bất kỳ
   endpoint nào trong `kc/v1`. Plugin hiện tại **chưa đăng ký** các method này nên
   WordPress sẽ trả `404 rest_no_route` — nếu bạn thấy `405` hoặc `rest_no_route`
   khi dùng POST/PUT/PATCH/DELETE thì đó là hành vi đúng và mong đợi.
2. **Không sửa dữ liệu trên website** trong quá trình kiểm tra: không tạo/sửa/xóa
   sản phẩm, không tạo đơn, không trừ tồn kho.
3. **Không đưa mật khẩu ứng dụng** vào tài liệu, commit Git, ảnh chụp màn hình hay
   tin nhắn. Xoá biến môi trường sau khi test: `Remove-Item Env:\MKC_APP`.
4. **Thu hồi Application Password** ngay sau khi test xong, tại
   *Hồ sơ người dùng → Application Passwords → Revoke*.
5. Nếu plugin gây lỗi trên website: **Deactivate ngay**. Plugin không tạo bảng
   riêng nên deactivate không làm mất dữ liệu.

---

## 7. Bảng ghi nhận kết quả

Điền sau khi test, để dùng làm đầu vào cho bước viết app Flutter.

| # | Endpoint | Kỳ vọng | HTTP thực tế | Kết quả | Ghi chú / JSON mẫu |
|---|---|---|---|---|---|
| 1 | `GET /health` | `200`, `woocommerce_active: true` | | ☐ Đạt ☐ Lỗi | |
| 2 | `GET /products` | `200`, có `data[]` | | ☐ Đạt ☐ Lỗi | |
| 3 | `GET /products?per_page=5&page=2` | `200`, phân trang đúng | | ☐ Đạt ☐ Lỗi | |
| 4 | `GET /products?search=…` | `200`, lọc đúng | | ☐ Đạt ☐ Lỗi | |
| 5 | `GET /products?per_page=100` | `400 rest_invalid_param` | | ☐ Đạt ☐ Lỗi | |
| 6 | `GET /products/{id}` (id thật) | `200`, đủ trường chi tiết | | ☐ Đạt ☐ Lỗi | |
| 7 | `GET /products/0` | `404 kc_not_found` | | ☐ Đạt ☐ Lỗi | |
| 8 | `GET /categories` | `200`, có `data[]` | | ☐ Đạt ☐ Lỗi | |
| 9 | `GET /variations?product_id={id}` | `200`, `product_id` đúng | | ☐ Đạt ☐ Lỗi | |
| 10 | `GET /variations?product_id=abc` | `400 rest_invalid_param` | | ☐ Đạt ☐ Lỗi | |
| 11 | `GET /orders` **không auth** | `401 kc_not_authenticated` | | ☐ Đạt ☐ Lỗi | |
| 12 | `GET /orders` **có auth** | `200`, có `data[]` | | ☐ Đạt ☐ Lỗi | |
| 13 | `GET /orders?status=processing` | `200`, lọc đúng | | ☐ Đạt ☐ Lỗi | |
| 14 | `GET /orders?status=xxx` | `400 rest_invalid_param` | | ☐ Đạt ☐ Lỗi | |
| 15 | `GET /orders?date_from=2026-01-01&date_to=2026-12-31` | `200` | | ☐ Đạt ☐ Lỗi | |
| 16 | `GET /orders?date_from=abc` | `400 rest_invalid_param` | | ☐ Đạt ☐ Lỗi | |
| 16b | `GET /orders?date_from=2026-12-31&date_to=2026-01-01` | `400 kc_invalid_date_range` | | ☐ Đạt ☐ Lỗi | |
| 17 | `GET /orders/{id}` **có auth** | `200`, đủ trường chi tiết | | ☐ Đạt ☐ Lỗi | |
| 18 | `GET /orders/{id}` **không auth** | `401 kc_not_authenticated` | | ☐ Đạt ☐ Lỗi | |
| 19 | `GET /orders/99999999` **có auth** | `404 kc_not_found` | | ☐ Đạt ☐ Lỗi | |
| 20 | Tài khoản không có quyền | `403 kc_cannot_view_orders` | | ☐ Đạt ☐ Lỗi | |

---

## 8. Giới hạn đã biết

| Vấn đề | Trạng thái |
|---|---|
| Chưa chạy được `php -l` (máy phát triển không có PHP) | Cần kiểm tra khi upload; nếu WordPress báo lỗi plugin sẽ báo ngay trong wp-admin |
| Đã runtime-test toàn bộ endpoint trên production (27/09/2026) | **Đạt**, gồm cả nhánh `/orders` có auth. Xem mục 7 |
| `count` là số item trong trang, không phải tổng số bản ghi | Chấp nhận để giảm truy vấn `COUNT` |
| `search` của `/variations` lọc sau khi lấy dữ liệu | Dùng `per_page=50` khi tìm biến thể |
| Chỉ trả sản phẩm `publish` | Sản phẩm nháp không xuất hiện ở endpoint public |
| `/variations` chỉ trả biến thể có cha `publish` | Sản phẩm nháp không lộ biến thể. `product_id` trỏ tới cha chưa publish trả `404 kc_not_found` |
| Mã lỗi validation gần như luôn là `rest_invalid_param` | Hành vi mặc định của WordPress (mọi lỗi `validate_callback` cấp tham số đều bị bọc lại). **Ngoại lệ đã kiểm tra production:** khoảng ngày ngược trả `400 kc_invalid_date_range` vì đó là `validate_callback` cấp route. App bắt lỗi theo HTTP status |
| Chưa có tổng tiền từng trạng thái đơn | App tự tính từ `total` của từng đơn |

---

## 8.1. URL cần kiểm tra lại sau khi sửa

Ba thay đổi trong bản sửa gần nhất (`variations` lọc theo cha publish, validation
`page`/`per_page` trả 400) cần xác nhận lại trên production sau khi upload:

```bash
# 1. Không còn biến thể của sản phẩm cha nháp 639 (trước đây trả 3 biến thể)
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?per_page=50"
#    → 200, mọi phần tử có product_id đều là sản phẩm publish

curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?product_id=639&per_page=50"
#    → 404 kc_not_found

curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/variations?search=buoi&per_page=50"
#    → 200, chỉ còn biến thể của sản phẩm publish

# 2. Validation page/per_page trả 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=0"    # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=51"   # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=100"  # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=-5"   # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=abc"  # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?page=0"        # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?page=-1"       # 400
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?page=abc"      # 400

# 3. Giá trị hợp lệ vẫn chạy bình thường
curl -i "https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=5&page=2"  # 200
```

> Lưu ý: `?per_page=abc` và `?page=abc` phải được gửi nguyên văn (không percent-encode).

## 8.2. URL cần kiểm tra lại sau bản sửa order detail

Bản sửa này đã được xác nhận trên production: `/orders/{id}` trả `200` JSON hợp lệ,
không còn `500` trang HTML. Phạm vi thay đổi:

- `handle_order_detail()` bọc `try/catch (\Throwable)` → lỗi trả JSON
  `500 kc_order_detail_failed` thay vì trang "critical error" của WordPress.
- 7 trường chỉ có ở chi tiết đơn đi qua `order_float_field()` / `order_text_field()`
  (guard `is_callable()`, không dùng `method_exists`).
- `serialize_order_items()` tách `try/catch` từng line item.

```bash
# Cần Application Password cho cả hai lệnh
curl -i -u "user:app-password" \
  "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/669"
#    → 200, JSON hợp lệ, đủ 23 trường; KHÔNG phải trang HTML

curl -i -u "user:app-password" \
  "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders/99999999"
#    → 404 kc_not_found

curl -i -u "user:app-password" \
  "https://myphamkimcuong.id.vn/wp-json/kc/v1/orders?date_from=2026-12-31&date_to=2026-01-01"
#    → 400 kc_invalid_date_range (ngoại lệ cấp route, xem mục 6)
```

---

## 9. Sau khi test xong

Gửi lại cho bước tiếp theo:

1. Kết quả bảng mục 7 (HTTP status thực tế của từng endpoint).
2. **JSON thực tế** của ít nhất: `/health`, `/products` (1 sản phẩm), `/products/{id}`,
   `/categories`, `/variations?product_id=…` (1 biến thể), `/orders` (1 đơn), `/orders/{id}`.
3. Nếu có endpoint nào lỗi: dán nguyên response nhận được.

App Flutter sẽ viết dựa trên JSON thực tế đó, không dựa trên giả định.
