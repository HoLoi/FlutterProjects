# 05 · Bảo Mật

## 1. Nguyên tắc bất biến

1. **Không đưa secret vào Flutter APK**: WooCommerce consumer key/secret, mật khẩu WordPress, mật khẩu DB.
2. **Chỉ HTTPS** — app từ chối URL không phải `https://`.
3. **Không log token, mật khẩu, secret** ở cả app và plugin.
4. **Kiểm tra quyền ở server** — không tin client.
5. **Không SQL tay** — dùng `$wpdb->prepare()`, WooCommerce CRUD.
6. **Không sửa core** WordPress/WooCommerce.
7. **Không tự động ghi dữ liệu production**.

## 2. Giai đoạn hiện tại (MVP-10, MVP-11)

- Endpoint **chỉ đọc** (GET): `/health`, `/products`, `/categories`, `/variations`, `/orders`, `/orders/{id}`
- Tạm thời cho phép public — chấp nhận được ở giai đoạn thử nghiệm vì **không ghi dữ liệu**
- Plugin có ghi chú TODO buộc phải thêm xác thực trước khi lên production cho endpoint ghi
- Rủi ro đã biết: đọc được dữ liệu công khai. Chấp nhận tạm thời, sẽ đóng ở MVP-12.

## 3. Trước khi ghi dữ liệu thật (bắt buộc từ MVP-12/MVP-13)

| Hạng mục | Yêu cầu |
|---|---|
| Xác thực | Đăng nhập, token (JWT hoặc nonce + cookie) |
| Phân quyền | Role admin / manager / staff, kiểm tra server-side mọi endpoint ghi |
| Chống tạo trùng | Header `Idempotency-Key` cho mọi lần tạo đơn |
| Secret | Lưu ở server, không trả về app |
| HTTPS | Bắt buộc, từ chối HTTP |

## 4. An toàn production

- **Không sửa production khi chưa có yêu cầu rõ ràng và backup đã kiểm chứng.**
- Không tự động cài plugin, sửa sản phẩm, tạo đơn, trừ kho trên production.
- Mọi thao tác trên production là **thủ công, từng bước có xác nhận**.
- Nếu plugin gây lỗi: **Deactivate ngay** (dữ liệu `kc_*` giữ nguyên), rồi khôi phục backup nếu cần.

## 5. Test

- **Automated test không dùng production** — chỉ dùng `MockClient` và dữ liệu local.
- Không có test nào chứa URL production.
- Không tự động gọi POST/PUT/PATCH/DELETE đến production.

## 6. Plugin PHP

- Kiểm tra ABSPATH trước khi thực thi
- Dùng `sanitize_text_field()`, `absint()` cho tham số đầu vào
- Không trả dữ liệu nhạy cảm (không trả giá vốn, email đầy đủ, secret)
- Cài đặt/uninstall thận trọng, `uninstall.php` không xóa dữ liệu người dùng

## 7. Giới hạn đã biết

| Vấn đề | Trạng thái | Khi nào xử lý |
|---|---|---|
| Endpoint đọc public | Đang chấp nhận tạm | MVP-12 |
| Chưa có phân quyền | Chưa có | MVP-12 |
| Chưa có chống tạo đơn trùng | Chưa có | MVP-13 |
| Chưa có rate limit | Chưa có | Khi cần, sau MVP-12 |

## 8. Tài liệu liên quan

[03_API_SPECIFICATION](03_API_SPECIFICATION.md) · [06_MVP_ROADMAP](06_MVP_ROADMAP.md) · [DECISIONS](DECISIONS.md)
