# 02 · Phân Tích Yêu Cầu (A → AE)

## 1. Mục đích

Phân tích từng nhóm yêu cầu mà chủ dự án nêu (A..AE): làm rõ, bổ sung quyết định thiết kế, phát hiện **mâu thuẫn**, **thiếu sót**, và các **điểm cần chủ dự án quyết định** trước khi lập kế hoạch chi tiết.

## 2. Phạm vi

Toàn bộ nghiệp vụ + kỹ thuật được nêu. Mỗi mục ghi: **Yêu cầu → Phân tích → Thiết kế đề xuất → Chưa quyết định**.

---

## A. Dashboard

**Yêu cầu**: tổng sản phẩm, đang bán, hết hàng, sắp hết hàng, sắp hết hạn, đã hết hạn, doanh thu hôm nay, doanh thu theo ngày/tháng/năm, giá vốn, lợi nhuận, số đơn, bán chạy, bán chậm, cảnh báo, đơn cần xử lý. Phải có biểu đồ.

**Phân tích**:
- Định nghĩa rõ **"doanh thu hôm nay"** theo ngày của cửa hàng (múi giờ `Asia/Ho_Chi_Minh`), gồm POS + đơn web, loại trừ đơn hủy/hoàn.
- "Giá vốn / lợi nhuận" chỉ chính xác nếu khai giá vốn lô. Nếu sản phẩm chưa có giá vốn → dùng fallback `_kc_cost` hoặc 0 (phải hiển thị cảnh báo dữ liệu giá vốn thiếu).

**Thiết kế**: 1 endpoint `GET /kc/v1/dashboard/summary` trả tất cả số liệu + chuỗi series cho biểu đồ (7 ngày / 12 tháng / 5 năm). App vẽ biểu đồ local (xem 07_FLUTTER).

**Chưa quyết định**: ngày bắt đầu "ngày hôm nay" (00:00 theo store tz — đề xuất mặc định).

## B. Quản lý sản phẩm

**Yêu cầu**: list/search/filter/CRUD/ẩn-hiện/giá bán/giá KM/giá vốn/SKU/barcode/danh mục/thương hiệu/mô tả/ảnh (nhiều ảnh, chụp camera, upload WP)/trạng thái.

**Phân tích**:
- Sản phẩm ghi vào **WooCommerce** qua CRUD chuẩn (WC REST API hoặc trực tiếp qua `wc_get_product`). Plugin không tạo bảng sản phẩm song song.
- **Giá vốn**: phân phối về 2 nơi: (a) giá vốn lô (`kc_lots.cost_unit`) cho COGS thực tế; (b) giá vốn mặc định `_kc_cost` trên postmeta dùng khi không có lô. `_kc_cost` không phải field chuẩn của WC → là meta plug-in (an toàn, không phá WC).
- **Barcode**: đề xuất lưu ở postmeta (dùng field EAN của WooCommerce 9.2+ nếu có sẵn `product_ean`/meta `_ean`, hoặc meta `_kc_barcode` nếu không) và **materialize vào bảng lookup `kc_barcodes`** (unique) để quét nhanh O(1). Cả sản phẩm lẫn variation đều có thể có barcode.
- **Thương hiệu**: WC mặc định không có. Đề xuất register **taxonomy `brand`** thuộc plugin (không đụng WC core); có thể dùng chung `product_brand` attribute. → chưa quyết định dùng taxonomy riêng hay Product Attribute.

**Chưa quyết định**: thương hiệu dùng taxonomy hay attribute; chuẩn mã vạch (EAN-13/UPC/Code128); có tự sinh barcode không (không đề xuất — tránh trùng).

## C. Sản phẩm biến thể

**Yêu cầu**: hỗ trợ variable product WC: SKU, barcode, giá, tồn kho, ảnh, giá vốn riêng theo variation; không phá vỡ cơ chế WC.

**Thiết kế**:
- Dùng đúng `variation_id` là đơn vị thao tác kho/giá; tồn kho đặt **per variation** (WC native). Product cha không lưu stock riêng.
- Barcode gắn per variation (bảng `kc_barcodes.variation_id`).
- Giá vốn per variation: postmeta `_kc_cost` trên variation; lô gắn `variation_id`.
- App hiển thị cây Product → Variations với các attribute (Ngày/Đêm, Màu, Dung tích, Kích thước, Mùi hương...).

## D. Quét Barcode / QR

