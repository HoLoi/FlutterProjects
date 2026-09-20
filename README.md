# Hệ Thống Quản Lý Cửa Hàng Mỹ Phẩm — MyPham Kim Cương

> **TRẠNG THÁI: GIAI ĐOẠN LẬP KẾ HOẠCH (PHASE 0)**
> Hiện tại project **chưa có code triển khai chức năng**. Toàn bộ tài liệu trong thư mục `/docs` là kế hoạch kiến trúc, database design, API design, và roadmap. Không được tự ý triển khai code, sửa database, hoặc thay đổi website trước khi có xác nhận chính thức.
>
> **QUAN TRỌNG về code hiện có trong project:**
> - `mypham_kim_cuong_app/` và `mypham-kim-cuong-manager/` hiện chỉ là **scaffold** (khung dự án khởi tạo) — **KHÔNG phải bản triển khai chức năng**.
> - **Không** được dùng scaffold hiện tại cho production; **không** build APK / tạo release từ scaffold.
> - **Không** upload/cài plugin (kể cả bất kỳ `*.zip` nào xuất hiện trong project) lên website production trước khi qua code review + staging + **Production Safety Gate** (mục 8).
> - Bất kỳ file `mypham-kim-cuong-manager.zip` hiện có trong thư mục project **không được coi là bản release**.

---

## 1. Tổng quan

Hệ thống gồm **2 thành phần**, quản lý cửa hàng mỹ phẩm với WordPress / WooCommerce làm nguồn dữ liệu chính:

| Thành phần | Đường dẫn | Vai trò |
|---|---|---|
| **Flutter App** (Android `.apk`) | `mypham_kim_cuong_app/` | App cho chủ cửa hàng/quản lý/nhân viên: POS, kho, lô hàng, hạn sử dụng, báo cáo, quét barcode... |
| **WordPress Plugin** | `mypham-kim-cuong-manager/` | Plugin "MyPham Kim Cuong Manager" — REST API trung gian, mở rộng nghiệp vụ (lô, nhà cung cấp, nhập kho, POS, báo cáo...) giữa App và WooCommerce. |

### Website hiện tại

- Site: `https://myphamkimcuong.id.vn` — **đang hoạt động thực tế**
- WordPress 7.1.1 · PHP 8.1 · WooCommerce 10.4.4
- **Ràng buộc bắt buộc**: không ảnh hưởng website hiện tại; không tự ý sửa/xóa dữ liệu WooCommerce hiện có; không sửa file core WP/WC.

### Kiến trúc tổng thể (mong muốn)

```
Flutter APK
   │  HTTPS
   ▼
[MyPham Kim Cuong Manager REST API]  (WordPress Plugin, namespace kc/v1)
   │
   ▼
WordPress / WooCommerce (CRUD, stock, orders, customers...)
   │
   ▼
MySQL/MariaDB của website
```

- Flutter **KHÔNG** kết nối trực tiếp MySQL.
- Không tạo database sản phẩm riêng cho Flutter.
- WooCommerce là nguồn dữ liệu chính: sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng, danh mục, hình ảnh.

---

## 2. Cấu trúc thư mục

```
D:\FlutterProjects\
├── README.md                         ← Bạn đang ở đây
├── docs/                             ← Toàn bộ tài liệu kế hoạch
│   ├── 01_PROJECT_OVERVIEW.md        ← Tổng quan, mục tiêu, phạm vi
│   ├── 02_REQUIREMENTS.md            ← Phân tích yêu cầu chi tiết (A→AE)
│   ├── 03_SYSTEM_ARCHITECTURE.md     ← Kiến trúc hệ thống tổng thể
│   ├── 04_DATABASE_DESIGN.md         ← Database design (WC + custom tables)
│   ├── 05_API_SPECIFICATION.md       ← API contract, method, error codes
│   ├── 06_WORDPRESS_PLUGIN_ARCHITECTURE.md ← Plugin architecture
│   ├── 07_FLUTTER_ARCHITECTURE.md    ← Flutter architecture
│   ├── 08_AUTHENTICATION_SECURITY.md ← Auth, bảo mật, rate limit
│   ├── 09_INVENTORY_AND_STOCK_FLOW.md← Tồn kho & đồng bộ (race condition)
│   ├── 10_POS_FLOW.md                ← Luồng bán hàng POS
│   ├── 11_EXPIRY_AND_LOT_MANAGEMENT.md ← Lô hàng, NSX/HSD, FEFO
│   ├── 12_REPORTING.md               ← Báo cáo: doanh thu/giá vốn/lợi nhuận
│   ├── 13_OFFLINE_SYNC.md            ← Offline & đồng bộ, conflict
│   ├── 14_PRINTER_BARCODE.md         ← Máy in nhiệt, biên lai, barcode
│   ├── 15_PERMISSION_SYSTEM.md       ← Vai trò & phân quyền
│   ├── 16_TESTING_PLAN.md            ← Kế hoạch kiểm thử
│   ├── 17_DEPLOYMENT_PLAN.md         ← Kế hoạch triển khai & rollback
│   ├── 18_IMPLEMENTATION_ROADMAP.md  ← Roadmap theo phase
│   └── DECISIONS.md                  ← Nhật ký quyết định kiến trúc
│
├── mypham_kim_cuong_app/            ← (tạo sẵn, Flutter template) — App Android
└── mypham-kim-cuong-manager/        ← (folder trống) — WordPress Plugin
```

