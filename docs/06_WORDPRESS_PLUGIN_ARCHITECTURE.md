# 06 · WordPress Plugin Architecture

## 1. Mục đích

Kiến trúc của plugin **MyPham Kim Cuong Manager** (folder `mypham-kim-cuong-manager`): cấu trúc file, lifecycle (activation/deactivation/uninstall), migration, REST, hooks, autoload — an toàn với website đang chạy.

## 2. Phạm vi

Thiết kế code (chưa viết). Mục tiêu: plugin tự-chứa, không dependency ngoài WC/WP, tương thích PHP 8.1, WC 10.4.4.

## 3. Quyết định chính

| Mã | Quyết định | Lý do |
|---|---|---|
| PL-01 | Autoload PSR-4 đơn giản (prefix `MKC\`) | không cần composer trên hosting, tự-bundled |
| PL-02 | Lifecycle hook chuẩn; **deactivate không xóa dữ liệu** | bảo vệ dữ liệu shop |
| PL-03 | Uninstall: file `uninstall.php`, chỉ xóa khi user chủ động + confirm | an toàn |
| PL-04 | Migration chạy trong `admin_init` + version `kc_db_version` | không đụng dữ liệu WC |
| PL-05 | Custom tables qua `dbDelta`; CHARSET utf8mb4 | chuẩn WP |
| PL-06 | REST namespace `kc/v1`, permission callback chính plugin | kiểm soát chặt |
| PL-07 | WC access qua CRUD API chuẩn (HPOS-aware cho order) | không phá WC |
| PL-08 | Không sửa file core; chỉ hook/filter chuẩn | không gãy khi update WP/WC |
| PL-09 | Settings lưu WP Options (`kc_` prefix); secret mã hóa (`\MKC\Security\SecretBox` dùng `wp_salt`) | không hard-code |

## 4. Cấu trúc folder (sơ bộ)

```
mypham-kim-cuong-manager/
├── mypham-kim-cuong-manager.php      ← file chính (header plugin, bootstrap)
├── uninstall.php
├── readme.txt                        ← WP.org style docs (bắt buộc format)
├── src/
│   ├── Bootstrap.php                 ← khởi tạo, autoload register, hooks nạp
│   ├── Activation.php / Deactivation.php
│   ├── Migration/
│   │   ├── Runner.php                ← đọc schema version, chạy upgrade
│   │   └── Schema_v1.php             ← SQL bảng + index (xem 04)
│   ├── Core/
│   │   ├── Container.php             ← DI container đơn giản (get/set)
│   │   ├── Config.php                ← settings + defaults
│   │   ├── Db.php                    ← wrapper $wpdb an toàn + query helpers
│   │   └── Tx.php                    ← begin/commit/rollback safe helper
│   ├── Auth/
│   │   ├── TokenService.php          ← tạo/verify JWT, refresh, revoke
│   │   ├── PermissionMiddleware.php  ← check permission trên REST
│   │   └── RateLimiter.php
│   ├── Http/
│   │   ├── Api.php                   ← register_routes grouping
│   │   ├── Response.php              ← envelope helpers
│   │   └── IdempotencyService.php
│   ├── Domain/
│   │   ├── Products/  (Controller+Service+Repository)
│   │   ├── Variations/
│   │   ├── Barcodes/
│   │   ├── Suppliers/
│   │   ├── Lots/       (Fefo.php)
│   │   ├── Inventory/  (StockManager.php, ReceivingService, Adjustment, StockCount)
│   │   ├── Pos/        (Session, SaleService, PaymentMethods, VietQr)
│   │   ├── Orders/
│   │   ├── Customers/
│   │   ├── Coupons/
│   │   ├── Returns/
│   │   ├── Reports/
│   │   ├── Notifications/
│   │   ├── Activity/
│   │   └── Sync/       (Outbox, ConflictResolver)
│   ├── Hooks/
│   │   ├── WcStockHooks.php          ← reduce/restore stock → tx + lot + notify
│   │   └── WcOrderHooks.php          ← order transitions → notify
│   ├── Admin/
│   │   ├── SettingsPage.php          ← cấu hình, system health
│   │   └── StaffPage.php
│   └── Security/
│       ├── Validators.php            ← sanitize/validate theo field
│       └── SecretBox.php
├── tests/                            ← PHPUnit (16_TESTING)
└── vendor/ (trống — tự-bundled, PSR-4 autoload riêng)
```

## 5. Lifecycle

### 5.1 Activation (không đụng dữ liệu WC)
- Kiểm tra: PHP ≥ 8.1, WooCommerce active (nếu chưa → deactivate kèm notice thân thiện, không crash).
- Chạy install: tạo bảng `kc_*` (idempotent), set option `kc_db_version`, `kc_installed_at`, seed `kc_payment_methods` (cash/bank/vietqr), tạo role WP `kc_admin/kc_manager/kc_staff` nếu chưa có.
- **Không** xóa/sửa bảng WC. Không chạy long-running.

### 5.2 Deactivation
- Xóa cron của plugin; **KHÔNG xóa bảng/dữ liệu**. Nhắc admin đọc lưu ý.

### 5.3 Uninstall (chỉ khi user chạy xóa)
- `uninstall.php` kiểm tra `WP_UNINSTALL_PLUGIN` + option `kc_confirm_uninstall` (bật từ Settings → "Xóa toàn bộ dữ liệu khi gỡ plugin"). Mặc định: **không** — plugin để dữ liệu nếu chưa confirm. Khi confirm: drop bảng danh sách cố định `kc_*`, xóa options `kc_*`, role, media không xóa (ảnh sản phẩm là của WC).

## 6. Migration

- Option `kc_db_version` (int).
- `Runner::upgrade()` chạy từng bước `v1 → v2 → ...`: mỗi bước mảng `['sql' => string|callable, 'description' => ...]`.
- `dbDelta` cho tạo bảng; ALTER riêng khi đổi cột đặc biệt.
- Safety: wrap từng bước transaction; ghi log; nếu fail → giữ version cũ, lỗi hiện ở admin notice; có flag `kc_migration_locked`.
- Không BAO GIỜ drop dữ liệu WC; chỉ quản lý bảng `kc_*`.

## 7. REST layer

- `register_rest_route('kc/v1', '/products', ['methods'=>GET/POST, 'callback'=>..., 'permission_callback'=>fn(MKC\Auth\PermissionMiddleware)..., 'args'=>...])`.
- Middleware order: **Auth → Permission → RateLimit → Idempotency (mutation) → Validate → Service (Tx)**.
- Callback trả `WP_REST_Response`; exceptions map sang envelope lỗi chuẩn (05_API).
- Cache: GET dashboard/reports dùng transients ngắn (30–60s) nếu cần.

## 8. Stock Manager (module cốt lõi)

Interface (giữ nhất quán cho mọi nơi — **MỘT kênh ghi stock**):
```
StockManager::change(product/variation, qty_signed, $type, $ref, $lot, $cost, $note, $guard=YES)
  → chọn cơ chế stock theo "chiến lược D-22":
      ƯU TIÊN 1: WC official functions (WC_Product::set_stock / wc_update_product_stock /
                 wc_reduce_stock_levels) → WC tự đồng bộ meta/lookup/cache + fire hook chuẩn
      DỰ PHÒNG 2: guarded SQL atomic CHỈ khi thật cần chống race & đã PASS concurrency test
                  trên staging. Khi dùng SQL bắt buộc đi kèm ĐỦ:
                    • cập nhật lookup + _stock postmeta trong cùng transaction
                    • clear cache/transient liên quan (wp_cache_delete, WC transients...)
                    • fire hook phù hợp (woocommerce_product_set_stock...) để plugin khác biết
                    • kiểm tra tương thích HPOS / WooCommerce 10.4.4
                    • test cùng các plugin đang có trên site (VietQR, Variation Swatches...)
                    • reconciliation job (cron) đối soát khi nghi ngờ lệch
  → insert kc_inventory_transactions (running_stock snapshot) + lot ledger (nếu có lot)
  → validate lot-sum = stock; chênh lệch → unassigned (lot_id = NULL) + cảnh báo
```
- Giao dịch kinh doanh bao quanh WC CRUD (vd POS sale) → áp dụng **logical unit + compensation/recovery** (xem 10_POS_FLOW §5), không phụ thuộc hoàn toàn vào rollback MySQL đối với side-effect của WC/hooks/plugin khác.
- Chi tiết race handling: `09_INVENTORY_AND_STOCK_FLOW.md`.

## 9. Hooks với WooCommerce (bắt buộc)

| Hook | Mục đích |
|---|---|
| `woocommerce_reduce_stock_levels` | web đơn trừ stock → ghi WEB_SALE tx + FEFO allocate lô + check expiry alerts |
| `woocommerce_restore_order_stock` | refund web → ghi RETURN tx (về lô gốc, hoặc unassigned `lot_id NULL`) |
| `woocommerce_order_status_*` (processing/completed) | notification mới |
| `woocommerce_new_order` | notification |
| `woocommerce_product_set_stock` / `woocommerce_variation_set_stock` | sync stock khi WC đổi (vd từ plugin khác/quản trị) → tính lại lot nếu cần (**chỉ khi đảm bảo không loop**: track bằng flag) |
| `woocommerce_product_created/updated` | upsert barcode meta (`_kc_barcode`) + kc_barcodes |
| `rest_prepare_product...` | (tùy chọn) thêm field khi web cần |

## 10. Admin UI (WP admin)

- Settings: expiry window, low stock default, offline policy, max discount %, store info (tên/địa chỉ/SĐT/in), payment methods (+ cấu hình VietnamQR ngân hàng), notifications.
- Staff management: tạo/KHÓA user, role, per-permission override, reset PIN.
- System health: version DB, migration status, đếm sync outbox, lỗi idempotency, expire cache, test connection.

## 11. An toàn khi gỡ/backup đi kèm

Plugin không viết vào bảng nào ngoài `kc_*` + postmeta `_kc_*`/`_ean`. Backup plugin = zip thư mục + `wp_options` (kc_) + bảng `kc_*`. Xem 17_DEPLOYMENT.

## 12. Chưa quyết định

- Có chạy Rốts/队列 nào ngoài cron WP (ok: dùng `wp_schedule_event` daily) — chờ PHASE.
- Namespace cho file thông dịch (Loco Translate) — text domain `mypham-kim-cuong-manager`.
- Có open API docs (OpenAPI export từ 05) cho dev.

## 13. Phụ thuộc

WordPress core (REST, Options, Cron, dbDelta), WooCommerce (CRUD products/orders/customers/coupons, stock hooks, HPOS), PHP ≥ 8.1.

## 14. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| dbDelta thay đổi giữa version WC | dùng API chuẩn; giữ adapter |
| Hook cả WC reduce & tự trừ đôi | GPS track `kc_processed` ref để tránh double, test đồng bộ |
| Plugin khác trigger stock hooks → lệch lot | handler idempotent + balance check batch (cron) |
| Uninstall xóa nhầm | confirmation option + danh sách bảng strict |
| Migrate đụng host load | migration chạy nhỏ, admin-triggred, transaction ngắn |

## 15. Tài liệu liên quan

[03_SYSTEM_ARCHITECTURE](03_SYSTEM_ARCHITECTURE.md) · [04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [17_DEPLOYMENT_PLAN](17_DEPLOYMENT_PLAN.md) · [18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md)