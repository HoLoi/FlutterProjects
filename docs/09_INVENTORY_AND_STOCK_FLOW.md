# 09 · Inventory & Stock Flow (Đồng Bộ Tồn Kho)

## 1. Mục đích

Định nghĩa **single source of truth** của tồn kho, mọi luồng làm thay đổi stock, chiến lược mutation an toàn, cơ chế chống race condition giữa: web bán, POS app, nhiều thiết bị POS, nhập/điều chỉnh/kiểm kho/trả hàng. Đảm bảo **mọi biến động đều có lịch sử** và **không có 2 hệ thống tồn kho**.

## 2. Phạm vi

Luồng stock + giao tác DB + idempotency + compensation/recovery + đồng bộ web↔app. Liên quan mật thiết 10_POS, 11_EXPIRY, 13_OFFLINE.

## 3. Nguyên tắc (bất biến)

1. **Một con số tồn** = `stock_quantity` của WooCommerce (WC quản lý trên `wp_wc_product_meta_lookup` + postmeta `_stock`, cùng cache nội bộ của WC).
2. Mọi thay đổi (`+`/`−`) đi qua **duy nhất** `StockManager` của plugin → **MỘT kênh ghi stock**.
3. Mọi `change()` GHI 1 dòng `kc_inventory_transactions` (type, qty signed, ref, running_stock snapshot).
4. Tổng `remaining_qty` các lô `open` của 1 (product, variation) == WC stock; **phần tồn chưa gắn lô = `lot_id NULL` ("unassigned")**, KHÔNG dùng giá trị số `-1` (cột BIGINT UNSIGNED). Cập nhật trong cùng giao dịch kinh doanh.
5. **Chiến lược mutation stock (D-22)** — theo thứ tự ưu tiên, phải kiểm nghiệm trước khi chốt:
   - **Ưu tiên 1**: dùng **WC official API / CRUD / functions** (`wc_update_product_stock`, `WC_Product::set_stock`, `wc_reduce_stock_levels`…) làm phương tiện thay đổi `stock_quantity`. WC tự đồng bộ lookup + postmeta + cache + fire hook chuẩn cho plugin khác.
   - **Ưu tiên 2 (dự phòng)**: nếu test concurrency thực tế trên staging chứng minh official functions chưa đủ chống oversell trong kịch bản nhiều device → mới cân nhắc **guarded SQL atomic**:
     `UPDATE ... SET stock_quantity = stock_quantity ± qty [WHERE stock_quantity >= qty]`
     Khi dùng SQL trực tiếp **bắt buộc** đi kèm đủ:
     - cập nhật `wp_wc_product_meta_lookup.stock_quantity` + `_stock` postmeta trong cùng transaction;
     - clear cache/transient liên quan (WC product cache, transients `wc_product_*`, đối tượng `(WC_Product)` được tạo lại);
     - fire `woocommerce_product_set_stock` / hook phù hợp để plugin khác đồng bộ;
     - kiểm tra tương thích **HPOS / WooCommerce 10.4.4**;
     - test cùng **plugin đang có trên site** (VietQR, Variation Swatches, Vietnam Checkout, PayPal...);
     - có **reconciliation job** đối soát định kỳ.
   - **KHÔNG khẳng định "direct SQL là giải pháp cuối cùng"** trước khi có kết quả kiểm nghiệm; quyết định cuối ghi vào DECISIONS.md.
6. Mỗi sự kiện kinh doanh có **idempotency key** → replay request không trừ 2 lần.
7. Giao dịch kinh doanh bao quanh WC CRUD (vd POS sale) dùng **logical unit of work + trạng thái trung gian + compensation/recovery**, không phụ thuộc hoàn toàn vào rollback MySQL (WC CRUD/hooks/plugin khác có side-effect không phải lúc nào cũng rollback sạch) — xem 10_POS_FLOW §5.

## 4. Sơ đồ luồng

```
Thay đổi từ đâu                            →  StockManager::change()
─────────────────────────────────────────────────────────────────
POS sale (app)        realtime → logical unit (stock + order + receipt) + compensation
POS sale (offline)    queue → server replay + re-check stock (13_OFFLINE)
Nhập kho (receiving)  +qty per line + lot
Kiểm kho (count)      diff làm ADJUST type STOCK_COUNT
Điều chỉnh (adjust)   ±qty + reason
Trả hàng (return)     +qty (về lot gốc/buffer) 
Xuất hủy (write-off)  −qty (expire/damage)
Web đơn (web)         WC giảm stock → hook ghi WEB_SALE tx + FEFO allocate
Web refund (web)      WC restore → hook ghi RETURN tx
Tạo SP / khởi tạo     INITIAL (tồn đầu kỳ)
Plugin bên thứ 3      woocommerce_product_set_stock hook → ghi tx (chống loop)
```

## 5. StockManager::change() — pseudocode (theo D-22)

