# POS API · Đặc Tả `POST /pos/sales`

> **CẢNH BÁO: ENDPOINT CHƯA ĐƯỢC UPLOAD LÊN PRODUCTION.**
> Mã trong `mypham-kim-cuong-manager/includes/class-pos.php` mới chỉ được
> static-check trên máy (không có PHP/Docker/WordPress ở máy dev). Chưa có
> request POST nào được gửi lên production và chưa tạo đơn hàng thật nào.
> Chỉ upload + kiểm tra trên staging hoặc site thật khi được cho phép.

Plugin: `mypham-kim-cuong-manager` · Namespace: `kc/v1`

Đây là **endpoint ghi duy nhất** của plugin. Toàn bộ endpoint còn lại
(`/health`, `/products`, `/products/{id}`, `/categories`, `/variations`,
`/orders`, `/orders/{id}`) vẫn là read-only và không bị thay đổi.

Đặc tả tổng thể: [03_API_SPECIFICATION](03_API_SPECIFICATION.md) ·
Bảo mật: [05_SECURITY](05_SECURITY.md)

---

## 1. URL và method

| Mục | Giá trị |
|---|---|
| URL | `https://myphamkimcuong.id.vn/wp-json/kc/v1/pos/sales` |
| Method | `POST` |
| Content-Type | `application/json` |
| Accept | `application/json` |
| Giao thức | HTTPS bắt buộc |
| Số request | 1 request = 1 lần thanh toán |

## 2. Xác thực

| Mục | Quy tắc |
|---|---|
| Cơ chế | WordPress **Application Password** qua HTTP Basic |
| Header | `Authorization: Basic base64(username:application-password)` |
| Điều kiện | `is_user_logged_in()` = true |
| Capability | `manage_woocommerce` |
| Chưa đăng nhập | HTTP `401` |
| Không phải HTTPS | HTTP `403` (`kc_https_required`) |
| Thiếu capability | HTTP `403` (`kc_cannot_create_sale`) |

Không dùng JWT tự viết, không có secret trong plugin, không có token hard-code
trong APK, không có bảng user riêng. WordPress tự xác thực Application
Password và dựng `current_user`; plugin chỉ kiểm tra đăng nhập, HTTPS và
capability.

Vì sao `manage_woocommerce` mà không dùng `edit_shop_orders` như lúc xem đơn:
đây là endpoint **ghi tiền và trừ kho**, nên yêu cầu quyền cao nhất.

## 3. Request

```json
{
  "request_id": "POS-DEVICE-20260927-000001",
  "payment_method": "cash",
  "customer_id": 0,
  "customer_note": "",
  "items": [
    { "product_id": 651, "variation_id": 0, "quantity": 1 }
  ]
}
```

| Trường | Bắt buộc | Kiểu | Quy tắc |
|---|---|---|---|
| `request_id` | Có | string | 1–64 ký tự, chỉ gồm `A–Z a–z 0–9 . _ : -`. Dùng làm khoá chống bấm thanh toán hai lần. |
| `payment_method` | Có | string | Một trong `cash`, `bacs`, `vietqr`. |
| `customer_id` | Không | int | `0` = khách lẻ, `> 0` = khách WordPress hợp lệ. Xem mục 3.1. |
| `customer_note` | Không | string | Ghi chú, cắt còn tối đa 500 ký tự. |
| `items[].product_id` | Có | int | Id sản phẩm WooCommerce, > 0. |
| `items[].variation_id` | Không | int | Sản phẩm simple dùng `0`; sản phẩm variable cần `> 0`. Xem mục 3.2. |
| `items[].quantity` | Có | int | Số nguyên dương, tối đa 9999. |

### 3.1. Quy tắc `customer_id`

```text
customer_id = 0: khách lẻ
customer_id > 0: khách WordPress hợp lệ
```

`0` là khách lẻ: đơn được tạo không gắn user, server **không** tra
`get_userdata( 0 )` (tra luôn ra `false`).

| Giá trị gửi lên | Kết quả |
|---|---|
| Bỏ trống (không có trường) | `0` — khách lẻ |
| `null` | `0` — khách lẻ |
| `""` (chuỗi rỗng) | `0` — khách lẻ |
| `0` | `0` — khách lẻ |
| `"0"`, `" 0 "`, `0.0`, `"0.0"` | Chuẩn hoá thành `0` — khách lẻ |
| Số nguyên `> 0` tồn tại trong WordPress | Dùng user đó |
| Chuỗi `"42"` hoặc `42.0` của user tồn tại | Chuẩn hoá thành `42` |
| Số nguyên `> 0` không tồn tại | `400` `kc_invalid_customer` |
| Số âm (`-1`), thập phân có phần lẻ (`1.5`, `"0.5"`) | `400` `kc_invalid_customer` |
| `true` / `false`, mảng, đối tượng, `"abc"`, `"7abc"`, `"  "` | `400` `kc_invalid_customer` |

