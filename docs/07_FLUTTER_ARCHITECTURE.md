# 07 · Flutter Architecture

## 1. Mục đích

Kiến trúc cho app Android Flutter `mypham_kim_cuong_app`: tổ chức code, state management, routing, DI, API client, local storage/cache, offline, scanner, printer, upload, error handling — phục vụ app lớn, đẹp, nhanh.

## 2. Phạm vi

Thiết kế (chưa code). Nêu tên package gợi ý (sẽ kiểm tra phiên bản tương thích Flutter 3.47.5 tại PHASE 4 khi bắt đầu code).

## 3. Bối cảnh & quyết định nền

| Mã | Quyết định | Lý do |
|---|---|---|
| FL-01 | State: **Riverpod** (2.x) | type-safe, testable, scale tốt cho app lớn |
| FL-02 | Routing: **GoRouter** | deep link, guard auth, navigation lồng với BottomNav |
| FL-03 | API: **Dio** + interceptor (auth/refresh/retry/log) | mạnh, quen thuộc, dễ custom offline mxh |
| FL-04 | Local storage: **Hive/Drift** + **flutter_secure_storage** | cache nhanh, queue offline; token trong secure storage |
| FL-05 | DI: Riverpod providers (lazy) + `container` composition | không cần get_it — Riverpod đủ |
| FL-06 | Barcode: **mobile_scanner** | quét mã vạch + QR bằng camera |
| FL-07 | Printer: **ESC/POS encoder tự viết (dựa `esc_pos_utils`-style) + `flutter_blue_plus`/`flutter_bluetooth_basic`** | in 58/80mm nhiệt qua Bluetooth |
| FL-08 | PDF: `pdf` package (biên lai PDF, temp share) | xuất PDF/BIÊN LAI nếu cần |
| FL-09 | ảnh: `image_picker` (gallery) + `camera` (chụp) + upload Dio multipart | yêu cầu B |
| FL-10 | Notify: `flutter_local_notifications` + `firebase_messaging` (opt-in later) | U |
| FL-11 | Network: `connectivity_plus` | phát hiện online/offline để cache/queue |

## 4. Cấu trúc thư mục (feature-first)

```
lib/
├── main.dart / app_config.dart
├── bootstrap/
│   ├── app.dart                  ← ProviderScope + MaterialApp.router
│   └── navigation.dart           ← GoRouter routes + guards
├── core/
│   ├── api/          api_client.dart (Dio), interceptors, auth_provider, endpoints.dart
│   ├── storage/      secure_storage, hive boxes
│   ├── sync/         outbox, sync_engine, conflict_models
│   ├── printer/      escpos_encoder, bluetooth_connector, thermal_payload
│   ├── scanner/      scan_overlay, barcode_stream
│   ├── pdf/          receipt_pdf
│   ├── utils/        money, date_time (tz display), result, pagination
│   └── theme/        app_theme, design_tokens
├── features/
│   ├── auth/         data/ domain/ presentation/
│   ├── dashboard/
│   ├── products/
│   ├── pos/
│   ├── cart/         (state trong pos)
│   ├── inventory/    (stock, count, receive)
│   ├── lots/         (expiry)
│   ├── suppliers/
│   ├── orders/
│   ├── customers/
│   ├── reports/
│   ├── returns/
│   ├── notifications/
│   └── settings/
└── shared/           widgets (MoneyText, StatusChip, EmptyState, ErrorView...)
```

Mỗi feature: `data/` (repositories, DTO), `domain/` (models, usecases), `presentation/` (screens, controllers).

## 5. State management & DI

- **ProviderScope** ở gốc; providers chia: `apiClientProvider`, `authControllerProvider`, `cartProvider`, `productsProvider` (family theo filters), `syncProvider`, `printerProvider`.
- Auth state (AuthNotifier): token, staff, permissions; auto-refresh; on `401` → refresh → retry 1 lần → logout.
- Cart POS: `PosCartController` (StateNotifier) — local nhanh; submit qua `PosSaleUsecase` (idempotency key).

## 6. API client

- Base url từ settings (màn hình cấu hình lần đầu) — lưu secure storage nếu cần; không hard-code secret.
- Dio interceptors: (1) add `Authorization: Bearer`; (2) log lỗi (không log token); (3) response decode `error_id` → hiển thị message; (4) retry idempotent với cùng `Idempotency-Key`.
- Mô hình `ApiResult<T>`: success/failure + typed errors (api exception mapping `code` sin bài 05 → lỗi UI tiếng Việt).
- Timeout: connect 10s, read 30s (tăng cho upload), config theo request.

## 7. Local storage & cache (offline)

- **Token**: `flutter_secure_storage`.
- **Cache sản phẩm/giá/tồn** để offline xem: Hive box `products`, `stock`, `settings`, `categories`; cache policy: khi online refresh từ `updated_after` (delta); TTL cho phép offline đọc (expiry theo setting). Được phép hiển thị giá/tồn **tại thời điểm lấy** và ghi chú "dữ liệu cũ".
- **Outbox offline POS**: Hive box `pos_outbox` (uuid, payload, idempotency_key, created_at) — chỉ khi device được phép offline POS.
- Không bao giờ lưu mật khẩu; chỉ thời gian PIN POS (tùy chọn, có TTL) — có thể bỏ (yêu cầu xác nhận).

