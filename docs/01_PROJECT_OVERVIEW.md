# 01 · Tổng Quan Dự Án

## 1. Mục đích

Tài liệu này cung cấp bức tranh toàn cảnh của hệ thống **Quản Lý Cửa Hàng Mỹ Phẩm MyPham Kim Cương**: mục tiêu, phạm vi, thành phần, nguyên tắc nền tảng, và lý do tồn tại của từng tài liệu kế hoạch.

## 2. Phạm vi

- Bao trùm cả **2 thành phần coding**: Flutter App (`mypham_kim_cuong_app`) + WordPress Plugin (`mypham-kim-cuong-manager`).
- Bao trùm toàn bộ nghiệp vụ A → AE mà chủ dự án liệt kê.
- **PHẠM VI HIỆN TẠI CỦA KẾ HOẠCH**: chỉ thiết kế. Không viết code, không đụng database, không đụng website.

## 3. Bối cảnh

Cửa hàng mỹ phẩm đang bán trên website `https://myphamkimcuong.id.vn` (WordPress 7.1.1 / PHP 8.1 / WooCommerce 10.4.4). Website đang hoạt động thực tế với các plugin bán hàng, thanh toán, vận chuyển, SEO... Chủ cửa hàng cần một ứng dụng Android POS + quản lý kho để vận hành cửa hàng vật lý song song với website, **không xây dựng hệ thống dữ liệu thứ hai song song**.

→ Giải pháp: một **plugin trung gian** mở rộng WooCommerce cung cấp REST API nghiệp vụ (lô hàng, nhà cung cấp, nhập kho, kiểm kho, POS, báo cáo, phân quyền...) mà WooCommerce mặc định không có, đồng thời **giữ WooCommerce làm nguồn dữ liệu chính**.

## 4. Mục tiêu

1. App quản lý + POS chạy trên Android, giao diện hiện đại, thao tác nhanh trên điện thoại.
2. WordPress/WooCommerce là nguồn dữ liệu duy nhất cho: sản phẩm, biến thể, giá bán, SKU, barcode, tồn kho, đơn website, khách hàng, danh mục, hình ảnh.
3. Plugin mở rộng nghiệp vụ: lô hàng (NSX/HSD), nhà cung cấp, nhập kho, kiểm kho, điều chỉnh kho, POS giao dịch, trả hàng, phân quyền, nhật ký, báo cáo, đồng bộ offline.
4. **Đồng bộ tồn kho 2 chiều nhất quán**, tránh race condition giữa website bán / POS bán / nhiều thiết bị.
5. An toàn tuyệt đối với dữ liệu & vận hành của website hiện tại.

## 5. Thành phần & trách nhiệm

```
┌──────────────────────────┐
│  Flutter App (Android)   │  POS, quét mã, nhập kho, quản lý, báo cáo...
│  mypham_kim_cuong_app    │  Chạy trên điện thoại của quản lý/nhân viên
└────────────┬─────────────┘
             │ HTTPS REST (chỉ qua plugin API, KHÔNG vào MySQL)
             ▼
┌──────────────────────────┐
│  Plugin REST API kc/v1   │  Auth/authorization, nghiệp vụ, transaction,
│  mypham-kim-cuong-manager│  đồng bộ stock, idempotency, log, settings
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│  WordPress / WooCommerce │  Products, Variations, Orders, Customers,
│  (data source)           │  Stock, Media, Coupons (CRUD qua API chuẩn)
└────────────┬─────────────┘
             ▼
   MySQL/MariaDB của website
```

**Dữ liệu nằm ở đâu (nguyên tắc 4 lớp):**

| Nhóm | Kho dữ liệu | Ví dụ |
|---|---|---|
| 1. Dùng WooCommerce | bảng WC + CRUD qua API WC | sản phẩm, biến thể, giá, SKU, tồn kho, đơn, khách, media |
| 2. Dùng WordPress | users, options, media | tài khoản user gắn với nhân viên, settings cache |
| 3. Custom tables plugin `wp_kc_*` | nghiệp vụ mở rộng | lô, nhà cung cấp, nhập kho, kiểm kho, POS tx, inventory history, activity log, outbox, idempotency, notifications |
| 4. Chỉ lưu local trên Flutter | dữ liệu không đồng bộ | session đăng nhập (token), cache sản phẩm để offline xem, hàng đợi offline, cài đặt máy in |

## 6. Nguyên tắc nền tảng (non-negotiable)