### 3.2. Quy tắc `variation_id`

```text
sản phẩm simple:   variation_id = 0   (không dùng variation)
sản phẩm variable: variation_id > 0  (bắt buộc có variation)
```

Server chỉ biết kiểu sản phẩm sau khi nạp sản phẩm lên, nên `variation_id: 0`
được chấp nhận ở bước kiểm tra hình thức; nếu sản phẩm hoá ra là **variable**
thì mới báo lỗi yêu cầu variation.

| Giá trị gửi lên | Kết quả |
|---|---|
| Bỏ trống (không có trường) | `0` — không dùng variation |
| `null`, `""` | `0` — không dùng variation |
| `0`, `"0"`, `" 0 "`, `0.0`, `"0.0"` | Chuẩn hoá thành `0` — không dùng variation |
| Số nguyên `> 0` | Variation tương ứng, phải tồn tại và thuộc `product_id` |
| Chuỗi `"2"` hoặc `2.0` | Chuẩn hoá thành `2` |
| Số âm (`-1`), thập phân có phần lẻ (`1.5`, `"0.5"`) | `400` `kc_invalid_variation` |
| `true` / `false`, mảng, đối tượng, `"abc"`, `"2abc"`, `"  "` | `400` `kc_invalid_variation` |

Ma trận sản phẩm × variation:

| Sản phẩm | `variation_id` | Kết quả |
|---|---|---|
| Simple | `0` hoặc bỏ trống | OK, bán chính sản phẩm |
| Simple | `> 0` | `400` `kc_invalid_variation` — variation không thuộc sản phẩm cha |
| Variable | `0` hoặc bỏ trống | `400` `kc_invalid_variation` — bắt buộc gửi `variation_id > 0` |
| Variable | `> 0`, tồn tại, đúng cha | OK, bán variation đó |
| Variable | `> 0`, không tồn tại | `400` `kc_invalid_variation` — không tìm thấy variation |
| Variable | `> 0`, thuộc sản phẩm cha khác | `400` `kc_invalid_variation` — không thuộc sản phẩm cha |

Lưu ý: `product_id` và `quantity` dùng bộ chuyển đổi `positive_integer()` và vẫn
phải `> 0`. Riêng `customer_id` và `variation_id` dùng
`non_negative_integer()` nên nhận `0`. Cả hai hàm đều từ chối số âm và không
dùng `absint()` (vì `absint( '-5' )` trả 5 nên số âm sẽ lọt qua).



Giới hạn khác: tối đa **50** dòng sản phẩm mỗi lần bán. Trong cùng một lần bán
không được trùng `product_id` + `variation_id`.

**Không có trường giá.** Client không được gửi giá và server cũng không đọc giá
từ client. Giá luôn được lấy lại từ WooCommerce tại thời điểm bán.

## 4. Response thành công

HTTP `201` khi tạo mới, HTTP `200` khi trả lại đơn cũ (idempotency).

```json
{
  "success": true,
  "replayed": false,
  "order": {
    "id": 700,
    "number": "700",
    "status": "completed",
    "created_via": "kc_pos",
    "payment_method": "cash",
    "currency": "VND",
    "total": 220000,
    "request_id": "POS-DEVICE-20260927-000001",
    "line_items": [
      {
        "id": 1,
        "product_id": 651,
        "variation_id": 0,
        "name": "Son Kem Lì Satin",
        "sku": "KC-0001-RED",
        "quantity": 2,
        "price": 110000,
        "subtotal": 220000,
        "total": 220000,
        "image_url": "https://myphamkimcuong.id.vn/wp-content/uploads/son-kem-li-satin.jpg"
      }
    ]
  }
}
```

| Trường response | Ý nghĩa |
|---|---|
| `success` | Luôn `true` khi thành công. |
| `replayed` | `true` = đơn do request trước tạo, `false` = đơn vừa tạo. |
| `order.status` | `completed` (tiền mặt) hoặc `on-hold` (chuyển khoản, VietQR). |
| `order.line_items[].image_url` | Có thể `null`; variation thiếu ảnh thì lấy ảnh sản phẩm cha. |

Response **không** chứa password, secret, token hay dữ liệu không cần thiết.

### Payment method → trạng thái đơn

| `payment_method` | Gateway ghi vào đơn | `status` | `date_paid` |
|---|---|---|---|
| `cash` | `cash` | `completed` | Có |
| `bacs` | `bacs` | `on-hold` | Không |
| `vietqr` | `vietqr` nếu site có cổng này, không thì `bacs` | `on-hold` | Không |

