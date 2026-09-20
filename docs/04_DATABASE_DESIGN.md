# 04 · Database Design

## 1. Mục đích

Định nghĩa chi tiết cơ sở dữ liệu: bảng WooCommerce nào được dùng, bảng custom `wp_kc_*` nào cần tạo, cột, khóa, index, quan hệ — đảm bảo **không trùng dữ liệu** với WooCommerce và nhất quán khi vận hành thật.

## 2. Phạm vi

- Các bảng WC/WP **được phép đọc/ghi** (chỉ ghi theo luồng nghiệp vụ).
- Toàn bộ bảng custom của plugin (version bắt đầu schema v1).
- Không bao gồm bảng của plugin khác (VietQR, Variation Swatches...) — **không đụng đến**.

## 3. Nguyên tắc

1. Sản phẩm/giá/SKU/tồn tổng/đơn/khách → **WC tables** (source of truth).
2. Nghiệp vụ mở rộng → custom tables `{prefix}kc_*`. Prefix khi `dbDelta`: `$wpdb->prefix . 'kc_'` (thường `wp_kc_`).
3. **Không tạo FK cứng** tới bảng WC (WC có thể thay đổi schema qua phiên bản); chỉ **FK logic** + index. Bảng-of-custom có thể tự FK lẫn nhau nhưng khuyến nghị index + xử lý trong code (portable, uninstall dễ).
4. Mọi table có `created_at`, `updated_at` (UTC) trừ khi có lý do; `created_by` (user_id) khi cần audit.
5. Tiền: `DECIMAL(14,2)` (VND). Số lượng: `INT` (signed). Stock cho phép âm chỉ khi bật setting.
6. ID: `BIGINT UNSIGNED AUTO_INCREMENT`; ref về WC: `product_id`, `variation_id` (0 = product / cha), `order_id`.
7. Bảng custom được khai qua **dbDelta** + `schema_version` lưu option `kc_db_version`; migration runner chạy khi version tăng (06_PLUGIN, 17_DEPLOYMENT).

## 4. Bảng WooCommerce / WordPress sử dụng

### 4.1 Đọc/ghi chuẩn (qua WC CRUD, không SQL tay)

| Bảng / API | Mục đích |
|---|---|
| `wc_get_product(+id)` | product, variation: giá, SKU, stock, status, categories |
| `wc_get_order(+id)` & HPOS tables | đơn hàng, items, totals, trạng thái, refund |
| `WC_Customer` / `wc_get_customer` | khách hàng |
| `wp_terms` + `wp_term_taxonomy` + `wp_term_relationships` | danh mục, attribute, brand (taxonomy do plugin register) |
| `wp_posts` (product_type, sub types, media) | sản phẩm, variation, **attachment ảnh** |
| `wp_postmeta` | `_price`, `_regular_price`, `_sale_price`, `_sku`, `_stock`, `_manage_stock`, `_low_stock_amount`, `_thumbnail_id`, gallery meta `_product_image_gallery`, attribute meta, **custom của plugin**: `_kc_cost` (giá vốn mặc định), `_kc_barcode` (fallback barcode), trạng thái stock |
| `wp_options` | settings plugin (`kc_` prefix), `kc_db_version`, caches transients |

### 4.2 Bảng meta/lookup WC quan trọng (đọc, đôi khi ghi có kiểm soát)

| Bảng | Cột | Plugin dùng |
|---|---|---|
| `wp_wc_product_meta_lookup` | `stock_quantity`, `onsale`, `min_price`, `max_price` | đọc nhanh tồn giá; **ghi stock qua Stock Manager theo D-22** (official WC functions ưu tiên; guarded SQL chỉ khi qua test staging) |
| `wp_wc_product_variation_lookup` | `product_id`, `variation_id`, `stock_quantity` | đọc/ghi stock variation |
| `wp_wc_order_stats`, `wp_wc_order_product_lookup` | `date_created`, `net_total`, qty | báo cáo (chỉ đọc; nếu thiếu → aggregate từ order items) |
| `wp_woocommerce_order_items` / `wp_woocommerce_order_itemmeta` | line items | chi tiết đơn (đọc; chỉ dùng khi HPOS cần) |

