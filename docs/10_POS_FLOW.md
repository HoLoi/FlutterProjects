# 10 · POS Flow (Bán Hàng Tại Cửa Hàng)

## 1. Mục đích

Đặc tả luồng POS: từ mở ca → giỏ hàng → thanh toán → trừ kho → ORDER + giao dịch + biên lai, và bảo vệ tình huống: trừ kho mà hỏng hóa đơn, hóa đơn mà không trừ kho, request gửi 2 lần.

## 2. Phạm vi

POS realtime online (chính); ghi chú cho offline POS (13_OFFLINE). Không gồm print chi tiết (14).

## 3. Nguyên tắc an toàn (không dựa hoàn toàn vào rollback MySQL)

WC CRUD, hooks, cache, plugin bên thứ ba có side-effect **không phải lúc nào cũng rollback sạch** khi MySQL transaction bị hủy. Vì vậy POS dùng **logical unit of work + trạng thái trung gian + compensation/recovery** (D-23):

1. **Trước khi trừ kho**: chắc chắn tạo được giao dịch — bắt đầu bằng trạng thái `pending`, khi chạy tốt dần lên `processing` → `completed`.
2. **Trái kho với giao dịch**: mọi bước (stock → order → pos_tx → receipt) nằm chung logical unit; giữa chừng lỗi → `void/needs_review` + **compensation/reversal** hoàn nguyên stock đã trừ.
3. **Cấm gửi 2 lần trừ kho 2 lần** → `Idempotency-Key` toàn hành trình POS checkout.
4. **Không bao giờ mất giao dịch**: nếu compensation không tự hoàn tất → `kc_audit_log` + recovery job retry; admin thấy trạng thái `needs_review` thay vì dữ liệu "biến mất" im lặng.

## 4. Luồng chi tiết (realtime)

### 4.1 Trước bán
- `POST /pos/sessions` (mở ca) — mỗi ca gắn `staff_id`, `device_id`, `opening_cash`. POS locking: 1 staff POS chỉ 1 ca mở tại 1 thời điểm.
- Configure: `POST /pos/payment-methods` trong settings (cash, bank_transfer, vietqr...).

### 4.2 Giỏ hàng (client-side)
- App tải `GET /products?stock_status=instock&include_variations=1` → cache; scan/tìm → thêm vào `PosCartController` (địa phương, không ghi server).
- Mỗi line: product/variation, qty, unit_price (lấy giá hiện tại server — refresh nếu dữ liệu cache cũ), line_discount.

### 4.3 Checkout (server) — logical unit of work

```
POST /pos/sales   (Authorization + Idempotency-Key)
  middleware: auth → perm pos.sale → rate limit → idempotency (replay? return cũ)
  → validate payload:
      - session mở? (else 409 KC_POS_SESSION_CLOSED)
      - item thuộc product/variation tồn tại, active
      - qty > 0; price ≥ 0; discount ≤ max theo role (KC_DISCOUNT_EXCEEDED)
      - payment_method có trong kc_payment_methods.enabled
      - cash_received ≥ total khi payment_method=cash (cho change)
  → 1) tạo kc_pos_transactions (status 'pending', payload_items JSON) — COMMIT điểm này
        // trạng thái trung gian để recovery biết "đang làm dở"
  → BEGIN TRANSACTION (DB bước)
      2) với mỗi item (sắp xếp theo id product đơn điều):
           StockManager::change(-qty, POS_SALE, pos_tx, lot FEFO allocate)
           (guard; thiếu → ném KC_INSUFFICIENT_STOCK)
           ghi kc_pos_transaction_items (kèm lot_allocation JSON + cost_total)
      3) tạo WooCommerce order (HPOS qua wc_create_order):
           type='shop_order'; status 'wc-completed' (POS đã bán)
           add product items (kèm variation); tax theo WC
           meta _kc_pos_tx_id, _kc_receipt_code, _kc_staff, _kc_payment_state
           (đảm bảo app/web thấy đơn — phục vụ doanh thu chung)
      4) insert kc_receipts (snapshot payload để in lại)
      5) activity log
      → UPDATE kc_pos_transactions SET status='completed' WHERE id=? AND status IN ('pending','processing')
  → COMMIT
  → response 201 { pos_tx_id, pos_tx_code, order_id, receipt_id, total, change,
                   lots: [ {product, variation, qty, lot_id, cost} ] }

→ on catch giữa chừng (validation/stock/DB/WC):
    - CẢI THIỆN 1 (rollback): rollback DB transaction đang mở → mọi thứ trong DB quay lại (stock, items, order...).
      NHƯNG side-effect ngoài DB của WC/hooks/plugin có thể KHÔNG quay lại.
    - CẢI THIỆN 2 (compensation, bắt buộc khi side-effect không chắc sạch):
      gọi kc_pos_transactions SET status='needs_review' + ghi kc_audit_log
      → compensation job chạy: hoàn trả stock nào đã trừ trong bước 2 nhưng transaction không completed
         (đối chiếu qua kc_inventory_transactions ref=pos_tx_id chưa hoàn tất)
      → admin dashboard hiện 'needs_review' cho tới khi xử lý/chốt.
    - Không để trạng thái 'processing' kẹt mãi: recovery job (cron) quét
      pos_transactions rơi vào 'processing' > N phút → re-check & hoàn tất hoặc chuyển needs_review.
```

### 4.4 Trạng thái trung gian của `kc_pos_transactions`

