# 15 · Permission System (Phân Quyền)

## 1. Mục đích

Thiết kế hệ thống vai trò & quyền cho app/plugin ngay từ đầu: 3 vai trò, permission grid, override theo nhân viên, áp dụng server-side.

## 2. Phạm vi

Roles, permission keys, ma trận, áp dụng (middleware), quản lý qua UI. Không gồm mật khẩu/token (08).

## 3. Mô hình

```
Mỗi nhân viên (kc_staff):
  role        ∈ { kc_admin, kc_manager, kc_staff }   → permission base (default set)
  overrides   ∈ kc_staff_permissions (key → allowed ∫)  (chỉ admin cấu hình)
  quyền thực   = base(role) ∪ overrides
```
- Role gắn thẳng nơi phần lúc dùng: `kc_staff.role`; muốn nâng cấp role: admin sửa.
- Khi không có kc_staff (user admin WP thuần) → permission deny cho kc API trừ login (admin dùng WP admin quản lý plugin settings thôi).
- Phân quyền nhạy cảm thêm điều kiện `pin_scope` (xác nhận bằng PIN manager) cho: discount > 0 (nếu max 0 với staff), refund, adjust, count confirm, void giao dịch.

## 4. Danh sách permission (keys)

| Key | Mô tả | admin | manager | staff |
|---|---|---|---|---|
| `dashboard.read` | xem dashboard | ✓ | ✓ | ✓ |
| `products.read` | xem sản phẩm/variation/giá/tồn | ✓ | ✓ | ✓ |
| `products.write` | tạo/sửa sản phẩm, giá, SKU, ảnh | ✓ | ✓ | ✗ |
| `products.delete` | xóa/ẩn sản phẩm | ✓ | ✓ | ✗ |
| `products.cost` | xem/sửa giá vốn | ✓ | ✓ | ✗ |
| `inventory.read` | xem tồn kho/lịch sử | ✓ | ✓ | ✓ |
| `inventory.receive` | nhập kho (receiving) | ✓ | ✓ | ✗ |
| `inventory.adjust` | điều chỉnh kho (+PIN khi đủ qty) | ✓ | ✓(PIN) | ✗ |
| `inventory.count` | tạo/điều phiếu kiểm kho | ✓ | ✓ | ✗ |
| `lots.read` | xem lô/HSD | ✓ | ✓ | ✓ |
| `lots.write` | tạo/sửa lô (gán lô) | ✓ | ✓ | ✗ |
| `suppliers.read` | xem nhà cung cấp | ✓ | ✓ | ✗ |
| `suppliers.write` | CRUD nhà cung cấp | ✓ | ✓ | ✗ |
| `pos.open` | mở/đóng ca | ✓ | ✓ | ✓ |
| `pos.sale` | bán tại POS | ✓ | ✓ | ✓ |
| `pos.discount` | giảm giá (theo mức tối đa role; staff có − nhưng ≤ max) | ✓ | ✓ | ✓(giới hạn) |
| `pos.refund` | trả/hoàn tại POS (+PIN) | ✓ | ✓(PIN) | ✗ |
| `pos.void` | hủy giao dịch | ✓ | ✓(PIN) | ✗ |
| `pos.cash_drawer` | xác nhận tiền mặt/đếm ca | ✓ | ✓ | ✗ |
| `pos.print` | in biên lai | ✓ | ✓ | ✓ |
| `orders.read` | xem đơn web | ✓ | ✓ | ✓ |
| `orders.update` | cập nhật trạng thái đơn | ✓ | ✓ | ✗ |
| `orders.refund` | tạo refund web (+PIN) | ✓ | ✓(PIN) | ✗ |
| `customers.read` | xem khách hàng | ✓ | ✓ | ✓ |
| `customers.write` | tạo/sửa khách | ✓ | ✓ | ✗ |
| `coupons.read` | xem mã giảm giá | ✓ | ✓ | ✗ |
| `coupons.write` | CRUD mã giảm | ✓ | ✓ | ✗ |
| `reports.read` | xem báo cáo | ✓ | ✓ | ✗ |
| `reports.profit` | xem lợi nhuận/giá vốn | ✓ | ✓ | ✗ |
| `settings.read` | đọc cấu hình | ✓ | ✓ | ✗ |
| `settings.write` | sửa cấu hình plugin | ✓ | ✗ | ✗ |
| `staff.read` | xem nhân viên | ✓ | ✓ | ✗ |
| `staff.write` | CRUD nhân viên/override | ✓ | ✗ | ✗ |
| `activity.read` | xem nhật ký hoạt động | ✓ | ✓ | ✗ |
| `sync.manage` | Sync Center / conflict | ✓ | ✓ | ✗ |
| `notifications.read` | xem thông báo | ✓ | ✓ | ✓ |

## 5. Vi phạm điển hình cần PIN (config)

- `PIN` scope: `discount_override`, `refund`, `adjust`, `count_confirm`, `void`, `order_refund`.
- Setting `kc_max_staff_discount_pct` (mặc định 5%), `kc_max_staff_line_discount_pct` (0 = dòng không được giảm).
- Khi staff giảm trên mức → app bắt nhập PIN manager (hoặc yêu cầu admin duyệt) — server kiểm tra `x-approver-pin` + quyền của approver.

## 6. Enforcement (server)

- Mỗi route khai `required_permissions` → `Middleware\Permission::check()`:
  - nạp staff + role base + overrides (transient cache 5s, vô hiệu khi đổi permission).
  - gọi `has_permission($staff, $key)`.
  - không đủ → `403 KC_FORBIDDEN` kèm `required[]`.
- Client: app nhận danh sách permission trong `/auth/me`, ẩn menu/button theo đó (UX). **Không tin client** — server vẫn chặn.

## 7. Nhân viên & mật khẩu/PIN

- Login: username/password (WP auth) hoặc phone + PIN (POS). PIN lưu `phpass`/`password_hash`, never plain.
- Thay đổi permission/role → invalidate token cache; có `kc_activity_log`.

## 8. Giao diện quản lý (admin)

- WP admin settings page: bảng nhân viên (tìm, tạo, sửa, khóa, role, override grid theo checkbox).
- App `Thêm → Nhân viên` (manager xem được, admin sửa được; override chỉ admin).

## 9. Chưa quyết định

- Cơ chế đại diện/permission theo chi nhánh (future — tạm dùng global).
- "Kế toán" role riêng (chỉ báo cáo) — có thể thêm role sau; hiện manager cover.
- Mức discount max cụ thể mỗi shop (cần cấu hình thực tế).

## 10. Phụ thuộc

Plugin: Auth + kc_staff + kc_staff_permissions + kc_activity_log; App: auth provider (permissions list), UI gating.

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Override sai role | prefix UI confirms + audit log ai sửa permission |
| Quên chặn endpoint mới | checklist code review: mọi route phải khai required permission; test negative |
| Nhân viên thoát việc | khóa staff + revoke tokens: tức thì `kc_staff.status`, `kc_auth_tokens.revoked_at` |

## 12. Tài liệu liên quan

[08_AUTHENTICATION_SECURITY](08_AUTHENTICATION_SECURITY.md) · [05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [06_WORDPRESS_PLUGIN_ARCHITECTURE](06_WORDPRESS_PLUGIN_ARCHITECTURE.md) · [16_TESTING_PLAN](16_TESTING_PLAN.md)