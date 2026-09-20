# DECISIONS — Nhật Ký Quyết Định Kiến Trúc

## 1. Mục đích

Ghi lại **mọi quyết định kiến trúc quan trọng**, lý do, và thay đổi sau này — nguồn tham chiếu duy nhất khi ai đó hỏi "vì sao lại làm vậy".

## 2. Quy ước

- Mã quyết định: `D-00` (từ tài liệu phân rã). Khi đổi/đảo ngược → ghi entry mới với `supersede`.
- Trạng thái: ✅ Đã duyệt (vào tài liệu) · 🔶 Đề xuất (chờ chủ dự án) · 🔄 Đã thay đổi.

## 3. Danh sách quyết định

### D-01 — WooCommerce là source of truth (products, price, stock, orders, customers)
- **Quyết định**: Woocomerce + WP DB = nguồn duy nhất; custom tables chỉ nghiệp vụ mở rộng. Không database sản phẩm riêng.
- **Lý do**: không 2 hệ giá/tồn; tận dụng WC ecosystem.
- **Trạng thái**: ✅ (03, 09)

### D-02 — App chỉ giao tiếp qua plugin REST (kc/v1)
- **Lý do**: bảo mật (no MySQL từ app), 1 nơi chốt permission/transaction/idempotency/rate limit.
- **Trạng thái**: ✅

### D-03 — Barcode: canonical trên WC meta + lookup `kc_barcodes` (unique)
- **Lý do**: scan O(1), unique toàn hệ; WC native EAN dùng nếu có, fallback `_kc_barcode`.
- **Trạng thái**: ✅

### D-04 — Stock atomic guard `UPDATE ... SET stock = stock ± qty WHERE stock >= qty` + transaction + row-lock
- **Lý do**: đánh bại race POS / web / đa device; không oversell.
- **Trạng thái**: 🔄 **Đã thay đổi một phần bởi D-22** — hướng "official API first, guarded SQL dự phòng" (giữ nguyên tinh thần chống oversell). (03, 09)

### D-05 — Idempotency bắt buộc mọi mutation chính (POS sale, receive, return, adjust, count confirm, sync queue)
- **Lý do**: chống double-tap / mạng retry (yêu cầu AC).
- **Trạng thái**: ✅ (05)

### D-06 — POS sale trải qua nhiều bước: trừ kho + tạo WC order (HPOS) + pos transaction + receipt + log
- **Lý do**: 3 điều cấm (10); tận dụng WC order để đồng bộ đơn/platform.
- **Trạng thái**: 🔄 **Đã thay đổi bởi D-23** — không còn tuyên bố "1 MySQL transaction tuyệt đối"; dùng logical unit + trạng thái trung gian + compensation/recovery.

### D-07 — COGS theo lô FEFO; fallback `_kc_cost`; báo cáo luôn tách revenue/cost/profit
- **Lý do**: mỹ phẩm hết hạn sớm; yêu cầu R không nhầm doanh thu = lợi nhuận.
- **Trạng thái**: ✅ (11, 12)

### D-08 — Web sale → hook `woocommerce_reduce_stock_levels` → ghi WEB_SALE tx + FEFO allocate (best-effort; thiếu → unassigned `lot_id NULL`)
- **Lý do**: app thấy web bán; lô khớp tồn dù WC không biết lô.
- **Trạng thái**: 🔄 biểu diễn unassigned nay là `lot_id NULL` (D-24), không dùng `-1`. (09, 11)

### D-09 — Auth: plugin JWT (access 1h + refresh 24h rotate) + device registry + permission từ DB
- **Lý do**: quyền granular, thu hồi nhanh; tránh WC consumer key quá rộng.
- **Trạng thái**: ✅ (08)

### D-10 — 3 role cơ bản (admin/manager/staff) + permission grid, override per staff; chặn server-side
- **Lý do**: linh hoạt nghiệp vụ mà vẫn chắc chắn.
- **Trạng thái**: ✅ (15)

