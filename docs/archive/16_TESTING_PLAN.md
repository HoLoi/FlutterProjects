# 16 · Testing Plan

## 1. Mục đích

Chiến lược kiểm thử toàn hệ thống: unit, integration, API, concurrency/load, UI/device, migration, an toàn website thật.

## 2. Phạm vi

Test ở các cấp độ + bộ công cụ + lịch gắn phase. Không code test — chỉ kế hoạch.

## 3. Các cấp độ

| Cấp độ | Nội dung | Công cụ |
|---|---|---|
| 1. Unit (plugin) | FEFO algorithm, validator, tax/money rounding, permission logic, envelope | PHPUnit (WP-core test lib, `WP_UnitTestCase`), wp-mock |
| 2. Integration (plugin+WC) | create product/order/stock qua API chuẩn, hook reduce/restore stock, migration, idempotency | PHPUnit + WP test env (SQLite/MySQL tạm) |
| 3. API contract | Mọi endpoint: method, error code, validation, pagination, auth, permission | Postman collection / newman + script assert; contract tests từ 05_API |
| 4. Concurrency & load | 2+ device POS cùng SP, web+POS đồng thời, replay idempotency, lock timeout | Locust / k6 + script chạy đúng hàng trăm request song song lên ngăn xếp staging |
| 5. Flutter unit/widget | state controllers (cart, auth, sync), formatting, navigation guard | `flutter test`, Riverpod test |
| 6. Device/E2E | POS thật trên Android: scan, in Bluetooth, camera, offline, conflict UI | Integration test (`integration_test`) + manual checklist trên thiết bị thật |
| 7. Migration test | upgrade schema cũ→mới không mất dữ liệu | scripts + staging copy từ production data |
| 8. An toàn/site thật | không làm ảnh hưởng website khi plugin hoạt động | golden site: smoke trước; staging song song |

## 4. Chiến lược

- **TDD cho module nhạy cảm**: StockManager (chiến lược D-22, guard/race), FEFO, POS sale (logical unit + compensation D-23), idempotency.
- **Test dữ liệu ngân hàng nhỏ chuẩn**: bộ fixtures: products (simple+variable), lots nhiều HSD, nhiều staff/role, orders web, refunds.
- **Test concurrency bắt buộc trước PHASE production**, chạy trên staging clone dữ liệu gần sản xuất.
- **Test an toàn dữ liệu website thật**: trước khi bật plugin production — chạy hàng loạt API chỉ đọc (GET) để chắc không lỗi + backup; sau đó mutation thật trên sản phẩm TEST (ẩn).

## 5. Ma trận case quan trọng (tối thiểu)

### 5.1 Plugin/Stock
- [ ] `update stock` atomic: 50 concurrent giảm → đúng 50 khi đủ hàng; 60 khi chỉ 50 → đúng 0 thắng + phần dư lỗi 409. **Kết quả này chốt D-22** (official WC functions đủ hay cần guarded SQL).
- [ ] POS sale: giả lập WC order/hook fail giữa sau khi đã trừ stock → **compensation/reversal** hoàn stock, pos_tx `needs_review` + audit; recovery job chốt `processing` kẹt (D-23).
- [ ] Idempotency: gửi 2 cùng key → 1 response; khác fingerprint → 409.
- [ ] Web order → reduce hook → WEB_SALE tx + FEFO allocate; refund → restore tx.
- [ ] Migration từ v0 (empty) và v-ghi cũ → bảng đúng, dữ liệu cũ giữ.
- [ ] FEFO: lô HSD sớm bán trước; lô hết hạn bị chặn; khác hàng lệch → unassigned (`lot_id NULL`).
- [ ] Kiểm kho: diff điều chỉnh, giao dịch xen → cảnh báo.
- [ ] Barcode unique; scan 404 → unlisted.
- [ ] Offline buffer: `kc_device_stock_buffers` giới hạn đúng theo mặt hàng/thiết bị; sync khi server thiếu → conflict rõ ràng, không tự xử lý.

### 5.2 API/Auth
- [ ] Mỗi endpoint với đủ role: đúng 200/403 theo permission matrix.
- [ ] Token hết hạn → 401 → refresh → retry.
- [ ] Rate limit login; lockout sau N lần sai.
- [ ] Validate input: giả mạo type, XSS trong name/description, SQLi qua params.

### 5.3 Flutter
- [ ] Cart POS cộng/giam/giảm giá đúng (money rounding VND).
- [ ] Auth flow + auto refresh khi 401.
- [ ] Offline: toggle online/offline; outbox đẩy 1 lần; conflict UI.
- [ ] QR/scan sync thật trên máy.
- [ ] Print từ máy thật (58 & 80), PDF fallback.
- [ ] Camera chụp → upload → gắn ảnh product.

### 5.4 Website an toàn (tương ứng Production Safety Gate — 17_DEPLOYMENT §6)
- [ ] Trước go-live: so dữ liệu (stock, orders) trước/sau khi bật plugin 7 ngày không lệch.
- [ ] Test **activation / deactivation** plugin (bật/tắt/tắt-bật) trên staging copy — không để lại dữ liệu rác, không dừng site.
- [ ] API **read-only** (GET) chạy sạch trên site thật: không lỗi PHP / warning / làm chậm web.
- [ ] Mutation thử chỉ trên **sản phẩm TEST ẩn**, cấu hình feature theo flag từng phần.
- [ ] Plugin active nhưng không dùng nghiệp vụ → site tốc độ ok (benchmark) và không warning PHP.

## 6. Môi trường test

| Môi trường | Dùng cho |
|---|---|
| Local dev (máy nhà): PHP chưa cài → **cần cài PHP 8.1 + WP + WC** để chạy PHPUnit/integration | phase 1–10 |
| Staging: copy website (plugin All-in-One WP Migration export) → clone DB | phase 14–16; test triển khai |
| Production: chỉ hotfix test nhanh ở giờ thấp điểm với backup | phase 17 |

## 7. CI/CD (đề xuất)

- GitHub Actions sân: test plugin (PHPUnit), test API (newman), `flutter test` + `flutter analyze`. Manual gate cho device test. (Repo git chưa có — sẽ khởi tạo Phase 1.)

## 8. Báo cáo bug template

- Severity, môi trường, bước tái hiện, dữ liệu liên quan (không gồm PII), response/error code, ảnh/log (không đăng token nào).

## 9. Chưa quyết định

- Dùng self-hosted runner hay Actions cloud (đề xuất Actions; không cần đụng site).
- Có cần screenshot baseline (golden) cho UI không (đề xuất bỏ qua — giảm chi phí; giữ visual QA thủ công).

## 10. Phụ thuộc

PHPUnit/wp-phpunit, newman/Postman, k6/Locust, Flutter integration_test, staging server.

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Không đủ thiết bị thật in/scan | manual matrix tối thiểu + phòng máy (owner có máy in) |
| Test concurrency trên staging yếu | số virtual user vừa, đo theo kapacity |
| Data copy production → staging có dữ liệu khách | anonymize email/phone khi copy test |

## 12. Tài liệu liên quan

[18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md) (gắn phase) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [08_AUTHENTICATION_SECURITY](08_AUTHENTICATION_SECURITY.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md)