> **Chiến lược ghi stock (D-22)**: **Ưu tiên WC official API / CRUD / functions** (`wc_update_product_stock`, `WC_Product::set_stock`, `wc_reduce_stock_levels`) — WC tự đồng bộ lookup/meta/cache/hook. Nếu vì race condition thật sự cần **guarded SQL trực tiếp**, bắt buộc: đồng bộ `wp_wc_product_meta_lookup.stock_quantity` + `_stock` postmeta trong cùng transaction; clear cache/transient liên quan; fire `woocommerce_product_set_stock` nếu plugin khác phụ thuộc; đã PASS concurrency test trên staging + kiểm tra HPOS / WC 10.4.4 + plugin đang có trên site (xem 09_INVENTORY, DECISIONS D-22). Thêm reconciliation job để đối soát định kỳ.

## 5. Custom tables `{prefix}kc_*` (schema v1)

> Ký hiệu: **PK** Khóa chính · **UQ** Unique · **IX** Index · `NULL`/`DEFAULT`. `user_id` = ID WP user. Mọi `id` BIGINT UNSIGNED AUTO_INCREMENT. Timestamp `DATETIME` UTC.

### 5.0 Config & version
- `wp_options` → `kc_db_version` (int), `kc_installed_at`, `kc_settings` (serialized array).

### 5.1 `kc_staff` — nhân viên mở rộng (mapping WS user)

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| user_id | BIGINT UQ | WP user id; NULL nếu thử nghiệm standalone |
| full_name | VARCHAR(191) | |
| phone | VARCHAR(20) NULL | |
| email | VARCHAR(191) NULL | |
| pos_pin | VARCHAR(255) NULL | bcrypt/`password_hash` (POS PIN) |
| role | ENUM('kc_admin','kc_manager','kc_staff') | role nghiệp vụ |
| status | ENUM('active','inactive') DEFAULT 'active' | |
| notes | TEXT NULL | |
| created_at / updated_at | DATETIME | |
| created_by | BIGINT NULL | |

### 5.2 `kc_auth_tokens` — token đăng nhập (session)

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| staff_id | BIGINT IX | → kc_staff.id |
| token_hash | VARCHAR(64) UQ | SHA-256 của JWT access (không lưu raw) |
| refresh_token_hash | VARCHAR(64) UQ NULL | |
| device_id | VARCHAR(64) IX | uuid thiết bị app |
| app_version | VARCHAR(20) NULL | |
| expires_at | DATETIME | |
| refresh_expires_at | DATETIME | |
| revoked_at | DATETIME NULL | |
| last_seen | DATETIME NULL | |
| ip / user_agent | VARCHAR/191 | (không log token) |

### 5.3 `kc_staff_permissions` — override permission

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| staff_id | BIGINT IX | |
| permission_key | VARCHAR(64) | danh sách ở 15_PERMISSION |
| allowed | TINYINT(1) DEFAULT 1 | |
| UQ(staff_id, permission_key) | | |

### 5.4 `kc_idempotency_keys` — chống trùng request

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| idempotency_key | VARCHAR(64) UQ | client gửi hoặc server sinh |
| fingerprint | VARCHAR(64) | hash của (staff_id, endpoint, method, payload hash) — phát hiện cùng key khác nội dung |
| endpoint | VARCHAR(191) | |
| response_code | INT | |
| response_body | MEDIUMTEXT | cache response replay |
| created_at / expires_at | DATETIME | TTL 24h mặc định |

### 5.5 `kc_devices` — registry thiết bị POS

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| device_id | VARCHAR(64) UQ | uuid do app tạo |
| name | VARCHAR(191) | "POS Quầy 1" |
| staff_id_default | BIGINT NULL | |
| offline_pos_enabled | TINYINT(1) DEFAULT 0 | cho phép offline POS |
| offline_enabled | TINYINT(1) DEFAULT 0 | cho phép offline POS cho thiết bị (chưa quyết định bật mặc định) — chi tiết buffer per mặt hàng ở `kc_device_stock_buffers` (§5.23) |
| printer_type | VARCHAR(20) NULL | 'thermal_58','thermal_80' |
| last_seen | DATETIME | |
| status | ENUM('active','disabled') DEFAULT 'active' | |

### 5.6 `kc_suppliers` — nhà cung cấp

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| name | VARCHAR(191) | |
| phone / email / address / tax_code | ... NULL | |
| note | TEXT NULL | |
| status | ENUM('active','inactive') DEFAULT 'active' | xóa mềm |
| created_by / created_at / updated_at | | |

