# Hệ Thống Quản Lý Cửa Hàng Mỹ Phẩm — MyPham Kim Cương

## Chế độ hiện tại: MVP thực dụng

Project đang ở chế độ **MVP thực dụng**: ưu tiên app chạy được, ít lỗi, dễ test.
Các phần enterprise (offline POS, multi-branch, load test lớn, CI/CD, notification phức tạp...) **tạm hoãn**.
Tài liệu thiết kế chi tiết cũ nằm trong `docs/`, chỉ tham khảo khi cần.

## Quy tắc an toàn tối thiểu

- **Không sửa `https://myphamkimcuong.id.vn`** (production) khi chưa có backup + xác nhận riêng.
- Không cài plugin lên website thật; không build APK release từ scaffold.
- Không trừ kho / tạo đơn hàng thật trong giai đoạn MVP.
- MVP chỉ **bổ sung** vào code hiện có, không phá cấu trúc.
- Mỗi phase kiểm chứng bằng `flutter analyze` + `flutter test`.

## Thành phần

| Thành phần | Đường dẫn | Vai trò |
|---|---|---|
| Flutter App (Android) | `mypham_kim_cuong_app/` | App chủ cửa hàng: POS, sản phẩm, kho... |
| WordPress Plugin | `mypham-kim-cuong-manager/` | REST API trung gian giữa App và WooCommerce (`kc/v1`) |

## Roadmap MVP

| Phase | Nội dung |
|---|---|
| **MVP-1** ✅ | Flutter UI skeleton: login giả, dashboard/sản phẩm/POS placeholder, settings base URL |
| **MVP-2** | Plugin REST skeleton local: `GET /wp-json/kc/v1/health` (chưa tạo bảng, chưa đụng WooCommerce) |
| **MVP-3** | App gọi health endpoint, hiển thị online/offline |
| **MVP-4** | Đọc sản phẩm WooCommerce (chỉ GET, không thêm/sửa/xóa) |
| **MVP-5** | POS demo: cart trong app, checkout mock, không trừ kho thật |

## Môi trường dev

- Flutter 3.47.5 / Dart 3.13.4 — app hiện chạy `flutter analyze` sạch và `flutter test` pass.
- PHP/Composer local: **chưa cài** — cần cho MVP-2 (test plugin local).
- Website thật: WordPress + WooCommerce — **chưa được phép đụng**.

## Đọc thêm

Tài liệu kế hoạch chi tiết (thiết kế cũ) đặt trong `docs/`.