**Yêu cầu**: quét bán hàng, nhập hàng, tìm nhanh, mở sản phẩm, tạo sản phẩm mới nếu chưa có.

**Thiết kế**:
- Endpoint `GET /kc/v1/products/by-barcode/{code}` → trả product hoặc variation; `404` + cờ `not_found_reason` để app hiển thị nút "Tạo sản phẩm mới". 404 hợp lệ nghiệp vụ (không phải lỗi server).
- Offline: tìm trong cache cục bộ; nếu không có thì (a) chỉ cảnh báo khi offline read-only, hoặc (b) xếp hàng query để reconcile sau (offline POS).
- QR: hỗ trợ QR nội dung như barcode (nhà cung cấp in QR) hoặc QR hóa đơn tra cứu.

## E. Quản lý lô hàng

**Yêu cầu**: 1 sản phẩm nhiều lô; mỗi lô: mã lô, NSX (nullable), HSD (nullable), giá nhập, số lượng nhập, số lượng còn, nhà cung cấp, ngày nhập. Xuất lô chiến lược ưu tiên gần hết hạn (FEFO).

**Phân tích & thiết kế chi tiết**: xem `11_EXPIRY_AND_LOT_MANAGEMENT.md`.
- Bảng `kc_lots` + `kc_lot_ledger` (nhật ký lô).
- **Vấn đề quan trọng**: WooCommerce chỉ quản stock theo số tổng `stock_quantity`. Số liệu lô (**remaining_qty**) là "lớp dữ liệu" song song nhưng **phải nhất quán**: tổng remaining của các lô đang mở của 1 product/variation phải bằng WC stock_quantity (điều chỉnh sau stock count / expire / return phải chạy cùng transaction).
- Trách nhiệm lô với **đơn website**: khi web đặt hàng, WC tự trừ stock nhưng không biết lô → plugin hook `woocommerce_reduce_stock_levels` để **allocate FEFO lô** theo lượng đã trừ (best-effort, vẫn đảm bảo tổng khớp). Nếu không khớp (vd đã hết lô) → phần không định danh ghi với `lot_id = NULL` (bán "unassigned") để tổng vẫn khớp, cảnh báo admin gán lô sau.

## F. Cảnh báo hạn sử dụng

**Yêu cầu**: cấu hình mốc 7/15/30/60/90/tùy chỉnh ngày; hiển thị sản phẩm sắp/đã hết hạn, số lượng, HSD, số ngày còn, lô.

**Thiết kế**:
- Setting plugin `kc_expiry_alert_days` (mặc định 30). Mốc là "số ngày tính tới HSD".
- Endpoint `GET /kc/v1/inventory/expiry-alerts?window=` trả các lô còn `remaining_qty > 0` và (a) HSD rỗng → nhóm "chưa có HSD", (b) HSD trong cửa sổ → "sắp hết hạn", (c) HSD < hôm nay → "đã hết hạn".
- Có thể cấu hình khác nhau theo products/group về sau.

**Chưa quyết định**: mốc cảnh báo mặc định cho toàn store; có **chặn bán** hàng hết hạn không (mặc định: chặn, có override cho admin).

## G. Nhập kho

**Yêu cầu**: nhà cung cấp, ngày nhập, sản phẩm, variation, SL, giá nhập, lô, NSX, HSD, tổng tiền, ghi chú. Sau xác nhận: cập nhật tồn WC, lịch sử kho, dữ liệu lô, lưu giá vốn.

**Thiết kế**:
- `POST /kc/v1/receivings` trong 1 transaction: tạo `kc_receivings` + items; với mỗi line: tạo/gắn `kc_lots` (mã lô tự sinh hoặc do user nhập), tăng WC stock qua StockManager theo D-22 (ưu tiên WC official functions), insert `kc_inventory_transactions` type `RECEIVING`, write `kc_lot_ledger`. Cập nhật `_kc_cost` nếu chưa có (or weighted avg — config).

## H. Nhà cung cấp

**Thiết kế**: CRUD `kc_suppliers`; lịch sử nhập qua `kc_receivings`; tổng tiền nhập = SUM(total_cost) của receivings theo supplier. Xóa mềm (`status`), không xóa cứng nếu có giao dịch (bảo toàn lịch sử).

## I. Quản lý kho + lịch sử

**Yêu cầu**: tồn hiện tại, hết hàng, sắp hết hàng, nhập/xuất/điều chỉnh/kiểm kho, lịch sử. Mọi thay đổi có lịch sử.