### 5.7 `kc_lots` — lô hàng

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| lot_code | VARCHAR(64) IX | mã lô user nhập hoặc auto |
| product_id | BIGINT IX | WC product (cha) |
| variation_id | BIGINT IX DEFAULT 0 | WC variation hoặc 0 |
| supplier_id | BIGINT IX NULL | → kc_suppliers |
| nsx | DATE NULL | ngày sản xuất (nullable) |
| hsd | DATE NULL | hạn dùng (nullable) |
| received_qty | INT | số lượng nhập |
| remaining_qty | INT | số lượng còn |
| cost_unit | DECIMAL(14,2) | giá nhập/đơn vị |
| received_at | DATETIME | ngày nhập |
| note | TEXT NULL | |
| status | ENUM('open','closed','expired','archived') DEFAULT 'open' | |
| created_by / created_at / updated_at | | |
| UQ(product_id, variation_id, supplier_id, lot_code, nsx, hsd) | | soft unique để tránh trùng lô chính hãng |

> **Ràng buộc nhất quán**: `SUM(open lots.remaining_qty) per (product_id, variation_id)` **bằng** WC `stock_quantity` (hiệu chỉnh trong mọi giao dịch liên quan; phần tồn chưa gắn lô được biểu diễn bằng `lot_id = NULL` — **"unassigned"**, KHÔNG dùng giá trị `-1` vì cột `id` là BIGINT UNSIGNED).

### 5.8 `kc_lot_ledger` — nhật ký lô (in/out từng lô)

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| lot_id | BIGINT IX NULL | NULL = lô unassigned |
| product_id / variation_id | BIGINT IX | |
| qty | INT | + in, − out |
| balance_after | INT | |
| tx_type | ENUM('RECEIVING','SALE','RETURN','ADJUST','COUNT','EXPIRE','REVERSAL','INITIAL') | |
| ref_type / ref_id | VARCHAR(32)/BIGINT | reference (pos tx / order / count...) |
| unit_cost | DECIMAL(14,2) NULL | snapshot giá vốn khi out |
| created_at / created_by | | |

### 5.9 `kc_inventory_transactions` — lịch sử tồn kho (bắt buộc cho MỌI biến động)

| Cột | Type | Ghi chú |
|---|---|---|
| id | BIGINT PK | |
| product_id / variation_id | BIGINT IX | |
| qty | INT | signed: + nhập, − bán/điều chỉnh giảm |
| type | ENUM('RECEIVING','POS_SALE','WEB_SALE','RETURN','ADJUST','STOCK_COUNT','REVERSAL','EXPIRE','INITIAL') IX | |
| ref_type / ref_id | | vd POS sale id / order id / count id |
| lot_id | BIGINT NULL | |
| unit_cost | DECIMAL(14,2) NULL | |
| cost_total | DECIMAL(14,2) NULL | qty × cost (âm nếu out) |
| running_stock | INT | stock sau giao dịch (snapshot) |
| note | VARCHAR(191) NULL | |
| created_at / created_by | | |
| IX(product_id, created_at), IX(type, created_at), IX(ref_type, ref_id) | | |

### 5.10 `kc_receivings` + `kc_receiving_items` — phiếu nhập kho

`kc_receivings`:
| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / receiving_code VARCHAR(32) UQ | | MHN-YYYYMMDD-XXXX |
| supplier_id IX NULL / warehouse_id BIGINT NULL / branch_id BIGINT NULL | | mở rộng |
| total_qty INT / total_cost DECIMAL(14,2) | | |
| note TEXT NULL / status ENUM('draft','confirmed','cancelled') DEFAULT 'confirmed' | | |
| created_by / created_at / updated_at / confirmed_at | | |

`kc_receiving_items`:
| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / receiving_id IX | | |
| product_id / variation_id IX | | |
| qty INT / unit_cost DECIMAL(14,2) / total DECIMAL(14,2) | | |
| lot_code VARCHAR(64) NULL / nsx DATE NULL / hsd DATE NULL | | |
| lot_id BIGINT NULL | | lô sau khi tạo |
| IX(receiving_id) | | |

### 5.11 `kc_adjustments` — điều chỉnh kho

| Cột | Type | Ghi chú |
|---|---|---|
| id / product_id / variation_id IX / lot_id NULL | | |
| qty INT | signed | |
| reason_code ENUM('damage','expired','miscount','other') | | |
| reason TEXT NULL | | |
| created_by / created_at | | |
| IX(product_id, created_at) | | |

