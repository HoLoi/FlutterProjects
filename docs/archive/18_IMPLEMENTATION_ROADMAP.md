# 18 · Implementation Roadmap

## 1. Mục đích

Chia triển khai thành các phase nhỏ, rõ ràng: mục tiêu, file tạo/sửa, chức năng, dependency, test, điều kiện hoàn thành, rollback. Đây là **kế hoạch — chưa thực thi**.

## 2. Phạm vi

Toàn bộ quá trình từ PHASE 0 (Planning — đang hoàn tất) đến go-live. Thứ tự đã tự đánh giá và tinh chỉnh so với đề xuất ban đầu: gom auth+permission sớm nền tảng; test concurrency đưa vào trước production; printing trong POS phase; offline muộn hơn.

## 3. Vòng đời chung mỗi phase

- **Mục tiêu** — kết quả mong muốn.
- **File tạo/sửa** — danh sách cụ thể.
- **Chức năng** — chi tiết.
- **Dependency** — phase cần trước.
- **Test** — bắt buộc trước khi xem hoàn thành.
- **Điều kiện hoàn thành** (DoD).
- **Rollback** — nếu phase này trục trặc.

---

## PHASE 0 — Planning (đang chạy)

- **Mục tiêu**: hoàn tất bộ tài liệu; chốt các quyết định + danh sách câu hỏi cần chủ dự án.
- **File**: README + toàn bộ `/docs/*` (đã tạo).
- **Điều kiện hoàn thành**: chủ dự án duyệt tài liệu + trả lời "Cần xác nhận" (mục 8 báo cáo cuối).
- **Rollback**: chỉnh sửa tài liệu, không ảnh hưởng hệ thống.

## PHASE 1 — Nền tảng: git + môi trường + staging copy + plugin skeleton

> PHASE 1 được chia làm 2 phần: **1A** (local + GitHub + scaffold review) đã hoàn tất; **1B** (staging site) đang pending vì chưa có staging/hosting phụ.

### PHASE 1A — Local + GitHub + scaffold review ✅

- **Mục tiêu**: repo git hoạt động, remote GitHub kết nối, `.gitignore` đúng chuẩn, review scaffold app + plugin; commit baseline. KHÔNG viết API/DB/migration, KHÔNG build APK.
- **File**: `.gitignore` (root), commit baseline; review `mypham_kim_cuong_app/` + `mypham-kim-cuong-manager/`.
- **Chức năng**: git init/remote (đã có sẵn), secret hygiene, xác nhận scaffold chạy được (`flutter analyze` + `flutter test`).
- **Dependency**: quyết định đã duyệt.
- **Test**: `flutter analyze` sạch; `flutter test` pass; `git status` gọn trước commit.
- **DoD**: ✅ commit baseline `chore: initialize planning docs and scaffold review baseline`; scaffold giữ nguyên (D-28).
- **Rollback**: revert commit; không ảnh hưởng hệ thống.

### PHASE 1B — Staging site + môi trường dev đầy đủ ⏸ (pending)

- **Mục tiêu**: môi trường dev hoạt động (PHP CLI 8.1 local + WP/WC test env), bản staging an toàn của website, skeleton plugin bật được trên staging mà KHÔNG ảnh hưởng gì.
- **File**: cấu hình local WP/WC, staging clone, plugin skeleton (header, activation/deactivation stub).
- **Chức năng**: cài PHP CLI 8.1 + Composer local; tạo bản copy staging (anonymize test); security: secret management.
- **Dependency**: **có staging site hoặc xác nhận chủ dự án** + access hosting.
- **Test**: activation an toàn (không lỗi, không chạm WC), smoke GET `/wp-json`.
- **DoD**: plugin activate trên staging + local; chưa đụng prod.
- **Rollback**: xóa plugin khỏi staging, bỏ cấu hình, không có gì tồn tại.

> **Gate bắt buộc**: KHÔNG bắt đầu PHASE 2 nếu chưa hoàn tất PHASE 1B (có staging) hoặc chưa có xác nhận rõ ràng của chủ dự án. Không thao tác trên production.

## PHASE 2 — Database schema + Migration framework