Chuyển khoản và VietQR để `on-hold` đúng như luồng BACS của WooCommerce để cửa
hàng đối soát sau; method gốc vẫn lưu ở order meta `_mkc_pos_payment_method`.
Cả `completed` và `on-hold` đều kích hoạt trừ kho của WooCommerce.

## 5. Lỗi

Mọi lỗi dùng cùng một định dạng JSON (chuẩn `WP_Error` của WordPress REST):

```json
{
  "code": "kc_invalid_request",
  "message": "items[0].quantity phải là số nguyên dương.",
  "data": { "status": 400 }
}
```

| Tình huống | HTTP | `code` |
|---|---|---|
| Body rỗng hoặc JSON hỏng | `400` | `kc_invalid_json` |
| Body không phải JSON object | `400` | `kc_invalid_request` |
| Thiếu `request_id`, sai kiểu, quá dài hoặc sai ký tự | `400` | `kc_invalid_request_id` |
| `payment_method` không nằm trong whitelist | `400` | `kc_invalid_payment_method` |
| `items` rỗng hoặc không phải mảng | `400` | `kc_invalid_items` |
| Quá 50 dòng sản phẩm | `400` | `kc_too_many_items` |
| `quantity` không phải số nguyên dương hoặc > 9999 | `400` | `kc_invalid_quantity` |
| Trùng `product_id` + `variation_id` trong cùng lần bán | `400` | `kc_duplicate_item` |
| `variation_id` sai định dạng (số âm, thập phân có phần lẻ, chuỗi, boolean, mảng) | `400` | `kc_invalid_variation` |
| `variation_id` không tồn tại, hoặc không thuộc sản phẩm cha, hoặc sản phẩm biến thể mà gửi `variation_id` = 0 | `400` | `kc_invalid_variation` |
| Sản phẩm không bán được: không publish, chưa có giá, sản phẩm ngoài | `400` | `kc_product_not_purchasable` |
| `customer_id` không hợp lệ | `400` | `kc_invalid_customer` |
| Sản phẩm không tồn tại | `404` | `kc_product_not_found` |
| Hết hàng hoặc thiếu tồn kho | `409` | `kc_out_of_stock` |
| Đơn cùng `request_id` đang được tạo dở | `409` | `kc_sale_in_progress` |
| Chưa đăng nhập | `401` | `kc_not_authenticated` |
| Không phải HTTPS | `403` | `kc_https_required` |
| Thiếu capability | `403` | `kc_cannot_create_sale` |
| Không tra được `request_id` (lỗi hệ thống) | `500` | `kc_idempotency_unavailable` |
| Lỗi khi tạo đơn | `500` | `kc_sale_failed` |
| Đơn đã tạo nhưng không đọc lại được chi tiết | `500` | `kc_sale_response_failed` |
| WooCommerce chưa active | `503` | `kc_woocommerce_unavailable` |

Lỗi `500` trả JSON, không bao giờ trả HTML của WordPress.

## 6. Idempotency

`request_id` là khoá chống bấm thanh toán hai lần.

| Tình huống | Kết quả |
|---|---|
| Gửi `request_id` lần đầu | Tạo đơn, HTTP `201`, `replayed: false`. |
| Gửi lại **cùng** `request_id` | Trả lại đơn cũ, HTTP `200`, `replayed: true`. **Không tạo đơn mới, không trừ kho thêm.** |
| Gửi `request_id` mới | Tạo đơn mới. |

Cơ chế lưu trữ:

- Order meta `_mkc_pos_request_id` là nguồn sự thật, được ghi **ngay** khi đơn vừa
  tạo, trước khi thêm sản phẩm. Nhờ vậy request đến sau trong lúc đơn đang tạo
  sẽ thấy đơn đó thay vì tạo đơn thứ hai.
- Nếu đơn cùng `request_id` còn đang tạo dở (chưa có dòng sản phẩm) thì trả
  `409 kc_sale_in_progress` để app thử lại, thay vì trả một đơn rỗng.
- Tra cứu phụ thuộc cách site lưu đơn hàng, nên code chọn đúng cơ chế:
  - **HPOS** (mặc định từ WooCommerce 8.2): `meta_query` của `wc_get_orders()`.
  - **Post storage**: `get_posts()` với `meta_key`/`meta_value` (vì `meta_query`
    không được hỗ trợ và sẽ bị WordPress bỏ qua âm thầm).
- Không tạo custom table, không dùng SQL thô.
- Nếu không tra được idempotency (lỗi hệ thống) endpoint trả `500` và **không**
  tạo đơn, vì tạo đơn mà không kiểm tra được sẽ sinh đơn trùng.

