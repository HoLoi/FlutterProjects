# 05 · API Specification

## 1. Mục đích

Định nghĩa **API contract** chuẩn giữa Flutter App và plugin: base conventions, authentication, error envelope, pagination/filter/sort, idempotency, và đặc tả từng nhóm endpoint (method, URL, request, response, permissions, validation).

## 2. Phạm vi

Mọi endpoint plugin REST namespace `kc/v1` (đường `https://myphamkimcuong.id.vn/wp-json/kc/v1/...`). Không phải endpoint WC REST chuẩn (bị tắt cho app trừ khi cần admin tool).

## 3. Conventions (base layout)

### 3.1 Giao thức
- Base URL: `https://{host}/wp-json/kc/v1`
- Chỉ HTTPS. Không HTTP.
- Content-Type: `application/json; charset=utf-8`. Upload: `multipart/form-data`.
- Ngôn ngữ lỗi: Vietnamese-friendly `message`, máy đọc: `code`.

### 3.2 Authentication
- Header: `Authorization: Bearer {access_token}`.
- Token: JWT (plugin issue), short-lived (~1h) + `POST /auth/refresh` với `refresh_token` (24h, rotate).
- Mỗi token gắn `staff_id` + `device_id`; thu hồi server-side (bảng `kc_auth_tokens`).
- Permission check trên **từng endpoint** (không phụ thuộc client).
- Lỗi: `401` token hết hạn (client tự refresh rồi retry 1 lần), `403` không quyền.

### 3.3 Envelope
- Thành công: trả thẳng resource hoặc:
  - List: `{ "data": [...], "meta": { "page":1, "per_page":50, "total":1234, "pages":25 } }`
  - Mutation: trả resource đã tạo/sửa + `meta.last_insert_id` nếu cần.
- Lỗi (chuẩn toàn plugin):
```json
{
  "code": "KC_VALIDATION_ERROR",
  "message": "Số lượng phải lớn hơn 0",
  "status": 422,
  "details": { "field": "qty", "reason": "must_be_positive" },
  "error_id": "abc123"
}
```
  Các `code` dùng chung: `KC_UNAUTHORIZED`, `KC_FORBIDDEN`, `KC_NOT_FOUND`, `KC_VALIDATION_ERROR`, `KC_CONFLICT`, `KC_INSUFFICIENT_STOCK`, `KC_RATE_LIMITED`, `KC_INTERNAL_ERROR`, `KC_IDEMPOTENCY_REPLAY`, `KC_IDEMPOTENCY_FINGERPRINT_MISMATCH`.

### 3.4 HTTP status
- `200` OK · `201` Created · `202` Accepted (queued/async) · `204` No content
- `400` Bad request · `401` Unauthorized · `403` Forbidden · `404` Not found · `409` Conflict (stock/version) · `422` Validation · `429` Rate limited · `500` Internal.

### 3.5 Pagination / Filter / Sort (list endpoints)
- `page` (≥1, default 1), `per_page` (1–100, default 50).
- Lọc: params riêng từng tài nguyên (`search`, `status`, `category_id`, `date_from`, `date_to`, `type`, `product_id`...).
- Sort: `orderby` + `order` (asc|desc) với danh sách trắng từng endpoint.
- Response meta mang `total`, `pages` để vẽ infinite scroll.

### 3.6 Idempotency (mutation quan trọng)
- Client gửi header `Idempotency-Key: {uuid}` cho: `POST pos/sales`, `POST receivings`, `POST pos/sales/{id}/refund` (thuộc returns), `POST inventory/adjust`, `PUT inventory/counts/{id}/confirm`, `POST returns`, `POST sync/queue`.
- Server: nếu key mới → xử lý; nếu key tồn tại + cùng fingerprint → **trả lại response cũ (200)**; khác fingerprint → `409 KC_IDEMPOTENCY_FINGERPRINT_MISMATCH`.
- TTL idempotency: 24h (config).

### 3.7 Transaction
- Các mutation ghi **multiple custom tables** gói trong **MySQL transaction** (BEGIN/COMMIT/ROLLBACK); với nghiệp vụ bao quanh WC CRUD/hooks (vd POS sale) dùng **logical unit of work + trạng thái trung gian + compensation/recovery** (D-23) vì side-effect của WC/plugin không phải lúc nào cũng rollback sạch. Retry: deadlock/timeout → `409 KC_CONFLICT` (client retry cùng idempotency key).
- `retry-after` header khi rate limit hoặc lock.

