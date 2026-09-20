# 03 · Kiến Trúc Hệ Thống

## 1. Mục đích

Mô tả kiến trúc tổng thể toàn hệ thống (App + Plugin + WooCommerce), các lớp, luồng dữ liệu, cơ chế đảm bảo nhất quán — làm nền cho các tài liệu con.

## 2. Phạm vi

Kiến trúc logic và triển khai; không đi vào chi tiết từng endpoint (05) hay từng bảng (04).

## 3. Ngữ cảnh & ràng buộc

- WordPress 7.1.1 / PHP 8.1 / WooCommerce 10.4.4 trên hosting thật của `https://myphamkimcuong.id.vn`.
- Website đang sản xuất; mọi thay đổi qua quy trình an toàn (17_DEPLOYMENT).
- App Android target API đời mới, chạy trên điện thoại cửa hàng.
- WP/WC version hiện tại mới hơn tài liệu chuẩn mà nhóm dev biết → **mọi tài liệu này giả định dùng API công khai ổn định**; phải "smoke test" các API nền tảng ngay PHASE 1 trước khi quyết định kiến trúc implementation chi tiết.

## 4. Các lớp (layers)

```
┌────────────────────────────────────────────────────────────┐
│  LỚP CLIENT — Flutter App                                  │
│  features/ (POS, Inventory, Products...)                   │
│  data/ (repository) · domain/ (model, usecase) · di/       │
│  api/ (Dio + interceptor) · local/ (Hive/Drift + outbox)   │
└──────────────────────────┬─────────────────────────────────┘
                           │ HTTPS (JSON REST, Authorization: Bearer)
                           ▼
┌────────────────────────────────────────────────────────────┐
│  LỚP PLUGIN — MyPham Kim Cuong Manager (PHP)              │
│  REST Endpoints (kc/v1) → Service Layer → Repositories     │
│  ├── Auth/Permission Middleware                            │
│  ├── Idempotency Middleware                                │
│  ├── RateLimit Middleware                                  │
│  ├── Transaction Manager (begin/commit/rollback)           │
│  ├── Stock Manager (single writer, D-22)                    │
│  ├── ActivityLog, Notifications                            │
│  └── WC Adapter (wc_get_product, WC_Order, Media...)       │
└──────────────────────────┬─────────────────────────────────┘
                           │ (các hook/filter chuẩn của WooCommerce)
                           ▼
┌────────────────────────────────────────────────────────────┐
│  LỚP NỀN TẢNG — WordPress / WooCommerce                    │
│  products, variations, orders (HPOS), customers, media,    │
│  coupons, taxes, stock tables                              │
└──────────────────────────┬─────────────────────────────────┘
                           ▼
                 MySQL/MariaDB của website
```

### Ghi chú quan trọng về WooCommerce hiện đại

- WC ≥ 9.x dùng **HPOS** (High-Performance Order Storage): đơn hàng nằm ở bảng `wp_wc_orders`, `wp_wc_order_addresses`, `wp_wc_order_operational_data`, `wp_wc_order_items`... Plugin **PHẢI truy cập order qua `wc_get_order()` / WC CRUD**, không viết SQL trực tiếp vào bảng order.
- `wp_wc_product_meta_lookup` là bảng lookups nhanh của sản phẩm (có `stock_quantity`, `rating`, `onsale`...). WooCommerce có cơ chế đồng bộ `_stock` postmeta với lookup này. **Ưu tiên mọi thay đổi stock qua WC official API / CRUD / functions** (`wc_update_product_stock`, `WC_Product::set_stock`, `wc_reduce_stock_levels`…) để WC tự lo đồng bộ meta/lookup/cache/hook. Plugin chỉ cân nhắc guarded SQL khi thật sự cần chống race và đã chứng minh bằng test trên staging (xem 09_INVENTORY).

## 5. Luồng dữ liệu chính

### 5.1 Luồng đọc (App hiển thị)
```
App → GET /kc/v1/products?... → Plugin (permission check) → WC Adapter (wc_get_products) → JSON (cam kết contract 05) → App cache
```
- Dữ liệu tĩnh (danh mục, setting) cache TTL theo kết quả; sản phẩm cache offline theo policy (13_OFFLINE).
- Plugin thêm các field nghiệp vụ (lot summary, cost, barcode, stock theo từng variation) vào response.

