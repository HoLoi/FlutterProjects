# 05 · Bảo Mật

## 1. Nguyên tắc bất biến

1. **Không đưa secret vào Flutter APK**: WooCommerce consumer key/secret, mật khẩu WordPress, mật khẩu DB.
2. **Chỉ HTTPS** — app từ chối URL không phải `https://`.
3. **Không log token, mật khẩu, secret** ở cả app và plugin.
4. **Kiểm tra quyền ở server** — không tin client.
5. **Không SQL tay** — dùng `$wpdb->prepare()`, WooCommerce CRUD.
6. **Không sửa core** WordPress/WooCommerce.
7. **Không tự động ghi dữ liệu production**.

## 2. Giai đoạn hiện tại (MVP-10 → MVP-12)

- Endpoint **chỉ đọc** (GET), vẫn **không ghi dữ liệu production**.
- Từ MVP-12 đã đóng lỗ hổng "đọc công khai dữ liệu đơn hàng":

| Endpoint | Xác thực |
|---|---|
| `/health`, `/products`, `/categories`, `/variations` | Public (dữ liệu catalog, chấp nhận được) |
| `/orders`, `/orders/{id}` | **Bắt buộc** WordPress Application Password |

## 2.1. Cơ chế xác thực (MVP-12)

| Vấn đề | Cách làm |
|---|---|
| Giao thức | HTTP Basic theo chuẩn **WordPress Application Password**: `Authorization: Basic base64(username:application-password)` |
| Bắt buộc | **HTTPS**. Basic chỉ base64, không mã hoá — gửi qua HTTP là lộ mật khẩu |
| Phía server | `permission_orders()`: `is_user_logged_in()` → `401`; `current_user_can()` → `403` |
| Capability | `manage_woocommerce` → fallback `edit_shop_orders` → fallback `read_private_shop_orders` |
| Plugin có tự parse header? | **Không.** WordPress tự xác thực, plugin chỉ kiểm tra `current_user` |
| Endpoint `POST /auth/login`? | **Không có.** Không cần vì đã dùng cơ chế sẵn có của WordPress |
| Token / refresh token | Không có, không cần cho phạm vi MVP-12 |

## 2.2. Phiên phía app (Flutter)

| Vấn đề | Cách làm |
|---|---|
| Lưu trữ | **Chỉ trong RAM** (`AuthSession extends ChangeNotifier`). Không SharedPreferences, không file |
| Mất phiên khi | Tắt app là mất đăng nhập; phải nhập lại Application Password |
| Getter mật khẩu | Không có. UI không thể vô tình hiển thị mật khẩu |
| `toString()` | Không chứa username, mật khẩu hay header, để không rò thông tin nếu bị in ra log |
| Ô nhập mật khẩu | `obscureText: true`, xoá controller ngay sau khi đăng nhập thành công |
| Log | Không ghi username, Application Password hay `Authorization` header |
| Xác minh đăng nhập | `GET /orders?per_page=1&page=1` (read-only, không tải/ghi dữ liệu đơn) |
| Chưa đăng nhập | Không gọi API đơn hàng; hiện màn hình yêu cầu đăng nhập |
| Bỏ qua đăng nhập | Chỉ mở khoá sản phẩm/POS; tab Đơn hàng vẫn yêu cầu đăng nhập |
| Package mới | Không thêm package nào cho MVP-12 |

## 3. Trước khi ghi dữ liệu thật (bắt buộc từ MVP-13)

| Hạng mục | Yêu cầu |
|---|---|
| Xác thực | Đã có (Application Password) — cần xác nhận hoạt động trên production |
| Phân quyền | Đã có cho đọc; cần thêm capability **ghi** và kiểm tra server-side mọi endpoint ghi |
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
- Không có test nào chứa URL production hay secret thật.
- Không tự động gọi POST/PUT/PATCH/DELETE đến production.
- Test auth chỉ dùng username/mật khẩu giả (`demo`), khẳng định:
  orders **có** header, catalog **không** có header, 401/403 đúng thông điệp,
  logout xoá phiên, chưa đăng nhập thì không gọi API đơn.

## 6. Plugin PHP

- Kiểm tra ABSPATH trước khi thực thi
- Dùng `sanitize_text_field()`, `absint()` cho tham số đầu vào
- Không trả dữ liệu nhạy cảm (không trả giá vốn, email đầy đủ, secret)
- Cài đặt/uninstall thận trọng, `uninstall.php` không xóa dữ liệu người dùng

## 7. Giới hạn đã biết

| Vấn đề | Trạng thái | Khi nào xử lý |
|---|---|---|
| Endpoint đọc public (catalog) | Chấp nhận: catalog là dữ liệu công khai | Nếu cần, sau MVP-12 |
| Endpoint đọc đơn hàng public | **Đã đóng ở MVP-12** | — |
| Chưa có phân quyền | **Đã có** cho đọc (`/orders`) | Viết: MVP-13 |
| Chưa có chống tạo đơn trùng | Chưa có | MVP-13 |
| Chưa có rate limit | Chưa có | Khi cần, sau MVP-12 |
| Chưa có kiểm kê phiên đăng nhập / hết hạn | Chưa có (MVP-12 chỉ lưu trong RAM) | Khi cần, sau MVP-12 |
| Chưa xác minh Application Password trên production | **Chưa xác minh** — không có môi trường PHP/WordPress local để test | Cần kiểm thử thủ công, có xác nhận |

## 8. Tài liệu liên quan

[03_API_SPECIFICATION](03_API_SPECIFICATION.md) · [06_MVP_ROADMAP](06_MVP_ROADMAP.md) · [DECISIONS](DECISIONS.md)