**Thiết kế**: mọi biến động ghi `kc_inventory_transactions` (type: `RECEIVING, POS_SALE, WEB_SALE, RETURN, ADJUST, STOCK_COUNT, REVERSAL, EXPIRE_WRITE_OFF, INITIAL`). Endpoint lịch sử lọc theo product/range/type. **Xuất kho**: qua POS sale hoặc xuất hủy (write-off) có lý do.

## J. Kiểm kho

**Thiết kế**: `kc_stock_counts` (phiên) + `kc_stock_count_items` (per product/variation: system_qty, actual_qty, diff, reason). Khi xác nhận: khoá phiên, áp chênh lệch bằng 1 transaction: điều chỉnh stock + tạo `ADJUST`/`STOCK_COUNT` transactions + đối soát lô (diff phân bổ theo chiến lược lô, phần không định danh → `lot_id = NULL`). Quyền: chỉ manager/admin xác nhận.

## K. POS bán hàng

**Yêu cầu**: tìm SP, quét barcode, giỏ, +/- số lượng, xóa, giảm giá, tổng tiền, thanh toán (tiền mặt, chuyển khoản, VietQR, mở rộng được), sau bán: tạo giao dịch POS, cập nhật WC stock, ghi lịch sử, tính giá vốn, lợi nhuận, hóa đơn. Cấm "chỉ trừ con số tồn mà không có lịch sử".

**Thiết kế chi tiết**: `10_POS_FLOW.md`. Cốt lõi:
- POS sale realtime (online): logical unit server-side (states + compensation, D-23); **idempotency** chống double-tap/mạng.
- POS session (ca làm việc) `kc_pos_sessions`: mở ca kê tiền quỹ đầu, đóng ca đối chiếu.
- Thanh toán: enum `CASH, BANK_TRANSFER, VIETQR, MOMO?, CARD?` — thiết kế table `kc_payment_methods` mở rộng được.
- Tạo **WooCommerce order** (status `completed`, payment_method ghi rõ) + **biên lai POS** `kc_receipts`.

## L. Đơn hàng website

**Thiết kế**: plugin đọc order qua WC CRUD API (HPOS-aware); endpoints `GET /kc/v1/orders` + `/{id}` + `PUT /{id}/status` (chỉ manager/admin) + `POST /{id}/refund`. Hiển thị items (kể cả variation), tổng, thanh toán, trạng thái, khách hàng. **Khi web đơn đặt → tự trừ stock → hook ghi inventory tx + allocate lô** (đã nêu ở E).

## M. Hóa đơn / biên lai

**Yêu cầu**: in ngay, in lại, xem hóa đơn, chia sẻ, xuất PDF. Nội dung: tên cửa hàng, mã hóa đơn, ngày giờ, SP, variation, SL, giá, giảm giá, tổng, thanh toán, lời cảm ơn. Ưu tiên Bluetooth thermal 58mm/80mm.

**Thiết kế**: `14_PRINTER_BARCODE.md`. Server lưu dữ liệu biên lai gốc (`kc_receipts`) để in lại bất kỳ lúc nào (đảm bảo khác với giá hiện tại của SP). App render ESC/POS hoặc PDF.

## N. Đồng bộ tồn kho (QUAN TRỌNG NHẤT)

**Yêu cầu**: WC tồn 5, POS bán 1 → WC = 4; web mua → app thấy đúng. Không hai hệ tồn kho. Tránh race: web bán lúc POS bán, nhiều POS bán cùng SP.

**Thiết kế** (`09_INVENTORY_AND_STOCK_FLOW.md`):
- Single source: `stock_quantity` của WooCommerce (qua **WC official functions / CRUD thứ nhất**, xem D-22).
- Chiến lược mutation (ưu tiên, sẽ xác minh ở PHASE 6 bằng test concurrency trên staging):
  1. **Ưu tiên dùng official WC API/functions** (`wc_update_product_stock`, `WC_Product::set_stock`, `wc_reduce_stock_levels`…) để động stock.
  2. Chỉ dùng SQL atomic có guard (`UPDATE ... WHERE stock_quantity >= qty`) **nếu thật sự cần chống race và đã chứng minh bằng test staged** — kèm đủ: đồng bộ lookup/meta, clear cache/transient, fire hook phù hợp, kiểm tra HPOS + plugin có sẵn trên site.
  3. Không khẳng định "direct SQL là giải pháp cuối cùng" trước khi kiểm nghiệm.
