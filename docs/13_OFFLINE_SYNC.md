# 13 · Offline & Đồng Bộ (Offline Sync)

## 1. Mục đích

Chiến lược offline cho app: cache đọc, hàng đợi giao dịch tạm (POS offline tùy chọn), cơ chế đồng bộ khi online, và PHÂN TÍCH conflict/race khi offline — đúng yêu cầu V: **không đơn giản "offline bán rồi online đẩy hết"**.

## 2. Phạm vi

Cơ chế offline ở app + server (outbox, sync queue, conflict), chính sách buffer. Không gồm stock race chung (đã 09).

## 3. Nguyên tắc

1. **Nguồn dữ liệu = server**. Cache local chỉ để: đọc nhanh, xem offline, tạo giao dịch offline trong giới hạn.
2. Offline **read-only** là mặc định mọi role. Offline POS là **tính năng bật riêng theo thiết bị** (admin cho phép) vì nó chứa rủi ro stock.
3. Mọi giao dịch offline được ghi outbox kèm `uuid` + `Idempotency-Key`; khi online **replay theo thứ tự** — server thực thi lại đầy đủ transaction với guard stock thật.
4. **Không luông mất mát**: conflict luôn được ghi, hiển thị Sync Center cho admin quyết định. Không tự hủy im lặng.
5. Buffer offline được khai **theo mặt hàng cho từng thiết bị** (bảng `kc_device_stock_buffers`: product_id/variation_id × device_id, `max_qty`, `used_qty`), mặc định **OFF / read-only** (D-25). Nếu server báo thiếu khi sync → không tự sửa, để admin.

## 4. Các chế độ kết nối

| Chế độ | Hành vi |
|---|---|
| Online | gọi API bình thường, refresh cache |
| Offline (read-only) | toàn màn hình dùng cache (đánh dấu dữ liệu cũ), mutation bị khóa (ẩn/hiện rõ) |
| Offline POS (device enable) | catalog cache + POS sale → outbox; nhập kho/điều chỉnh/kiểm kho vẫn khóa |

## 5. Cache đọc (read-only offline)

- Box: `settings` (TTL dài), `categories`, `products` (id, name, price, stock, barcode, image thumb — chỉ fields cần POS), `lots/expiry` (đọc), `customers` (tìm local tối đa 500 gần nhất).
- Cập nhật: khi online chạy delta `GET /products?updated_after={cursor}` (server trả `updated_after` tương ứng) — chạy thu gọn trong vòng lặp per_page=100.
- **Nhãn thời gian cache**: mọi màn hiển thị dữ liệu offline đính "cập nhật lúc hh:mm" để nhân viên biết.
- Mặc định: stock cache có thể cũ → **POS online vẫn luôn đối chiếu server khi checkout** (gửi stock via cart? server chốt guard khi checkout; hiển thị an toàn).

## 6. Outbox queue (POS offline)

- Khi checkout offline:
  1. App chọn sản phẩm (từ cache), giỏ; **kiểm tra local**: qty ≤ (stock cache) và ≤ hạn mức `kc_device_stock_buffers` **của mặt hàng đó × thiết bị này** (tổng qty outbox pending + qty trong giỏ không vượt `max_qty`).
  2. Ghi `pos_outbox` local: `uuid`, `payload` (y hệt body POST /pos/sales + idempotency_key = uuid), `session_id` (session offline local hoặc "pending"), `created_at`, `status=pending`.
  3. Hiển thị "Đã lưu — chờ đồng bộ". Biên lai tạm local (QR/dạng xem được).
  4. Trừ **buffer local** (stock cache − qty) — theo dõi riêng `kc_devices` server cũng nhớ quota; client trình bày hạn mức rõ.
- Khi online: `SyncEngine` drain (FIFO theo created_at) qua `POST /sync/queue` (batch) — server từng item: idempotency check → `process_pos_sale()` đầy đủ (guard stock thật).
- Kết quả per item:
  - `200/201` synced → xóa outbox, nhận pos_tx_id/receipt về.
  - `409 INSUFFICIENT_STOCK` → `kc_sync_conflicts` (uuid, code) + app đánh dấu item conflict, báo admin.
  - 4xx vĩnh viễn → conflict ghi lỗi; 5xx/network → retry sau (attempts + exponential backoff, max N → "failed" cảnh báo).