### 3.8 Time
- Request có thể gửi `client_sent_at` (UTC ISO) để khớp đồng hồ — chỉ tham khảo; **server là nguồn thời gian** cho giao dịch. Response luôn trả `server_time`.

## 4. Danh mục endpoint tổng quan

| Nhóm | Endpoints |
|---|---|
| Auth | `/auth/login`, `/auth/refresh`, `/auth/logout`, `/auth/me`, `/auth/permissions`, `/auth/change-pin` |
| Dashboard | `/dashboard/summary`, `/dashboard/alerts` |
| Products | `/products`, `/products/{id}`, `/products/by-barcode/{barcode}`, `/products/by-sku/{sku}`, `/variations`, `/variations/{id}`, `/categories`, `/brands` |
| Media | `/uploads`, `/media/{id}` |
| Suppliers | `/suppliers`, `/suppliers/{id}`, `/suppliers/{id}/purchases` |
| Receiving | `/receivings`, `/receivings/{id}` |
| Lots | `/lots`, `/lots/{id}`, `/lots/{id}/ledger`, `/lots/by-product/{product_or_variation_id}` |
| Inventory | `/inventory/stock`, `/inventory/transactions`, `/inventory/adjust`, `/inventory/counts`, `/inventory/counts/{id}`, `/inventory/counts/{id}/items`, `/inventory/counts/{id}/confirm`, `/inventory/expiry-alerts`, `/inventory/summary` |
| POS | `/pos/sessions`, `/pos/sessions/{id}`, `/pos/sessions/{id}/close`, `/pos/sales`, `/pos/sales/{id}`, `/pos/payment-methods`, `/pos/vietqr/new` |
| Receipts | `/receipts/{id}`, `/receipts/{id}/print` |
| Returns | `/returns`, `/returns/{id}` |
| Orders | `/orders`, `/orders/{id}`, `/orders/{id}/status`, `/orders/{id}/refund` |
| Customers | `/customers`, `/customers/{id}`, `/customers/{id}/orders` |
| Coupons | `/coupons`, `/coupons/{id}`, `/coupons/validate` |
| Reports | `/reports/summary`, `/reports/sales`, `/reports/profit`, `/reports/products`, `/reports/inventory` |
| Notifications | `/notifications`, `/notifications/unread-count`, `/notifications/{id}/read`, `/notifications/read-all` |
| ActivityLog | `/activity-log` |
| Staff | `/staff`, `/staff/{id}`, `/staff/{id}/permissions` |
| Settings | `/settings`, `/settings/store-info` |
| Sync (offline) | `/sync/queue` (POST batch), `/sync/status`, `/sync/devices`, `/sync/devices/{id}` |

## 5. Đặc tả chi tiết (nhóm chính)

> Dưới đây là đặc tả ngắn gọn nhưng đủ để dev thực thi. Một số endpoint dạng "list" ghi rõ param lọc.

### 5.1 Auth

#### POST `/auth/login`
- Request: `{ "username": "...", "password": "..." }` hoặc `{ "phone": "...", "pin": "123456", "device_id": "uuid" }` (PIN POS)
- Response `201`:
```json
{
  "token_type": "Bearer",
  "access_token": "...", "access_expires_at": "...",
  "refresh_token": "...", "refresh_expires_at": "...",
  "staff": { "id": 1, "user_id": 3, "full_name": "...", "role": "kc_staff", "permissions": ["pos.open", "pos.sale", ...] },
  "store": { "name": "...", "address": "...", "phone": "...", "timezone": "Asia/Ho_Chi_Minh", "currency": "VND" }
}
```
- Permission: public (rate limited).
- Lỗi: `401` sai thông tin, `423` nhân viên bị khóa.

#### POST `/auth/refresh`
- Request: `{ "refresh_token": "...", "device_id": "uuid" }`; rotate refresh token; `401` nếu revoked/hết hạn.

#### GET `/auth/me` — thông tin + permission hiện tại. `403` nếu role bị đổi.
#### POST `/auth/logout` — revoke token (có thể revoke mọi device của người đó với `all=true`).
#### POST `/auth/change-pin` — đổi PIN POS (cần `old_pin` hoặc password).

### 5.2 Dashboard

