# 02 · Kiến Trúc Đơn Giản

## 1. Tổng quan

```text
┌─────────────────────────────────┐
│  Flutter App (Android)          │  Giao diện người dùng
│  mypham_kim_cuong_app           │  Không chứa dữ liệu chính
└───────────────┬─────────────────┘
                │ HTTPS REST (GET)
                ▼
┌─────────────────────────────────┐
│  WordPress Plugin mỏng          │  Chuẩn hoá dữ liệu
│  mypham-kim-cuong-manager       │  + nghiệp vụ WC chưa có
│  namespace: kc/v1               │  Không tự lưu sản phẩm
└───────────────┬─────────────────┘
                │ WooCommerce CRUD / REST API
                ▼
┌─────────────────────────────────┐
│  WooCommerce (nguồn dữ liệu)    │  Sản phẩm, biến thể, giá,
│  https://myphamkimcuong.id.vn  │  tồn kho, đơn hàng, khách hàng
└─────────────────────────────────┘
```

## 2. Trách nhiệm từng lớp

### Flutter app
- Hiển thị dữ liệu, điều hướng, thao tác người dùng
- Gọi plugin qua HTTPS
- **Không** chứa database sản phẩm, **không** tự tính tồn kho
- Cache phiên bộ nhớ (biến), **chưa** có offline database

### WordPress plugin (mỏng)
- Cung cấp endpoint REST `kc/v1`
- Chuẩn hoá dữ liệu WooCommerce thành JSON gọn cho app
- Xử lý nghiệp vụ WooCommerce **chưa có** (ví dụ: mã request duy nhất chống tạo đơn trùng — MVP-13)
- Dùng WooCommerce CRUD chính thức: `wc_get_product()`, `WC_Product_Query()`, `wc_get_order()`, `wc_get_orders()`
- **Không** sửa core WordPress/WooCommerce, chỉ dùng hook/filter chuẩn

### WooCommerce
- Nguồn dữ liệu chính, đã có sẵn dữ liệu thật
- Tự xử lý tồn kho khi có đơn hàng

## 3. Luồng đọc dữ liệu (hiện tại)

```text
App → GET /wp-json/kc/v1/products
    → Plugin: WC_Product_Query
        → WooCommerce: sản phẩm, giá, SKU, tồn kho
    ← JSON chuẩn hoá (id, name, sku, barcode, price, stock_status...)
App hiển thị danh sách, có fallback khi thiếu trường
```

## 4. Luồng ghi dữ liệu (tương lai — MVP-13)

```text
App → POST /wp-json/kc/v1/pos/sales (có Idempotency-Key)
    → Plugin: tạo WooCommerce order bằng wc_create_order()
        → WooCommerce tự trừ tồn kho
    ← order_id, tổng tiền, thay đổi
```

- WooCommerce tự xử lý tồn kho → không trừ kho thủ công ở app
- Mã request duy nhất chống tạo đơn trùng
- Chưa hỗ trợ offline

## 5. Nguyên tắc kỹ thuật

| Vấn đề | Quyết định |
|---|---|
| Truy cập dữ liệu | Chỉ qua REST API, không nối MySQL từ app |
| Sửa tồn kho | WooCommerce CRUD chính thức, không SQL tay |
| Ghi dữ liệu | Chỉ từ MVP-13, có auth + idempotency |
| Bảo mật | Permission kiểm tra ở server, không tin client |
| Múi giờ | Lưu UTC, hiển thị theo giờ cửa hàng |
| Tiền tệ | VND |

## 6. Cấu trúc thư mục

```text
FlutterProjects/
├── mypham_kim_cuong_app/          # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/                # Product, Order, AppSettings
│   │   ├── data/                  # Repository (mock + API)
│   │   ├── services/              # ApiClient, controllers
│   │   ├── screens/               # Giao diện
│   │   └── widgets/
│   └── test/                      # Test MockClient
├── mypham-kim-cuong-manager/      # WordPress plugin
│   ├── mypham-kim-cuong-manager.php
│   ├── uninstall.php
│   └── includes/
│       └── class-rest-api.php     # Endpoint kc/v1
└── docs/                          # Tài liệu (rút gọn)
```

## 7. Những gì CHƯA làm (cố ý)

- ❌ Offline database, sync engine, outbox
- ❌ Multi-branch / multi-warehouse
- ❌ Hệ thống tồn kho riêng (lô, FEFO đầy đủ) — chỉ khi WooCommerce thiếu
- ❌ Event bus, recovery job, kiến trúc enterprise
- ❌ Notification phức tạp, loyalty, in hoá đơn chi tiết

Các ý tưởng này còn nằm trong `docs/archive/` nhưng **không phải kế hoạch bắt buộc**.

## 8. Tài liệu liên quan

[01_PROJECT_OVERVIEW](01_PROJECT_OVERVIEW.md) · [03_API_SPECIFICATION](03_API_SPECIFICATION.md) · [04_DATA_MODEL](04_DATA_MODEL.md) · [05_SECURITY](05_SECURITY.md) · [DECISIONS](DECISIONS.md)