- Web sales: web tự trừ stock qua cơ chế WC; plugin hook ghi lại → app luôn thấy đúng số.
- Mọi đường trừ đều chống oversell (guard); device nào trừ trước thì thắng, device sau nhận lỗi `INSUFFICIENT_STOCK`.
- Idempotency key chống duplicate request.
- Lưu thêm `running_stock` snapshot trong inventory tx để truy vết.

## O. Trả hàng / hoàn hàng

**Thiết kế**: chọn hóa đơn (POS hoặc web order), chọn lines, SL, lý do, hoàn tiền (có/không), nhập lại kho (vào lô gốc nếu còn mở, hoặc tạo lô "trả hàng"). Ghi `kc_returns` + items + inventory tx `RETURN` + nếu web order → tạo refund qua WC API + restore stock. Idempotency dùng chung key gốc (phòng double hoàn).

## P. Khách hàng

**Thiết kế**: đọc từ WC customers API; lịch sử mua = orders → tổng đơn, tổng tiền. POS có thể chọn/tạo khách hàng (WC customer). Nếu website dùng khách vãng lai → nhóm "Khách lẻ".

## Q. Khuyến mãi / giảm giá

- Web: dùng **Coupon của WooCommerce** (rule engine có sẵn, không tự tạo hệ mới). Plugin endpoints CRUD coupon + `validate` cho POS.
- POS: giảm giá **theo từng dòng** hoặc **toàn hóa đơn** với mức tối đa theo role/device (setting `kc_max_total_discount_pct`, `kc_max_line_discount_pct`); trên mức buộc xác nhận PIN manager. Ghi lý do.
- Kết hợp coupon + mã giảm manual thủ công → cần quy định ưu tiên (chưa quyết định: có cho POS dùng coupon website không).

## R. Báo cáo

**Yêu cầu**: doanh thu ngày/tháng/năm/tùy chọn; giá vốn; lợi nhuận; số đơn; số lượng bán; bán chạy/chậm; tồn kho; nhập/xuất; sắp hết hàng; sắp hết hạn; đã hết hạn. Lợi nhuận dựa trên giá vốn thực tế (lô). Phân biệt doanh thu / giá vốn / lợi nhuận gộp.

**Thiết kế**: `12_REPORTING.md`.
- **Doanh thu** = tổng giá trị bán (sau giảm giá) của POS + web orders trong kỳ (loại trừ hủy/hoàn).
- **Giá vốn (COGS)** = tổng `lot_allocation.cost` (FEFO) khi bán + web sale allocate; fallback `_kc_cost` khi thiếu lô.
- **Lợi nhuận gộp = Doanh thu − COGS**. Không bao giờ gọi doanh thu là lợi nhuận.
- Group by day/month/year; endpoint `reports/summary`, `reports/sales`, `reports/profit`, `reports/products`, `reports/inventory`.

## S. Nhân viên / phân quyền

**Thiết kế**: 3 role mặc định `kc_admin` (toàn quyền), `kc_manager` (product/kho/đơn/báo cáo/POS), `kc_staff` (POS, scan, in, xem được phép). Permission grid chi tiết: `15_PERMISSION_SYSTEM.md`. Nhân viên = WP user (role custom `kc_staff` + mapping `kc_staff` table), check ở plugin layer (không phụ thuộc +WP Capabilities thô).

## T. Nhật ký hoạt động

**Thiết kế**: `kc_activity_log`: staff_id, action, object_type/id, before/after JSON, IP, device_id, time. Ghi trong transaction với nghiệp vụ liên quan (ai sửa giá, ai bán, ai điều chỉnh kho). **Không log token/password**.

## U. Thông báo

**Thiết kế**: bảng `kc_notifications` (type, severity, nội dung, link/object, read). Nguồn: đơn mới, sắp hết hàng, sắp hết hạn, hết hạn, lỗi đồng bộ. Push (FCM) để mở rộng phase sau.

## V. Offline

**Yêu cầu cấm**: không đơn giản "offline bán, online đẩy hết". Phải phân tích conflict/race và chiến lược đồng bộ.

**Thiết kế**: `13_OFFLINE_SYNC.md`.
- Mặc định: offline = **read-only cache** (sản phẩm, giá, tồn cho phép của role, danh mục; hết hạn cache theo policy).
- Offline POS = **tùy chọn bật theo device** (quyền admin): device được ấn định **hạn mức "offline buffer stock"** mỗi product/variation; khi offline bán, trừ trong buffer local; lúc đồng bộ, đẩy outbox theo thứ tự + idempotency; server kiểm tra stock thực tế; nếu thiếu → conflict, báo admin, không im lặng mất mát.
- Outbox `kc_sync_outbox` lưu UUID + payload + attempts + error; dùng **idempotency** để server tránh xử lý 2 lần nếu cùng 1 giao dịch bị gửi lại.
- Không bán quá buffer local; nhân viên không bypass (chặn tại UI + server).