## 8. Offline sync (13_OFFLINE detail)

- `SyncEngine`: đợi `connectivity` → drain queue theo FIFO + server `POST /sync/queue` (batch), với mỗi item giữ `uuid` + `Idempotency-Key`. Kết quả per-item: synced / conflict / retryable; conflict → màn hình Sync Center (admin).
- Cursor delta cho cache: `GET /products?updated_after=`; `GET /inventory/transactions?since=` để cập nhật stock cache hợp lệ.

## 9. Scanner (barcode/QR)

- `ScanOverlay` dùng `mobile_scanner`, liên tục code 128/EAN13/UPCA/QR.
- Luồng: scan → `GET /products/by-barcode/{code}` (có cache → offline tra) → thành công: mở POS add to cart hoặc mở product tùy ngữ cảnh; 404 `unlisted` → màn hình Tạo sản phẩm (prefill barcode).
- Đồng thời hỗ trợ **chế độ máy quét HID** (nhập bằng keyboard) — luồng input.

## 10. Printer (14_PRINTER detail)

- `ThermalPayload` model → encode ESC/POS (58mm: center 32 chars/line; 80mm: 42) — các lệnh hệ số in đậm, cắt giấy, mở ngăn kéo.
- `BluetoothConnector` (flutter_blue_plus): scan tên máy in lưu cấu hình; in receipt sau thanh toán; in lại từ `receipts/{id}`; in label barcode (nếu thêm).
- PDF: nếu không Bluetooth → xem PDF + share.

## 11. Upload ảnh

- `ProductImageUsecase`: chọn gallery/camera → compress (image lib) → `POST /uploads` (Dio multipart, progress) → gắn `media_id` vào product. Pattern retry với progress UI.

## 12. Error handling & UX

- `ErrorView` toàn app: retry button. `SnackBar` cho lỗi nhẹ.
- Async state pattern: `AppAsyncValue<T>` (loading/error/data) dùng ở mọi màn.
- Không bao giờ để app crash ở release: `FlutterError.onError` + sentry/firebase crashlytics (opt-in later).

## 13. Giao diện & Navigation (AA)

### 13.1 Đánh giá navigation đề xuất của chủ dự án
Đề xuất gốc: Dashboard · Kho · Scan/POS · Đơn hàng · More.

**Đánh giá**: POS là màn thao tác thường xuyên nhất (nhân viên bán) → nên đặt **giữa, nổi**. Dashboard dùng nhiều bởi quản lý → giữ. Kho/Đơn là 2 nhóm nghiệp vụ tách. Tab "Scan" riêng gây thêm bước (scan nằm trong POS + FAB toàn app scanning được) → gộp.

**Đề xuất mới** (giữ 5 tab nhưng tinh chỉnh):
```
[POS  (nổi, center)] · [Kho] · [Đơn hàng] · [Dashboard] · [Thêm (More)]
```
- POS: danh mục sản phẩm + giỏ 2 khung (landscape-friendly), nút scan to, tìm nhanh.
- Thêm (More): Sản phẩm, Nhập kho, Nhà cung cấp, Lô hạn dùng, Kiểm kho, Khách hàng, Báo cáo, Trả hàng, Nhân viên, Đồng bộ, Cài đặt, Thông báo.
- FAB scan toàn cục (bật camera lớp phủ).

### 13.2 Design tokens
- Màu: thương hiệu mỹ phẩm — trắng sạch + màu hồng/tím pastel accent (đề xuất), dùng Material 3 `ColorScheme.fromSeed`.
- Typography đồng nhất; hiển thị tiền VND không số lẻ, dấu chấm nghìn; nhịp tô nền theo status (hết hàng đỏ nhạt, còn ít vàng, OK xanh).
- Motions nhẹ; bottom nav icon+label.

## 14. Notifications (in-app)

- `NotificationCenterProvider`: poll `/notifications/unread-count` (30s) + badge trên tab; FCM optional phase sau.

## 15. Chưa quyết định

- Sentry/Crashlytics — để sau (production hardening).
- Có dùng FCM ngay không — chờ (U).
- Ngôn ngữ app: VN first (có Loco Translate cho web; app có thể support VN + EN sau).
- Device orientation: POS nên landscape hay portrait? (POS bán nhanh — đề xuất cho chọn trong settings thiết bị).

## 16. Phụ thuộc

Flutter 3.47.5 / Dart 3.13.4 (đã confirm). Packages sẽ khóa version tại PHASE 4 sau khi `flutter pub outdated` khảo sát.

## 17. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Package printer không ổn định / dạng cũ | chuẩn hóa tự viết encoder; kết nối qua bluetooth protocol level |
| Camera permission/machine | khai báo AndroidManifest + runtime; test trên thiết bị thật |
| Cache/offline lệch dữ liệu | policy: offline chỉ đọc cache có nhãn thời gian; offline POS có buffer + conflicts surface |
| App lớn chậm build | chia modules, codegen Riverpod, profile build |

## 18. Tài liệu liên quan

[03_SYSTEM_ARCHITECTURE](03_SYSTEM_ARCHITECTURE.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [13_OFFLINE_SYNC](13_OFFLINE_SYNC.md) · [14_PRINTER_BARCODE](14_PRINTER_BARCODE.md) · [18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md)