- **Mục tiêu**: tạo custom tables `wp_kc_*` (schema v1, 04) với migration versioned.
- **File**: `src/Migration/*` (Runner, Schema_v1), `uninstall.php` stub.
- **Chức năng**: dbDelta create, upgrade từ version cũ, downgrade-safe, log, `kc_db_version`.
- **Dependency**: PHASE 1B (staging sẵn sàng). **KHÔNG bắt đầu nếu chưa có staging hoặc chưa có xác nhận chủ dự án.**
- **Test**: migration unit (upfresh/upgrade/downgrade), verify no touch WC tables.
- **DoD**: schema đúng 04; ACTIVE trên staging.
- **Rollback**: drop tables kc_* (chưa có dữ liệu) — an toàn.

## PHASE 3 — Auth + Permission + REST core

- **Mục tiêu**: login (password/PIN), JWT + refresh + revoke, device registry, permission middleware, rate limit, envelope lỗi, idempotency service.
- **File**: `src/Auth/*`, `src/Http/*`, `src/Core/Tx.php`, `src/Security/*`; endpoints `/auth/*`.
- **Chức năng**: contract 05 §5.1; register roles WP.
- **Dependency**: PHASE 2.
- **Test**: positive/negative từng permission; token lifecycle; error envelope.
- **DoD**: `/auth/me` trả đúng permission theo role từ DB.
- **Rollback**: vô hiệu plugin (không xóa token bảng chưa có dữ liệu).

## PHASE 4 — Products & Variations & Media (đọc/ghi qua WC)

- **Mục tiêu**: CRUD sản phẩm + variation qua WC, categories, brand taxonomy, barcode (`kc_barcodes` + meta), cost `_kc_cost`, images upload.
- **File**: `src/Domain/Products|Variations|Barcodes|Media`, app: khung features/products (list, detail, form, upload).
- **Chức năng**: endpoints `/products*`, `/uploads`, `/categories`.
- **Dependency**: PHASE 3.
- **Test**: create/sửa/ẩn product + variation trên staging (product TEST); ảnh upload; barcode unique; Flutter view.
- **DoD**: app thấy đúng sản phẩm website hiện tại (có biến thể, giá, ảnh).
- **Rollback**: xoá sản phẩm TEST; plugin tắt chỉ ảnh hưởng API.

## PHASE 5 — Suppliers + Receiving (nhập kho) + Lots + EXPIRY alerts

- **Mục tiêu**: nhà cung cấp, phiếu nhập tạo lô, giá nhập, stock + lịch sử, alerts hạn dùng.
- **File**: `src/Domain/Suppliers|Lots|Inventory(ReceivingService, StockManager v1)|Notifications`; app: features/suppliers, inventory (receive form, lots screens).
- **Chức năng**: `POST /receivings`, `GET /expiry-alerts`, lot ledger, FEFO module (ra dáng).
- **Dependency**: PHASE 2, 3 (staging quan trọng).
- **Test**: nhập lô → stock WC thay đổi đúng; alert theo window; ledger đúng; khởi tạo tồn "INITIAL" cho SP hiện có.
- **DoD**: app nhập 1 phiếu → WC web thấy stock mới.
- **Rollback**: deactivate; kc_* giữ; có thể xoá phiếu test đã tạo (nhưng không xoá lot nếu risk — để admin).

## PHASE 6 — Stock sync + inventory tx core + Web hooks

- **Mục tiêu**: `StockManager` hoàn chỉnh theo **chiến lược D-22** (ưu tiên WC official functions; guarded SQL chỉ khi concurrency test chứng minh cần), hooks web: reduce/restore → WEB_SALE/RETURN tx + FEFO, adjust, inventory transactions list, running_stock.
- **File**: `src/Hooks/WcStockHooks.php`, `src/Domain/Inventory/StockManager.php` (full), endpoints `/inventory/*` list/adjust.
- **Chức năng**: mọi thay đổi có tx; "không 2 hệ tồn kho".
- **Dependency**: PHASE 4 (sản phẩm có stock), 5.
- **Test**: **concurrency test quyết định D-22** (official functions đủ hay phải guarded SQL) + unit test guard; web order tự động ghi tx.
- **DoD**: đơn web mới → app thấy WEB_SALE trong lịch sử + stock đúng; **D-22 chốt** ghi DECISIONS.
- **Rollback**: hook có feature-flag; tắt → plugin không nhận web events (nhưng stock vẫn đúng vì WC tự giảm).

## PHASE 7 — POS sale (core) + sessions

