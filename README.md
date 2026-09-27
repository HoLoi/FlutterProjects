# MyPham Kim Cuong — Quản Lý Cửa Hàng Mỹ Phẩm

## Đây là MVP thực dụng

Dự án ở chế độ **MVP thực dụng**: app chạy được, ít lỗi, dễ kiểm chứng. Không thiết kế sẵn cho quy mô doanh nghiệp lớn.

## Kiến trúc

```text
Flutter app  (giao diện)
    ↓ HTTPS REST API
WordPress plugin mỏng  (lớp API bổ sung)
    ↓ WooCommerce REST API / CRUD chính thức
Dữ liệu WooCommerce hiện có  (nguồn dữ liệu chính)
```

- **Flutter là giao diện** — không chứa database sản phẩm, không tự tính tồn kho.
- **WooCommerce là nguồn dữ liệu chính** — sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng.
- **Plugin là lớp API bổ sung mỏng** — chuẩn hoá dữ liệu và xử lý nghiệp vụ mà WooCommerce chưa có.
- **Không tạo database sản phẩm riêng.** Không viết SQL trực tiếp để sửa tồn kho.

## Chưa làm (có chủ ý)

- ❌ **Chưa làm offline** — app cần mạng để đọc dữ liệu.
- ❌ **Chưa làm nhiều chi nhánh** — mô hình một cửa hàng.
- ❌ **Chưa làm hệ thống tồn kho riêng** — dùng tồn kho WooCommerce. Bảng riêng chỉ tạo khi WooCommerce thật sự thiếu nghiệp vụ (lô, NCC, lịch sử nhập kho).
- ❌ **Chưa làm tính năng enterprise** — không multi-warehouse, loyalty, notification phức tạp, event bus, recovery job, hàng chục custom table.
- ❌ **Chưa được tự động ghi dữ liệu production** — MVP-10 và MVP-11 chỉ đọc (GET). Ghi dữ liệu bắt đầu từ MVP-13 kèm auth.

## Thành phần

| Thành phần | Đường dẫn | Vai trò |
|---|---|---|
| Flutter App | `mypham_kim_cuong_app/` | Giao diện: sản phẩm, POS, đơn hàng, nhập kho (demo) |
| WordPress Plugin | `mypham-kim-cuong-manager/` | REST API `kc/v1` |

## Endpoint

| Method | Đường dẫn | Mô tả |
|---|---|---|
| GET | `/wp-json/kc/v1/health` | Kiểm tra kết nối |
| GET | `/wp-json/kc/v1/products` | Sản phẩm WooCommerce |
| GET | `/wp-json/kc/v1/categories` | Danh mục sản phẩm (MVP-11) |
| GET | `/wp-json/kc/v1/variations` | Biến thể sản phẩm (MVP-11) |
| GET | `/wp-json/kc/v1/orders` | Đơn hàng WooCommerce (MVP-11) |
| GET | `/wp-json/kc/v1/orders/{id}` | Chi tiết đơn hàng (MVP-11) |

Chi tiết: [docs/03_API_SPECIFICATION.md](docs/03_API_SPECIFICATION.md)

## Roadmap

MVP-10 ✅ · MVP-11 ✅ · MVP-12 auth · MVP-13 POS thật · MVP-14 nhập kho · MVP-15 trả hàng + báo cáo · MVP-16 lô hàng · MVP-17 camera + máy in

Chi tiết: [docs/06_MVP_ROADMAP.md](docs/06_MVP_ROADMAP.md)

## Môi trường

- Website: `https://myphamkimcuong.id.vn` — WordPress 7.1.1 / PHP 8.1 / WooCommerce 10.4.4
- Flutter 3.47.5 / Dart 3.13.4
- **Không có PHP, Docker, WordPress local** → code plugin không lint/runtime-test được trên máy dev
- **Không có staging site**
- Kiểm chứng code Flutter: `flutter analyze` + `flutter test` (test dùng MockClient, không dùng production)

## Quy tắc an toàn

- Không sửa production khi chưa có yêu cầu rõ ràng và backup đã kiểm chứng.
- Không tự động cài plugin, sửa sản phẩm, tạo đơn hoặc trừ kho trên production.
- Không dùng dữ liệu production trong automated test.
- Không đưa WooCommerce consumer key/secret hay mật khẩu WordPress vào Flutter APK.
- Scaffold Flutter và cấu trúc cơ bản plugin được giữ nguyên, không tạo lại.

## Tài liệu

| File | Nội dung |
|---|---|
| [01_PROJECT_OVERVIEW](docs/01_PROJECT_OVERVIEW.md) | Tổng quan dự án |
| [02_SIMPLE_ARCHITECTURE](docs/02_SIMPLE_ARCHITECTURE.md) | Kiến trúc đơn giản |
| [03_API_SPECIFICATION](docs/03_API_SPECIFICATION.md) | Đặc tả API |
| [04_DATA_MODEL](docs/04_DATA_MODEL.md) | Mô hình dữ liệu |
| [05_SECURITY](docs/05_SECURITY.md) | Bảo mật |
| [06_MVP_ROADMAP](docs/06_MVP_ROADMAP.md) | Roadmap MVP |
| [DECISIONS](docs/DECISIONS.md) | Nhật ký quyết định |
| [archive/](docs/archive/) | Tài liệu thiết kế cũ, không phải kế hoạch bắt buộc |
