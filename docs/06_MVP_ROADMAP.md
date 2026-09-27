# 06 · MVP Roadmap

## Nguyên tắc

Mỗi MVP chỉ làm **đúng phạm vi** của MVP đó. Không tự động nhảy sang MVP tiếp theo.

## MVP-10 ✅ Đã hoàn tất
- [x] Health endpoint
- [x] Đọc sản phẩm thật
- [x] Hiển thị sản phẩm thật trong Flutter
- [x] Fallback cho dữ liệu thiếu tên, SKU, barcode, giá, tồn kho

## MVP-11 ✅ Đã hoàn tất — Chỉ đọc
- [x] Đọc biến thể thật
- [x] Đọc danh mục thật
- [x] Đọc đơn hàng WooCommerce
- [x] Flutter hiển thị danh sách và chi tiết đơn hàng
- **Chỉ đọc, không sửa dữ liệu.** Không tạo bảng mới. POS vẫn giữ mock.

## MVP-12 ✅ Đã hoàn tất — Auth tối thiểu
- [x] Xác thực bằng WordPress Application Password qua HTTPS (không tự viết cơ chế auth)
- [x] Bảo vệ `GET /orders` và `GET /orders/{id}`; catalog vẫn public
- [x] `401` khi chưa xác thực, `403` khi thiếu capability xem đơn
- [x] Phân quyền: `manage_woocommerce` → fallback `edit_shop_orders` → `read_private_shop_orders`
- [x] Màn hình đăng nhập + đăng xuất trong Flutter
- [x] Phiên chỉ lưu trong RAM, không ghi secret xuống đĩa, không thêm package
- [x] Không lưu secret WooCommerce trong APK
- **Chỉ đọc.** Không thêm endpoint ghi, không tạo bảng mới, POS vẫn giữ mock.
- Chưa xác minh được trên production (không có môi trường PHP/WordPress local, không dùng secret thật).

## MVP-13 ⏳ POS thật
- [ ] Flutter gửi sản phẩm và số lượng lên plugin
- [ ] Plugin tạo WooCommerce order bằng API/chức chức năng chính thức
- [ ] WooCommerce tự xử lý tồn kho
- [ ] Mã request duy nhất để tránh tạo đơn trùng
- Chưa hỗ trợ offline. Chưa làm lô hàng nếu chưa cần.

## MVP-14 ⏳ Nhập kho
- [ ] Nhập kho đơn giản
- [ ] Nhà cung cấp và lịch sử nhập kho tối thiểu
- [ ] Cập nhật tồn kho qua WooCommerce
- Chỉ triển khai sau khi kiểm tra kỹ endpoint và dữ liệu.

## MVP-15 ⏳ Trả hàng & báo cáo
- [ ] Trả hàng
- [ ] Báo cáo doanh thu cơ bản
- [ ] In hóa đơn nếu cần

## MVP-16 ⏳ Lô hàng (theo yêu cầu cửa hàng)
- [ ] Lô hàng, hạn sử dụng, FEFO
- Chỉ làm khi cửa hàng xác nhận nghiệp vụ này cần ngay.

## MVP-17 ⏳ Cải tiến thiết bị
- [ ] Camera barcode
- [ ] Bluetooth printer
- [ ] Các cải tiến giao diện

## Ngoài roadmap (không phải kế hoạch bắt buộc)
Offline database, multi-branch, multi-warehouse, loyalty, notification phức tạp, recovery job, event bus, kiến trúc enterprise, hàng chục custom table. Nếu sau này cần, xem `archive/`.