1. Không đụng trực tiếp MySQL từ App.
2. Không hard-code mật khẩu/secret trong App hay repo.
3. Không tạo database sản phẩm riêng.
4. Không sửa/xóa dữ liệu WooCommerce hiện có ngoài phạm vi luồng nghiệp vụ được duyệt.
5. Không sửa core WP/WC; chỉ dùng hook/filter/API chính thức + custom tables với prefix riêng.
6. Deactivate plugin ≠ xóa dữ liệu. Uninstall phải thận trọng, có xác nhận.
7. Mọi biến động tồn kho phải có lịch sử (inventory transaction).
8. Doanh thu ≠ Lợi nhuận. Lợi nhuận phải dựa trên giá vốn/lô.
9. Mọi request quan trọng phải chống trùng lặp (idempotency).
10. Website thật phải được backup trước khi triển khai bất kỳ thứ gì.

## 7. Quyết định chính

| # | Quyết định | Lý do | Chi tiết |
|---|---|---|---|
| D1 | WooCommerce là source of truth cho dữ liệu bán hàng chính | tránh 2 hệ thống tồn kho/giá | DECISIONS.md |
| D2 | Plugin REST `kc/v1` là lớp trung gian duy nhất | bảo mật, một nơi kiểm soát permission + transaction | DECISIONS.md, 05_API |
| D3 | Custom tables prefix `wp_kc_` cho nghiệp vụ mở rộng | không trùng dữ liệu WC, dễ identify | 04_DATABASE |
| D4 | Stock mutation ưu tiên WC official API + guarded SQL dự phòng (D-22) + idempotency | giải quyết race condition POS/web/đa thiết bị | 09_INVENTORY |
| D5 | POS sale đi qua WooCommerce order + giao dịch riêng `kc_pos_transactions` | tận dụng order system, có giao dịch riêng, hóa đơn riêng | 10_POS |
| D6 | COGS theo lô FEFO, fallback giá vốn sản phẩm | đúng nghiệp vụ mỹ phẩm hết hạn sớm | 11_EXPIRY |
| D7 | Auth plugin-managed (JWT + refresh token server-side) | phân quyền nghiệp vụ, thu hồi được token | 08_AUTH |
| D8 | Offline mặc định read-only; offline POS là tùy chọn có buffer | an toàn tồn kho | 13_OFFLINE |

## 8. Chưa quyết định (cần chủ dự án)

- Chế độ offline chính thức (xem 13_OFFLINE_SYNC).
- Máy in nhiệt 58mm hay 80mm; hãng.
- VAT đã gồm trong giá chưa; hạch toán giá vốn.
- VietQR thanh toán tại POS có dùng không.
- Chặn bán hàng hết hạn hay không.
- Kênh thông báo (trong app / FCM / TG / email).

## 9. Phụ thuộc

- Flutter 3.47.5 / Dart 3.13.4 (đã xác nhận có trên máy dev).
- PHP CLI **chưa có** trên máy dev → cần cài để test plugin local (xem 16_TESTING).
- Site thật cần quyền truy cập (FTP/cPanel + WP admin) khi tới giai đoạn triển khai, luôn có bản backup trước.

## 10. Rủi ro cấp hệ thống

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Phiên bản WP/WC cập nhật hơn so với tài liệu chuẩn | Trung bình | Thiết kế theo API public, decouple bằng custom tables; kiểm chứng tại Phase 1 |
| Website thật — sai sót làm gián đoạn bán hàng | Cao | Staging copy trước, backup đầy đủ, triển khai từng bước nhỏ, feature-flag |
| Race condition khi bán đồng thời nhiều nơi | Cao | Thiết kế guard stock (D-22) + idempotency (thuộc Phase core, test load ở Phase 16) |
| Plugin mới va chạm plugin có sẵn (VietQR, Variation Swatches, HPOS...) | Trung bình | Kiểm tra tương thích Phase 1; dùng hook chuẩn; không cố tương tác chi tiết private của plugin khác |
| Nhân viên lạm dụng giảm giá/hoàn tiền | Trung bình | Permission + mức giảm tối đa + lịch sử + audit log |

## 11. Tài liệu liên quan

[README.md](../../README.md) · [02_REQUIREMENTS](02_REQUIREMENTS.md) · [03_SYSTEM_ARCHITECTURE](03_SYSTEM_ARCHITECTURE.md) · [18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md) · [DECISIONS](DECISIONS.md)