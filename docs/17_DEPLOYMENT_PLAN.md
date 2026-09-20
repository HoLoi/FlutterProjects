# 17 · Deployment Plan

## 1. Mục đích

Quy trình triển khai an toàn plugin lên website thật + phân phối APK: kiểm tra trước, cài, backup, rollback, nâng cấp, khôi phục.

## 2. Phạm vi

Triển khai plugin (staging + prod), rollout của Flutter app (APK), backup/recovery, deployment lặp, monitoring sau go-live.

### 2.1 Trạng thái PHASE 1 (A/B)

- **PHASE 1A — ✅ xong**: local + GitHub + review scaffold. `.gitignore` root đã tạo, commit baseline; KHÔNG deploy, KHÔNG cài plugin lên prod.
- **PHASE 1B — ⏸ pending**: cần **staging site**. Hiện **chưa có staging/hosting phụ**, nên §4.1 chưa thực hiện được.
- **Điều kiện gate**: không chạy bất kỳ bước nào trong tài liệu này trên production cho tới khi có staging (hoặc xác nhận rõ của chủ dự án) và qua Production Safety Gate (§5.1).

## 3. Backup & Recovery (trước MỌI thay đổi)

| Loại | Công cụ | Định kỳ |
|---|---|---|
| Full DB | cPanel/mySQL dump các bảng + All-in-One WP Migration (và) bản staging | trước mỗi deployment; tuần tự lịch |
| Media/uploads | FTP copy `wp-content/uploads` | trước go-live; hàng ngày nếu rảnh |
| Plugin/Core | zip thư mục `wp-content/plugins` (thuộc dự án) | per release |
| Kiểm thử khôi phục | restore staging từ backup để chắc quy trình | 1 lần trước Phase 15 |

- Lưu backup tối thiểu 3 gần nhất, xa hơn theo chính sách.
- Document recovery runbook: tắt plugin (deactivate) → restore DB/plugin → xác minh orders/stock.

## 4. Hai môi trường

### 4.1 Staging
- **Bắt buộc tạo bản staging copy** trước khi đụng plugin sản xuất (khuyến nghị subdomain, VD `staging.myphamkimcuong.id.vn` hoặc local dev).
- **Trạng thái hiện tại: CHƯA CÓ staging/hosting phụ → PHASE 1B đang bị block.** Không thao tác production khi thiếu môi trường này.
- Đồng bộ dữ liệu mới nhất gần go-live (data anonymized cho test).
- Kiểm: activation plugin trên staging, các test (16), benchmark, tương thích plugin hiện có.

### 4.2 Production
- Cài qua WP admin (Plugins → Upload) hoặc FTP (tam hoạt). Chạy active; chạy migration tự động đầu tiên (chỉ tạo bảng kc_*).
- **Không sửa file core**. Không chạy script trực tiếp ngoài plugin.
- Giờ thấp điểm khi bật tính năng nặng.

## 5. Deployment flow (plugin)

```
PHASE pre: backup (3.1) → staging cập nhật → chạy test suite
1. Copy code plugin → staging; activate; kiểm migration + smoke test GET APIs
2. (nếu ok) Backup production DB
3. Upload plugin zip lên production → activate (chỉ tạo bảng kc_*, không đụng WC tables)
4. Smoke test production: login kc API 1 tài khoản test; GET /products; tạo/ẩn test product (đánh dấu TEST); POS test trên staging-front khớp
5. Tắt 'is staging' feature, bàn giao cho chủ shop test thủ công 1 ca POS
6. Monitored 48h: log errors, stock balance check, drop in performance
Rollback nếu có sự cố: deactivate plugin (dữ liệu kc_* giữ nguyên), app đã giảm dần; nếu nặng → restore backup đã chụp.
```

### 5.1 Production Safety Gate (bắt buộc) — D-27

KHÔNG deploy gì lên production khi CHƯA pass tất cả:

- [ ] **Backup** DB + files đã **verify bằng cách khôi phục thử** trên môi trường khác.
- [ ] **Staging clone** cập nhật sát production (dữ liệu gần thật).
- [ ] Test **activation / deactivation** plugin (KHÔNG xóa dữ liệu, KHÔNG ngừng site).
- [ ] Test API **read-only** (GET) chạy sạch: không lỗi PHP / warning / chậm web.
- [ ] Test mutation chỉ trên **sản phẩm TEST ẩn**, không đụng sản phẩm thật.
- [ ] **Rollback plan** viết sẵn (steps 1–5 ở trên, kèm backup điểm khôi phục).
- [ ] **Chủ dự án xác nhận thủ công** dưới dạng văn bản/email trước go-live.
- [ ] Bật feature theo **flag từng phần** (không bật tất cả cùng lúc); monitor 48h sau mỗi nhóm.

## 6. Nâng cấp plugin (không mất dữ liệu)

- Migration versioned; chạy tự động mỗi lần activate/update.
- **Không bao giờ** downgrade database (nếu cần → sao lưu + hướng dẫn).
- Release notes bắt buộc; check plugin có update có kiểm tra staging trước.

## 7. Flutter APK distribution

- Build: `flutter build apk --release --split-per-abi` (arm64, armeabi, x86_64) hoặc fat; ký bằng keystore cá nhân (file `.jks` — **phải lưu bí mật, không commit**; đăng ký backup keystore).
- Version: `versionName` + `versionCode` tăng chuẩn (1.0.0+1 → ).
- Phân phối: link private (Firebase App Distribution optional) hoặc server; đính checksum.
- Khi cần Play Store: cần tài khoản Google Play (chi phí) — chờ quyết định.

## 8. Monitoring sau go-live

- `WP_DEBUG_LOG` bật (không hiển thị client) + plugin log riêng heading kc.
- Theo dõi: số sync outbox, conflicts, lỗi idempotency, stock lệch cron, email admin khi critical (through WP Mail SMTP đã có sẵn).
- Benchmark nhẹ tháng đầu: thời gian load dashboard, số request API.

## 9. Recovery runbook (tóm tắt)

```
Sự cố → 
1. Đánh giá mức độ: nội dung plugin (chỉ kc_*) hay ảnh hưởng WC site.
2. Nếu ảnh hưởng đến bán web: DEACTIVATE plugin ngay (dữ liệu WC không mất; chỉ ngừng nghiệp vụ mở rộng).
3. Xử lý cause: fix bug → release patch (test trên staging).
4. Nếu cần restore: dùng backup gần nhất report timeline; cẩn thận mất dữ liệu ít nhất.
5. Thông báo chủ shop; bàn khôi phục từng phần.
```

## 10. Checklist trước go-live (Phase 17)

- [ ] Production Safety Gate (§5.1) pass đủ 8 hạng mục + chủ dự án xác nhận.
- [ ] Backup full đã verify restore staging.
- [ ] Test suite (16) pass - concurrency test OK.
- [ ] Security checklist (08 §10) pass.
- [ ] Permission matrix thực tế đúng ý chủ shop.
- [ ] Settings thực tế: store info, VAT, expiry days, discount max, offline policy, printer models.
- [ ] Nhân viên demo & training.
- [ ] Kế hoạch communication khi bảo trì.

## 11. Chưa quyết định

- Subdomain staging chính thức (cần hosting hỗ trợ) hay chỉ local PHP test.
- Play Store release hay APK private.
- Chính sách backup tự động (lịch cụ thể của hosting).

## 12. Phụ thuộc

Hosting access (cPanel/FTP/WP admin), All-in-One WP Migration (đã có sẵn trên site), WP Mail SMTP (đã có), Flutter signing.

## 13. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Deploy xuống site đang bán bị gián đoạn | staging test trước, giờ thấp điểm, deactivate nhanh |
| Mất keystore app | backup keystore chỗ an toàn |
| Data backup sai | verify restore 1 lần trước go-live |

## 14. Tài liệu liên quan

[06_WORDPRESS_PLUGIN_ARCHITECTURE](06_WORDPRESS_PLUGIN_ARCHITECTURE.md) · [16_TESTING_PLAN](16_TESTING_PLAN.md) · [18_IMPLEMENTATION_ROADMAP](18_IMPLEMENTATION_ROADMAP.md) /* AD & backport */