### D-11 — Offline mặc định READ-ONLY; offline POS = tùy chọn theo device có buffer; sync qua outbox + idempotency + conflict center
- **Lý do**: an toàn tồn kho; không "đẩy hết" (yêu cầu V).
- **Trạng thái**: 🔶 dự phần policy cho chủ shop verify (13)

### D-12 — Expiry alert: setting cửa sổ ngày (default 30); chặn bán hết hạn mặc định (override có PIN)
- **Lý do**: bảo vệ khách; nghiệp vụ mỹ phẩm.
- **Trạng thái**: 🔶 cần xác nhận (11)

### D-13 — Custom tables prefix `{prefix}kc_`; schema versioned (kc_db_version); deactivate không xóa, uninstall có confirm
- **Lý do**: an toàn dữ liệu; migration chuẩn.
- **Trạng thái**: ✅ (04, 06)

### D-14 — Migration/dbDelta + ALTER; custom FK chỉ logic (index); không FK cứng sang WC tables
- **Lý do**: WC schema có thể đổi; portability.
- **Trạng thái**: ✅ (04)

### D-15 — Plugin không sửa core; dùng hook/filter + CRUD WC; HPOS-aware qua wc_get_order
- **Lý do**: không gãy khi WP/WC update.
- **Trạng thái**: ✅ (06)

### D-16 — Flutter: Riverpod + GoRouter + Dio + Hive/secure_storage + feature-first; mobile_scanner; ESC/POS tự viết + Bluetooth; PDF fallback
- **Lý do**: scale, testable, offline; linh hoạt máy in giá rẻ.
- **Trạng thái**: 🔶 chốt ở Phase 4 khi khảo sát package (07)

### D-17 — Navigation 5 tab tinh chỉnh: [POS · Kho · Đơn hàng · Dashboard · Thêm] (POS center nổi)
- **Lý do**: tần suất thao tác; gộp scan vào POS + FAB toàn cục.
- **Trạng thái**: 🔶 chờ đồng thuận UX (07, AA)

### D-18 — Thời gian chuẩn UTC trong DB; hiển thị theo tz shop Asia/Ho_Chi_Minh
- **Lý do**: report đúng trên đa thiết bị.
- **Trạng thái**: ✅

### D-19 — Báo cáo snapshot giá tại giao dịch (không đổi khi sửa giá/lô sau đó) + net refund theo kỳ
- **Lý do**: báo cáo ổn định, dễ đối soát.
- **Trạng thái**: 🔶 cân nhắc "re-evaluate" khi có yêu cầu sửa giá lùi (12)

### D-20 — Kernel plugin không dùng thư viện ngoài (autoload tự viết, không composer build bắt buộc)
- **Lý do**: host chia sẻ đơn giản, tự-bundled.
- **Trạng thái**: ✅

### D-21 — Bỏ đề xuất "Endpoint inventory/receive" trùng lặp: nhập kho chuẩn hóa `/receivings`
- **Lý do**: clean API; alias tùy chọn.
- **Trạng thái**: ✅ (05)

### D-22 — Chiến lược mutation stock: ưu tiên WC official API/CRUD/functions; guarded SQL chỉ khi có bằng chứng test staging
- **Quyết định**:
  1. Mặc định thay đổi `stock_quantity` qua **WC official functions** (`wc_update_product_stock`, `WC_Product::set_stock`, `wc_reduce_stock_levels`…) để WC tự đồng bộ lookup/meta/cache/hook.
  2. Chỉ dùng **guarded SQL atomic** (`UPDATE ... WHERE stock_quantity >= qty`) nếu concurrency test trên staging chứng minh official functions chưa đủ chống oversell đa device; khi đó bắt buộc kèm: đồng bộ lookup + `_stock` postmeta, clear cache/transient, fire hook phù hợp, kiểm tra HPOS/WC 10.4.4, test cùng plugin đang có (VietQR, Variation Swatches, Vietnam Checkout, PayPal...), reconciliation job.
  3. KHÔNG tuyên bố "direct SQL là giải pháp cuối cùng" trước khi kiểm nghiệm.