> Ghi chú: hai thư mục thành phần đã tồn tại dạng scaffold. Code thật sẽ được xây trong các phase theo `18_IMPLEMENTATION_ROADMAP.md`.

---

## 3. Các module chức năng (tóm tắt)

| Ký hiệu | Module | Trạng thái trong kế hoạch |
|---|---|---|
| A | Dashboard + biểu đồ | Thiết kế xong — chờ duyệt |
| B | Quản lý sản phẩm (bao gồm ảnh, upload WP) | Thiết kế xong — chờ duyệt |
| C | Sản phẩm biến thể (variable products) | Thiết kế xong — chờ duyệt |
| D | Quét Barcode/QR | Thiết kế xong — chờ duyệt |
| E | Quản lý lô hàng (NSX/HSD, nhiều lô/product) | Thiết kế xong — chờ duyệt |
| F | Cảnh báo hạn sử dụng | Thiết kế xong — chờ duyệt |
| G | Nhập kho (khai báo lô, NSX/HSD, giá nhập) | Thiết kế xong — chờ duyệt |
| H | Nhà cung cấp | Thiết kế xong — chờ duyệt |
| I | Quản lý kho (lịch sử mọi biến động) | Thiết kế xong — chờ duyệt |
| J | Kiểm kho | Thiết kế xong — chờ duyệt |
| K | POS bán tại cửa hàng | Thiết kế xong — chờ duyệt |
| L | Đơn hàng website (WooCommerce) | Thiết kế xong — chờ duyệt |
| M | Hóa đơn / biên lai (in nhiệt, 58/80mm) | Thiết kế xong — chờ duyệt |
| N | Đồng bộ tồn kho (quan trọng nhất) | Thiết kế xong — chờ duyệt |
| O | Trả hàng / hoàn hàng | Thiết kế xong — chờ duyệt |
| P | Khách hàng | Thiết kế xong — chờ duyệt |
| Q | Khuyến mãi / giảm giá | Thiết kế xong — chờ duyệt |
| R | Báo cáo (doanh thu, giá vốn, lợi nhuận) | Thiết kế xong — chờ duyệt |
| S | Nhân viên / phân quyền | Thiết kế xong — chờ duyệt |
| T | Nhật ký hoạt động | Thiết kế xong — chờ duyệt |
| U | Thông báo | Thiết kế xong — chờ duyệt |
| V | Offline / đồng bộ | Thiết kế xong — chờ duyệt |
| W | Bảo mật | Thiết kế xong — chờ duyệt |
| X | Plugin structure | Thiết kế xong — chờ duyệt |
| Y | API | Thiết kế xong — chờ duyệt |
| Z | Flutter architecture | Thiết kế xong — chờ duyệt |
| AA | Giao diện | Đề xuất xong — chờ duyệt |
| AB | Database | Thiết kế xong — chờ duyệt |
| AC | Tính nhất quán dữ liệu | Thiết kế xong — chờ duyệt |
| AD | Backup/Recovery | Thiết kế xong — chờ duyệt |
| AE | Khả năng mở rộng | Thiết kế xong — chờ duyệt |

---

## 4. Quyết định kiến trúc then chốt (tóm tắt)

Chi tiết đầy đủ tại `docs/DECISIONS.md`.

1. **WooCommerce = source of truth duy nhất** cho sản phẩm, biến thể, giá, SKU, tồn kho, đơn hàng, khách hàng.
2. **Plugin REST API (`kc/v1`)** là lớp trung gian duy nhất; App chỉ gọi HTTPS.
3. **Dữ liệu nghiệp vụ mở rộng** (lô, nhà cung cấp, nhập kho, kiểm kho, POS transaction, activity log, sync outbox...) nằm trong **custom tables `wp_kc_*`**.
4. **Tồn kho = cột `stock_quantity` của WooCommerce** + ghi **mọi biến động vào `kc_inventory_transactions`**. Mọi thay đổi tồn kho đều có lịch sử.
5. **Chống race condition** bằng: `UPDATE ... SET stock = stock − qty WHERE stock >= qty` (atomic) + MySQL transaction + row lock + **idempotency key** trên POS sale và các request quan trọng.
6. **POS sale = tạo WooCommerce order + giao dịch POS + trừ kho + biên lai trong 1 transaction**.
7. **Giá vốn (COGS)** theo lô, chiến lược **FEFO** (ưu tiên lô gần hết hạn); fallback giá vốn trên sản phẩm `_kc_cost`. Báo cáo **luôn tách bạch: Doanh thu ≠ Lợi nhuận**.
8. **Auth**: tài khoản nhân viên do plugin quản lý, mở rộng từ WordPress user + JWT/token server-side, phân quyền theo vai trò `kc_admin / kc_manager / kc_staff` + grid permissions.
9. **Offline**: mặc định **read-only (cache)**; offline POS có thể bật tùy chọn với **hạn mức buffer theo thiết bị** + hàng đợi outbox có idempotency — không bao giờ sync "đẩy hết không kiểm soát".
10. **Deactivate plugin không xóa dữ liệu**; Uninstall chỉ xóa khi người dùng chủ động, có xác nhận.