- **Mục tiêu**: POS bán realtime hoàn chỉnh (10): session, cart→checkout, transaction POS + order HPOS + receipt snapshot + lot allocation + idempotency + payment methods (cash/bank), devise.
- **File**: `src/Domain/Pos/*` (SaleService, Session, PaymentMethods, VietQr config placeholder); app: features/pos (POS screens, scan add, cart, pay).
- **Chức năng**: endpoints `/pos/*`.
- **Dependency**: PHASE 6 (stock), 5 (FEFO), 3 (auth).
- **Test**: E2E POS realtime; concurrency 2 device; double-tap idempotency; **compensation/reversal khi order/hook fail giữa** + recovery job (D-23).
- **DoD**: bán hàng → web thấy đơn + stock giảm; app có receipt.
- **Rollback**: không ảnh hưởng web (chỉ tạo thêm order POS đã completed; có thể deactivate khi xấu).

## PHASE 8 — Returns hoàn tiền + Orders (web) + Customers (đọc)

- **Mục tiêu**: /returns (POS + web), /orders list/detail/status/refund, customers list/detail/orders.
- **File**: `src/Domain/Returns|Orders|Customers`.
- **Chức năng**: app screens: orders, returns, customers.
- **Dependency**: PHASE 7 (POS refund dùng pos tx).
- **Test**: trả hàng POS nhập lại kho; refund web đúng WC; đổi trạng thái đơn.
- **DoD**: mọi trạng thái đơn web app thấy; trả hàng điều chỉnh stock + tx.
- **Rollback**: các thao tác test có data đảo.

## PHASE 9 — Printing (thermal PDF) + Barcode label

- **Mục tiêu**: in ngay sau POS + in lại + PDF/share; ESC/POS encoder; Bluetooth; label (khảo sát máy thật).
- **File**: app `core/printer`, `core/pdf`; feature receipt screen.
- **Dependency**: PHASE 7.
- **Test**: máy thật 58/80; offline vouchers.
- **DoD**: in thành công từ thiết bị thật; payload snapshot đúng.
- **Rollback**: chỉ client.

## PHASE 10 — Reports + Dashboard

- **Mục tiêu**: các report (12) + dashboard aggregate + charts app (fl_chart), role-gated.
- **File**: `src/Domain/Reports`; app features/reports + dashboard refresh.
- **Chức năng**: endpoints `/reports/*`, `/dashboard/summary`.
- **Dependency**: PHASE 7, 8 (dữ liệu pos/order/return); đặc tả: docs/12_REPORTING.
- **Test**: số liệu khớp dữ liệu test (revenue ≠ profit); tz đúng.
- **DoD**: dashboard chủ shop chạy đúng số thực.
- **Rollback**: cache thay đổi, không phá dữ liệu.

## PHASE 11 — Offline & Sync

- **Mục tiêu**: cache đọc offline (default), offline POS tùy chọn (device), outbox + sync queue, Sync Center.
- **File**: app `core/sync/*`, `core/api` delta; server `src/Domain/Sync/*`.
- **Chức năng**: `/sync/queue`, `/sync/status`;
- **Dependency**: PHASE 10 (các feature online ổn trước).
- **Test**: mô phỏng mất mạng → cache đọc; POS offline buffer; conflict UI (web bán lúc app offline); outbox retry.
- **DoD**: offline read-only hoạt động; offline POS chỉ khi device enabled; conflict hiện rõ.
- **Rollback**: tắt offline POS per device; kc_sync_outbox dọn.

## PHASE 12 — Notifications + Activity Log full + Staff management UI

- **Mục tiêu**: in-app notifications (đơn mới, stock thấp, hết hạn, sync error), activity log đầy đủ (T), quản lý nhân viên (tạo/khóa/override) qua app + WP admin.
- **File**: `src/Domain/Notifications`, `src/Domain/Activity`, `src/Domain/Staff`, admin pages; app screens.
- **Dependency**: PHASE 10 (dữ liệu), 7.
- **Test**: events sinh đúng; log không secret; quyền thay đổi tức thì.
- **DoD**: manager tạo tài khoản nhân viên mới → login → quyền đúng.

## PHASE 13 — Coupons + VietQR + các tùy chọn thanh toán khác

