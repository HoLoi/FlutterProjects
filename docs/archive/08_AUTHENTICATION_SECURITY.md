# 08 · Authentication & Security

## 1. Mục đích

Thiết kế xác thực, phân quyền, bảo mật API/plugin/app: token lifecycle, permission enforcement, bảo vệ secret, rate limiting, hardening — theo yêu cầu W.

## 2. Phạm vi

Auth (app ↔ plugin), bảo mật data layer, bảo mật deploy, chống lạm dụng. Không phải phân quyền chi tiết (15_PERMISSION).

## 3. Nguyên tắc bất biến

1. App **không bao giờ** kết nối MySQL. Chỉ gọi HTTPS REST.
2. Không hard-code mật khẩu/secret/api key trong app hay repo.
3. Không log password/token/secret.
4. Mọi endpoint check: auth → permission → rate limit → validate.
5. Kiểm soát quyền **ở server**, không tin client.

## 4. Luồng xác thực

### 4.1 Đăng nhập
```
App → POST /auth/login (username+password hay phone+PIN)
Server:
  - tim kc_staff (active) + user WP => verify password (`wp_check_password`) hoặc PIN (password_hash bcrypt)
  - sinh access JWT (payload: staff_id, device_id, role, iat, exp ~1h)
  - sinh refresh token (ngẫu nhiên 256-bit, hash SHA-256 lưu bảng kc_auth_tokens, exp 24h)
  - lưu token_hash + refresh_hash + device_id
  - trả token + staff + permissions + store info
```
### 4.2 Sử dụng
- Access token ở header `Authorization: Bearer`.
- 401 → client gọi `/auth/refresh` (refresh token) → token mới (rotate: refresh cũ bị vô hiệu) → retry request cũ 1 lần.
- Mất refresh → logout → login lại.

### 4.3 Thu hồi / an toàn
- Revoke 1 token, revoke tất cả thiết bị của 1 nhân viên (`logout?all=true`), admin khóa nhân viên → vô hiệu mọi token (check `kc_staff.status` + `kc_auth_tokens.revoked_at` trong middleware — gọi DB, đợn giản nhưng tin cậy; cache ngắn).

## 5. JWT — chi tiết

- SHA-256 HMAC với key từ `wp_salt('auth')` + plugin secret (không lưu static). JWT claim: `iss`, `st` (staff), `dev` (device), `rol`, `iat`, `exp`.
- **Không** nhúng permission vào token (thay đổi role tức thì nên check DB mỗi request — bảng permission nhỏ, cache trong transient 5s).
- Nếu hosting không có firewall chặn → luôn xác thực trước khi đọc bất kỳ route.

## 6. Permission enforcement (server)

- Mỗi route khai báo 1 danh sách `required_permissions[]` (vd: pos/sales → `pos.sale`).
- `PermissionMiddleware`: kết hợp role (**base role** của `kc_staff.role`) + override `kc_staff_permissions`.
- Mỗi permission key ~ hành động nghiệp vụ (danh sách: 15_PERMISSION).
- Các quyền nhạy cảm (POS discount > setting, inventory.adjust, refund, staff.write...) thêm **PIN xác nhận** do client gửi `x-approver-pin` (manager) — validate server.

## 7. Bảo mật dữ liệu

### 7.1 Secret quản lý
- Cấu hình nhạy cảm (VietQR ngân hàng, mail...) lưu trong WP options nhưng giá trị **mã hóa** (openssl + key từ `wp_salt('kc')`), chỉ decrypt server-side; không trả ra API công khai.
- WooCommerce API keys, FTP, DB creds: nằm ở hosting/config — KHÔNG lưu trong plugin/repo.

### 7.2 Validate / sanitize
- Mọi input REST: whitelist param (`Args` của WP REST) + `Sanitize\dry` theo loại (intval, sanitize_text_field, wp_kses cho HTML mô tả, json dùng `wp_json_encode` output).
- SQL: dùng `$wpdb->prepare` 100%; không nối chuỗi.

### 7.3 CSRF/XSS/SSRF
- REST Cookie-auth không dùng → CSRF giảm; vẫn bật `rest_authentication_errors` để chặn. CORS: chỉ cho origin cần nếu mở web tool (mặc định same-origin validate `Origin` nếu cần).
- Output HTML luôn escape. Upload file: kiểm tra extension/MIME/bảo mật (limit size, không thực thi php).

### 7.4 Rate limiting
- `kc_rate_limit`: sliding window theo (staff_id + endpoint group + IP). Default: login 5/min/IP, mutation 60/min/staff, GET lists 300/min/staff. Trả `429` + `Retry-After`.

### 7.5 Logging (an toàn)
- `kc_activity_log` chỉ ghi các field cần; không ghi password/token/payload raw nếu có secret.
- `error_log` server: log `error_id` + code, không log body login.

## 8. Bảo mật Flutter app (client)

- Token trong `flutter_secure_storage` (Keystore Android); không `SharedPreferences`.
- Không hard-code base url có thể đổi nhưng default duy nhất HTTPS; app từ chối HTTP (build config).
- ProGuard/R8: keep classes cần; không cần obfuscation mạnh.
- Certificate: `https` pinning tùy chọn (đề xuất sau khi chắc host stable; ban đầu không pin để linh hoạt).
- Không lưu số TMDB/SĐT khách hàng ngoài cache nếu không cần (GDPR-ish tốt).

## 9. Bảo mật plugin & hosting

- Chặn truy cập trực tiếp file (guard `defined('ABSPATH')`).
- Không expose phpinfo / debug off production (`WP_DEBUG_DISPLAY` off).
- Cập nhật WP/WC/plugin định kỳ; plugin chỉ dùng API cần thiết (nguyên tắc least privilege).
- Uninstall quyền admin; activation check.

## 10. Security review checklist (chạy trong PHASE 14 — xem roadmap; cơ bản lồng từ PHASE 7)

- [ ] Pen-test cơ bản các endpoint: auth bypass, IDOR (sửa object của người khác bằng param), injection SQL/XSS.
- [ ] Thử rate limit, brute force login, token replay (refresh rotate).
- [ ] Kiểm tra permission matrix theo role.
- [ ] Check raw logs không có secret.
- [ ] Kiểm tra upload file không thực thi.
- [ ] Confirm HTTPS + không kết nối MySQL từ app (kiểm tra build).

## 11. Chưa quyết định

- OTP SMS qua email/password (GD11) — nếu dùng phải provider.
- Biometric (fingerprint face) cho đăng nhập POS — đề xuất thêm Option later (config per device).
- TLS pinning.

## 12. Phụ thuộc

WP Core (auth_salt, REST), plugin modules (Auth, RateLimiter, Permission, Validators, SecretBox), Flutter (secure storage, crypto).

## 13. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Token bị đánh cắp (device root) | short expiry + revoke + device registry |
| Brute-force login | rate limit + lockout IP/staff sau N lần |
| Quyền rộng vô tình | permission whitelist + review matrix mỗi release |
| Secret bị lộ qua backup rep | .gitignore + secret không commit; `wp-config` ngoài repo |

## 14. Tài liệu liên quan

[05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [15_PERMISSION_SYSTEM](15_PERMISSION_SYSTEM.md) · [07_FLUTTER_ARCHITECTURE](07_FLUTTER_ARCHITECTURE.md) · [16_TESTING_PLAN](16_TESTING_PLAN.md)