### 5.12 `kc_stock_counts` + `kc_stock_count_items` — phiếu kiểm kho

`kc_stock_counts`: id, count_code VARCHAR(32) UQ, status ENUM('draft','ongoing','completed','cancelled'), warehouse_id NULL, note, created_by, created_at, completed_at, completed_by.

`kc_stock_count_items`: id, count_id IX, product_id / variation_id IX, system_qty INT, actual_qty INT, diff INT, reason VARCHAR(191) NULL, status ENUM('pending','approved','rejected') DEFAULT 'pending'. UQ(count_id, product_id, variation_id).

### 5.13 `kc_pos_sessions` — ca làm việc POS

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| session_code VARCHAR(32) UQ | | CA-YYMMDD-XXXX |
| staff_id IX | | người mở ca (cashier) |
| device_id VARCHAR(64) NULL | | |
| opened_at / closed_at DATETIME NULL | | |
| opening_cash DECIMAL(14,2) | | quỹ tiền mặt đầu ca |
| closing_cash DECIMAL(14,2) NULL | | đếm cuối ca |
| expected_cash DECIMAL(14,2) NULL | | tính từ giao dịch |
| cash_diff DECIMAL(14,2) NULL | | chênh lệch |
| status ENUM('open','closed') | | |
| note TEXT NULL | | |

### 5.14 `kc_pos_transactions` + items — giao dịch POS

`kc_pos_transactions`:
| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| pos_tx_code VARCHAR(32) UQ | | HD-YYMMDD-XXXX |
| session_id IX | → kc_pos_sessions | |
| order_id IX NULL | | WC order (HPOS id) — nếu tạo |
| customer_id IX NULL | | WC customer id; null = khách lẻ |
| status ENUM('pending','processing','completed','needs_review','void','refunded') DEFAULT 'pending' | | trạng thái trung gian cho luồng logical-unit + compensation (xem 10_POS_FLOW §5) |
| subtotal DECIMAL(14,2) / discount_total DECIMAL(14,2) / total DECIMAL(14,2) | | |
| discount_reason VARCHAR(191) NULL | | |
| payment_method VARCHAR(32) | cash/bank/vietqr/... | |
| payment_status ENUM('paid','pending','failed') DEFAULT 'paid' | | |
| cash_received DECIMAL(14,2) NULL / change_amount DECIMAL(14,2) NULL | | |
| idempotency_key VARCHAR(64) UQ NULL | | chống double |
| generated_by VARCHAR(32) | pos / offline-queue / web-import | |
| note TEXT NULL / created_by / created_at | | |

`kc_pos_transaction_items`:
| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / pos_tx_id IX | | |
| product_id / variation_id IX | | |
| qty INT / unit_price DECIMAL(14,2) / line_discount DECIMAL(14,2) / line_total DECIMAL(14,2) | | |
| lot_allocation JSON NULL | | [ {lot_id, qty, cost} ] FEFO |
| cost_total DECIMAL(14,2) NULL | | COGS của dòng |
| IX(pos_tx_id) | | |

### 5.15 `kc_receipts` — biên lai (in lại bất kỳ lúc nào)

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| receipt_code VARCHAR(32) UQ | | trùng/liên quan pos_tx_code |
| pos_tx_id IX NULL / order_id IX NULL / return_id IX NULL / type ENUM('pos','return','order') | | |
| payload JSON | | dữ liệu gốc biên lai (tên shop, lines, totals, thanh toán) — snapshot |
| printed_count INT DEFAULT 0 / last_printed_at DATETIME NULL | | |
| print_device VARCHAR(64) NULL | | |
| created_at / created_by | | |

### 5.16 `kc_returns` + `kc_return_items` — trả hàng

`kc_returns`: id, return_code VARCHAR(32) UQ, source ENUM('pos','order'), pos_tx_id NULL, order_id NULL, customer_id NULL, total_refund DECIMAL(14,2), refund_method VARCHAR(32) NULL, status ENUM('draft','completed','cancelled'), note, restocked TINYINT(1) DEFAULT 1, created_by, created_at, completed_at.

`kc_return_items`: id, return_id IX, product_id / variation_id IX, qty INT, unit_price DECIMAL(14,2), refund_amount DECIMAL(14,2), location_returned_to IX NULL (lot_id; NULL = unassigned), status ENUM('pending','processed').

