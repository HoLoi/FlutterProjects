<?php
/**
 * Tra cứu sản phẩm theo barcode (namespace `kc/v1`).
 *
 * Endpoint: `GET /wp-json/kc/v1/products/barcode/{barcode}`.
 *
 * Vì sao endpoint này yêu cầu xác thực trong khi `/products` và `/variations`
 * vẫn public: kết quả tra cứu KHÔNG lọc theo trạng thái, nên sẽ trả cả sản
 * phẩm nháp (`draft`), sản phẩm `private` và biến thể của chúng. Chỉ tài khoản
 * có quyền quản lý sản phẩm mới được thấy dữ liệu đó.
 *
 * Nguyên tắc bắt buộc:
 * - Tìm sản phẩm bằng WordPress API chính thức (`get_posts()` + `meta_query`),
 *   sau đó đọc chi tiết bằng WooCommerce CRUD (`wc_get_product()`). Không SQL,
 *   không đọc trực tiếp bảng postmeta, không `WP_Query` tự viết SQL.
 * - Barcode lưu ở meta chính thức `_mkc_barcode`; `_barcode` là key dự phòng vì
 *   một số sản phẩm cũ dùng key này. Cả hai cùng được tra trong META_KEYS.
 * - Xác thực bằng WordPress Application Password qua HTTPS + capability quản
 *   lý sản phẩm. Không JWT tự viết, không token trong plugin.
 * - Response chỉ chứa dữ liệu catalog, không có credential, không đường dẫn
 *   filesystem, không dữ liệu quản trị.
 *
 * @package mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class MKC_Product_Barcode_API {

	/** Độ dài tối đa của barcode trước khi bị từ chối. */
	const MAX_BARCODE_LENGTH = 64;

	/**
	 * Số kết quả tối đa lấy ra để biết barcode có bị trùng hay không.
	 *
	 * Chỉ cần 2 là đủ để kết luận "trùng" mà không quét hết catalog.
	 */
	const MAX_MATCHES = 2;

	/**
	 * Meta key chứa barcode. Key đầu là key chính thức của plugin, key sau là
	 * key dự phòng cho sản phẩm nhập trước khi có key chính thức.
	 */
	const META_KEYS = array( '_mkc_barcode', '_barcode' );

	/**
	 * Đăng ký route tra cứu barcode.
	 *
	 * Regex path cố ý cho phép barcode rỗng (`[^/]*` thay vì `[^/]+`) để
	 * `GET /products/barcode/` vẫn khớp route và trả HTTP 400 với mã
	 * `kc_invalid_barcode` thay vì rơi vào `rest_no_route` của WordPress.
	 *
	 * Không xung đột với `/products/(?P<id>\d+)`: `barcode` không phải chữ số
	 * nên route đó không bao giờ khớp `/products/barcode/...`.
	 */
	public static function register_routes() {
		register_rest_route(
			MKC_REST_API::REST_NAMESPACE,
			'/products/barcode/(?P<barcode>[^/]*)',
			array(
				'methods'             => 'GET',
				'callback'            => array( __CLASS__, 'handle_lookup' ),
				'permission_callback' => array( __CLASS__, 'permission_lookup' ),
			)
		);
	}

	/* ---------------------------------------------------------------------
	 * Permission
	 * ------------------------------------------------------------------ */

	/**
	 * Quyền tra cứu barcode: bắt buộc đăng nhập, HTTPS và quyền quản lý sản phẩm.
	 *
	 * Thứ tự trả lỗi cố định:
	 *
	 * - Chưa đăng nhập  → 401 kc_not_authenticated
	 * - Không phải HTTPS → 403 kc_https_required
	 * - Thiếu quyền     → 403 kc_cannot_view_products
	 *
	 * @return true|WP_Error
	 */
	public static function permission_lookup() {
		if ( ! is_user_logged_in() ) {
			return self::error( 'kc_not_authenticated', 'Cần đăng nhập để tra cứu sản phẩm theo barcode.', 401 );
		}

		if ( ! self::is_secure_request() ) {
			return self::error(
				'kc_https_required',
				'Chỉ chấp nhận kết nối HTTPS vì header xác thực được gửi dạng chữ thường.',
				403
			);
		}

		if ( ! self::can_view_products() ) {
			return self::error( 'kc_cannot_view_products', 'Tài khoản không có quyền xem sản phẩm.', 403 );
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

	/**
	 * Capability tối thiểu để xem sản phẩm, kể cả sản phẩm nháp.
	 *
	 * Ưu tiên `manage_woocommerce` như các endpoint ghi khác. Ngoài ra chấp nhận
	 * `edit_shop_products` và `edit_products` vì đó là capability WooCommerce và
	 * WordPress gán cho Shop Manager / Kỹ thuật viên, là những tài khoản dùng POS
	 * thực tế. Endpoint này chỉ đọc nên không cần quyền ghi.
	 *
	 * @return bool
	 */
	private static function can_view_products() {
		if ( current_user_can( 'manage_woocommerce' ) ) {
			return true;
		}

		if ( current_user_can( 'edit_shop_products' ) ) {
			return true;
		}

		return current_user_can( 'edit_products' );
	}

	/* ---------------------------------------------------------------------
	 * Handler
	 * ------------------------------------------------------------------ */

	/**
	 * Tra cứu một sản phẩm hoặc biến thể theo barcode.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_lookup( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$barcode = self::read_barcode( $request );
		if ( is_wp_error( $barcode ) ) {
			return $barcode;
		}

		$ids = self::find_product_ids( $barcode );

		if ( empty( $ids ) ) {
			return self::error(
				'kc_not_found',
				sprintf( 'Không tìm thấy sản phẩm nào có barcode "%s".', $barcode ),
				404
			);
		}

		$product = wc_get_product( $ids[0] );

		// Lệch giữa id trả về và WooCommerce (ví dụ dữ liệu bị xoá giữa chừng)
		// thì coi như không tìm thấy thay vì trả payload rỗng.
		if ( ! $product instanceof WC_Product ) {
			return self::error(
				'kc_not_found',
				sprintf( 'Không tìm thấy sản phẩm nào có barcode "%s".', $barcode ),
				404
			);
		}

		return rest_ensure_response( self::serialize_match( $product, count( $ids ) > 1 ) );
	}

	/* ---------------------------------------------------------------------
	 * Input
	 * ------------------------------------------------------------------ */

	/**
	 * Đọc và kiểm tra barcode trên path.
	 *
	 * Chỉ chấp nhận chữ, số và `. _ -`: đây là tập ký tự an toàn cho mọi loại
	 * mã vạch phổ biến (EAN-8, EAN-13, UPC, Code 39, Code 128) và giữ được
	 * nguyên vẹn khi đưa vào `meta_value` của `meta_query`.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return string|WP_Error
	 */
	private static function read_barcode( $request ) {
		$barcode = trim( (string) $request->get_param( 'barcode' ) );

		if ( '' === $barcode ) {
			return self::error( 'kc_invalid_barcode', 'Thiếu barcode cần tra cứu.', 400 );
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
				'Barcode chỉ gồm chữ cáa không dấu, chữ số và các ký tự . _ -',
				400
			);
		}

		return $barcode;
	}

	/* ---------------------------------------------------------------------
	 * Tra cứu
	 * ------------------------------------------------------------------ */

	/**
	 * Tìm id sản phẩm/biến thể có barcode trùng khớp.
	 *
	 * Dùng `get_posts()` với `meta_query` trên `post_type` product và
	 * product_variation. Đây là API chính thức của WordPress nên hoạt động giống
	 * nhau dù site lưu dữ liệu theo kiểu nào; sản phẩm WooCommerce không nằm
	 * trong HPOS nên không phụ thuộc cách lưu đơn hàng.
	 *
	 * `post_status` dùng `any` vì endpoint dành cho người quản lý: sản phẩm
	 * nháp vẫn phải tra được, nếu không POS sẽ báo "không tìm thấy" cho một sản
	 * phẩm có thật. `any` của WordPress không bao gồm `trash` và `auto-draft`.
	 *
	 * @param string $barcode Barcode đã kiểm tra.
	 * @return array<int> Danh sách id, đã sort tăng dần theo id.
	 */
	private static function find_product_ids( $barcode ) {
		$meta_query = array( 'relation' => 'OR' );

		foreach ( self::META_KEYS as $meta_key ) {
			$meta_query[] = array(
				'key'     => $meta_key,
				'value'   => $barcode,
				'compare' => '=',
			);
		}

		$ids = get_posts(
			array(
				'post_type'        => array( 'product', 'product_variation' ),
				'post_status'      => 'any',
				'posts_per_page'   => self::MAX_MATCHES,
				'orderby'          => 'ID',
				'order'            => 'ASC',
				'fields'           => 'ids',
				'no_found_rows'    => true,
				'suppress_filters' => false,
				'meta_query'       => $meta_query,
			)
		);

		return array_map( 'absint', (array) $ids );
	}

	/* ---------------------------------------------------------------------
	 * Response
	 * ------------------------------------------------------------------ */

	/**
	 * Bọc kết quả tra cứu thành payload.
	 *
	 * Với biến thể, `product_id` là id sản phẩm cha và `variation_id` là id biến
	 * thể; với sản phẩm simple, `variation_id` bằng 0 để app dùng chung một
	 * kiểu payload với đơn POS (sản phẩm simple dùng `variation_id: 0`).
	 *
	 * @param WC_Product $product   Sản phẩm hoặc biến thể tìm được.
	 * @param bool       $ambiguous Barcode có trùng ở nhiều sản phẩm hay không.
	 * @return array
	 */
	private static function serialize_match( WC_Product $product, $ambiguous ) {
		$is_variation = $product->is_type( 'variation' );

		$payload = array(
			'found'          => true,
			'type'           => $product->get_type(),
			'product_id'     => $is_variation ? (int) $product->get_parent_id() : (int) $product->get_id(),
			'variation_id'   => $is_variation ? (int) $product->get_id() : 0,
			'name'           => $product->get_name(),
			'parent'         => null,
			'sku'            => self::text_or_null( $product->get_sku() ),
			'barcode'        => self::text_or_null( $product->get_meta( '_mkc_barcode' ) ),
			'price'          => self::price_or_zero( $product->get_price() ),
			'regular_price'  => self::price_or_null( $product->get_regular_price() ),
			'sale_price'     => self::price_or_null( $product->get_sale_price() ),
			'stock_quantity' => $product->get_stock_quantity(),
			'stock_status'   => $product->get_stock_status(),
			'status'         => $product->get_status(),
			'manage_stock'   => (bool) $product->managing_stock(),
			'image_url'      => self::image_url( $product ),
			'attributes'     => array(),
			'ambiguous'      => (bool) $ambiguous,
		);

		if ( '' === $payload['barcode'] ) {
			$payload['barcode'] = self::text_or_null( $product->get_meta( '_barcode' ) );
		}

		if ( $is_variation ) {
			$payload['name']       = self::variation_name( $product );
			$payload['attributes'] = self::serialize_attributes( $product );

			$parent = wc_get_product( (int) $product->get_parent_id() );

			if ( $parent instanceof WC_Product ) {
				$payload['parent'] = array(
					'id'     => (int) $parent->get_id(),
					'name'   => $parent->get_name(),
					'sku'    => self::text_or_null( $parent->get_sku() ),
					'status' => $parent->get_status(),
				);
			}
		}

		return $payload;
	}

	/**
	 * Tên hiển thị của biến thể: tên sản phẩm cha kèm option thuộc tính.
	 *
	 * `WC_Product_Variation::get_name()` chỉ trả option ("30ml"), app cần tên
	 * đầy đủ để hiện trên giỏ hàng.
	 *
	 * @param WC_Product_Variation $variation Biến thể.
	 * @return string
	 */
	private static function variation_name( WC_Product_Variation $variation ) {
		$parent = wc_get_product( (int) $variation->get_parent_id() );

		if ( ! $parent instanceof WC_Product ) {
			return $variation->get_name();
		}

		$options = array();

		foreach ( $variation->get_attributes() as $attribute_name => $value ) {
			if ( '' === (string) $value ) {
				continue;
			}

			$options[] = wc_attribute_label( $attribute_name, $variation ) . ': ' . $value;
		}

		if ( empty( $options ) ) {
			return $parent->get_name();
		}

		return $parent->get_name() . ' - ' . implode( ' / ', $options );
	}

	/**
	 * Thuộc tính của biến thể theo cùng định dạng `/variations` đang trả.
	 *
	 * @param WC_Product_Variation $variation Biến thể.
	 * @return array
	 */
	private static function serialize_attributes( WC_Product_Variation $variation ) {
		$attributes = array();

		foreach ( $variation->get_attributes() as $name => $value ) {
			$attributes[] = array(
				'name'   => wc_attribute_label( $name, $variation ),
				'option' => self::text_or_null( $value ),
			);
		}

		return $attributes;
	}

	/**
	 * URL ảnh thumbnail của sản phẩm/variation.
	 *
	 * Biến thể chưa có ảnh thì dùng ảnh sản phẩm cha. Chỉ trả URL http/https,
	 * không trả đường dẫn filesystem.
	 *
	 * @param WC_Product $product Sản phẩm hoặc biến thể.
	 * @return string|null
	 */
	private static function image_url( $product ) {
		$image_id = (int) $product->get_image_id();

		if ( ! $image_id && $product->is_type( 'variation' ) ) {
			$parent = wc_get_product( (int) $product->get_parent_id() );

			if ( $parent instanceof WC_Product ) {
				$image_id = (int) $parent->get_image_id();
			}
		}

		if ( ! $image_id ) {
			return null;
		}

		$image_url = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );

		if ( ! is_string( $image_url ) || '' === $image_url ) {
			return null;
		}

		$scheme = wp_parse_url( $image_url, PHP_URL_SCHEME );

		if ( 'http' !== $scheme && 'https' !== $scheme ) {
			return null;
		}

		return esc_url_raw( $image_url );
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
	 * Trả về WP_Error 503 nếu WooCommerce chưa active, ngược lại null.
	 *
	 * @return WP_Error|null
	 */
	private static function require_wc() {
		$ready = class_exists( 'WooCommerce' )
			&& function_exists( 'wc_get_product' )
			&& function_exists( 'wc_attribute_label' );

		if ( $ready ) {
			return null;
		}

		return self::error(
			'kc_woocommerce_unavailable',
			'WooCommerce chưa active nên không tra cứu được sản phẩm.',
			503
		);
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

add_action( 'rest_api_init', array( 'MKC_Product_Barcode_API', 'register_routes' ) );
