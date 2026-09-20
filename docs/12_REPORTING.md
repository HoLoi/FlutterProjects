# 12 · Reporting (Báo Cáo, Doanh Thu, Giá Vốn, Lợi Nhuận)

## 1. Mục đích

Định nghĩa chỉ số báo cáo (doanh thu / giá vốn / lợi nhuận gộp), các báo cáo hệ thống phân phối, cách tính, và nguyên tắc "không gọi doanh thu là lợi nhuận".

## 2. Phạm vi

Chỉ số + endpoint + cách aggregate từ dữ liệu (kc tables + WC orders). Không gồm biểu đồ cụ thể (app tự vẽ).

## 3. Định nghĩa chỉ số (canonical)

| Chỉ số | Định nghĩa | Nguồn |
|---|---|---|
| Doanh thu (revenue) | Tổng giá trị bán sau giảm giá (net) của POS + web orders trong kỳ, loại hoàn/hủy | `kc_pos_transactions(status=completed)` + WC orders (không trashed) |
| Giá vốn (COGS) | Chi phí hàng bán: Σ lô cost đã allocate (FEFO) + web sale allocate; thiếu lot → `_kc_cost` fallback | `kc_pos_transaction_items.cost_total` + web order lines (plugin ghi) |
| Lợi nhuận gộp (gross profit) | **Revenue − COGS** | tính toán |
| Số đơn | số giao dịch/đơn | đếm |
| Số lượng bán | Σ qty line items (không tính refund/reversal khi đã trừ) | items |

> Bao giờ cũng hiển thị đủ 3 con số revenue / cost / profit; không bao giờ chỉ mỗi "doanh thu".

## 4. Phạm vi kỳ (period)

- "Hôm nay / ngày / tháng / năm / tùy chọn": theo múi giờ cửa hàng `Asia/Ho_Chi_Minh` (lưu UTC, convert theo tz setting).
- `group_by = day | month | year`; dữ liệu series đủ để vẽ biểu đồ.

## 5. Các báo cáo chính

| Báo cáo | Endpoint | Nội dung |
|---|---|---|
| Tổng hợp | `GET /reports/summary?date_from&date_to` | revenue, cost, gross_profit, orders, units, AOV, theo payment method |
| Doanh thu theo kỳ | `GET /reports/sales?group_by=day|month|year` | series revenue/cost/profit/orders/units |
| Lợi nhuận chi tiết | `GET /reports/profit` | COGS theo lot + fallback; margin % |
| Sản phẩm | `GET /reports/products?sort=best|slow` | top bán chạy (qty, revenue, profit), bán chậm |
| Tồn kho | `GET /reports/inventory` | tồn theo trạng thái, giá trị tồn (Σ stock×cost), sắp hết, hết hạn |
| Nhập/Xuất | thêm `group=receiving|out` | phiếu nhập, số lượng nhập/tổng tiền; xuất (POS sale, write-off) |

- Dashboard dùng chính `reports/summary` + `dashboard/summary` (lấy thêm product/expiry alerts).

## 6. Cách phối dữ liệu (aggregation)

- **POS**: direct đọc `kc_pos_transactions` + items (có sẵn `cost_total` snapshot) → nhanh & chính xác.
- **Web orders**: WC HPOS `wc_get_order` từng đơn (hoặc bảng stats nếu ổn); `_kc_*` meta đã ghi từ hook để biết COGS. Nếu đơn chưa có COGS (order cũ trước plugin) → fallback `_kc_cost`; báo `cost_method`.
- **Refund/return**: trừ ra khỏi revenue các `kc_returns`/WC refund trong kỳ; COGS trừ lại theo LVL cùng kỳ (giữ đơn giản: gross profit = Σ(gross at sale) − Σ(refund cost at refund)). Battach đơn giản hoá: tính net bằng (revenue − refund_amount) và (cost − refund_cost).
- Thống nhất: các chỉ số **đều được tính tại thời điểm giao dịch (snapshot)**, không thay đổi khi sửa giá sau đó → báo cáo ổn định.

## 7. Cash & session (POS)

- Per ca: `reports/summary?session_id=` — tổng doanh thu ca, số giao dịch, cash/bank split, cash_diff.

## 8. Hiệu năng & caching

- Báo cáo nhỏ (< 60 ngày): query trực tiếp chỉ số.
- Dashboard: transient cache 60s.
- Khoảng dài (năm): aggregate theo `group_by` bằng SQL `GROUP BY DATE(created_at)` + index `(type, created_at)`; Phase sau có thể xây bảng aggregate `kc_report_daily` (đã note ở 04 archive).

## 9. Chưa quyết định

- VAT: revenue trước hay gồm thuế (chờ shop) — hiện tại dùng giá đã gồm VAT (giá shop ghi) và tách WC tax engine khi có.
- Có cần so sánh period (tháng này vs tháng trước) — có thể thêm param `compare`.
- Export Excel/CSV từ app — đề xuất thêm: export CSV endpoint.

## 10. Phụ thuộc

Plugin: Reports repository, kc pos tx/items, WC orders, lots costs. App: charts (fl_chart) dashboard; report screens.

## 11. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Web order cũ không có COGS | fallback + ghi chú `cost_method` |
| Refund làm profit âm/cộng | net bằng (sale − refund) theo kỳ, snapshot |
| Series lệch khi đổi tz | lưu UTC + convert chuẩn |
| Báo cáo chậm khi DB lớn | index + cache + aggregate table (Phase sau) |

## 12. Tài liệu liên quan

[05_API_SPECIFICATION](05_API_SPECIFICATION.md) · [10_POS_FLOW](10_POS_FLOW.md) · [11_EXPIRY_AND_LOT_MANAGEMENT](11_EXPIRY_AND_LOT_MANAGEMENT.md) · [09_INVENTORY_AND_STOCK_FLOW](09_INVENTORY_AND_STOCK_FLOW.md)