### 5.2 Luồng ghi chuẩn (mutation)
```
App → POST (kèm Idempotency-Key) → Plugin:
  1) Auth + permission
  2) Idempotency check (đã có response chưa? → trả lại)
  3) Validate + sanitize
  4) BEGIN transaction (DB bước)
  5) Thao tác nghiệp vụ (stock theo D-22, insert custom tables, WC CRUD)
  6) Activity log
  7) COMMIT  (nếu lỗi → ROLLBACK, trả lỗi chuẩn)
  8) Return response; lưu idempotency response
```
> Ghi chú: với nghiệp vụ bao quanh WC CRUD/hooks/plugin (vd POS sale), rollback MySQL không đảm bảo sạch 100% side-effect ngoài DB → dùng **logical unit + trạng thái trung gian + compensation/recovery** (D-23, xem 10_POS_FLOW). Các nghiệp vụ thuần custom-table (receiving, adjust, counts) vẫn dùng transaction DB như trên.

### 5.3 Luồng stock (quan trọng)
```
Mọi nơi làm thay đổi stock: POS, web đơn, nhập, điều chỉnh, kiểm kho, trả hàng
  → Chỉ duy nhất qua Stock Manager (MỘT kênh ghi stock)
  → Ưu tiên WC official functions; nếu cần atomic chống race → guarded SQL
    (chỉ sau khi verified trên staging; kèm đồng bộ lookup/meta + clear cache/transient + fire hook)
  → insert kc_inventory_transactions (type, ref, running_stock)
  → nếu liên quan lot → kc_lot_ledger (FEFO nếu bán)
```
Chi tiết & chiến lược lựa chọn: `09_INVENTORY_AND_STOCK_FLOW.md`.

### 5.4 Đồng bộ web sale → lô (web bán)
```
WC order status thay đổi / reduce_stock → hook woocommerce_reduce_stock_levels
  → Plugin đọc delta → ghi WEB_SALE inventory tx + allocate lô FEFO best-effort
```
Điều này đảm bảo **app luôn "nhìn thấy" web sale** trong lịch sử kho và báo cáo, dù web không gọi plugin trực tiếp.

## 6. Chiến lược nhất quán & đồng thời (summary)

| Tình huống | Cơ chế |
|---|---|
| 2 POS bán cùng SP cuối cùng | guard stock (`stock >= qty`; official set_stock hoặc guarded SQL khi cần) → 1 thắng, 1 nhận `INSUFFICIENT_STOCK` (409) |
| Web bán lúc POS bán | web dùng cơ chế giảm stock của WC; plugin hook ghi tx; POS vẫn guard → số liệu nhất quán vì cùng 1 cột |
| Double-tap / mạng retry | `Idempotency-Key` + server cache response |
| Mất mạng giữa chừng | client giữ key, retry idempotent; POS dùng "check-giỏ/nonce" nếu cần |
| Thất bại giữa transaction | DB rollback cho bước DB; side-effect WC/hook/plugin → compensation/recovery + `needs_review` (D-23) |
| Offline POS | buffer theo device + outbox sort + server-side re-validate (13_OFFLINE) |
| Web refund | WC restore stock → hook ghi `RETURN`/reversal tx + lot |
| Đồng hồ/server lệch | lấy thời gian server khi commit; client không tự sinh timestamp nghiệp vụ trừ field `client_sent_at` chỉ để tham khảo |

## 7. Backend module map (plugin)

Xem chi tiết `06_WORDPRESS_PUGIN_ARCHITECTURE.md`. Module chính:

| Module | Trách nhiệm |
|---|---|
| `Bootstrap` | autoload, activation, migration runner, requires |
| `Migration` | version schema, upgrade/downgrade-safe |
| `Auth` | login, token, refresh, logout, device registry |
| `Permissions` | role/permission grid, enforce |
| `Idempotency` | key cache, replay guard |
| `RateLimit` | sliding window per token/IP |
| `Products` | product/variation CRUD mở rộng (barcode, cost), categories |
| `Barcodes` | unique lookup, upsert, sync WC meta |
| `Lots` | CRUD lô, ledger, FEFO allocation |
| `Inventory` | receive/adjust/count/transactions, expiry alerts |
| `POS` | session, sale (atomic), payment methods, receipt, vietqr |
| `Orders` | list/detail/status/refund (WC API) |
| `Customers` | list/detail/orders |
| `Coupons` | CRUD + validate |
| `Reports` | aggregate queries (kc tx + WC stats), profit calc |
| `Notifications` | CRUD, generation from events |
| `ActivityLog` | write logs |
| `Sync` | outbox processing, conflict resolution |
| `Media` | upload images to WC media |
| `Settings` | store settings (encrypted fields OK dùng WP `Options` + `kc_` prefix) |
| `WC Hooks` | reduce/restore stock, order transitions → ghi tx + notify + catégorie |