#### GET `/dashboard/summary`
- Permission: `dashboard.read`
- Query: `?date=YYYY-MM-DD` (default hôm nay), `&compare=previous` optional.
- Response:
```json
{
  "products": { "total": 100, "publish": 95, "out_of_stock": 4, "low_stock": 6 },
  "expiry": { "expiring_soon": 3, "expired": 1, "no_hsd": 12 },
  "sales": { "today": { "revenue": 1200000, "cost": 700000, "gross_profit": 500000, "orders": 8 },
             "period": { "day": 1200000, "month": 35000000, "year": 410000000 } },
  "series": { "revenue_7d": [ { "date": "...", "revenue": 0 } ], "month_12": [...], "year_5": [...] },
  "best_sellers": [ { "product_id": 1, "name": "...", "qty": 10 } ],
  "slow_sellers": [...],
  "alerts": { "pending_orders": 2, "critical": [...] }
}
```
- Lưu ý: `revenue ≠ profit`; luôn có `cost` + `gross_profit` đi kèm.

#### GET `/dashboard/alerts` — danh sách cảnh báo (dữ liệu nguồn của notification).

### 5.3 Products

#### GET `/products`
- Lọc: `search` (name/sku), `status` (publish|draft|trash), `type` (simple|variable), `category_id`, `stock_status` (instock|outofstock|low), `include_variations` (bool, mặc định false — chỉ gửi product; app mở rộng khi cần), `barcode`, `updated_after` (ISO, dùng cho sync offline).
- Response (item):
```json
{
  "id": 12, "type": "variable", "name": "...", "slug": "...",
  "status": "publish", "sku": "ABC-01", "barcode": "8934...", "cost": 100000,
  "regular_price": 250000, "sale_price": 220000, "price": 220000,
  "images": [ {"id": 9, "src": "https://...", "position": 0} ],
  "categories": [ {"id": 3, "name": "Serum"} ],
  "brand": "Bioderma",
  "manage_stock": true, "stock_quantity": 20, "stock_status": "instock", "low_stock_amount": 5,
  "description": "...", "short_description": "...",
  "attributes": [ { "name": "Kích thước", "options": ["30ml","50ml"] } ],
  "variations": [ { "id": 88, "attributes": {"Kích thước":"50ml"}, "sku": "...", "barcode":"...", "cost":0, "price":0, "stock_quantity":0 } ],
  "lots_summary": { "open_lots": 2, "expiring_soon": 0, "expired": 0, "no_hsd": 0 },
  "updated_at": "..."
}
```
- Sort: `orderby=name|price|stock_quantity|updated_at|popularity`, default `updated_at desc`. Có thể `by_ids=1,2,3` để lấy theo danh sách (dùng cho sync offline).

#### POST `/products` (permission `products.write`)
- Body: subset WC fields + `barcode`, `cost`, `variations[]` (khi variable), `images[]` (uploadId).
- Plugin: tạo WC product qua `wc_get_product`/`WC_Product` API → barcode upsert `kc_barcodes` + meta → trả `201`.

#### GET `/products/{id}` — chi tiết đầy đủ (bao gồm `variations[]` đầy đủ).
#### PUT `/products/{id}` — cập nhật (validator: nếu đổi `sku` trùng → `409`).
#### DELETE `/products/{id}` — xóa mềm (→ `trash`) nếu có lịch sử; xóa hẳn nếu chưa có giao dịch.
#### GET `/products/by-barcode/{barcode}` — barcode không tồn tại → `404` với body `{ "code":"KC_NOT_FOUND", "unlisted": true, "suggest_create": true, "barcode": "..." }`; app bật nút tạo SP.
#### GET `/products/by-sku/{sku}` — tương tự.

### 5.4 Variations

#### GET `/variations?product_id=` — lấy variations của product (có `stock_quantity`, `cost`, `barcode`, `attributes`, images).
#### POST `/variations` / PUT `/variations/{id}` / (DELETE) — vòng đời variation qua WC CRUD + `kc_barcodes`.

### 5.5 Supplying & Lot & Inventory

#### GET `/suppliers` (role: xem bởi người có `suppliers.read`)
#### POST `/suppliers` (`suppliers.write`) — body: name*, phone, email, address, tax_code, note.
#### GET `/suppliers/{id}/purchases` — receivings theo supplier + `total_cost`.

