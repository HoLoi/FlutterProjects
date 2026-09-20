# MVP-10B: Test plugin read-only trên website thật (Production)

Hướng dẫn kiểm tra endpoint đọc sản phẩm của plugin `mypham-kim-cuong-manager`
trên website thật tại `https://myphamkimcuong.id.vn`.

> **Quan trọng:** Chỉ thực hiện từng bước khi người thao tác (chủ cửa hàng)
> đồng ý. Người thao tác kiểm thủ công; công cụ/ứng dụng không tự đụng production.

## 1. Mục tiêu

- Xác nhận plugin cài được lên WordPress thật, activate bình thường.
- Xác nhận `GET /wp-json/kc/v1/health` trả dữ liệu chuẩn.
- Xác nhận `GET /wp-json/kc/v1/products` đọc được sản phẩm WooCommerce
  (read-only), đúng cấu trúc JSON đã định nghĩa.
- Xác nhận website frontend vẫn hoạt động bình thường sau khi cài/activate.
- Không thay đổi bất kỳ dữ liệu nào của WooCommerce.

## 2. Điều kiện trước khi test

- Đã có quyền admin WordPress + quyền quản trị hosting (để backup).
- Đã có file cài đặt:
  `mypham-kim-cuong-manager-mvp-readonly.zip`
  (zip chỉ chứa file plugin, không kèm app/docs/secret).
- WooCommerce đã active trên website (nếu chưa active, endpoint sẽ báo
  `wc_active: false` — vẫn là kết quả hợp lệ để ghi nhận).
- Plugin chưa từng được cài trên production trước đó (lần đầu).

## 3. Backup checklist (BẮT BUỘC trước khi cài)

- [ ] Backup đầy đủ **database** (dùng công cụ hosting bản quyền riêng hoặc
      plugin backup đã tin cậy).
- [ ] Backup **thư mục `wp-content/`** (ít nhất là `plugins/` và `uploads/`).
- [ ] Ghi lại phiên bản WordPress + WooCommerce hiện tại (có trong màn
      Cài đặt / Trạng thái site).
- [ ] Xác nhận file backup tải về máy và **mở được** trước khi cài plugin.
- [ ] Xác nhận hosting hỗ trợ **rollback** (snapshot/redeploy) nếu có.

## 4. Cách cài plugin (thủ công từng bước, có xác nhận)

1. Đăng nhập `https://myphamkimcuong.id.vn/wp-admin`.
2. Vào **Plugins → Add New → Upload Plugin**.
3. Chọn file `mypham-kim-cuong-manager-mvp-readonly.zip` → **Install Now**.
4. Nếu WordPress báo cài đặt xong: **Activate** plugin.
5. Kiểm tra màn **Plugins** thấy plugin active, không báo lỗi PHP.

## 5. URL test (chỉ GET, chỉ đọc)

Mở bằng trình duyệt (hoặc `curl -i`) các URL sau:

| Bước | URL | Ghi chú |
| --- | --- | --- |
| 1 | `https://myphamkimcuong.id.vn/wp-json/kc/v1/health` | Kiểm tra plugin hoạt động |
| 2 | `https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=5` | Đọc 5 sản phẩm đầu |
| 3 | `https://myphamkimcuong.id.vn/wp-json/kc/v1/products?per_page=5&search=son` | (tuỳ chọn) tìm theo từ khoá |

Không bấm nút gửi form, không đăng nhập API bên thứ ba, không bật App Flutter
gọi production (app mặc định dùng dữ liệu mock).

## 6. Kết quả mong đợi

### `/wp-json/kc/v1/health` (HTTP 200)

```json
{
  "ok": true,
  "plugin": "mypham-kim-cuong-manager",
  "version": "1.0.0",
  "time": "…",
  "wordpress": "…",
  "woocommerce_active": true
}
```

- Chấp nhận: `woocommerce_active: true` hoặc `false` (ghi chú lại trạng thái).

### `/wp-json/kc/v1/products?per_page=5` (HTTP 200)

```json
{
  "wc_active": true,
  "count": 5,
  "page": 1,
  "per_page": 5,
  "data": [
    {
      "id": 0,
      "name": "…",
      "sku": "…",
      "barcode": "… hoặc null",
      "price": 0,
      "regular_price": 0,
      "sale_price": 0,
      "stock_quantity": 0,
      "stock_status": "instock",
      "image_url": "… hoặc null",
      "categories": [ { "id": 0, "name": "…", "slug": "…" } ],
      "type": "simple"
    }
  ]
}
```

- `count` không vượt quá `per_page` (tối đa 50).
- Nếu WooCommerce chưa active:
  `{ "wc_active": false, "count": 0, "data": [], "message": "WooCommerce chưa
  active, không đọc được sản phẩm." }`

## 7. Kiểm tra website frontend

- [ ] Mở trang chủ và 1 trang sản phẩm bất kỳ: tải nhanh, không báo lỗi.
- [ ] Mở trang quản trị **Products**: danh sách sản phẩm hiển thị bình thường.
- [ ] Kiểm tra **revision/audit** (nếu có): không có thay đổi dữ liệu nào từ plugin.

## 8. Rollback / Deactivate (khi cần)

- Bất kỳ lỗi nào (HTTP 500, plugin báo lỗi, website chậm/lỗi):
  - **Deactivate plugin ngay**: WordPress → Plugins → Deactivate.
  - Ghi lại lỗi (screenshot + message) gửi về repo.
  - Nếu website vẫn lỗi sau deactivate: **khôi phục backup** (database + wp-content).
- Khi test xong và không có thêm pha nào: có thể **Deactivate** plugin
  (plugin không cắm CSS/JS vào frontend nên deactivate không ảnh hưởng gì).

## 9. Những việc TUYỆT ĐỐI không làm

- Không tạo/sửa/xóa sản phẩm, danh mục, thuộc tính, biến thể.
- Không nhập kho, không trừ kho, không cập nhật tồn kho.
- Không tạo order, không cập nhật order, không dùng chức năng POS thật.
- Không gửi POST/PUT/DELETE/PATCH tới bất kỳ endpoint `/wp-json/...`.
- Không chỉnh sửa WooCommerce settings, không chạy cập nhật plugin/theme
  trong lúc test.
- Không tải zip lên kênh khác, không để zip ở nơi công khai truy cập được.
- Không để ứng dụng Flutter (hoặc bất kỳ tool nào) tự động gọi production
  khi chưa có xác nhận từng bước.