```
function change(product_id, variation_id, qty_signed, type, ref, opts):
    $id = variation_id ?: product_id         // unit thao tác: variation riêng, product đơn
    begin_transaction_if_needed()

    // A. Chọn cơ chế stock:
    //    ƯU TIÊN official WC functions — WC tự đồng bộ lookup/meta/cache/hook:
    if official_path => $product = wc_get_product($id);
                        $new = $product->set_stock($product->get_stock_quantity() + qty_signed) // qua WC
                        // WC fire woocommerce_product_set_stock; handler plugin của ta chống loop
    //    DỰ PHÒNG guarded SQL (CHỈ khi qua test staging + đủ checklist D-22):
    else =>
        row = SELECT stock_quantity FROM wp_wc_product_meta_lookup WHERE id=$id FOR UPDATE
        if qty_signed < 0:
            affected = UPDATE wp_wc_product_meta_lookup
                       SET stock_quantity = stock_quantity + qty_signed
                       WHERE id=$id AND stock_quantity + qty_signed >= 0
            if affected == 0 → rollback; throw KC_INSUFFICIENT_STOCK (kèm có, cần)
        else:
            UPDATE ... stock_quantity = stock_quantity + qty_signed
        // đồng bộ postmeta _stock trong cùng transaction
        UPDATE wp_postmeta SET meta_value = $new WHERE post_id=$id AND meta_key='_stock'
        // clear cache/transient liên quan
        cache_delete / wc_delete_product_transients($id) / (WC_Product)->get_data() re-read
        // fire hook woocommerce_product_set_stock (flag chống re-enter)
        do_action('woocommerce_product_set_stock', $product)

    // B. Ghi lịch sử & lô
    insert kc_inventory_transactions(product_id, variation_id, qty, type, ref, running_stock=$new)
    nếu liên quan lô (bán/nhập/trả...) → FEFO/LotLedger (11_EXPIRY)

    // C. validate nhất quán
    //    SELECT SUM(open lots.remaining) vs stock; lệch → unassigned = lot_id NULL + cảnh báo
    return $new
```

### Chi tiết quan trọng
- **Khóa thứ tự nhất quán** khi nhiều dòng: lock/xử lý theo `id` tăng dần trong 1 transaction để tránh deadlock cross-product.
- **Deadlock/timeout**: bắt exception MySQL (1213/1205) → rollback → retry ≤ 3 lần (small jitter) → nếu vẫn fail trả `409 KC_CONFLICT` + `Retry-After`, client có idempotency key tự retry an toàn.
- **Hủy atomic trong PHP**: WP `$wpdb` không quản transaction; dùng helper `Tx::run(callable)` (BEGIN/COMMIT/ROLLBACK) gói mọi bước DB của một nghiệp vụ.
- **Side-effect ngoài DB** (WC CRUD, hooks, cache, plugin khác): KHÔNG coi là rollback sạch được → nghiệp vụ kinh doanh lớn phải có compensation/recovery (10_POS_FLOW §5).

## 6. Các nguồn thay đổi — chi tiết & chống đúp

### 6.1 Web đơn (website bán)
- WooCommerce tự giảm stock bằng cơ chế riêng (hàm `wc_update_product_stock` / `wc_reduce_stock_levels`) → **plugin lắng nghe hook**:
  - `woocommerce_reduce_stock_levels` — array [id => qty] → với mỗi item: xác định type WEB_SALE + ref (order_id), ghi inventory tx + FEFO allocate lô (nếu hết lô → phần thừa **`lot_id = NULL`** unassigned & cảnh báo), cập nhật `running_stock`.
  - `woocommerce_restore_order_stock` — refund: ghi RETURN tx (về lot gốc hoặc NULL/buffer).
- **Cờ chống loop**: mọi handler stock phải kiểm tra ref (đã xử lý chưa / flag trong transaction) để không ghi trùng tx khi `woocommerce_product_set_stock` bị fire ngược.

### 6.2 POS sale realtime (app)
- Thực thi theo **logical unit of work** (10_POS_FLOW §4–5): trạng thái trung gian `pending/processing`, sau `completed`; nếu thất bại giữa chừng → **compensation/reversal** (hoàn stock + mark `void/needs_review` + audit).
- Idempotency: `Idempotency-Key` gửi kèm → server replay cũ → không trừ 2 lần.

### 6.3 Nhiều thiết bị POS cùng SP
- Mọi đường trừ đều qua **guard** (official `set_stock` giảm có guard do WC tích hợp; nếu dùng SQL → có `WHERE stock >= qty`). Device nào trừ trước thắng; device sau nhận `KC_INSUFFICIENT_STOCK` 409 → POS hiển thị "Sản phẩm X còn 2, còn lại 0", cho cập nhật giỏ và bán tiếp phần còn.
- **Yêu cầu kiểm nghiệm**: kịch bản này phải chạy concurrency test trên staging để chốt dùng official hay cần guarded SQL (PHASE 6).

