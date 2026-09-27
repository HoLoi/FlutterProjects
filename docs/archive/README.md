# docs/archive — Tài liệu thiết kế cũ (KHÔNG phải kế hoạch bắt buộc)

Thư mục này chỉ chứa **tài liệu thiết kế cũ** của dự án, được giữ lại để tham khảo lịch sử.

## Không dùng thư mục này để lên kế hoạch

- Các tài liệu ở đây **không còn hiệu lực** làm kế hoạch triển khai.
- Dự án đã chuyển sang **kiến trúc đơn giản** (xem `../02_SIMPLE_ARCHITECTURE.md`).
- Nếu có mâu thuẫn giữa `docs/archive/` và tài liệu trong `docs/`, **tài liệu trong `docs/` thắng**.

## Danh sách file

| File | Nội dung cũ |
|---|---|
| `02_REQUIREMENTS.md` | 30 mục nghiệp vụ A→AE, phân tích mâu thuẫn/thiếu sót |
| `03_SYSTEM_ARCHITECTURE.md` | Kiến trúc 3 lớp chi tiết, module map, luồng đồng bộ |
| `04_DATABASE_DESIGN.md` | Schema 24 bảng `wp_kc_*` (nhiều bảng không dùng cho MVP) |
| `05_API_SPECIFICATION.md` | API contract cũ (thay bằng `../03_API_SPECIFICATION.md`) |
| `06_WORDPRESS_PLUGIN_ARCHITECTURE.md` | Cấu trúc plugin, DI container, migration runner |
| `07_FLUTTER_ARCHITECTURE.md` | Cấu trúc feature-first, Riverpod/Drift/offline cache |
| `08_AUTHENTICATION_SECURITY.md` | JWT chi tiết, luồng refresh token, hardening |
| `09_INVENTORY_AND_STOCK_FLOW.md` | StockManager, guarded SQL, luồng trừ kho |
| `10_POS_FLOW.md` | Luồng POS, logical unit of work, compensation/recovery |
| `11_EXPIRY_AND_LOT_MANAGEMENT.md` | Lô hàng, FEFO, cảnh báo hạn dụng |
| `12_REPORTING.md` | 6 báo cáo, cách tính doanh thu/COGS/lợi nhuận |
| `13_OFFLINE_SYNC.md` | Outbox, SyncEngine, xử lý conflict — **không làm trong MVP** |
| `14_PRINTER_BARCODE.md` | Máy in ESC/POS, nhãn barcode |
| `15_PERMISSION_SYSTEM.md` | 33 permission key, override, PIN |
| `16_TESTING_PLAN.md` | 8 cấp độ test, k6/Locust, GitHub Actions |
| `17_DEPLOYMENT_PLAN.md` | 2 môi trường, monitoring, runbook go-live |
| `18_IMPLEMENTATION_ROADMAP.md` | Roadmap cũ 18 phase (thay bằng `../06_MVP_ROADMAP.md`) |
| `MVP_10B_READONLY_PRODUCTION_TEST.md` | Runbook test read-only production (đã dùng xong) |

## Vì sao archive thay vì xóa

- Giữ lịch sử thiết kế để khi cần mở rộng có thể tham khảo ý tưởng cũ.
- Không xóa Git history.
