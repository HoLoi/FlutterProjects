# DECISIONS — Nhật Ký Quyết Định

Quy ước: `D-xx` · trạng thái ✅ đã áp dụng · 🔶 đang áp dụng

## D-01 — WooCommerce là nguồn dữ liệu chính ✅
Sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng đều lấy từ WooCommerce.
**Lý do:** cửa hàng đang bán trên website; tạo database thứ hai gây lệch tồn kho và giá.

## D-02 — App chỉ gọi plugin REST `kc/v1` ✅
App không nối MySQL, không gọi thẳng WooCommerce REST API.
**Lý do:** một nơi kiểm soát chuẩn hoá dữ liệu, phân quyền và audit.

## D-03 — Plugin là lớp mỏng ✅
Chỉ chuẩn hoá dữ liệu + xử lý nghiệp vụ WooCommerce chưa có. Không làm framework riêng, không DI container, không event bus.
**Lý do:** MVP thực dụng, code dễ đọc và bảo trì.

## D-04 — Không tạo bảng riêng cho sản phẩm/tồn kho ✅
Chỉ tạo bảng `wp_kc_*` khi WooCommerce thật sự không có nghiệp vụ đó (lô, NCC, lịch sử nhập kho, giao dịch POS).
**Lý do:** tránh hai nguồn dữ liệu tồn kho.

## D-05 — Sửa dữ liệu qua WooCommerce CRUD chính thức ✅
Ưu tiên `wc_get_product()`, `wc_create_order()`, `wc_update_product_stock()`… Không SQL tay.
**Lý do:** an toàn, đúng cache/hook, tránh lệch lookup table.

## D-06 — Đọc đơn hàng bằng `wc_get_orders()` ✅
WooCommerce dùng HPOS, đơn nằm ở `wp_wc_orders`.
**Lý do:** SQL tay vào bảng đơn hàng sẽ hỏng khi HPOS đổi cấu trúc.

## D-07 — Giai đoạn hiện tại chỉ dùng GET 🔶
MVP-10 và MVP-11 chỉ đọc. Ghi dữ liệu bắt đầu từ MVP-13, kèm auth + idempotency.
**Lý do:** không có auth thì không được ghi production.

## D-08 — Endpoint đọc tạm thời public 🔶
Chấp nhận rủi ro đọc dữ liệu công khai trong giai đoạn thử nghiệm; đóng lại ở MVP-12.
**Lý do:** giữ MVP đơn giản, không làm auth sớm khi chưa cần.

## D-09 — Không đưa secret vào APK ✅
WooCommerce consumer key/secret và mật khẩu WP chỉ nằm ở server.
**Lý do:** APK có thể bị decompile, secret trong app là lộ hoàn toàn.

## D-10 — Mọi lần tạo đơn phải có mã request duy nhất ⏳
Áp dụng từ MVP-13 để tránh tạo đơn trùng khi retry.
**Lý do:** mạng di động dễ timeout sau khi server đã tạo đơn.

## D-11 — Không làm offline ở giai đoạn hiện tại ✅
Chỉ cần khi nghiệp vụ thực tế yêu cầu. Thiết kế offline cũ nằm ở `archive/13_OFFLINE_SYNC.md`.
**Lý do:** offline POS là nguồn rủi ro lớn về tồn kho, chưa cần thì chưa làm.

## D-12 — Không multi-branch / multi-warehouse ✅
Chưa có nhu cầu đã xác nhận.
**Lý do:** thêm sớm làm phình schema và logic.

## D-13 — Lưu UTC, hiển thị giờ cửa hàng ✅
Múi giờ `Asia/Ho_Chi_Minh`.
**Lý do:** nhất quán khi đọc dữ liệu từ website.

## D-14 — Test Flutter dùng MockClient ✅
Không dùng production trong automated test.
**Lý do:** test tự động không được phụ thuộc dữ liệu thật, cũng không được ghi production.

## D-15 — Không có PHP/Docker/staging local ✅
Chấp nhận giới hạn: code plugin chỉ kiểm tra bằng đọc, không giả vờ đã lint/runtime-test.
**Lý do:** thiếu hạ tầng; phải nói rõ giới hạn thay vì giả vờ.

## D-16 — Không tự động thao tác production ✅
Mọi thao tác production là thủ công, từng bước có xác nhận.
**Lý do:** tránh rủi ro mất dữ liệu cửa hàng đang bán thật.

## D-17 — Tài liệu thiết kế cũ chuyển vào `docs/archive/` ✅
Không phải kế hoạch bắt buộc.
**Lý do:** giữ lịch sử nhưng tránh nhầm lẫn khi triển khai.

## D-18 — Không nhảy MVP ✅
Mỗi MVP đúng phạm vi, xong thì dừng chờ yêu cầu tiếp.
**Lý do:** kiểm soát phạm vi, tránh làm dở dang nhiều phần cùng lúc.