### 5.17 `kc_activity_log` — nhật ký hoạt động

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / staff_id IX | | |
| action VARCHAR(64) | vd 'product.price_updated' | |
| object_type VARCHAR(32) / object_id BIGINT NULL | | |
| before / after JSON NULL | | diff dữ liệu quan trọng |
| ip VARCHAR(64) NULL / device_id VARCHAR(64) NULL | | |
| created_at | | |
| IX(created_at), IX(staff_id, created_at), IX(object_type, object_id) | | |

### 5.18 `kc_notifications` — thông báo

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / type VARCHAR(32) IX | | stock_low, expiry_soon, expired, new_order, sync_error... |
| severity ENUM('info','warning','critical') | | |
| title VARCHAR(191) / body TEXT | | |
| data JSON NULL | | object refs |
| data JSON NULL | | object refs — trạng thái đọc theo dõi ở bảng riêng `kc_notification_reads` (D-26) |
| created_at / expires_at NULL | | |

### 5.19 `kc_sync_outbox` — hàng đợi offline (client ops)

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / uuid VARCHAR(64) UQ | | |
| device_id VARCHAR(64) IX | | |
| staff_id IX | | |
| endpoint VARCHAR(191) / method VARCHAR(10) | | |
| payload MEDIUMTEXT | | |
| status ENUM('pending','processing','synced','failed') | | |
| attempts INT DEFAULT 0 / last_error VARCHAR(500) NULL / synced_at DATETIME NULL | | |
| processed_key VARCHAR(64) NULL | | idempotency key ở server |
| created_at | | |
| IX(status, created_at) | | |

### 5.20 `kc_sync_conflicts` — ghi nhận conflict offline

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK / outbox_id IX NULL | | |
| uuid VARCHAR(64) | | |
| device_id / conflict_type ENUM('stock','duplicate','auth','other') | | |
| message TEXT / payload JSON NULL / resolution ENUM('pending','resolved','discarded') | | |
| resolved_by BIGINT NULL / resolved_at DATETIME NULL | | |
| created_at | | |

### 5.21 `kc_barcodes` — lookup barcode (materialize, unique)

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| barcode VARCHAR(64) UQ | | chuẩn hóa uppercase |
| product_id BIGINT IX NULL | | đúng 1 trong 2 |
| variation_id BIGINT IX NULL | | |
| source ENUM('product','variation','unlisted') DEFAULT 'product' | | 'unlisted' → SP chưa tạo (pending create) |
| created_at / updated_at | | |

> Barcode canonical lưu cả vào WC meta (`_ean` nếu WC hỗ trợ native, ngược lại `_kc_barcode`); `kc_barcodes` là lookup index để scan O(1). Cập nhật đồng bộ trong transaction.

### 5.22 `kc_payment_methods` — danh sách payment method POS (mở rộng)

| Cột | Type | Ghi chú |
|---|---|---|
| id / code VARCHAR(32) UQ | cash, bank_transfer, vietqr, momo, card, other | |
| label VARCHAR(191) / icon VARCHAR(64) NULL | | |
| enabled TINYINT(1) DEFAULT 1 / sort INT | | |
| config JSON NULL | | các field cấu hình (vd bank/VietQR params) |

### 5.23 `kc_device_stock_buffers` — hạn mức offline buffer theo (product/variation × device)

Bổ sung theo D-25 — buffer **không chỉ là tổng số units của thiết bị** mà được khai theo từng mặt hàng cho từng thiết bị.

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| device_id VARCHAR(64) IX | | uuid thiết bị (gắn `kc_devices`) |
| product_id BIGINT IX | | |
| variation_id BIGINT IX DEFAULT 0 | | 0 = product đơn/cha |
| max_qty INT | | hạn mức tối đa bán offline cho mặt hàng này/thiết bị |
| used_qty INT DEFAULT 0 | | tổng số đã lấy (outbox pending) — giảm khi sync thành công |
| updated_at | | |
| UQ(device_id, product_id, variation_id) | | |

> Luật: mặc định **OFF / read-only** (đây là phần mở rộng chỉ tồn tại khi offline POS được bật cho thiết bị). `used_qty` không được vượt `max_qty`. Server **vẫn kiểm stock thật** khi đồng bộ (guard), conflict không tự xử lý im lặng (xem 13_OFFLINE_SYNC).