- **Lý do**: giảm rủi ro lệch meta/cache/plugin, tăng tương thích và an toàn production.
- **Hệ quả**: PHASE 6 chạy concurrency test để chốt official-only hay cần guarded SQL.
- **Trạng thái**: 🔶 Đề xuất (chốt cứng ở PHASE 6). Supersede một phần D-04. (09, 04, 06)

### D-23 — POS sale dùng logical unit of work + trạng thái trung gian + compensation/recovery (không dựa hoàn toàn rollback MySQL)
- **Quyết định**: `kc_pos_transactions` có trạng thái `pending → processing → completed`, và `void` / `needs_review` khi hỏng giữa chừng; side-effect WC/hooks/plugin không luôn rollback sạch → compensation/reversal hoàn stock đã trừ + audit log + recovery job quét `processing` kẹt; client kiểm tra trạng thái trước khi retry.
- **Lý do**: WC CRUD/cache/hook/plugin thứ ba để lại side-effect DB ngoài tầm rollback; đảm bảo không "mất" giao dịch, không trừ kho mồ côi.
- **Hệ quả**: thay đổi cách diễn đạt ở 05/06/09/10.
- **Trạng thái**: ✅ (10, 05, 09). Thay thế tuyên bố "1 transaction" của D-06.

### D-24 — Biểu diễn tồn chưa gắn lô = `lot_id NULL` ("unassigned"), không dùng `-1`
- **Quyết định**: cột `lot_id` là BIGINT UNSIGNED nullable; phần tồn/lượt bán chưa định danh lô ghi `lot_id = NULL` + lý do/cảnh báo admin gán lô sau.
- **Lý do**: `-1` xung đột kiểu dữ liệu (UNSIGNED) và khó truy vấn; NULL là biểu diễn chuẩn tự nhiên.
- **Trạng thái**: ✅ (04, 09, 11). Thay thế cách viết "lot -1"/"lot 0" (D-08, tài liệu 11).

### D-25 — Offline buffer khai theo (product/variation × device) qua `kc_device_stock_buffers`, mặc định OFF/read-only
- **Quyết định**: bảng `kc_device_stock_buffers` (device_id, product_id, variation_id, max_qty, used_qty) thay cho 1 số "offline_buffer" tổng; `max_qty=0` = read-only; `used_qty` giảm khi sync thành công; server vẫn guard stock thật khi sync, conflict không tự xử lý.
- **Lý do**: hạn mức theo mặt hàng an toàn hơn tổng units; buộc admin chủ động bật.
- **Trạng thái**: ✅ mặc định; 🔶 chờ chủ shop chốt có bật & mức cụ thể (13, 04).

### D-26 — Trạng thái đã đọc thông báo lưu ở bảng riêng `kc_notification_reads`
- **Quyết định**: dùng bảng `kc_notification_reads(notification_id, staff_id, read_at)` (UQ cặp) thay vì JSON `read_by_user`.
- **Lý do**: JSON không scale/truy vấn khi số thông báo và nhân viên tăng; bảng riêng chuẩn hóa, đánh index được.
- **Trạng thái**: ✅ (04).

### D-27 — Production Safety Gate bắt buộc trước mọi thay đổi production
- **Quyết định**: phải pass đủ trước go-live: backup DB+files (verify restore), staging clone, test activation/deactivation, test API read-only, test sản phẩm TEST, rollback plan, **chủ dự án xác nhận thủ công**, bật feature theo flag từng phần.
- **Lý do**: tránh rủi ro lên website thật; có đường lùi rõ ràng.
- **Trạng thái**: ✅ (README, 17_DEPLOYMENT §5.1, 18 PHASE 16).