## 8. Frontend module map (Flutter)

Xem chi tiết `07_FLUTTER_ARCHITECTURE.md`. Module chính: auth, dashboard, products, pos, cart, inventory, lots/expiry, reports, orders, customers, settings, sync.

## 9. Xử lý lỗi & logging

- **Envelope lỗi chuẩn** của API: `{ "code": "KC_xxx", "message": "...", "details": {...}, "error_id": "..." }` (RFC 7807 vẫn kế thừa với `type/title/status` optional).
- Log: chỉ log code lỗi + context; **không log token/password**; log ra `error_log` và bảng `kc_activity_log` theo nghiệp vụ.
- Monitoring: WP `WP_DEBUG_LOG` có sẵn; thêm admin page "System health" (đếm queue, lỗi sync, lần cuối thành công).

## 10. Triển khai (deployment topology)

- Plugin: upload qua WP admin (zip) hoặc FTP; không đòi phải cài composer trên hosting — **plugin tự-bundled** (không dependency ngoài WC/WP).
- App: `flutter build apk` (release, R8) → distribute qua link APK private (không cần Play Store ban đầu; có thể thêm sau).
- HTTPS: site đã có SSL (do WP+hosting); app nhất định chỉ gọi `https://`.
- Staging: tạo bản staging trước khi triển khai plugin xuống production (17_DEPLOYMENT).

## 11. Quyết định kiến trúc quan trọng

| Mã | Quyết định | Lý do |
|---|---|---|
| ARCH-01 | Plugin là thin-but-complete service layer trên WC | một nơi chốt permission, transaction, idempotency |
| ARCH-02 | Custom tables `wp_kc_*` (prefix qua `$wpdb->prefix`) | rõ ràng, versionable, uninstall-safe |
| ARCH-03 | Không dùng WC REST Consumer Keys cho app (dùng JWT plugin) | consumer keys cấp quyền WC rộng, khó thu hồi granular; JWT plugin scope-permission |
| ARCH-04 | Stock mutation: **WC official API first**; guarded SQL chỉ khi thật cần chống race và qua test staging (kèm sync lookup/meta + clear cache + fire hook + test HPOS/plugin đang có) | an toàn, tương thích HPOS 10.4.4 + plugin hiện có |
| ARCH-05 | Timestamp: lưu theo `UTC` chuẩn, hiển thị theo tz shop | tránh lệch giờ report |
| ARCH-06 | POS ghi qua WC order (HPOS CRUD) + bảng POS riêng | kế thừa ecosystem WC (báo cáo, mail, plugin), có siêu dữ liệu POS riêng |
| ARCH-07 | Client-side cache chỉ là phụ; server luôn là nguồn tin | không tạo hệ tồn kho song song |

## 12. Chưa quyết định

- Có dùng message queue ngoài WP (Redis) cho web sale → lô allocation không? *(mặc định KHÔNG — dùng hook synchronous đơn giản, gọn, an toàn; mở rộng sau nếu cần)*.
- CRON cho notifications tổng hợp hàng ngày? (đề xuất: cron daily gửi reminders).

## 13. Phụ thuộc

- WC `wc_get_product`, `wc_update_product_stock`, hook stock, media, coupons, customers, HPOS orders.
- WP REST API framework, Options API, Cron API, wpdb.
- Flutter plugins: (07_FLUTTER).

## 14. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| WC version thay đổi API (HPOS, EAN, coupon...)| smoke test Phase 1; thin adapter quanh WC |
| Hosting hạn chế (timeout, cron, memory) | query phân trang, transaction ngắn, không lạm dụng cron |
| Plugin khác (VietQR, Variation Swatches) trigger stock hooks khác | test concurrency
với toàn bộ plugin có sẵn trên staging |
| DB size lớn theo thời gian (inventory tx, logs) | thiết kế index + archive policy Phase 17+ |

## 15. Tài liệu liên quan

[01_PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md) · [04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [06_WORDPRESS_PLUGIN_ARCHITECTURE](06_WORDPRESS_PLUGIN_ARCHITECTURE.md) · [07_FLUTTER_ARCHITECTURE](07_FLUTTER_ARCHITECTURE.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [DECISIONS](DECISIONS.md)