### 5.24 `kc_notification_reads` — theo dõi đã đọc thông báo (D-26)

| Cột | Type | Ghi chú |
|---|---|---|
| id BIGINT PK | | |
| notification_id BIGINT IX | → kc_notifications.id | |
| staff_id BIGINT IX | | người đọc |
| read_at DATETIME | | |
| UQ(notification_id, staff_id) | | chống đọc trùng lặp |

> Quyết định: dùng **bảng riêng** thay vì JSON `read_by_user` (khi số thông báo + số nhân viên tăng, JSON khó truy vấn/không scalable). JSON từng là phương án MVP — không dùng làm chuẩn.

## 6. Sơ đồ quan hệ (logic)

```
kc_staff (1─*) kc_auth_tokens
kc_staff (1─*) kc_staff_permissions
kc_suppliers (1─*) kc_lots ─────────┐
WC product/variation (1─*) kc_lots ─┼─ (*) kc_lot_ledger
                                    └─ (*) kc_inventory_transactions
kc_receivings (1─*) kc_receiving_items ─(nhiều→1) kc_lots
kc_lots ─ (1) kc_lot_ledger
kc_stock_counts (1─*) kc_stock_count_items
kc_pos_sessions (1─*) kc_pos_transactions ─ (1) WC order (HPOS)
kc_pos_transactions (1─*) kc_pos_transaction_items (+ lot_allocation JSON)
kc_pos_transactions (1─*) kc_receipts
kc_returns (1─*) kc_return_items
kc_staff/kc_devices → kc_activity_log, kc_notifications
kc_sync_outbox → kc_sync_conflicts
```

## 7. Chiến lược index & archive

- Index cho query thường: (a) inventory tx theo `(type, created_at)` cho report; `(product_id, created_at)` cho history SP. (b) lots theo `(hsd)` cho cảnh báo hết hạn + `(product_id, variation_id, status)`. (c) `kc_activity_log(created_at)`. (d) `kc_sync_outbox(status, created_at)`.
- Archive: sau khi site lớn, lịch sử tx > 24 tháng chuyển bảng `kc_inventory_transactions_archive` theo cron (Phase 17+).

## 8. Migration & version

- Option `kc_db_version`; mỗi bản schema tăng version; MRI: array `vN => SQL`; chạy `dbDelta`; log kết quả; support upgrade từ bất kỳ version cũ nào (loop).
- Không bao giờ xóa cột không an toàn tự động; xóa bảng chỉ khi uninstall có xác nhận (06_PLUGIN, 17_DEPLOYMENT).

## 9. Chưa quyết định

- Có FK cứng `kc_lots.supplier_id → kc_suppliers` không (đề xuất: index only, soft FK).
- Field mở rộng theo chi nhánh: `branch_id` bắt đầu NULL (single branch) hay tạo ngay default branch.
- Chuẩn lưu giá theo đơn vị: coin (tiền tệ nhỏ) hay DECIMAL. Đề xuất DECIMAL(14,2) hiển tại, có thể đổi sang BIGINT(int cents) trước Phase 3 nếu ngân hàng yêu cầu độ chính xác (test: tổng tiền VND lớn > 12 chữ số hiếm).

## 10. Phụ thuộc

- `$wpdb`, `dbDelta()` (WP core), WC HPOS + product lookup (phần ghi stock).

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| dbDelta không đổi cột type nullable theo ý | migration code phụ: ALTER rõ ràng cho trường hợp đặc biệt; test migration trên staging |
| Lookup stock vs postmeta lệch | transaction + fire WC action + `wc_update_product_lookup_tables`; check consistency trong test |
| Bảng thiếu index → chậm | review query plan; bảng nhỏ ban đầu, index chuẩn ngay từ đầu |
| Uninstall xóa nhầm | prefix `kc_` strict + danh sách bảng cố định; xác nhận 2 bước |

## 12. Tài liệu liên quan

[03_SYSTEM_ARCHITECTURE](03_SYSTEM_ARCHITECTURE.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [06_WORDPRESS_PLUGIN_ARCHITECTURE](06_WORDPRESS_PLUGIN_ARCHITECTURE.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [11_EXPIRY_AND_LOT_MANAGEMENT](11_EXPIRY_AND_LOT_MANAGEMENT.md)