- **Mục tiêu**: coupon CRUD + validate POS; VietQR (config ngân hàng) + các method mở rộng; POS discount rule + PIN override.
- **File**: `src/Domain/Coupons`, payment methods seed mở rộng.
- **Dependency**: PHASE 7 (POS).
- **Test**: validate coupon POS; mã giảm tối đa; QR nội dung hợp lệ.
- **DoD**: tính năng hoạt động được cấu hình thật.
- **Rollback**: coupon = WC native (tắt không ảnh hưởng).

## PHASE 14 — Security hardening + Load/Concurrency test chính thức

- **Mục tiêu**: quét bảo mật (08 §10 checklist), load test (16), tunning index mà cần thiết, audit log kiểm.
- **File**: patch security, tunning SQL.
- **Dependency**: tất cả tính năng online.
- **Test**: security checklist + load test + pen-test cơ bản.
- **DoD**: checklist pass.

## PHASE 15 — Staging end-to-end + UAT với chủ shop

- **Mục tiêu**: chạy full quy trình trên staging (data gần thật), chủ shop dùng thử, sửa bug, chốt settings thật.
- **File**: settings configuration, tinh chỉnh UI.
- **Dependency**: PHASE 14.
- **Test**: kịch bản UAT: nhập kho → bán → trả → in → báo cáo → offline.
- **DoD**: chủ shop đồng ý.

## PHASE 16 — Production deployment (golden go-live)

- **Mục tiêu**: backup verify + deploy plugin production theo 17; tạo nhân viên thật; bật từng block (bắt đầu read-only).
- **Production Safety Gate (D-27, bắt buộc trước khi bật)**: backup DB+files verify, staging clone, test activation/deactivation, test API read-only, test sản phẩm TEST, rollback plan, **chủ dự án xác nhận thủ công**, bật feature theo flag từng phần (chi tiết 17_DEPLOYMENT §5.1).
- **File**: deployment artifacts.
- **Dependency**: PHASE 15 + xác nhận sidebar.
- **Test**: smoke production + 48h monitoring + rollback sơ đồ chuẩn bị.
- **DoD**: app vận hành thật an toàn 7 ngày.

## PHASE 17 — Production stabilization + training + iterates

- **Mục tiêu**: quan sát, fix patch, training nhân viên, đánh giá mở rộng (inventory/lots bổ sung) — phần AE mở rộng (multi-branch...) để Phase sau.

## 4. Đánh giá thứ tự (thay đổi so với đề xuất ban đầu)

| Đề xuất gốc | Điều chỉnh | Lý do |
|---|---|---|
| Auth sau DB | Giữ gần (Phase 3) | nền tảng API |
| Printing phase 8 → sau order | Đẩy sau POS (Phase 9) | cần POS xong để in thực tế |
| Offline phase 10 | Đẩy muộn (Phase 11) | offline dựa trên feature online ổn; test trước online ổn |
| Security phase 11 | Giữ (Phase 14) sau mọi feature | bảo mật toàn bề mặt hoàn chỉnh khi hardening |
| Test cuối | Concurrency test lồng Phase 6/7 (sớm) | phát hiện sớm | — tech

## 5. Điểm mốc (milestones)

| Milestone | Khi | Nghĩa |
|---|---|---|
| M0 | cuối Phase 1A | ✅ Repo GitHub + `.gitignore` + baseline commit (không code nghiệp vụ) |
| M0b | cuối Phase 1B | ⏸ Staging site sẵn sàng + plugin skeleton activate an toàn |
| M1 | cuối Phase 3 | Auth/API nền hoạt động |
| M2 | cuối Phase 6 | Stock real chạy + web hooks |
| M3 | cuối Phase 7 | **Bán được hàng qua POS (MVP)** |
| M4 | cuối Phase 10 | Báo cáo + dashboard — dùng thử nội bộ |
| M5 | cuối Phase 15 | Sẵn sàng go-live |
| M6 | sau Phase 16 | Go-live sản xuất |

## 6. Quản lý backlog / thay đổi

- Mọi thay đổi yêu cầu → ghi vào DECISIONS.md (addition): mã, mô tả, ảnh hưởng, phase.
- Ưu tiên fix bug trước feature; feature chưa trong phase → backlog.

## 7. Chưa quyết định

- Có cần phase riêng "FCM push" (có thể gộp Phase 12 optional).
- Có muốn mở rộng multi-branch/điểm trong year 2.

## 8. Tài liệu liên quan

Toàn bộ `/docs`; README.md.