Giới hạn đã biết: nếu hai request **thật sự chạy song song** cùng một
`request_id` thì vẫn có thể tạo ra hai đơn, vì không có ràng buộc unique ở tầng
database mà không cần custom table. App POS phải gửi lại tuần tự (mỗi lần bán
chờ xong response trước khi bấm tiếp), khi đó idempotency đảm bảo tuyệt đối.

## 7. WooCommerce xử lý dòng sản phẩm và tồn kho

Plugin chỉ làm 4 việc, tất cả qua CRUD chính thức:

| Bước | Hàm dùng | Ý nghĩa |
|---|---|---|
| 1 | `wc_create_order()` | Tạo đơn `pending`, `created_via = kc_pos`. |
| 2 | `WC_Order::add_product( $product, $qty )` | Thêm dòng sản phẩm. Không truyền `subtotal`/`total` nên WooCommerce tự lấy **giá hiện tại** của sản phẩm. |
| 3 | `WC_Order::calculate_totals()` | WooCommerce tự tính tổng tiền, thuế, phí. |
| 4 | `WC_Order::update_status( 'completed' \| 'on-hold' )` | Hook `wc_maybe_reduce_stock_levels` của WooCommerce tự trừ kho **đúng một lần** (đã có guard bằng meta `_order_stock_reduced`). |

Những gì plugin **không** làm:

- Không SQL trực tiếp, không `$wpdb`, không custom table.
- Không tự sửa `_stock`, không dùng `wc_update_product_stock()` hay phép trừ số
  học thủ công.
- Không trừ kho hai lần: chuyển trạng thái **sau khi** đã có dòng sản phẩm, và
  WooCommerce tự chốn giảm trùng.

Trước khi tạo đơn, server kiểm tra: sản phẩm tồn tại, đang `publish`, không
phải sản phẩm ngoài, có giá, `is_in_stock()`, `is_purchasable()` và nếu
`managing_stock()` thì tồn kho phải đủ số lượng. Bản này cố ý **không** dựa
vào backorder, số lượng phải có thật trong kho. Kiểm tra tồn kho không cộng dồn
đơn đang `pending`/`on-hold` sẵn có — giới hạn này ghi nhận để các phase sau xử
lý.

Nếu có lỗi giữa chừng (sau khi tạo đơn nhưng chưa chuyển trạng thái, tức là chưa
trừ kho), đơn đó bị xoá để không để lại đơn rỗng; `request_id` được giải phóng
nên app gửi lại là bán được.

## 8. Cách test sau này

Chưa test được ở giai đoạn này vì máy dev không có PHP/Docker/WordPress.
Khi được phép, thực hiện theo thứ tự an toàn:

1. **Chưa upload production.** Chạy trên staging hoặc bản sao của site trước.
2. Gửi `GET /wp-json/kc/v1/health` để chắc plugin đã nạp.
3. Gửi `POST /pos/sales` **không** có header `Authorization` → phải nhận `401`
   và **không** tạo đơn.
4. Gửi `POST /pos/sales` với tài khoản không có `manage_woocommerce` → `403`.
5. Gửi body hỏng (`{` hoặc `"abc"`) → `400`, không tạo đơn.
6. Thiếu `request_id`, `items` rỗng, `quantity = 0`, `product_id` không tồn tại
   → lần lượt `400` / `404`, không tạo đơn.
7. Sản phẩm **simple** với `variation_id: 0` → phải tạo được đơn (dùng đúng
   `variation_id: 0`, `"0"`, `0.0`, `"0.0"` hoặc bỏ hẳn trường đều được).
8. Sản phẩm **variable** với `variation_id: 0` → `400 kc_invalid_variation`.
9. Sản phẩm **variable** với `variation_id` không tồn tại, hoặc thuộc sản phẩm
   cha khác → `400 kc_invalid_variation`.
10. `customer_id: 0` (khách lẻ) → phải tạo được đơn, đơn không gắn user.
11. Dùng `request_id` cố định, gửi **hai lần** → lần một `201`, lần hai `200`
    với `replayed: true` và **cùng** `order.id`; kiểm tra trong wp-admin chỉ có
    **một** đơn và tồn kho chỉ trừ **một** lần.
12. Một lần bán thật với số lượng vượt tồn kho → `409 kc_out_of_stock`, không tạo
    đơn.
13. Kiểm tra đơn trong wp-admin: `created_via = kc_pos`, đúng payment method,
    đúng tổng tiền, tồn kho khớp.

Danh sách kiểm tra tổng thể: [API_TEST_CHECKLIST](API_TEST_CHECKLIST.md).

## 9. Ngoài phạm vi phiên bản này

Chưa làm, để phase sau: trả hàng, nhập kho, sửa/huỷ đơn POS, nhiều chi nhánh,
thuế theo từng địa điểm, in hoá đơn, đọc barcode trong request, lô hàng và hạn
sử dụng, POS offline.