#### POST `/receivings` (`inventory.receive`) — **quan trọng, transaction**
- Body:
```json
{
  "supplier_id": 4,
  "received_at": "2026-09-20 08:00:00",
  "note": "Nhập lô đầu kỳ",
  "items": [
    { "product_id": 12, "variation_id": 88, "qty": 20, "unit_cost": 90000,
      "lot_code": "LOT-KC-001", "nsx": "2026-08-01", "hsd": "2028-08-01" }
  ]
}
```
- Server: BEGIN → per item tạo/gắn lot (auto `lot_code` nếu trống), tăng WC stock qua StockManager (D-22), insert `kc_inventory_transactions` (RECEIVING) + `kc_lot_ledger`, update `_kc_cost` weight, insert `kc_receivings/items` → COMMIT.
- Response `201`: `receiving_id`, `receiving_code`, items với `lot_id` gắn.

#### GET `/receivings` (lọc supplier_id, date_from/date_to, status). GET `/receivings/{id}` chi tiết + items.

#### GET `/inventory/stock` — snapshot stock per product/variation (joined WC + lot summary). Lọc `stock_status`, `product_id`.
#### GET `/inventory/transactions`
- Query: `product_id`, `variation_id`, `type`, `date_from`, `date_to`, `page`, `per_page`, `orderby=created_at`.
- Response item:
```json
{ "id": 9, "product_id": 12, "variation_id": 88, "qty": -1, "type": "POS_SALE",
  "ref_type": "pos_tx", "ref_id": 55, "lot_id": 31, "unit_cost": 90000, "cost_total": -90000,
  "running_stock": 19, "note": null, "created_at": "...", "created_by": 2 }
```
- Ví dụ hiển thị app: `19/09 +20 Nhập hàng · 19/09 -1 POS ...`.

#### POST `/inventory/adjust` (`inventory.adjust`) — body: `{ "product_id":.., "variation_id":.., "lot_id":..(nullable), "qty": -2, "reason_code":"damage", "reason":"vỡ", "note":"" }`. Transaction: thay stock qua StockManager (D-22), tx ADJUST, ledger, log. Response 200.

#### POST `/inventory/counts` — tạo phiên: body `{ "note": "Kiểm kho cuối tháng", "warehouse_id": null }`; response `201` phiên kiểm kho (app gọi tiếp GET items trống và điền dần).
#### GET `/inventory/counts` + `/{id}` + `/{id}/items` (trả system_qty — **snapshot tại thời điểm tạo items** để cố định chuẩn so sánh).
#### PUT `/inventory/counts/{id}/items` — gửi `actual_qty` theo từng item (from app sau khi đếm).
#### POST `/inventory/counts/{id}/confirm` (`inventory.adjust`) — **transaction**: khóa phiên, tính diff, với từng diff ≠0: thay stock qua StockManager (D-22), tx STOCK_COUNT, ledger; đặt status completed; trả bảng tóm tắt chênh lệch + cảnh báo nếu stock/expected mismatch (do có giao dịch xen giữa — ghi notice).

#### GET `/inventory/expiry-alerts?window=30`
- Response:
```json
{
  "expiring": [ { "lot_id": 12, "product_id": 12, "variation_id": 0, "name":"...", "lot_code":"...", "hsd":"2026-10-05", "days_left": 14, "remaining_qty": 8 } ],
  "expired": [...], "no_hsd": [...]
}
```

### 5.6 POS