## W. Bảo mật

**Thiết kế**: `08_AUTHENTICATION_SECURITY.md`. HTTPS bắt buộc; JWT access + refresh token server-side; permission check toàn bộ endpoint; validate + sanitize; nonce/CSRF không áp dụng (REST token-based) nhưng cần CORS/ORIGIN check; rate limiting (`kc_rate_limit` qua transients); secret/credentials trong `wp-config` hoặc settings encrypted, không log.

## X. Plugin

**Yêu cầu**: tương thích WP hiện tại / WC 10.4.4 / PHP 8.1; activation/deactivation/uninstall an toàn; migration/versioning; không xóa data khi deactivate; không sửa core; hook/filter chuẩn; custom tables `wp_kc_*`; namespace `kc/v1`.

**Thiết kế**: `06_WORDPRESS_PLUGIN_ARCHITECTURE.md`.

## Y. API

**Yêu cầu**: contract rõ ràng, endpoint không được mặc định hoàn thiện, cần method/URL/request/response/auth/permission/validation/error code/pagination/filter/sort/transaction/idempotency.

**Thiết kế**: `05_API_SPECIFICATION.md` — BLS (`base layout`): error envelope, meta pagination, consistency, idempotency header.

## Z. Flutter architecture

**Thiết kế**: `07_FLUTTER_ARCHITECTURE.md` — Riverpod + GoRouter + Dio + repository/use-case, Hive/Drift local, secure storage, mobile_scanner, image_picker, printer integration, offline outbox, DI.

## AA. Giao diện

**Đề xuất navigation đánh giá lại**: giữ 5 tab nhưng đổi thứ tự theo tần suất: **POS (center, nổi bật) · Kho · Đơn hàng · Dashboard · Thêm**. Lý do: POS là việc nhiều nhất với nhân viên; Dashboard là màn hình "mở app để xem" của quản lý. Nút quét nhanh (Scan) nổi bật trong POS. Xem `07_FLUTTER_ARCHITECTURE.md` (mục giao diện).

## AB. Database

**Thiết kế**: `04_DATABASE_DESIGN.md`.

## AC. Tính nhất quán dữ liệu

**Yêu cầu**: transaction, atomic, rollback, concurrency, race, duplicate request, retry, idempotency, timeout, mất mạng, thất bại giữa chừng. POS tránh: trừ kho mà chưa hóa đơn / hóa đơn mà chưa trừ kho / trừ 2 lần.

**Thiết kế**: `09_INVENTORY_AND_STOCK_FLOW.md` + `10_POS_FLOW.md` + `05_API_SPECIFICATION.md` (section tin cậy).

## AD. Backup / Recovery

**Thiết kế**: `17_DEPLOYMENT_PLAN.md`. Backup DB + plugin + media; cơ chế upngrấp migration (bảng `kc_db_version` trong options); rollback plan từng phase.

## AE. Khả năng mở rộng

**Thiết kế**: thiết kế đa cửa hàng/đa kho (cột `warehouse_id`, `branch_id` nullable sẵn từ đầu nhưng mặc định 1 branch), đa máy POS (device_id), đa nhân viên, membership/points (bảng để trống extension), báo cáo nâng cao, máy quét chuyên dụng (HID keyboard → chế độ "scan input" trong app), đồng bộ nhiều thiết bị.

---

## 3. Mâu thuẫn / xung đột phát hiện