## 7. Phân tích conflict / race (offline)

| Kịch bản | Hệ quả | Quyết định thiết kế |
|---|---|---|
| A bán offline 5 SP X, web bán X trong lúc đó | khi A sync: X còn 2 → server chỉ chấp 2, dư 3 conflict | Ghi conflict, admin xử lý (soi lô, hoàn khách hoặc điều chỉnh) |
| 2 device offline cùng 1 GIỎ | giao dịch là 2 đơn riêng; hết hàng → 1 thắng 1 conflict | như trên; không merge tự động |
| Đơn offline nhưng khách chuyển sang tiền mặt/khác | không — chỉ ghi sau khi thanh toán | bán offline phải hoàn tất thanh toán trước khi đẩy |
| Sync 2 lần cùng 1 uuid | idempotency server trả response cũ | an toàn |
| Outbox hết hạn (device mất) | server giữ conflicts & cảnh báo | hệ thống ghi nhận dữ liệu lơ lửng |
| Kíp bán lúc offline, ca đóng nhưng không sync | ca đóng local; sync Ca-giao sau → session server tạo | sequence server quyết định session_id |

## 8. Tính nhất quán buffer (server-side quota)

- Quota buffer lưu **per (product/variation × device)** trong `kc_device_stock_buffers` (`max_qty`, `used_qty`) — không phải 1 con số tổng cho thiết bị. Admin khai theo từng mặt hàng (hoặc import hàng loạt); server validate khi bật: không quá X% tổng stock của mặt hàng.
- App tính quota còn lại = `max_qty` − (Σ outbox pending của mặt hàng trên thiết bị). Chặn tại UI khi vượt (thông báo rõ "vượt hạn mức offline cho mặt hàng này").
- `used_qty` tăng khi tạo outbox và **được giảm khi sync thành công**.
- Mặc định `max_qty=0` → thiết bị **read-only** cho tới khi admin cấu hình. Server khi sync **không trừ dựa trên buffer** — chỉ dùng guard stock thật; buffer chỉ giới hạn rủi ro lúc offline.

## 9. Sync Center (admin)

- Màn hình: danh sách outbox/conflict của thiết bị; trạng thái (pending/synced/failed/conflict).
- Thao tác admin: xem, retry, discard (kèm lý do), điều chỉnh kho cho đúng thực tế sau whenêu trường hợp bị chặn.
- Thông báo severity khi có conflict mới.

## 10. Không làm (anti-patterns bị loại)

- ❌ "Bán hết, online đẩy tất cả" (có thể trừ quá stock thật / bán hàng đã hết) → dùng buffer + guard + conflict.
- ❌ Cache như "database phụ" có thể ghi mọi thứ (chỉ cho phép POS offline trong buffer).
- ❌ Tự đổi stock offline local rồi gửi "diff" — server phải tự trừ lại từ đầu (replay), không tin diff.

## 11. Chưa quyết định

- Bật offline POS không: **mặc định KHÔNG bật**; buffer mặc định `max_qty=0` (read-only); admin chủ động cấu hình `kc_device_stock_buffers` cho từng mặt hàng/thiết bị khi quyết định bật (D-25).
- Có nên tải cache toàn catalog xuống app (SP ít → được; SP > 5000 → cân nhắc chỉ tải sản phẩm thường bán).
- Thời gian đồng bộ tự động: realtime khi online hoặc chạy nền 15 phút.

## 12. Phụ thuộc

App: Hive outbox, SyncEngine, connectivity; Server: `/sync/queue`, tx idempotency, `kc_sync_outbox/conflicts`, StockManager.

## 13. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Nhân viên lợi dụng offline bán vô hạn | buffer server-side + chỉ bật device + audit log |
| Conflict nhiều gây thêm việc | cảnh báo sớm khi offline; quy định phổ biến |
| Cache cũ gây hiểu nhầm giá | luôn label "dữ liệu cũ"; POS online check server khi checkout |
| Outbox lớn đẩy chậm | batching, per_page=50 item, retry backoff |

## 14. Tài liệu liên quan

[07_FLUTTER_ARCHITECTURE](07_FLUTTER_ARCHITECTURE.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [10_POS_FLOW](10_POS_FLOW.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md)