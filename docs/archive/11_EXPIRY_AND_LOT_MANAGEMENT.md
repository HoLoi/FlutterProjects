# 11 · Expiry & Lot Management (Lô Hàng & Hạn Dùng)

## 1. Mục đích

Thiết kế quản lý lô hàng (NSX/HSD nullable), cảnh báo hạn dùng, chiến lược xuất lô FEFO, và sự nhất quán lô ↔ tồn WooCommerce.

## 2. Phạm vi

Nghiệp vụ E & F: cấu trúc lô, ledger, cảnh báo, chặn bán hết hạn, allocation khi bán.

## 3. Khái niệm

- **Lô (lot)**: một đợt hàng của 1 (product hoặc variation) với `lot_code`, `nsx` NULL, `hsd` NULL, `cost_unit` (giá nhập), `received_qty`, `remaining_qty`, `supplier`, `received_at`.
- **Một sản phẩm nhiều lô**; tổng `remaining_qty` lô mở của sản phẩm **bằng** WC stock (xem 09).
- **FEFO**: First-Expiry First-Out — ưu tiên bán lô gần HSD hoặc HSD sớm nhất; nếu các lô cùng giả hạn/không HSD → FIFO (nhập trước bán trước).

## 4. Bảng dữ liệu (chi tiết tại 04_DATABASE_DESIGN)

- `kc_lots` — lô; `kc_lot_ledger` — nhật ký in/out từng lô.
- **unassigned** = lượng tồn không gắn được lô (web sale thiếu thông tin, trả hàng chưa định lô, tồn đầu kỳ chưa khai lô). Biểu diễn bằng **`lot_id = NULL`** (cột BIGINT UNSIGNED nullable), **không dùng số `-1`** (D-24). Luôn cần nhắc admin gán lô.

## 5. Luồng nghiệp vụ

### 5.1 Nhập kho / tạo lô
- Via `POST /receivings`: mỗi line có `lot_code` (tùy chọn — auto fallback `LOT-{product_id}-{yyyymmdd}-{n}`), `nsx`, `hsd` (cả 2 nullable), `unit_cost`, `qty`.
- Transaction: tạo lot (open, remaining = qty) + `StockManager::change(+qty, RECEIVING, lot_id)` + ledger `RECEIVING +qty`.
- Dọn `_kc_cost` theo weighted-average cập nhật từ giá nhập (setting `cost_update_mode`: keep | weighted_avg | last).

### 5.2 Bán hàng → FEFO
- POS/Web sale: allocation theo FEFO:
  1. lọc lô `status=open AND remaining_qty>0 AND (hsd IS NULL OR hsd >= hôm nay)`
  2. sort: (a) hsd ASC (bỏ qua lô quá hạn trừ khi setting cho phép), (b) giữa same-hsd → received_at ASC (FIFO)
  3. trừ tuần tự cho đủ qty; ghi ledger `SALE −x`, giảm `remaining_qty`
  4. nếu qty còn lại chưa đủ trong các lô hợp lệ → phần thừa ghi **unassigned (`lot_id = NULL`)** (hoặc chặn bán tùy setting `kc_block_expired_sale` + stock guard).
- Web sale (hook): allocate FEFO những gì thực tế WC đã trừ (`woocommerce_reduce_stock_levels` mang [id => qty]).

### 5.3 Trả hàng
- Về lô gốc nếu lot còn open + khớp sản phẩm → `+qty` qua ledger; nếu không → **unassigned (`lot_id = NULL`)** (admin gán lại sau). `STOCK_COUNT/ADJUST` tương tự.

### 5.4 Cảnh báo & chặn bán
- Cấu hình `kc_expiry_alert_days` (default 30; chọn 7/15/30/60/90/tùy chọn).
- `GET /inventory/expiry-alerts?window=`:
  - `expiring`: `remaining_qty > 0 AND hsd BETWEEN today AND today+window`
  - `expired`: `remaining_qty > 0 AND hsd < today`
  - `no_hsd`: lô mở không có hsd (nhiều tháng không khai → nghi ngờ).
  - Mỗi dòng: lot_id, product, variation, lot_code, hsd, days_left, remaining_qty.
- **Chặn bán** hết hạn: mặc định có — POS/web-sale allocation bỏ lô expired; nếu setting `kc_block_expired_sale`=ON thì nếu mọi hàng chỉ còn expired → `KC_EXPIRED_STOCK` 409 (admin override: `x-approve-expired` + quyền). Chờ chủ shop xác nhận.
- Cron daily: sinh `kc_notifications` (expired / expiring / no_hsd) gửi admin+manager role.

### 5.5 Điều chỉnh theo lô
- `POST /inventory/adjust` với `lot_id` optional: nếu lot → sửa `remaining_qty` qua ledger; không lot → buffer.

## 6. Nhất quán lô ↔ stock (bảo trì)

- Batch verify (cron daily): với từng product/variation: `SUM(open lots.remaining) vs stock_quantity`; lệch → tạo notification "Lệch lô −X" + an error trong system health.
- Công cụ repair (admin): "Gán toàn bộ unassigned vào lô mới nhất" hoặc "Tạo lô chính xác cho phần lệch".

## 7. Giao diện app (sơ bộ)

- Tab "Kho/Hạn dùng": lọc (sắp hết hạn / hết hạn / chưa HSD), sort theo days_left, hiện số ngày còn (nền màu: <7 đỏ, <window vàng, > window xanh).
- Product detail: danh sách lô (lot_code, HSD, còn/đã nhập, giá nhập).
- Receiving: form line với NSX/HSD picker (date nullable — nút "Xoá ngày").

## 8. Chưa quyết định

- Đơn vị cảnh báo chung hay theo category/product.
- Xử lý "sản phẩm không có lô": có bắt buộc khai lô khi trả? (đề xuất: không bắt buộc, chỉ bắt buộc nếu `_manage_stock` và mặc định COGS per lot).
- Bán hàng hết hạn: chặn hay cho phép theo setting (cần shop quyết).

## 9. Phụ thuộc

Plugin: Lots repository, Fefo, StockManager, Notifications. App: expiry screens, receiving form, alert push.

## 10. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Lot lệch với stock (web sale unassigned) | balance check + repair tool + cảnh báo |
| HSD rỗng → báo lệch nhiều | nhóm no_hsd riêng, không tính vào alert hạn |
| FEFO phức tạp khi nhiều lô | thuật toán rõ + unit test cases |
| Bán lô hết hạn (lỗi nghiệp vụ) | chặn mặc định + override ghi log |

## 11. Tài liệu liên quan

[04_DATABASE_DESIGN](04_DATABASE_DESIGN.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [10_POS_FLOW](10_POS_FLOW.md) · [12_REPORTING](12_REPORTING.md)