| # | Vấn đề | Xử lý đề xuất |
|---|---|---|
| X1 | **Offline POS vs race condition tồn kho** (V + N): offline bán đồng thời web bán → khi online chia số tồn nào? | Offline dùng **buffer hạn mức** + outbox idempotent + server kiểm stock thực tế khi sync; vẫn có thể thừa/thiếu cực nhỏ → ghi conflict, admin xử lý. Không chọn phương án "đẩy hết". |
| X2 | **Barcode duy nhất toàn hệ thống** (D + B): 1 barcode 1 sản phẩm/1 variation. | Unique constraint `kc_barcodes.barcode`; khi scan trùng hoặc lỗi format → báo cụ thể. |
| X3 | **"Không tạo database sản phẩm riêng" vs lô hàng phải có SL còn** (E): lô là dữ liệu bên ngoài WC. | Không tạo sản phẩm riêng; chỉ tạo bảng nghiệp vụ lô; tồn tổng luôn = WC stock; lô là phân lớp chi tiết của tồn. |
| X4 | **Nhiều chi nhánh** (AE) vs **1 stock WC**: WC stock là tổng kho duy nhất. | Khóa mở rộng `warehouse_id` từ đầu; tuy nhiên chưa hỗ trợ "kho riêng chi nhánh" vì WC không có; nếu cần → sau phase (plugin có thể tách bằng bảng stock theo kho, phải thiết kế riêng). |
| X5 | **Nhân viên giảm giá/hoàn tiền không kiểm soát** (S/O/Q) | Mức max % theo role + PIN manager + audit log. |
| X6 | **Đồng bộ lô với web sale** (E + N): WC trừ stock nhưng không biết lô. | Hook `woocommerce_reduce_stock_levels` + lot allocation FEFO best-effort, phần sai lệch ghi `lot_id = NULL` (unassigned), báo admin. |
| X7 | **Báo cáo lợi nhuận thiếu giá vốn lịch sử** (R): đơn web cũ không có lot. | Khai báo giá vốn `_kc_cost` tối thiểu; báo cáo ghi chú "theo giá vốn fallback". |
| X8 | **VAT** (R/M): giá đã/từng gồm thuế? | Cần chủ dự án xác nhận; thiết kế tách biệt doanh thu thuần / gồm VAT theo setting. |
| X9 | **Timeout/mất mạng giữa chừng** (AC): POST có thể đã commit mà client tưởng fail. | Idempotency + client retry cùng key; server trả phản hồi cũ nếu cùng key (RFC 7807 style). |

## 4. Thiếu sót / cần chủ dự án bổ sung

| # | Thiếu | Ảnh hưởng |
|---|---|---|
| GD1 | Máy in nhiệt model/nhãn hiệu, 58 hay 80mm, có hỗ trợ ESC/POS không | Thiết kế in / nhận diện printer |
| GD2 | Có dùng VietQR tại POS không + ngân hàng | Endpoint tạo QR cần config ngân hàng |
| GD3 | Giá bán/giá nhập của shop gồm VAT 10% chưa | Công thức lợi nhuận |
| GD4 | Có chặn bán SP hết hạn | Kiểm tra trong POS/server |
| GD5 | Nhân viên đăng nhập riêng hay dùng số điện thoại + PIN? Bắt buộc đăng nhập mỗi ca? | UX POS ca làm việc |
| GD6 | Số lượng SKU/sản phẩm hiện tại khoảng bao nhiêu | Kích thước cache offline, tunning |
| GD7 | Ai tạo tài khoản Python số liệu khởi tạo? Cần nhập "tồn đầu kỳ" (INITIAL) bao nhiêu SP | Nhập khởi tạo Phase 5 |
| GD8 | Đơn order hiện tại của website dùng trạng thái/bỏ stock... | Mapping trạng thái app |
| GD9 | Muốn quét qua **máy quét cầm tay HID** (như bàn phím) không? | Thêm chế độ nhận input |
| GD10 | Cần barcode **printer 58mm/40x20 nhãn** để in tem hàng? | 14_PRINTER |
| GD11 | Có cần đăng nhập bằng OTP/Nhà cung cấp SMS? | Auth |

## 5. Quyết định đã chốt (từ tài liệu này)

| Mã | Quyết định |
|---|---|
| RQ-01 | WooCommerce = nguồn dữ liệu chính; custom tables chỉ cho nghiệp vụ mở rộng. |
| RQ-02 | Stock single source = WC `stock_quantity`; mọi thay đổi ghi inventory tx. |
| RQ-03 | Lô + COGS FEFO; fallback `_kc_cost`. |
| RQ-04 | POS realtime bắt buộc online trừ khi bật offline-buffer. |
| RQ-05 | Idempotency bắt buộc cho MỌI mutation quan trọng (POS sale, receiving, return, adjust, count confirm). |
| RQ-06 | Barcode: unique, per product/variation, lookup index `kc_barcodes`. |
| RQ-07 | Deactivate không xóa; uninstall có xác nhận. |
| RQ-08 | Permission check server-side mọi endpoint; role 3 cấp. |

## 6. Tài liệu liên quan

[01_PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md) · [04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md)