---

## 5. Môi trường dev hiện tại (đã kiểm tra)

| Hạng mục | Giá trị |
|---|---|
| Working directory | `D:\FlutterProjects` |
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| PHP (local) | **Chưa cài** — cần cài để test plugin/API local |
| Git | Chưa khởi tạo repo |
| App scaffold | `mypham_kim_cuong_app` = template `flutter create` mặc định |
| Plugin scaffold | `mypham-kim-cuong-manager` = folder trống |

---

## 6. Đọc từ đâu?

Nếu là người phát triển mới, đọc theo thứ tự:

1. `docs/01_PROJECT_OVERVIEW.md` — bức tranh toàn cảnh
2. `docs/02_REQUIREMENTS.md` — yêu cầu chi tiết
3. `docs/03_SYSTEM_ARCHITECTURE.md` — kiến trúc
4. `docs/04_DATABASE_DESIGN.md` — database
5. `docs/05_API_SPECIFICATION.md` — API contract
6. `docs/06_WORDPRESS_PLUGIN_ARCHITECTURE.md` — plugin
7. `docs/07_FLUTTER_ARCHITECTURE.md` — Flutter
8. Các tài liệu chuyên sâu theo nhu cầu (POS, kho, offline, báo cáo...)
9. `docs/18_IMPLEMENTATION_ROADMAP.md` — bắt đầu từ PHASE nào, làm gì
10. `docs/DECISIONS.md` — vì sao lại quyết định như vậy

---

## 7. Trạng thái code scaffold hiện tại

- `mypham_kim_cuong_app/` — scaffold mặc định của `flutter create` (chỉ có app demo đếm số, **chưa có chức năng hệ thống**).
- `mypham-kim-cuong-manager/` — folder trống (chưa có file plugin thật).
- **Cả hai chưa phải bản triển khai hoàn chỉnh**, chưa được dùng ở production, **không build APK** từ scaffold này.
- **PHASE 1 sẽ review lại scaffold**: giữ nguyên nếu phù hợp hoặc tạo lại — quyết định cuối ghi vào `docs/DECISIONS.md`.
- Mọi file `*.zip` xuất hiện trong project đều **chưa được coi là release**; chỉ làm việc với code đã qua code review + test.

## 8. Production Safety Gate (bắt buộc trước khi chạm production)

Không được triển khai bất cứ thứ gì lên website thật khi CHƯA vượt qua gate sau (chi tiết `docs/17_DEPLOYMENT_PLAN.md` §6 + `docs/18_IMPLEMENTATION_ROADMAP.md` PHASE 16):

- [ ] Backup database + files (đã **verify khôi phục**).
- [ ] Staging clone cập nhật sát production.
- [ ] Test **activation / deactivation** plugin trên staging.
- [ ] Test API **read-only** chạy sạch (không lỗi PHP / không warning).
- [ ] Test với **sản phẩm TEST** — không đụng sản phẩm thật.
- [ ] **Rollback plan** viết sẵn.
- [ ] **Chủ dự án xác nhận thủ công** (bằng văn bản/email) trước khi go-live.
- [ ] Bật feature theo **flag từng phần**, không bật tất cả cùng lúc.

## 9. Chặn trước khi bắt đầu PHASE 1

Trước khi triển khai bất kỳ code nào, cần **xác nhận từ chủ dự án** các mục trong mục 10 phần báo cáo của `docs/02_REQUIREMENTS.md` — đặc biệt:

- Chế độ **offline** (mặc định read-only, hay cho phép offline POS?)
- In biên lai: máy in 58mm hay 80mm, hãng nào, kết nối Bluetooth model ra sao.
- Tính giá: giá bán/gía nhập đã gồm VAT chưa; quy định hạch toán giá vốn.
- Có dùng **VietQR POS** không → cần cấu hình tài khoản ngân hàng.
- Chính sách **hết hạn**: có chặn bán sản phẩm hết hạn không.
- Mức giảm giá tối đa cho nhân viên.
- Cần không cần **xác nhận bằng mật khẩu/PIN** khi vô ca POS.

---

**Lưu ý pháp lý & hệ thống**: tuân thủ đúng luồng an toàn — luôn backup (theo `docs/17_DEPLOYMENT_PLAN.md`) trước mọi thay đổi trên website thật.# FlutterProjects
# FlutterProjects
