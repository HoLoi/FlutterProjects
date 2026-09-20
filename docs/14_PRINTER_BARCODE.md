# 14 · Printer & Barcode

## 1. Mục đích

Thiết kế in hóa đơn/biên lai nhiệt (58/80mm, Bluetooth), xuất biên lai PDF/share, và barcode (in nhãn, quét, encode).

## 2. Phạm vi

Module máy in (app) + dữ liệu biên lai (server `kc_receipts`) + barcode trong sản phẩm/quét.

## 3. Máy in — quyết định

| Mã | Quyết định | Lý do |
|---|---|---|
| PR-01 | Ưu tiên **Bluetooth thermal** qua ESC/POS | phổ biến giá rẻ cho shop nhỏ; không cần server |
| PR-02 | Hỗ trợ 2 width: **58mm** (32 chars/line, font A) và **80mm** (42–48 chars/line) | đúng dòng máy phổ biến |
| PR-03 | Encode ESC/POS **tự viết** (không phụ thuộc hãng cụ thể) | linh hoạt mọi máy EPSON/Xprinter/khuôn com khác |
| PR-04 | Luôn in từ **snapshot payload** biên lai gốc (`kc_receipts`) | in lại khớp giá lúc bán, không phụ thuộc dữ liệu hiện tại |
| PR-05 | **PDF fallback** + share khi không có máy in | M |

## 4. Kiến trúc in (app)

```
[POS success / hoá đơn detail]
   → ReceiptController (load kc_receipts.payload hoặc local tạm khi offline)
   → ThermalPayloadBuilder (build text + ESC/POS commands theo width & dpi)
   → PrinterService
        ├─ Bluetooth (flutter_blue_plus): tìm, pair, connect, print bytes, disconnect
        └─ PDF fallback (pdf pkg): render → save temp → share/print via platform
```

- Cấu hình máy in: lưu per device (tên Bluetooth, width) trong `settings` box.
- Trạng thái: chưa kết nối / kết nối / in xong / lỗi (hiển thị rõ, cho retry).
- Đếm print: `POST /receipts/{id}/print` tăng `printed_count`, `last_printed_at`.

## 5. Layout biên lai (template chuẩn)

```
      MỸ PHẨM KIM CƯƠNG
       123 Đường ABC, ...
      ĐT: 09xx ... · MST: ...
────────────────────────────
  HD-260920-0001
  20/09/2026 18:24
  Thu ngân: Nhân viên A
────────────────────────────
  Serum ABC 50ml       1
     x 220.000       220.000
  Kem Dưỡng Nhật 30ml  2
     x 180.000        360.000
────────────────────────────
  Tạm tính          580.000
  Giảm giá           -20.000
  TỔNG              560.000
  Tiền mặt           600.000
  Trả lại             40.000
────────────────────────────
  Thanh toán: Tiền mặt
  Mã GD: HD-260920-0001
────────────────────────────
   Cảm ơn quý khách!
   Hẹn gặp lại ♥
```

- Nội dung gồm đủ: tên shop, địa chỉ, SĐT, mã hóa đơn, ngày giờ, từng dòng (SP + variation attribute như "50ml"), SL, giá, giảm giá, tổng, phương thức thanh toán, tiền trả/trả lại, cảm ơn.
- Ưu tiên ký tự ASCII full-width nếu font máy hỗ trợ tiếng Việt (phông CP437/CP850); nếu máy không hỗ trợ → fallback ASCII không dấu (cấu hình).

## 6. Barcode

### 6.1 Quét (app)
- `mobile_scanner`: các symbology EAN-13, EAN-8, UPC-A, UPC-E, Code128, Code39, QR.
- Luồng scan theo ngữ cảnh: POS (add to cart), receiving (add line), products (mở detail), returns (tìm hóa đơn).
- Barcode không tìm thấy → 404 unlisted → nhảy màn "Tạo sản phẩm" prefill.
- HID scanner (máy quét cầm tay như bàn phím): app nhận đầu vào `\n` kết thúc → xử lý như scan. (tùy chọn Phase sau)

### 6.2 Lưu trữ & uniqueness
- Source: postmeta (`_ean` nếu WC native; ngược lại `_kc_barcode`) + `kc_barcodes` (unique index). Nếu trùng → `409 KC_DUPLICATE`.

### 6.3 In nhãn barcode (tùy chọn Phase sau)
- Layout nhãn 40×30mm / 50×30mm: tên SP, giá, barcode (Code128), optional price.
- In qua cùng Bluetooth printer (network Y nhiệt hỗ trợ label): build ESC/POS với `GS k` (GS s for scale) — kiểm chứng hãng máy trước khi bật.
- QR label dùng cho sản phẩm đang triển khai (tím mã hóa định dạng `KC|{barcode}`).

## 7. API liên quan

- `GET /receipts/{id}` · `POST /receipts/{id}/print`
- `GET /products/by-barcode/{code}` · `GET /inventory/expiry-alerts` (với barcode để in nhãn lô khi đổi)
- `POST /uploads` (dành label asset)

## 8. Format/encoding quyết định

- Biên lai gửi lướt: `payload` JSON server giữ nguyên giá trị gốc; app chỉ render.
- ESC/POS commands cần: init, select font, bold, size, cuts, feed, drawer open (tuỳ).
- Nếu máy in USB/LAN → bỏ qua v1 (chỉ Bluetooth + PDF), mở rộng sau.

## 9. Chưa quyết định

- Chính xác hãng/model máy in của cửa hàng (cần khảo sát — để hỗ trợ/ESC bg đúng).
- Có cần máy in nhãn riêng (hoặc in qua cùng máy).
- Mã in tiếng Việt không dấu hay có dấu phụ thuộc firmware máy.

## 10. Phụ thuộc

App: printer service, escpos encoder, pdf pkg, bluetooth pkg; Server: `kc_receipts`, `kc_payment_methods`.

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Máy in firmware khác nhận ESC lệnh lệch | encoder dùng lệnh chuẩn (ESC/POS basic), test với máy thật |
| Bluetooth pair nhà máy phức tạp | UI hướng dẫn pair OS trước; retry/error message rõ |
| Font tiếng Việt thiếu | auto-detect + fallback ASCII; cấu hình |
| In sai định giá (sale giữa chừng) | in từ snapshot |

## 12. Tài liệu liên quan

[07_FLUTTER_ARCHITECTURE](07_FLUTTER_ARCHITECTURE.md) · [10_POS_FLOW](10_POS_FLOW.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md)