### D-28 — PHASE 1 chia 1A/1B; giữ nguyên scaffold; PHASE 1B (staging) là gate cho PHASE 2
- **Quyết định**:
  1. **PHASE 1A** = local + GitHub + review scaffold (KHÔNG API/DB/migration/build APK) — đã hoàn tất.
  2. **Giữ nguyên** `mypham_kim_cuong_app/` (Flutter create) và `mypham-kim-cuong-manager/` (skeleton) — không tạo lại; chỉ sửa khi có yêu cầu scaffold hygiene rõ ràng (hỏi trước).
  3. **PHASE 1B** = staging site + môi trường dev (PHP CLI 8.1 local); hiện **pending vì chưa có staging/hosting phụ**.
  4. **Gate**: KHÔNG bắt đầu PHASE 2 nếu chưa có staging hoặc chưa có xác nhận rõ của chủ dự án.
- **Lý do**: tách phần an toàn (local/GitHub) khỏi phần phụ thuộc hạ tầng (staging); tránh đụng production.
- **Trạng thái**: ✅ (README §10, 17_DEPLOYMENT §2.1/§4.1, 18 PHASE 1A/1B).

### D-29 — Git policy: monorepo `FlutterProjects`, `.gitignore` root, không commit secret
- **Quyết định**: repo GitHub `HoLoi/FlutterProjects` chứa cả docs + app + plugin; `.gitignore` root chặn OS/IDE, secret/local config, `vendor/`, `node_modules/`, log, cache, build output. `mypham-kim-cuong-manager.zip` **chưa** đưa vào git ở PHASE 1A (chờ quyết định giữ/bỏ).
- **Lý do**: an toàn (không lộ secret/keystore), repo gọn, dễ tái lập môi trường.
- **Trạng thái**: ✅ (`.gitignore`, commit baseline). zip: 🔶 chờ chủ dự án.

## 4. Thay đổi so với yêu cầu ban đầu (đề xuất chủ dự án xem xét)

| Yêu cầu gốc | Đề xuất thay đổi | Lý do |
|---|---|---|
| Tab Scan riêng (AA) | Gộp vào POS + FAB global | giảm bước thao tác |
| Receiving endpoint `/inventory/receive` | Chuẩn `/receivings` | nhất quán model phiếu nhập |
| Offline "nghiên cứu" | Cụ thể hóa: đọc offline mặc định; POS offline có buffer + conflict | an toàn + rõ chính sách |
| Barcode "nếu phù hợp" | Bắt buộc uniqueness + lookup bảng | scan yêu cầu D |
| Lợi nhuận báo cáo | Snapshot + net refund + chỉ rõ cost_method | không nhầm lẫn |
| Permission "cần thiết kế từ đầu" | 3 role + grid + override + PIN | hoàn chỉnh ngay |

## 5. Các câu hỏi chưa quyết định (cần chủ dự án — danh sách đầy đủ ở 02 §4)

1. Offline POS: có bật không; mức buffer theo từng mặt hàng/thiết bị là bao nhiêu (nền tảng đã chốt ở D-25 — chỉ còn giá trị cụ thể).
2. Máy in 58/80, hãng.
3. VAT trong giá bán/giá nhập.
4. VietQR POS cấu hình ngân hàng & xác nhận thanh toán.
5. Chặn bán hết hạn.
6. Nhân viên login: user/pass hay phone+PIN; bắt buộc mỗi ca?
7. Số lượng SKU hiện tại (định cỡ cache).
8. Nhờ khai "tồn đầu kỳ" (INITIAL) — nhập như thế nào, ai nhập.
9. Máy quét HID hay không.
10. Play Store hay APK private.
11. Push FCM hay chỉ in-app.

## 6. Tài liệu liên quan

README · 02_REQUIREMENTS (§3-4) · 18_IMPLEMENTATION_ROADMAP · tất cả doc theo liên kết trong từng quyết định.