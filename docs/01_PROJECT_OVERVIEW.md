# 01 · Tổng Quan Dự Án

## 1. Mục đích

Hệ thống quản lý cửa hàng mỹ phẩm **MyPham Kim Cương**: một app Flutter (Android) làm giao diện, đọc dữ liệu từ WooCommerce qua một plugin WordPress mỏng.

Dự án ở chế độ **MVP thực dụng**: app chạy được, ít lỗi, dễ kiểm chứng.

## 2. Bối cảnh

- Website đang hoạt động thật: `https://myphamkimcuong.id.vn`
- WordPress 7.1.1 · PHP 8.1 · WooCommerce 10.4.4
- Cửa hàng cần app Android để vận hành cửa hàng vật lý **song song với website**
- Yêu cầu quan trọng: **không xây hệ thống dữ liệu thứ hai** (không có database sản phẩm riêng)

## 3. Kiến trúc (rút gọn)

```text
Flutter app  (giao diện)
    ↓ HTTPS REST API
WordPress plugin mỏng  (lớp API bổ sung, chuẩn hoá dữ liệu)
    ↓ WooCommerce REST API / CRUD chính thức
Dữ liệu WooCommerce hiện có  (nguồn dữ liệu chính)
```

Chi tiết: [02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md)

## 4. Nguyên tắc bất biến

1. **WooCommerce là nguồn dữ liệu chính** cho sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng.
2. **Không tạo database sản phẩm riêng** cho Flutter.
3. **Không viết SQL trực tiếp** để sửa tồn kho — ưu tiên WooCommerce REST API / CRUD chính thức.
4. **Plugin chỉ là lớp API bổ sung**: chuẩn hoá dữ liệu và xử lý nghiệp vụ WooCommerce chưa có.
5. **Không đưa secret** (WooCommerce consumer key/secret, mật khẩu WordPress) vào Flutter APK.
6. **Chưa làm offline** ở giai đoạn hiện tại.
7. **Không tự động ghi dữ liệu production** — chỉ đọc (GET) cho tới khi có MVP-12 (auth) và MVP-13 (POS thật).
8. **Không tự ý sửa production** nếu chưa có yêu cầu rõ ràng.
9. **Test Flutter dùng MockClient/dữ liệu local** — không dùng production trong automated test.
10. **Deactivate plugin không xóa dữ liệu.**

## 5. Thành phần

| Thành phần | Đường dẫn | Vai trò |
|---|---|---|
| Flutter App | `mypham_kim_cuong_app/` | Giao diện: sản phẩm, POS, đơn hàng, nhập kho (demo) |
| WordPress Plugin | `mypham-kim-cuong-manager/` | REST API `kc/v1` mỏng giữa app và WooCommerce |

## 6. Trạng thái hiện tại

| Hạng mục | Trạng thái |
|---|---|
| Health endpoint | ✅ Hoàn tất (MVP-10) |
| Đọc sản phẩm thật | ✅ Hoàn tất (MVP-10) |
| Flutter hiển thị sản phẩm thật | ✅ Hoàn tất (MVP-10) |
| Fallback dữ liệu thiếu | ✅ Có (tên/SKU/barcode/giá/tồn kho) |
| Đọc biến thể / danh mục / đơn hàng | ✅ Hoàn tất (MVP-11) |
| Flutter hiển thị đơn hàng | ✅ Danh sách + chi tiết (MVP-11) |
| POS | ⚠️ Demo, dùng mock — chưa tạo đơn thật |
| Auth / phân quyền | ⏳ MVP-12 |
| Offline | ❌ Chưa làm (không thuộc MVP) |

## 7. Môi trường

- Flutter 3.47.5 / Dart 3.13.4
- **Không có PHP, Docker, WordPress local** → code plugin không lint/runtime-test được trên máy dev
- **Không có staging site**
- Vì vậy: công việc local tập trung vào Flutter; plugin chỉ viết code và kiểm tra bằng đọc, phải ghi rõ giới hạn này trong báo cáo

## 8. Tài liệu liên quan

[README](../README.md) · [02_SIMPLE_ARCHITECTURE](02_SIMPLE_ARCHITECTURE.md) · [03_API_SPECIFICATION](03_API_SPECIFICATION.md) · [04_DATA_MODEL](04_DATA_MODEL.md) · [05_SECURITY](05_SECURITY.md) · [06_MVP_ROADMAP](06_MVP_ROADMAP.md) · [DECISIONS](DECISIONS.md)