### 6.4 Offline POS (queue)
- Buffer theo mức (product/variation × device) qua `kc_device_stock_buffers` (13_OFFLINE). Khi sync: mỗi giao dịch replay qua `POST /sync/queue` → server gọi lại `process_pos_sale()` với guard stock thật. Nếu stock thực tế thiếu (web bán trước) → **conflict rõ ràng**, admin xử lý — không tự xử lý im lặng.

### 6.5 Nhập kho / count / adjust / return
- Tất cả qua endpoint (transaction + idempotency). Count: diff chạy qua `StockManager`.

## 7. Consistency giữa lookup / postmeta / WC cache

- Ưu tiên official functions → WC tự đồng bộ. Nếu dùng SQL guarded → cập nhật lookup + postmeta cùng transaction và **clear cache/transient** liên quan.
- Reconciliation: batch định kỳ (cron) so `wc_get_product()->get_stock_quantity()` với `kc_inventory_transactions` running stock & tổng lô; lệch → notification + repair tool. Chạy `wc_update_product_lookup_tables()` nếu cần so khớp.

## 8. Đồng bộ App thấy số mới (pull)

- App gọi `GET /inventory/stock` (hoặc `GET /products?updated_after=`) để cập nhật cache.
- Push trực tiếp (webhook/FCM) tùy chọn — polling 30–60s ở app khi có mạng là đủ T0; chiến lược offline ở 13.

## 9. Bảng tổng "ai trừ khi nào"

Ví dụ minh hoạ (giống yêu cầu I):

| Ngày | Sự kiện | qty | running | loại | ref |
|---|---|---|---|---|---|
| 19/09 | Nhập hàng LOT001 | +20 | 20 | RECEIVING | recv #1 |
| 19/09 | POS bán | −1 | 19 | POS_SALE | pos #5 |
| 19/09 | Web đơn | −1 | 18 | WEB_SALE | order #1234 |
| 20/09 | Trả hàng (nhập lại) | +1 | 19 | RETURN | return #1 |
| 21/09 | Điều chỉnh kho | −2 | 17 | ADJUST | adj #1 |

## 10. Trường hợp đặc biệt

| Tình huống | Xử lý |
|---|---|
| **Âm kho**: "hết hàng nhưng khách cần mua" | mặc định **chặn**; setting `kc_allow_negative_stock` cho phép − (ghi inventory tx âm, lot unassigned `NULL`) |
| **Đơn web hủy trả hàng** | WC restore → hook; nếu đơn đã completed và đã ghi COGS → ghi reversal/return để kéo lợi nhuận về |
| **Kiểm kho giữa ca** | system snapshot lúc tạo items; diff chấp nhận "có giao dịch xen" — snapshot `created_at` lưu; tùy chọn `count_mode`: chờ phiên không phát sinh giao dịch (khuyến nghị count ban đêm) |
| **Sản phẩm mới không có stock** | `_manage_stock` off → không quản lý; plugin hiển thị "không quản lý kho"; POS cảnh báo trước khi bán |
| **Chuyển kho/chi nhánh** (future) | chưa hỗ trợ; khi có nhiều kho cần cột bổ sung + tách stock theo kho — mở rộng Phase sau |

## 11. Chưa quyết định

- Có cho phép âm kho không (mặc định: không). Chờ chủ dự án.
- Tần suất polling app thích hợp (30s? 60s?).
- Có dùng notification push tích cực cho "stock thay đổi" không.
- Kết quả concurrency test PHASE 6 sẽ chốt: official functions là đủ, hay phải dùng guarded SQL cho kịch bản đa device.

## 12. Phụ thuộc

Plugin: StockManager, Tx, WC hooks, kc_inventory_transactions, kc_lots/ledger. App: sync engine, cache refresh.

## 13. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| WC version đổi luồng reduce stock | adapter + smoke test hook Phase 6; dự phòng đọc lại order_itemmeta delta |
| Race giữa hook (web) và StockManager | một kênh ghi + lock dòng (FOR UPDATE khi dùng SQL) + idempotent tx handler |
| Lệch lookup/postmeta/cache do SQL tay | checklist D-22 (sync meta + clear cache + fire hook) + reconciliation job |
| Side-effect WC/hook/plugin khác lệch khi rollback MySQL | logical unit + compensation/recovery (10_POS_FLOW §5) + audit |
| Nhập/trả song song cùng product | guard + lock theo thứ tự id |

## 14. Tài liệu liên quan

[04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [10_POS_FLOW](10_POS_FLOW.md) · [11_EXPIRY_AND_LOT_MANAGEMENT](11_EXPIRY_AND_LOT_MANAGEMENT.md) · [13_OFFLINE_SYNC](13_OFFLINE_SYNC.md)