| Trạng thái | Ý nghĩa | Tác động stock |
|---|---|---|
| `pending` | vừa tạo, chưa trừ | chưa trừ |
| `processing` | đang thực thi steps | có thể đã trừ một phần |
| `completed` | thành công, đã trừ đủ | stock đã giảm |
| `needs_review` | hỏng giữa chừng, chờ admin/compensation | phải rà — compensation job sẽ cân |
| `void` | hủy có chủ đích (đã compensation) | đã hoàn |
| `refunded` | trả hàng/hoàn tiền sau completed | stock về theo return |

> Nếu `payment_method = vietqr` & chờ thanh toán: tạo order status `pending`; **chỉ trừ kho tại điểm "đã nhận thanh toán"** (đơn giản nhất: POS chỉ checkout sau khi đã thấy tiền; nếu ngân hàng chưa về → giữ giỏ phía client, không gửi checkout). VietQR tự động xác nhận (webhook ngân hàng) để tính cho Phase sau.

### 4.4 Idempotency tại POS (double-tap / mạng)
- App sinh key `uuid` TRƯỚC khi gọi checkout; giữ trong bộ nhớ + Hive; nếu response mất (timeout) → nhấn lại → gửi LẠI cùng key → server replay response cũ (hoặc báo status đã tồn tại).
- Giao diện nút "Thanh toán" disabled khi đang xử lý + hiển thị "Đang lưu..." để tránh tự gửi.

## 5. Giá vốn & lợi nhuận trong POS

- `lot_allocation` = FEFO (11_EXPIRY): lô open còn hàng, sort hsd asc (cùng ngày → FIFO), trừ khớp qty.
- `cost_total` (COGS) = Σ(lot_qty × lot.cost_unit); nếu không có lô → dùng `_kc_cost` × qty, đánh dấu `cost_method: "fallback"`.
- Transaction ghi sẵn để báo cáo/đối soát không cần tính lại.

## 6. Trả hàng tại POS (O)

- `POST /returns` với `source: pos`, `pos_tx_id`, items (tối đa ≤ qty đã mua trừ lượt trả trước — check trong tx từ kc_return_items + pos tx items).
- restocked=true → `StockManager::change(+qty, RETURN)` về lot gốc (nếu lot còn open & khớp sản phẩm) hoặc lot unassigned (lot_id NULL) — admin/chủ quyết.
- Hoàn tiền: tạo `kc_return_items` refund_amount + nếu cần WC refund (khi nguồn pos có order → update WC order total? Chỉ tạo WC refund nếu đơn web; POS refund không tạo WC refund object, chỉ ghi kc_returns + cập nhật total_pos of session) — tránh double.
- Idempotency key dùng luôn để chống double hoàn.

## 7. Ca làm việc (session) & tiền mặt

- Mở ca: `opening_cash`; mỗi giao dịch gắn session_id.
- Đóng ca: `closing_cash` (đếm thực), `expected_cash` = opening + Σ(cash sales) − Σ(cash refunds). `cash_diff` = closing − expected. Cảnh báo nếu diff ≠ 0; chỉ admin/manager chốt ca (có ghi note).
- Báo cáo theo ca (per session) cho staff summary hàng ngày.

## 8. Các màn hình POS (app)

- **POS home**: grid product (tab category) + search + scan FAB + cart drawer dọc (amount top, nút thanh toán nổi). Desktop/tablet: 2-column cart.
- **Pay screen**: tổng tiền, discount, payment method picker, cash received keypad (auto change), VietQR QR (nếu có), xác nhận.
- **Success screen**: receipt preview → in ngay / in lại / share PDF.
- **Shift screen**: mở/đóng ca, tổng doanh thu ca, chênh lệch.

## 9. Checklist an toàn khi code (Phase 6)

- [ ] Sinh test cho: (1) idempotency replay không trừ 2 lần; (2) WC order / HPOS fail giữa chừng → compensation hoàn stock, pos_tx `needs_review` + audit; (3) recovery job chốt/hoàn tất trạng thái `processing` kẹt.
- [ ] Test 2 thiết bị con-con cùng 1 SP cuối trong stock → chỉ 1 device thắng.
- [ ] Test POS khi WC order HPOS chậm/lỗi → stock không bị trừ "mất" (được hoàn qua compensation hoặc nằm trong `needs_review` rõ ràng).
- [ ] Cash đóng ca diff sai lệch đúng mức.

## 10. Chưa quyết định

- VietQR: xác nhận thanh toán tự động thế nào (webhook ngân hàng) — cần provider.
- Có dùng giỏ "hold" (tạm giữ hóa đơn) hay không.
- Tip (tiền bo) — không yêu cầu.

## 11. Phụ thuộc

Plugin: Pos service, StockManager, FEFO, Receipt, ActivityLog, Session; WC: order creation (HPOS). App: PosCartController, printer, scanner.

## 12. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| HPOS order fail giữa chừng sau khi trừ stock | compensation/reversal + pos_tx `needs_review` + audit; recovery job |
| Side-effect WC/hook/plugin khác không rollback sạch | logical unit + states + compensation (D-23), không dựa rollback MySQL |
| Khách xác nhận chưa thanh toán VietQR | giữ giỏ cho tới khi xác nhận tiền; cảnh báo |
| Double-tap | idempotency + UI lock |
| Cash thiếu/đầy | mở/đóng ca + count + diff |

## 13. Tài liệu liên quan

[05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md) · [11_EXPIRY_AND_LOT_MANAGEMENT](11_EXPIRY_AND_LOT_MANAGEMENT.md) · [14_PRINTER_BARCODE](14_PRINTER_BARCODE.md) · [13_OFFLINE_SYNC](13_OFFLINE_SYNC.md)