#### POST `/pos/sessions` — mở ca: `{ "device_id": "...", "opening_cash": 200000 }` → `201` session.
#### POST `/pos/sessions/{id}/close` — `{ "closing_cash": 1500000, "note": "..." }` → tính `expected_cash` = opening + Σ cash sales − Σ cash refunds; trả diff.
#### GET `/pos/sales?date=&session_id=&payment_method=&page=` — danh sách giao dịch.
#### POST `/pos/sales` — **endpoint quan trọng nhất**. Chạy theo **logical unit of work** (không chỉ dựa 1 MySQL transaction vì WC CRUD/hooks/plugin có side-effect không rollback sạch): trạng thái trung gian `pending → processing → completed`, và `void / needs_review` khi hỏng giữa chừng + compensation/reversal + recovery job (chi tiết 10_POS_FLOW §4.3–4.4, DECISIONS D-23).
- Body:
```json
{
  "session_id": 3,
  "customer_id": null,
  "items": [
    { "product_id": 12, "variation_id": 88, "qty": 2, "unit_price": 220000, "line_discount": 0, "discount_reason": "" }
  ],
  "discount_total": 0, "discount_reason": "",
  "payment_method": "cash",
  "cash_received": 500000,
  "note": ""
}
```
- Flow server: check session open → tạo `kc_pos_transactions` status `pending` → BEGIN db transaction → với từng item: guard stock (`stock >= qty`; FAILED → rollback + `409 KC_INSUFFICIENT_STOCK` details item), ghi ledger + inventory tx (POS_SALE); tạo WC order (HPOS, status `completed`, payment, customer, line items để web thấy); insert `kc_pos_transaction_items` (lot_allocation FEFO), `kc_receipts` snapshot, activity log → update pos_tx `completed` → COMMIT.
- Nếu WC order/hook/plugin fail sau khi đã trừ stock (side-effect không luôn rollback sạch) → **compensation/reversal** + pos_tx `needs_review`; client **kiểm tra `GET /pos/sales/{id}` trước khi retry** (không retry mù) — xem 10_POS_FLOW §4.3–4.4 (D-23).
- Response `201`: `{ "pos_tx_id": ..., "pos_tx_code": "HD-...", "order_id": ..., "receipt_id": ..., "total": ..., "change": ..., "lot_allocations": [...] }`.
- Nếu `payment_method=vietqr` và trạng thái `pending` (chờ thanh toán) → app bấm "xác nhận đã nhận" bằng `POST /pos/sales/{id}/confirm-payment` (admin/manager hoặc quyền `pos.cash_drawer`).

#### GET `/pos/payment-methods` — danh sách method enabled.
#### POST `/pos/vietqr/new` — body `{ "amount": 500000, "note": "HD-..." }` → trả QR content/image (từ config ngân hàng trong settings).
#### GET `/receipts/{id}` — payload biên lai (để in lại). `POST /receipts/{id}/print` — ghi `printed_count` (tăng).

### 5.7 Returns

#### POST `/returns` (idempotent) — body:
```json
{ "source": "pos", "pos_tx_id": 55, "reason": "khách đổi", "restocked": true,
  "items": [ { "product_id":12, "variation_id":88, "qty":1, "return_to_lot_id": null } ] }
```
- Transaction: nếu restocked → thay đổi stock (+qty) qua StockManager (D-22), tx RETURN, ledger (về lô gốc nếu khớp `lot_id`, nếu không → unassigned `lot_id NULL`), ghi return record + receipt loại return; nếu nguồn web order → tạo refund WC (restore stock chuẩn của WC) — tránh 2 đường trừ ngược nhau (chỉ cho plugin create refund; không double). Idempotency chống double hoàn.

### 5.8 Orders

#### GET `/orders` — `search` (order number/customer), `status`, `date_from/date_to`, `payment_method`, `customer_id`. Trả: id (HPOS), number, status, created_at, customer, total, payment_method, items count, payment_status.
#### GET `/orders/{id}` — chi tiết items (kể cả variation attributes, `_kc` line cost nếu có), shipping, notes, refunds.
#### PUT `/orders/{id}/status` — `{ "status": "processing" }` (permission `orders.update`, whitelist status). Ghi activity log.
#### POST `/orders/{id}/refund` — `{ "amount": .., "reason": .., "restock": true }` (permission `orders.refund`). Server gọi WC refund API + restore stock + ghi tx RETURN + ledger.

### 5.9 Customers / Coupons

#### GET/POST/PUT `/customers`... — thao tác WC customers (kiểm tra email/phone trùng khi tạo).
#### GET `/customers/{id}/orders` — lịch sử + `totals: { orders: n, spent: x }`.
#### GET `/coupons?search=` ; POST/PUT `/coupons` (WC coupon CRUD); GET `/coupons/validate?code=X&product_ids=...` → trả mức giảm áp dụng được (dùng cho POS nếu bật).

### 5.10 Reports

