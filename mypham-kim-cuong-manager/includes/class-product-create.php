<?php
/**
 * Tạo sản phẩm đơn giản từ app POS (namespace `kc/v1`).
 *
 * Endpoint: `POST /wp-json/kc/v1/products`.
 *
 * Phạm vi cố ý hẹp — chỉ những gì luồng "quét mã → nhập nhanh" cần:
 * - Chỉ tạo sản phẩm **simple**. Không tạo biến thể, không tạo sản phẩm nhóm,
 *   không tạo sản phẩm ngoài. App muốn bán sản phẩm biến thể phải tạo trước
 *   trong trang quản trị WooCommerce.
 * - Không upload ảnh. Ảnh được đặt sau trong trang quản trị.
 * - Không tạo sản phẩm nhập kho, lô hàng, nhiều kho, nhập kho. Chỉ tồn kho đơn
 *   giản của WooCommerce.
 * - Mặc định `status` là `draft` để người dùng rà soát trước khi đăng bán.
 *
 * Nguyên tắc bắt buộc:
 * - Tạo sản phẩm bằng WooCommerce CRUD chính thức (`new WC_Product_Simple()`
 *   + setter + `save()`). Không `wp_insert_post()`, không SQL, không bảng riêng.
 * - Barcode ghi vào meta chính thức `_mkc_barcode` qua `update_meta_data()`, đúng
 *   key mà `GET /products/barcode/{barcode}` đọc lại. Không tự sửa `_stock` bằng
 *   phép toán: tồn kho đi qua `set_manage_stock()` / `set_stock_quantity()` /
 *   `set_stock_status()` để WooCommerce tự đồng bộ.
 * - SKU và barcode phải duy nhất. Kiểm tra trước khi tạo bằng API chính thức:
 *   `wc_get_product_id_by_sku()` cho SKU, `get_posts()` + `meta_query` cho
 *   barcode (cùng cơ chế với endpoint tra cứu barcode).
 * - Xác thực bằng WordPress Application Password qua HTTPS + capability
 *   `manage_woocommerce`. Không JWT tự viết, không secret trong plugin.
 * - Không trả credential, không trả đường dẫn filesystem.
 * - KHÔNG dùng `set_created_via()` / `get_created_via()` trên sản phẩm: đó là
 *   thuộc tính của order và customer, không phải của product. Gọi nó trên
 *   `WC_Product_Simple` rơi vào magic method `WC_Data::__call()` và làm request
 *   chết với HTTP 500. Nếu cần đánh dấu nguồn gốc sản phẩm thì dùng meta riêng.
 * - Mọi exception trong lúc tạo đều bị bắt, ghi ra log máy chủ kèm tên giai đoạn
 *   và tên class exception, nhưng response chỉ trả mã lỗi chung. Log KHÔNG chứa
 *   body request, header `Authorization`, mật khẩu hay dữ liệu khách hàng.
 *
 * Route `POST /products` được đăng ký bởi `MKC_REST_API` cùng GET `/products`
 * (xem `create_endpoint()`); file này chỉ cung cấp permission, validation và CRUD.
 *
 * @package mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class MKC_Product_Create_API {

	/** Độ dài tối đa của tên sản phẩm. */
	const MAX_NAME_LENGTH = 200;

	/** Độ dài tối đa của SKU. */
	const MAX_SKU_LENGTH = 100;

	/** Độ dài tối đa của barcode, khớp với endpoint tra cứu barcode. */
	const MAX_BARCODE_LENGTH = 64;

	/** Số ký tự tối đa của mô tả ngắn. */
	const MAX_SHORT_DESCRIPTION_LENGTH = 500;

	/** Số ký tự tối đa của mô tả. */
	const MAX_DESCRIPTION_LENGTH = 5000;

	/** Giá lớn nhất được nhận, chặn nhập nhầm số khổng lồ. */
	const MAX_PRICE = 999999999;

	/** Tồn kho lớn nhất được nhận. */
	const MAX_STOCK_QUANTITY = 999999;

	/**
	 * Meta key chứa barcode. Phải giống `MKC_Product_Barcode_API::META_KEYS[0]`
	 * để sản phẩm tạo ở đây luôn tra cứu được ngay.
	 */
	const BARCODE_META = '_mkc_barcode';

	/**
	 * KHÔNG có hằng `CREATED_VIA` cho sản phẩm.
	 *
	 * `created_via` là thuộc tính của **order** (`WC_Abstract_Order`) và của
	 * **customer**, không phải của product. `WC_Product` không khai báo prop
	 * này, nên gọi `$product->set_created_via()` rơi vào magic method
	 * `WC_Data::__call()` và làm request chết với HTTP 500. Nếu sau này cần
	 * đánh dấu sản phẩm tạo từ POS thì dùng **meta** riêng, ví dụ
	 * `_mkc_created_via`, chứ không dùng lại thuộc tính của order.
	 */

	/** Trạng thái sản phẩm được phép tạo. `draft` là mặc định. */
	const ALLOWED_STATUSES = array( 'draft', 'publish' );

	/** Trạng thái tồn kho được phép đặt tường minh. */
	const ALLOWED_STOCK_STATUSES = array( 'instock', 'outofstock', 'onbackorder' );

	/** Tên nguồn log khi ghi vào WooCommerce log. */
	const LOG_SOURCE = 'mkc-product-create';

	/**
	 * Cấu hình endpoint `POST /products`.
	 *
	 * Endpoint này được `MKC_REST_API::register_routes()` gắn vào CÙNG một lệnh
	 * gọi `register_rest_route()` với GET `/products`, nên file này không tự
	 * gọi `register_rest_route()` và không tự hook `rest_api_init`. Lý do: WP
	 * core định nghĩa rõ ràng dạng nhiều endpoint cho một path, còn việc gọi
	 * `register_rest_route()` hai lần với cùng path thì phụ thuộc cơ chế merge
	 * nội bộ và có thể làm mất `args` phân trang của GET.
	 *
	 * `class-product-create.php` phải được nạp trước khi route được đăng ký
	 * (bootstrap nạp nó cùng các file khác, route chỉ đăng ký lúc `rest_api_init`).
	 *
	 * @return array Endpoint definition cho `register_rest_route()`.
	 */
	public static function create_endpoint() {
		return array(
			'methods'             => 'POST',
			'callback'            => array( __CLASS__, 'handle_create_product' ),
			'permission_callback' => array( __CLASS__, 'permission_create_product' ),

			// Không khai báo `args`: body JSON được đọc thủ công trong handler,
			// nên JSON hỏng hoặc thiếu trường trả đúng mã lỗi của plugin thay vì
			// bị WordPress bọc thành `rest_invalid_param`.
		);
	}

	/* ---------------------------------------------------------------------
	 * Permission
	 * ------------------------------------------------------------------ */

	/**
	 * Quyền tạo sản phẩm: bắt buộc đăng nhập, HTTPS và `manage_woocommerce`.
	 *
	 * Không nới quyền như `GET /products/barcode/{barcode}` vì đây là thao tác
	 * ghi: tạo sản phẩm trong catalog dùng chung với website. Thứ tự trả lỗi
	 * cố định:
	 *
	 * - Chưa đăng nhập  → 401 kc_not_authenticated
	 * - Không phải HTTPS → 403 kc_https_required
	 * - Thiếu quyền     → 403 kc_cannot_create_product
	 *
	 * @return true|WP_Error
	 */
	public static function permission_create_product() {
		if ( ! is_user_logged_in() ) {
			return self::error( 'kc_not_authenticated', 'Cần đăng nhập để tạo sản phẩm.', 401 );
		}

		if ( ! self::is_secure_request() ) {
			return self::error(
				'kc_https_required',
				'Chỉ chấp nhận kết nối HTTPS vì header xác thực được gửi dạng chữ thường.',
				403
			);
		}

		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			return self::error( 'kc_cannot_create_product', 'Tài khoản không có quyền tạo sản phẩm.', 403 );
		}

		return true;
	}

	/**
	 * Request có đi qua HTTPS hay không.
	 *
	 * `is_ssl()` đã tự nhận `X-Forwarded-Proto`, nên thêm fallback theo scheme
	 * của `home_url()` phòng trường hợp site chạy sau proxy mà WordPress không
	 * nhận diện được. Nếu site thật sự chạy HTTP thì endpoint trả 403 thay vì
	 * nhận mật khẩu dạng chữ thường.
	 *
	 * @return bool
	 */
	private static function is_secure_request() {
		if ( is_ssl() ) {
			return true;
		}

		$scheme = wp_parse_url( home_url(), PHP_URL_SCHEME );

		return ( 'https' === $scheme );
	}

	/* ---------------------------------------------------------------------
	 * Handler
	 * ------------------------------------------------------------------ */

	/**
	 * Tạo một sản phẩm simple.
	 *
	 * Luồng: đọc JSON → kiểm tra input → kiểm tra SKU/barcode trùng → tạo bằng
	 * WooCommerce CRUD → đọc lại sản phẩm vừa lưu để trả payload.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_create_product( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$payload = self::read_json_body( $request );
		if ( is_wp_error( $payload ) ) {
			return $payload;
		}

		$input = self::read_input( $payload );
		if ( is_wp_error( $input ) ) {
			return $input;
		}

		$conflict = self::check_conflicts( $input );
		if ( is_wp_error( $conflict ) ) {
			return $conflict;
		}

		return self::create_product( $input );
	}

	/* ---------------------------------------------------------------------
	 * Input
	 * ------------------------------------------------------------------ */

	/**
	 * Đọc body JSON thủ công để kiểm soát lỗi parse.
	 *
	 * `WP_REST_Request::get_json_params()` im lặng khi JSON hỏng, nên đọc raw
	 * body và `json_decode()` trực tiếp để trả 400 rõ ràng.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return array|WP_Error
	 */
	private static function read_json_body( $request ) {
		$body = trim( (string) $request->get_body() );

		if ( '' === $body ) {
			return self::error( 'kc_invalid_json', 'Body rỗng, phải gửi nội dung JSON.', 400 );
		}

		// `[]` cũng decode thành array rỗng, nên kiểm tra ký tự đầu để bắt đúng
		// trường hợp body phải là JSON object.
		if ( '{' !== substr( $body, 0, 1 ) ) {
			return self::error( 'kc_invalid_request', 'Body phải là JSON object.', 400 );
		}

		$data = json_decode( $body, true );

		if ( JSON_ERROR_NONE !== json_last_error() || ! is_array( $data ) ) {
			return self::error(
				'kc_invalid_json',
				sprintf( 'Body không phải JSON hợp lệ (%s).', json_last_error_msg() ),
				400
			);
		}

		return $data;
	}

	/**
	 * Kiểm tra toàn bộ payload và trả về dữ liệu đã chuẩn hoá.
	 *
	 * Mọi trường đều kiểm tra TRƯỚC khi đụng WooCommerce, nếu không người gọi sẽ
	 * phải dò từng lỗi một. Thứ tự trả lỗi theo thứ tự trường trong tài liệu:
	 * `name` → `barcode` → `sku` → `price` → tồn kho → `status`.
	 *
	 * @param array $payload Body đã decode.
	 * @return array|WP_Error
	 */
	private static function read_input( $payload ) {
		$name = self::read_name( $payload );
		if ( is_wp_error( $name ) ) {
			return $name;
		}

		$barcode = self::read_barcode( $payload );
		if ( is_wp_error( $barcode ) ) {
			return $barcode;
		}

		$sku = self::read_sku( $payload );
		if ( is_wp_error( $sku ) ) {
			return $sku;
		}

		$regular_price = self::read_regular_price( $payload );
		if ( is_wp_error( $regular_price ) ) {
			return $regular_price;
		}

		$sale_price = self::read_sale_price( $payload, $regular_price );
		if ( is_wp_error( $sale_price ) ) {
			return $sale_price;
		}

		$stock = self::read_stock( $payload );
		if ( is_wp_error( $stock ) ) {
			return $stock;
		}

		$status = self::read_status( $payload );
		if ( is_wp_error( $status ) ) {
			return $status;
		}

		return array(
			'name'              => $name,
			'barcode'           => $barcode,
			'sku'               => $sku,
			'regular_price'     => $regular_price,
			'sale_price'        => $sale_price,
			'manage_stock'      => $stock['manage_stock'],
			'stock_quantity'    => $stock['stock_quantity'],
			'stock_status'      => $stock['stock_status'],
			'status'            => $status,
			'short_description' => self::read_short_description( $payload ),
			'description'       => self::read_description( $payload ),
		);
	}

	/**
	 * `name`: bắt buộc, không rỗng sau khi làm sạch.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_name( $payload ) {
		$raw = isset( $payload['name'] ) ? $payload['name'] : '';

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_name', 'name phải là chuỗi.', 400 );
		}

		$name = sanitize_text_field( $raw );
		$name = trim( $name );

		if ( '' === $name ) {
			return self::error( 'kc_invalid_name', 'Thiếu tên sản phẩm.', 400 );
		}

		if ( self::length( $name ) > self::MAX_NAME_LENGTH ) {
			return self::error(
				'kc_invalid_name',
				sprintf( 'Tên sản phẩm tối đa %d ký tự.', self::MAX_NAME_LENGTH ),
				400
			);
		}

		return $name;
	}

	/**
	 * `barcode`: bắt buộc, đúng định dạng mà endpoint tra cứu chấp nhận.
	 *
	 * Dùng chung regex với `GET /products/barcode/{barcode}` để sản phẩm tạo ở
	 * đây luôn tra cứu được ngay sau khi tạo.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_barcode( $payload ) {
		$raw = isset( $payload['barcode'] ) ? $payload['barcode'] : '';

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_barcode', 'barcode phải là chuỗi.', 400 );
		}

		$barcode = trim( $raw );

		if ( '' === $barcode ) {
			return self::error( 'kc_invalid_barcode', 'Thiếu barcode sản phẩm.', 400 );
		}

		if ( strlen( $barcode ) > self::MAX_BARCODE_LENGTH ) {
			return self::error(
				'kc_invalid_barcode',
				sprintf( 'Barcode tối đa %d ký tự.', self::MAX_BARCODE_LENGTH ),
				400
			);
		}

		if ( ! preg_match( '/^[A-Za-z0-9._-]+$/', $barcode ) ) {
			return self::error(
				'kc_invalid_barcode',
				'Barcode chỉ gồm chữ cái không dấu, chữ số và các ký tự . _ -',
				400
			);
		}

		return $barcode;
	}

	/**
	 * `sku`: tuỳ chọn. Bỏ trống thì không đặt SKU.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_sku( $payload ) {
		$raw = isset( $payload['sku'] ) ? $payload['sku'] : '';

		// `null` và số đều được đưa về chuỗi rồi xử lý như text: app có thể gửi
		// SKU dạng số (mã vạch nằm trong trường này) và đó là cách sử dụng hợp lệ.
		if ( null === $raw || is_int( $raw ) || is_float( $raw ) ) {
			$raw = (string) $raw;
		}

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_sku', 'sku phải là chuỗi.', 400 );
		}

		$sku = trim( $raw );

		if ( '' === $sku ) {
			return '';
		}

		if ( self::length( $sku ) > self::MAX_SKU_LENGTH ) {
			return self::error(
				'kc_invalid_sku',
				sprintf( 'SKU tối đa %d ký tự.', self::MAX_SKU_LENGTH ),
				400
			);
		}

		// Cùng bộ ký tự với barcode để SKU an toàn khi hiển thị trên báo cáo và
		// khớp với những gì WooCommerce sinh ra cho sản phẩm khác.
		if ( ! preg_match( '/^[A-Za-z0-9._-]+$/', $sku ) ) {
			return self::error(
				'kc_invalid_sku',
				'SKU chỉ gồm chữ cái không dấu, chữ số và các ký tự . _ -',
				400
			);
		}

		return $sku;
	}

	/**
	 * `regular_price`: bắt buộc, số không âm.
	 *
	 * Chấp nhận cả số và chuỗi số ("189000") vì form của app hay gửi text.
	 * Dùng `is_numeric()` thay vì ép kiểu để tránh biến "12abc" thành 12.
	 *
	 * @param array $payload Body đã decode.
	 * @return float|WP_Error
	 */
	private static function read_regular_price( $payload ) {
		$raw = isset( $payload['regular_price'] ) ? $payload['regular_price'] : null;

		if ( null === $raw || '' === $raw || ! is_scalar( $raw ) ) {
			return self::error( 'kc_invalid_price', 'Thiếu regular_price.', 400 );
		}

		if ( ! is_numeric( $raw ) ) {
			return self::error( 'kc_invalid_price', 'regular_price phải là số.', 400 );
		}

		$price = (float) $raw;

		if ( $price < 0 ) {
			return self::error( 'kc_invalid_price', 'regular_price không được âm.', 400 );
		}

		if ( $price > self::MAX_PRICE ) {
			return self::error(
				'kc_invalid_price',
				sprintf( 'regular_price tối đa %d.', (int) self::MAX_PRICE ),
				400
			);
		}

		return round( $price, wc_get_price_decimals() );
	}

	/**
	 * `sale_price`: tuỳ chọn. Bỏ trống hoặc 0 nghĩa là không giảm giá.
	 *
	 * @param array $payload      Body đã decode.
	 * @param float $regular_price Giá gốc đã kiểm tra.
	 * @return float|WP_Error Giá giảm, `0.0` nghĩa là không có giá giảm.
	 */
	private static function read_sale_price( $payload, $regular_price ) {
		$raw = isset( $payload['sale_price'] ) ? $payload['sale_price'] : null;

		if ( null === $raw || '' === $raw ) {
			return 0.0;
		}

		if ( ! is_scalar( $raw ) || ! is_numeric( $raw ) ) {
			return self::error( 'kc_invalid_sale_price', 'sale_price phải là số.', 400 );
		}

		$price = (float) $raw;

		if ( $price < 0 ) {
			return self::error( 'kc_invalid_sale_price', 'sale_price không được âm.', 400 );
		}

		if ( $price > self::MAX_PRICE ) {
			return self::error(
				'kc_invalid_sale_price',
				sprintf( 'sale_price tối đa %d.', (int) self::MAX_PRICE ),
				400
			);
		}

		if ( $price > 0 && $price >= $regular_price ) {
			return self::error( 'kc_invalid_sale_price', 'sale_price phải nhỏ hơn regular_price.', 400 );
		}

		if ( 0.0 === $price ) {
			return 0.0;
		}

		return round( $price, wc_get_price_decimals() );
	}

	/**
	 * Tồn kho: `stock_quantity` và `stock_status`.
	 *
	 * Mặc định quản lý kho với số lượng 0, vì sản phẩm mới tạo từ POS chưa có
	 * hàng thật. Số âm bị từ chối.
	 *
	 * @param array $payload Body đã decode.
	 * @return array|WP_Error
	 */
	private static function read_stock( $payload ) {
		$quantity = isset( $payload['stock_quantity'] ) ? $payload['stock_quantity'] : 0;

		if ( null === $quantity || '' === $quantity ) {
			$quantity = 0;
		}

		$parsed = self::non_negative_integer( $quantity );

		if ( null === $parsed ) {
			return self::error( 'kc_invalid_stock', 'stock_quantity phải là số nguyên không âm.', 400 );
		}

		if ( $parsed > self::MAX_STOCK_QUANTITY ) {
			return self::error(
				'kc_invalid_stock',
				sprintf( 'stock_quantity tối đa %d.', self::MAX_STOCK_QUANTITY ),
				400
			);
		}

		$manage_stock = isset( $payload['manage_stock'] ) ? $payload['manage_stock'] : true;

		if ( ! is_bool( $manage_stock ) ) {
			if ( null === $manage_stock || '' === $manage_stock ) {
				$manage_stock = true;
			} elseif ( is_string( $manage_stock ) && in_array( strtolower( $manage_stock ), array( 'true', 'false' ), true ) ) {
				$manage_stock = ( 'true' === strtolower( $manage_stock ) );
			} elseif ( is_int( $manage_stock ) && in_array( $manage_stock, array( 0, 1 ), true ) ) {
				$manage_stock = ( 1 === $manage_stock );
			} else {
				return self::error( 'kc_invalid_stock', 'manage_stock phải là boolean.', 400 );
			}
		}

		$stock_status = isset( $payload['stock_status'] ) ? $payload['stock_status'] : '';

		if ( is_string( $stock_status ) ) {
			$stock_status = trim( $stock_status );
		}

		if ( null === $stock_status || '' === $stock_status ) {
			// Không chỉ định thì suy ra từ số lượng: có hàng thì `instock`, hết
			// hàng thì `outofstock`. Không tự đặt `onbackorder` vì bán thiếu hàng
			// là quyết định của người dùng, không phải suy luận của API.
			$stock_status = ( $parsed > 0 ) ? 'instock' : 'outofstock';
		}

		if ( ! in_array( $stock_status, self::ALLOWED_STOCK_STATUSES, true ) ) {
			return self::error(
				'kc_invalid_stock',
				sprintf(
					'stock_status không hợp lệ. Chỉ nhận: %s.',
					implode( ', ', self::ALLOWED_STOCK_STATUSES )
				),
				400
			);
		}

		return array(
			'manage_stock'   => (bool) $manage_stock,
			'stock_quantity' => $parsed,
			'stock_status'   => $stock_status,
		);
	}

	/**
	 * `status`: tuỳ chọn, mặc định `draft`.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_status( $payload ) {
		$raw = isset( $payload['status'] ) ? $payload['status'] : '';

		if ( null === $raw || '' === $raw ) {
			return 'draft';
		}

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_status', 'status phải là chuỗi.', 400 );
		}

		$status = trim( $raw );

		if ( ! in_array( $status, self::ALLOWED_STATUSES, true ) ) {
			return self::error(
				'kc_invalid_status',
				sprintf(
					'status không hợp lệ. Chỉ nhận: %s.',
					implode( ', ', self::ALLOWED_STATUSES )
				),
				400
			);
		}

		return $status;
	}

	/**
	 * `short_description`: tuỳ chọn, cắt còn tối đa 500 ký tự.
	 *
	 * @param array $payload Body đã decode.
	 * @return string
	 */
	private static function read_short_description( $payload ) {
		$raw = isset( $payload['short_description'] ) ? $payload['short_description'] : '';

		if ( ! is_string( $raw ) ) {
			$raw = is_scalar( $raw ) ? (string) $raw : '';
		}

		return self::truncate( sanitize_textarea_field( $raw ), self::MAX_SHORT_DESCRIPTION_LENGTH );
	}

	/**
	 * `description`: tuỳ chọn, cắt còn tối đa 5000 ký tự.
	 *
	 * @param array $payload Body đã decode.
	 * @return string
	 */
	private static function read_description( $payload ) {
		$raw = isset( $payload['description'] ) ? $payload['description'] : '';

		if ( ! is_string( $raw ) ) {
			$raw = is_scalar( $raw ) ? (string) $raw : '';
		}

		return self::truncate( sanitize_textarea_field( $raw ), self::MAX_DESCRIPTION_LENGTH );
	}

	/* ---------------------------------------------------------------------
	 * Kiểm tra trùng
	 * ------------------------------------------------------------------ */

	/**
	 * Kiểm tra SKU và barcode chưa tồn tại.
	 *
	 * - SKU: `wc_get_product_id_by_sku()` tra cả sản phẩm lẫn biến thể, an toàn
	 *   với HPOS.
	 * - Barcode: `get_posts()` + `meta_query` trên `product` và `product_variation`,
	 *   đúng cơ chế endpoint tra cứu barcode, bao gồm cả key dự phòng
	 *   `_barcode` để không tạo ra sản phẩm trùng với dữ liệu cũ.
	 *
	 * @param array $input Dữ liệu đã chuẩn hoá.
	 * @return true|WP_Error
	 */
	private static function check_conflicts( $input ) {
		$existing_sku = self::check_sku_conflict( $input['sku'] );
		if ( is_wp_error( $existing_sku ) ) {
			return $existing_sku;
		}

		if ( $existing_sku > 0 ) {
			return self::error(
				'kc_duplicate_sku',
				sprintf( 'SKU "%s" đã thuộc sản phẩm #%d.', $input['sku'], (int) $existing_sku ),
				400
			);
		}

		$existing_barcode = self::check_barcode_conflict( $input['barcode'] );
		if ( is_wp_error( $existing_barcode ) ) {
			return $existing_barcode;
		}

		if ( $existing_barcode > 0 ) {
			return self::error(
				'kc_duplicate_barcode',
				sprintf( 'Barcode "%s" đã thuộc sản phẩm #%d.', $input['barcode'], (int) $existing_barcode ),
				400
			);
		}

		return true;
	}

	/**
	 * SKU đã thuộc sản phẩm nào chưa, `0` nếu còn trống.
	 *
	 * @param string $sku SKU đã chuẩn hoá, có thể rỗng.
	 * @return int
	 */
	private static function check_sku_conflict( $sku ) {
		if ( '' === $sku ) {
			return 0;
		}

		try {
			return (int) wc_get_product_id_by_sku( $sku );
		} catch ( \Throwable $e ) {
			return 0;
		}
	}

	/**
	 * Id sản phẩm hoặc biến thể đang giữ barcode này, `0` nếu chưa có ai giữ.
	 *
	 * Trả `WP_Error` 500 khi không tra được, để caller KHÔNG tạo sản phẩm. Nếu
	 * im lặng coi như không trùng thì một lỗi tạm thời sẽ sinh ra sản phẩm trùng
	 * barcode mà app không hề biết.
	 *
	 * @param string $barcode Barcode đã kiểm tra.
	 * @return int|WP_Error
	 */
	private static function check_barcode_conflict( $barcode ) {
		$meta_query = array( 'relation' => 'OR' );

		foreach ( MKC_Product_Barcode_API::META_KEYS as $meta_key ) {
			$meta_query[] = array(
				'key'     => $meta_key,
				'value'   => $barcode,
				'compare' => '=',
			);
		}

		try {
			$ids = get_posts(
				array(
					'post_type'        => array( 'product', 'product_variation' ),
					'post_status'      => 'any',
					'posts_per_page'   => 1,
					'orderby'          => 'ID',
					'order'            => 'ASC',
					'fields'           => 'ids',
					'no_found_rows'    => true,
					'suppress_filters' => false,
					'meta_query'       => $meta_query,
				)
			);
		} catch ( \Throwable $e ) {
			return self::error(
				'kc_product_check_failed',
				'Không kiểm tra được barcode đã tồn tại hay chưa, vui lòng thử lại.',
				500
			);
		}

		$ids = array_map( 'absint', (array) $ids );

		return empty( $ids ) ? 0 : (int) $ids[0];
	}

	/* ---------------------------------------------------------------------
	 * Tạo sản phẩm
	 * ------------------------------------------------------------------ */

	/**
	 * Tạo sản phẩm bằng WooCommerce CRUD.
	 *
	 * Thứ tự thao tác:
	 * 1. `new WC_Product_Simple()` — chỉ loại sản phẩm endpoint này hỗ trợ.
	 * 2. Đặt tên, SKU, mô tả, trạng thái.
	 * 3. Đặt giá gốc / giá giảm. `sale_price` rỗng nghĩa là không giảm giá.
	 * 4. Đặt tồn kho qua các setter chính thức để WooCommerce tự đồng bộ
	 *    `_stock` và `_stock_status`; plugin không tự tính tồn kho.
	 * 5. Ghi barcode vào meta chính thức rồi `save()`.
	 * 6. Đọc lại bằng `wc_get_product()` để response phản ánh đúng dữ liệu vừa
	 *    lưu, kể cả giá mà WooCommerce đã chuẩn hoá.
	 *
	 * Endpoint này KHÔNG idempotent, nên một sản phẩm đã tạo không được phép
	 * biến thành HTTP 500: app sẽ bấm lại và sinh sản phẩm trùng. Vì vậy từ bước
	 * `save()` trở đi, lỗi chỉ được ghi ra log và response vẫn là 201 với payload
	 * tối thiểu.
	 *
	 * @param array $input Dữ liệu đã chuẩn hoá.
	 * @return WP_REST_Response|WP_Error
	 */
	private static function create_product( $input ) {
		$stage = 'instantiate';

		try {
			$product = new WC_Product_Simple();
		} catch ( \Throwable $e ) {
			self::log_failure( $stage, $e );
			return self::error( 'kc_product_create_failed', 'Không tạo được sản phẩm.', 500 );
		}

		$stage = 'set_props';

		try {
			$product->set_name( $input['name'] );

			if ( '' !== $input['sku'] ) {
				$product->set_sku( $input['sku'] );
			}

			$product->set_short_description( $input['short_description'] );
			$product->set_description( $input['description'] );
			$product->set_status( $input['status'] );
			$product->set_catalog_visibility( 'visible' );
			$product->set_regular_price( (string) $input['regular_price'] );

			// WooCommerce dùng chuỗi rỗng để biểu diễn "không có giá giảm".
			$product->set_sale_price( $input['sale_price'] > 0 ? (string) $input['sale_price'] : '' );

			$product->set_manage_stock( $input['manage_stock'] );

			// Chỉ đặt số lượng khi WooCommerce đang quản lý kho, nếu không giá trị
			// này bị WooCommerce bỏ qua và response sẽ gây hiểu nhầm.
			if ( $input['manage_stock'] ) {
				$product->set_stock_quantity( $input['stock_quantity'] );
			}

			$product->set_stock_status( $input['stock_status'] );
			$product->update_meta_data( self::BARCODE_META, $input['barcode'] );

			// Cố ý KHÔNG gọi `set_created_via()`: đó là thuộc tính của order,
			// không phải của product. Xem ghi chú ở hằng BARCODE_META.
		} catch ( \Throwable $e ) {
			self::log_failure( $stage, $e );
			return self::error( 'kc_product_create_failed', 'Không lưu được sản phẩm.', 500 );
		}

		$stage = 'save';

		try {
			$product_id = $product->save();
		} catch ( \Throwable $e ) {
			self::log_failure( $stage, $e );
			return self::error( 'kc_product_create_failed', 'Không lưu được sản phẩm.', 500 );
		}

		$product_id = absint( $product_id );

		if ( ! $product_id ) {
			self::log_note( $stage, 'save() không trả về product id.' );
			return self::error( 'kc_product_create_failed', 'Không lưu được sản phẩm.', 500 );
		}

		// Từ đây sản phẩm ĐÃ tồn tại trong database. Mọi lỗi còn lại chỉ ghi log
		// và vẫn trả 201, để app không tạo lại và sinh bản trùng.
		$stage = 'read_back';

		try {
			$created = wc_get_product( $product_id );
		} catch ( \Throwable $e ) {
			self::log_failure( $stage, $e );

			return self::created_response( self::minimal_payload( $product_id, $input ) );
		}

		if ( ! $created instanceof WC_Product ) {
			self::log_note( $stage, 'wc_get_product() không trả về WC_Product.' );

			return self::created_response( self::minimal_payload( $product_id, $input ) );
		}

		$stage = 'serialize';

		try {
			$payload = self::serialize_created( $created );
		} catch ( \Throwable $e ) {
			self::log_failure( $stage, $e );

			return self::created_response( self::minimal_payload( $product_id, $input ) );
		}

		return self::created_response( $payload );
	}

	/**
	 * Bọc payload thành HTTP 201.
	 *
	 * @param array $payload Nội dung response.
	 * @return WP_REST_Response
	 */
	private static function created_response( $payload ) {
		$response = rest_ensure_response(
			array(
				'success' => true,
				'product' => $payload,
			)
		);

		$response->set_status( 201 );

		return $response;
	}

	/**
	 * Payload tối thiểu dùng khi đọc lại sản phẩm lỗi.
	 *
	 * Chỉ dựa vào dữ liệu đã chuẩn hoá sẵn, không đọc gì thêm từ database, nên
	 * không thể hỏng. Thiếu `id` thì app vẫn biết sản phẩm nào vừa được tạo và
	 * không cần tạo lại.
	 *
	 * @param int   $product_id Id vừa tạo.
	 * @param array $input     Dữ liệu đã chuẩn hoá.
	 * @return array
	 */
	private static function minimal_payload( $product_id, $input ) {
		return array(
			'id'             => (int) $product_id,
			'product_id'     => (int) $product_id,
			'variation_id'   => 0,
			'name'           => $input['name'],
			'sku'            => self::text_or_null( $input['sku'] ),
			'barcode'        => self::text_or_null( $input['barcode'] ),
			'price'          => ( $input['sale_price'] > 0 ) ? $input['sale_price'] : $input['regular_price'],
			'regular_price'  => $input['regular_price'],
			'sale_price'     => ( $input['sale_price'] > 0 ) ? $input['sale_price'] : null,
			'stock_quantity' => $input['manage_stock'] ? $input['stock_quantity'] : null,
			'stock_status'   => $input['stock_status'],
			'image_url'      => null,
			'type'           => 'simple',
			'status'         => $input['status'],
			'created_via'    => null,
		);
	}

	/* ---------------------------------------------------------------------
	 * Response
	 * ------------------------------------------------------------------ */

	/**
	 * Payload của sản phẩm vừa tạo.
	 *
	 * Cùng bộ trường với `GET /products/barcode/{barcode}` cộng thêm `status`,
	 * để app dùng chung một model sau khi tạo xong mà không phải gọi lại API.
	 *
	 * @param WC_Product $product Sản phẩm vừa tạo.
	 * @return array
	 */
	private static function serialize_created( $product ) {
		$is_variation = $product->is_type( 'variation' );

		$image_id = (int) $product->get_image_id();
		$image_url = null;

		if ( $image_id ) {
			$candidate = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );

			if ( is_string( $candidate ) && '' !== $candidate ) {
				$scheme = wp_parse_url( $candidate, PHP_URL_SCHEME );

				if ( 'http' === $scheme || 'https' === $scheme ) {
					$image_url = esc_url_raw( $candidate );
				}
			}
		}

		return array(
			'id'             => (int) $product->get_id(),
			'product_id'     => $is_variation ? (int) $product->get_parent_id() : (int) $product->get_id(),
			'variation_id'   => $is_variation ? (int) $product->get_id() : 0,
			'name'           => $product->get_name(),
			'sku'            => self::text_or_null( $product->get_sku() ),
			'barcode'        => self::text_or_null( $product->get_meta( self::BARCODE_META ) ),
			'price'          => self::price_or_zero( $product->get_price() ),
			'regular_price'  => self::price_or_null( $product->get_regular_price() ),
			'sale_price'     => self::price_or_null( $product->get_sale_price() ),
			'stock_quantity' => $product->get_stock_quantity(),
			'stock_status'   => $product->get_stock_status(),
			'image_url'      => $image_url,
			'type'           => $product->get_type(),
			'status'         => $product->get_status(),

			// Luôn null. `created_via` là thuộc tính của order/customer, product
			// không có field này. Giữ nguyên key để app không đổi model, nhưng KHÔNG
			// gọi `$product->get_created_via()`: đó là magic call lên prop không tồn
			// tại và sẽ ném exception. Xem ghi chú ở hằng BARCODE_META.
			'created_via'    => null,
		);
	}

	/* ---------------------------------------------------------------------
	 * Helpers
	 * ------------------------------------------------------------------ */

	/**
	 * Bọc lỗi theo định dạng thống nhất của WordPress REST.
	 *
	 * @param string $code    Mã lỗi.
	 * @param string $message Thông báo cho app.
	 * @param int    $status  HTTP status.
	 * @return WP_Error
	 */
	private static function error( $code, $message, $status ) {
		return new WP_Error( $code, $message, array( 'status' => (int) $status ) );
	}

	/**
	 * Ghi lỗi nội bộ ra log máy chủ, KHÔNG gửi về app.
	 *
	 * HTTP response chỉ nhận mã lỗi và thông báo chung. Chi tiết lỗi thật nằm ở
	 * log máy chủ (WooCommerce log nếu có, nếu không thì PHP error log), nơi chỉ
	 * quản trị viên đọc được.
	 *
	 * Cố ý KHÔNG ghi vào log:
	 * - body của request (chứa tên, barcode, giá),
	 * - header `Authorization` và mọi thông tin đăng nhập / mật khẩu ứng dụng,
	 * - dữ liệu khách hàng, dữ liệu đơn hàng,
	 * - stack trace đầy đủ (nó kéo theo đường dẫn file máy chủ không cần thiết).
	 *
	 * Chỉ ghi: giai đoạn xử lý, class exception, mã exception, thông điệp (cắt
	 * ngắn) và file:dòng phát sinh — đủ để tìm ra nguyên nhân thật mà không lộ
	 * bí mật.
	 *
	 * @param string    $stage Giai đoạn xử lý (`instantiate`, `set_props`, `save`…).
	 * @param \Throwable $e     Exception đã bắt.
	 */
	private static function log_failure( $stage, $e ) {
		$message = method_exists( $e, 'getMessage' ) ? $e->getMessage() : '';
		$message = self::truncate( self::redact( (string) $message ), 500 );

		$origin = '';

		if ( method_exists( $e, 'getFile' ) ) {
			$origin = basename( (string) $e->getFile() ) . ':' . (int) $e->getLine();
		}

		self::log_internal(
			sprintf(
				'stage=%s exception=%s code=%s origin=%s message=%s',
				$stage,
				is_object( $e ) ? get_class( $e ) : gettype( $e ),
				is_object( $e ) && method_exists( $e, 'getCode' ) ? (string) $e->getCode() : '0',
				$origin,
				$message
			)
		);
	}

	/**
	 * Ghi một dòng chẩn đoán không kèm exception.
	 *
	 * @param string $stage   Giai đoạn xử lý.
	 * @param string $message Mô tả ngắn.
	 */
	private static function log_note( $stage, $message ) {
		self::log_internal(
			sprintf(
				'stage=%s note=%s',
				$stage,
				self::truncate( self::redact( (string) $message ), 500 )
			)
		);
	}

	/**
	 * Bỏ dấu chuỗi có thể chứa dữ liệu nhạy cảm trước khi ghi log.
	 *
	 * Chỉ là lớp phòng thủ thứ hai. Luồng log vốn chỉ nhận tên giai đoạn, class
	 * exception, file:dòng và message của exception — không có body request, không
	 * có header, không có dữ liệu khách hàng. Các message của WooCommerce là
	 * chuỗi tĩnh do developer viết.
	 *
	 * Cố ý KHÔNG dùng luật "mọi chuỗi dài đều là base64": luật đó xoá luôn tên
	 * class và tên file hữu ích cho việc chẩn đoán, mà Application Password của
	 * WordPress lại có khoảng trắng nên vốn không khớp. Thay vào đó khớp đúng
	 * bốn dạng credential thật: header `Authorization`, cặp khoá–giá trị
	 * (`password=`, `["api_key"] => "..."`), Application Password dạng 4–5 nhóm
	 * ký tự, và cặp `user:pass` trần.
	 *
	 * @param string $message Thông điệp thô.
	 * @return string
	 */
	private static function redact( $message ) {
		$patterns = array(
			// `Authorization: Basic <base64>` và `Bearer <token>`.
			'/(authorization\s*:\s*)(basic|bearer)\s+\S+/i' => '$1[redacted]',

			// `password=...`, `token => ...`, `api_key -> ...`, và cả dạng
			// `["key"] => "value"` mà PHP var_dump in ra.
			'/\b(authorization|passwd|password|pwd|secret|token|api[_-]?key)\b["\']?\s*\]?\s*[-:=]>?\s*["\']?\S+/i' => '$1=[redacted]',

			// Application Password của WordPress: `abcd EFGH ijkl MNOP qrst`.
			'/\b[a-z0-9]{4,5}(?:\s+[a-z0-9]{4,5}){3,4}\b/i' => '[redacted]',

			// Cặp `user:pass` trần.
			'/\b[\w.+-]+:[^\s:@]{6,}/' => '[redacted]',
		);

		$message = preg_replace(
			array_keys( $patterns ),
			array_values( $patterns ),
			$message
		);

		// `preg_replace` trả null khi lỗi regex (ví dụ backtrack limit). Không
		// được để null lọt vào log.
		return null === $message ? '[unloggable]' : $message;
	}

	/**
	 * Ghi dòng log ra WooCommerce log, fallback sang PHP error log.
	 *
	 * @param string $message Nội dung đã redact.
	 */
	private static function log_internal( $message ) {
		$line = 'MKC product create: ' . $message;

		if ( function_exists( 'wc_get_logger' ) ) {
			try {
				$logger = wc_get_logger();

				if ( $logger ) {
					$logger->error(
						$line,
						array( 'source' => self::LOG_SOURCE )
					);
				}
			} catch ( \Throwable $e ) {
				// Logger hỏng không được làm hỏng request; rơi xuống error_log.
				unset( $e );
			}
		}

		// Ghi luôn error_log: khi `wc_get_logger()` không tồn tại hoặc bị chặn ghi,
		// đây là chỗ duy nhất còn lại để tìm nguyên nhân 500.
		if ( ! function_exists( 'error_log' ) ) {
			return;
		}

		error_log( $line );
	}

	/**
	 * Trả về WP_Error 503 nếu WooCommerce chưa active, ngược lại null.
	 *
	 * @return WP_Error|null
	 */
	private static function require_wc() {
		$ready = class_exists( 'WooCommerce' )
			&& class_exists( 'WC_Product_Simple' )
			&& function_exists( 'wc_get_product' )
			&& function_exists( 'wc_get_product_id_by_sku' )
			&& function_exists( 'wc_get_price_decimals' );

		if ( $ready ) {
			return null;
		}

		return self::error(
			'kc_woocommerce_unavailable',
			'WooCommerce chưa active nên không tạo được sản phẩm.',
			503
		);
	}

	/**
	 * Chuyển số bất kỳ thành số nguyên không âm, hoặc null nếu không hợp lệ.
	 *
	 * Cố ý không dùng `absint()`: `absint('-5')` trả 5 nên số âm sẽ lọt qua. Số
	 * thực nguyên (10.0) và chuỗi "10" được chuẩn hoá thành int; số thập phân có
	 * phần lẻ (10.5), số âm, boolean, mảng và đối tượng đều bị từ chối.
	 *
	 * @param mixed $value Giá trị thô.
	 * @return int|null
	 */
	private static function non_negative_integer( $value ) {
		if ( is_int( $value ) ) {
			return ( $value >= 0 ) ? $value : null;
		}

		if ( is_float( $value ) ) {
			if ( $value >= 0 && floor( $value ) === $value && $value <= PHP_INT_MAX ) {
				return (int) $value;
			}

			return null;
		}

		if ( is_string( $value ) ) {
			$value = trim( $value );

			if ( preg_match( '/^[0-9]+(\.0+)?$/', $value ) ) {
				$number = (float) $value;

				if ( $number >= 0 && $number <= PHP_INT_MAX ) {
					return (int) $number;
				}
			}
		}

		return null;
	}

	/**
	 * Độ dài chuỗi, ưu tiên `mb_strlen` để không đếm sai với tiếng Việt.
	 *
	 * @param string $value Chuỗi.
	 * @return int
	 */
	private static function length( $value ) {
		if ( function_exists( 'mb_strlen' ) ) {
			return mb_strlen( $value );
		}

		return strlen( $value );
	}

	/**
	 * Cắt chuỗi theo độ dài ký tự, ưu tiên `mb_substr`.
	 *
	 * @param string $value  Chuỗi.
	 * @param int    $length Độ dài tối đa.
	 * @return string
	 */
	private static function truncate( $value, $length ) {
		if ( function_exists( 'mb_substr' ) ) {
			return mb_substr( $value, 0, $length );
		}

		return substr( $value, 0, $length );
	}

	/**
	 * Chuỗi rỗng thành null.
	 *
	 * @param mixed $value Raw value.
	 * @return string|null
	 */
	private static function text_or_null( $value ) {
		if ( null === $value ) {
			return null;
		}

		$value = trim( (string) $value );

		return ( '' !== $value ) ? $value : null;
	}

	/**
	 * Giá rỗng thành null.
	 *
	 * @param mixed $value Raw value.
	 * @return float|null
	 */
	private static function price_or_null( $value ) {
		if ( null === $value || '' === $value ) {
			return null;
		}

		return (float) $value;
	}

	/**
	 * Giá rỗng thành 0.
	 *
	 * @param mixed $value Raw value.
	 * @return float
	 */
	private static function price_or_zero( $value ) {
		return ( null === $value || '' === $value ) ? 0.0 : (float) $value;
	}
}