#### GET `/reports/summary?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD`
```json
{ "date_from":"...", "date_to":"...",
  "revenue": 1200000, "cost": 700000, "gross_profit": 500000,
  "orders": 8, "units_sold": 25,
  "avg_order_value": 150000, "payment_methods": { "cash": 800000, "bank_transfer": 400000 } }
```
#### GET `/reports/sales?group_by=day|month|year&date_from=&date_to=` — chuỗi series (revenue, cost, profit, orders, units).
#### GET `/reports/profit?group_by=...` — chi tiết COGS theo lô + fallback note.
#### GET `/reports/products?from=&to=&sort=sales|best|slow` — bán chạy/chậm, qty, revenue, cost, profit.
#### GET `/reports/inventory` — snapshot: tồn theo loại, giá trị tồn kho (theo cost), sắp hết, hết hạn.

> **Nguyên tắc**: mọi report có `revenue`, `cost`, `gross_profit` để không nhầm doanh thu = lợi nhuận. Profit only dựa trên cost lô/FEFO hoặc `_kc_cost` fallback (ghi `cost_method` trong response).

### 5.11 Staff / Settings / Notifications / Sync

- `/staff` (CRUD; `staff.write`) — tạo nhân viên + gán role + permissions override.
- `/staff/{id}/permissions` — ghi lại grid.
- `/settings` (GET: `settings.read`, PUT: `settings.write`) — settings client cần (store info, expiry window, offline policy, low-stock default, max discount, ...). Không trả secret ngân hàng/host.
- `/notifications` (GET, `read`), `/notifications/unread-count`, `/{id}/read`.
- `/activity-log` (GET, `activity.read`) — lọc staff_id, action, date.
- `POST /sync/queue` — app gửi batch outbox (endpoint + payload + uuid + idempotency), server process từng cái, trả kết quả per-item `[ { uuid, status, response|error } ]`. (chi tiết 13_OFFLINE)
- `GET /sync/status` — server so sánh con trỏ `updated_after` cho cache delta.

### 5.12 Media upload

#### POST `/uploads` (multipart, `products.write`)
- Phần upload ảnh → WC media library (`wp_insert_attachment`), trả `{ "media_id": 9, "src": "https://...", "thumb": "..." }`. App dùng `media_id` gắn vào product (`images[]`).

## 6. Validation & error codes quan trọng

| Tình huống | code | status |
|---|---|---|
| Stock không đủ | `KC_INSUFFICIENT_STOCK` (kèm `details.item`) | 409 |
| SKU/barcode trùng | `KC_DUPLICATE` | 409 |
| Barcode không tồn tại khi scan | `KC_NOT_FOUND` + `unlisted:true` | 404 |
| Session POS đóng | `KC_POS_SESSION_CLOSED` | 409 |
| Đã khoá kiểm kho | `KC_COUNT_CLOSED` | 409 |
| Idempotency key xung đột nội dung | `KC_IDEMPOTENCY_FINGERPRINT_MISMATCH` | 409 |
| Barcode/sku invalid format | `KC_VALIDATION_ERROR` (`details.format`) | 422 |
| Người dùng bị khoá | `KC_ACCOUNT_DISABLED` | 423 |
| Quá hạn mức giảm giá | `KC_DISCOUNT_EXCEEDED` | 422 |
| Refund vượt số còn lại | `KC_REFUND_EXCEEDS_REMAINING` | 409 |

## 7. Chưa quyết định

- Có cần endpoint webhook (plugin → app) hay app chỉ polling/notification? (đề xuất: polling 30–60s giai đoạn đầu; hỗ trợ FCM sau).
- Có mở endpoint sang plugin bên thứ 3 (VietQR config ĐỊA CHỈ) không.
- Versioning: `kc/v1` cố định; breaking change dùng `kc/v2` song song.

## 8. Phụ thuộc

- WP REST API infrastructure; WooCommerce for products/orders/coupons/customers; plugin internals (permission, idempotency, transaction, stock, lot, reports).

## 9. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Contract lớn → lệch triển khai | Đặc tả này + schema JSON mẫu + Postman collection (Phase 4) + contract test |
| Plugin khác cùng namespace | kiểm tra trước; namespace `kc/v1` hiếm đụng |
| Response nặng (include variations) | strip theo param; pagination; fields filter `fields=` nếu cần |
| Timeout trên hosting yếu | endpoint nặng (reports) chạy async khi data lớn (trả 202 + /reports/jobs) — Phase sau |

## 10. Tài liệu liên quan

[05 → 03_SYSTEM_ARCHITECTURE](03_SYSTEM_ARCHITECTURE.md) · [04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [10_POS_FLOW](10_POS_FLOW.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [13_OFFLINE_SYNC](13_OFFLINE_SYNC.md)