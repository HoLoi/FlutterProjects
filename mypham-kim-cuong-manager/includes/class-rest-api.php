<?php
/**
 * REST API for MyPham Kim Cuong Manager.
 *
 * Read-only API (namespace `kc/v1`). Không có endpoint ghi, không SQL trực tiếp,
 * chỉ dùng WooCommerce CRUD / hàm chính thức của WooCommerce.
 *
 * @package mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class MKC_REST_API {

	const REST_NAMESPACE = 'kc/v1';

	/** Giới hạn số item mỗi trang. */
	const MAX_PER_PAGE = 50;

	/** Số ký tự tối đa cho tham số search. */
	const MAX_SEARCH_LENGTH = 200;

	/**
	 * Ghi nhớ trạng thái publish của sản phẩm cha trong phạm vi một request,
	 * dùng cho endpoint /variations để tránh gọi wc_get_product() lặp lại.
	 *
	 * @var array<int,bool>
	 */
	private static $parent_status_cache = array();

	/**
	 * Đăng ký toàn bộ route.
	 *
	 * Public    : /health, /products, /products/{id}, /categories, /variations
	 * Cần xác thực: /orders, /orders/{id}
	 */
	public static function register_routes() {
		register_rest_route(
			self::REST_NAMESPACE,
			'/health',
			array(
				'methods'             => 'GET',
				'callback'            => array( __CLASS__, 'handle_health' ),
				'permission_callback' => array( __CLASS__, 'permission_public' ),
			)
		);

		self::register_list_route(
			'/products',
			array( __CLASS__, 'handle_products' ),
			true
		);

		self::register_item_route(
			'/products/(?P<id>\d+)',
			array( __CLASS__, 'handle_product_detail' )
		);

		self::register_list_route(
			'/categories',
			array( __CLASS__, 'handle_categories' ),
			true
		);

		self::register_list_route(
			'/variations',
			array( __CLASS__, 'handle_variations' ),
			true,
			array(
				'product_id' => array(
					'type'              => 'integer',
					'required'          => false,
					'sanitize_callback' => 'absint',
					'validate_callback' => array( __CLASS__, 'validate_optional_id' ),
				),
			)
		);

		self::register_list_route(
			'/orders',
			array( __CLASS__, 'handle_orders' ),
			true,
			array(
				'status'    => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_key',
					'validate_callback' => array( __CLASS__, 'validate_order_status' ),
				),
				'date_from' => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
					'validate_callback' => array( __CLASS__, 'validate_date_param' ),
				),
				'date_to'   => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
					'validate_callback' => array( __CLASS__, 'validate_date_param' ),
				),
			),
			array( __CLASS__, 'permission_orders' ),
			array( __CLASS__, 'validate_orders_date_range' )
		);

		self::register_item_route(
			'/orders/(?P<id>\d+)',
			array( __CLASS__, 'handle_order_detail' ),
			array(
				'id' => array(
					'type'              => 'integer',
					'required'          => true,
					'sanitize_callback' => 'absint',
					'validate_callback' => array( __CLASS__, 'validate_resource_id' ),
				),
			),
			array( __CLASS__, 'permission_orders' )
		);
	}

	/* ---------------------------------------------------------------------
	 * Route helpers
	 * ------------------------------------------------------------------ */

	/**
	 * Đăng ký route danh sách (có phân trang + search).
	 *
	 * @param string   $path        Đường dẫn sau namespace.
	 * @param callable $callback    Handler.
	 * @param bool     $with_search Bật tham số search.
	 * @param array    $extra_args  Tham số riêng của route.
	 * @param callable $permission  permission_callback, mặc định public.
	 * @param callable $validate    validate_callback cấp route, tuỳ chọn.
	 */
	private static function register_list_route( $path, $callback, $with_search = false, $extra_args = array(), $permission = null, $validate = null ) {
		$args = self::pagination_args();

		if ( $with_search ) {
			$args['search'] = array(
				'type'              => 'string',
				'required'          => false,
				'sanitize_callback' => 'sanitize_text_field',
			);
		}

		if ( ! empty( $extra_args ) ) {
			$args = array_merge( $args, $extra_args );
		}

		self::register_rest_route( $path, $callback, $args, $permission, $validate );
	}

	/**
	 * Đăng ký route chi tiết theo id. Chỉ nhận tham số `id` trong path.
	 *
	 * @param string   $path        Đường dẫn sau namespace.
	 * @param callable $callback    Handler.
	 * @param array    $extra_args  Tham số riêng của route.
	 * @param callable $permission  permission_callback, mặc định public.
	 */
	private static function register_item_route( $path, $callback, $extra_args = array(), $permission = null ) {
		self::register_rest_route( $path, $callback, $extra_args, $permission );
	}

	/**
	 * Đăng ký một route GET read-only.
	 *
	 * @param string   $path        Đường dẫn sau namespace.
	 * @param callable $callback    Handler.
	 * @param array    $extra_args  Tham số của route.
	 * @param callable $permission  permission_callback, mặc định public.
	 * @param callable $validate    validate_callback cấp route, tuỳ chọn.
	 */
	private static function register_rest_route( $path, $callback, $extra_args, $permission, $validate = null ) {
		if ( null === $permission ) {
			$permission = array( __CLASS__, 'permission_public' );
		}

		$route_args = array(
			'methods'             => 'GET',
			'callback'            => $callback,
			'permission_callback' => $permission,
			'args'                => $extra_args,
		);

		if ( null !== $validate ) {
			$route_args['validate_callback'] = $validate;
		}

		register_rest_route( self::REST_NAMESPACE, $path, $route_args );
	}

	/**
	 * Tham số phân trang dùng chung.
	 *
	 * per_page tối đa 50, tối thiểu 1. Giá trị sai bị từ chối bằng HTTP 400
	 * (mã `rest_invalid_param`) TRƯỚC khi tới handler: validate_callback kiểm
	 * trên giá trị thô, nên không có chuyện âm thầm sửa `0`, số âm hay chuỗi
	 * không phải số thành giá trị hợp lệ.
	 *
	 * @return array
	 */
	private static function pagination_args() {
		return array(
			'per_page' => array(
				'type'              => 'integer',
				'required'          => false,
				'default'           => 20,
				'minimum'           => 1,
				'maximum'           => self::MAX_PER_PAGE,
				'sanitize_callback' => 'absint',
				'validate_callback' => array( __CLASS__, 'validate_per_page' ),
			),
			'page'     => array(
				'type'              => 'integer',
				'required'          => false,
				'default'           => 1,
				'minimum'           => 1,
				'sanitize_callback' => 'absint',
				'validate_callback' => array( __CLASS__, 'validate_page' ),
			),
		);
	}

	/* ---------------------------------------------------------------------
	 * Permission callbacks
	 * ------------------------------------------------------------------ */

	/**
	 * Endpoint public (dữ liệu catalog, không chứa dữ liệu khách hàng).
	 *
	 * @return true
	 */
	public static function permission_public() {
		return true;
	}

	/**
	 * Endpoint đơn hàng: bắt buộc xác thực.
	 *
	 * Xác thực bằng WordPress Application Password qua HTTPS. App gửi header
	 * `Authorization: Basic base64(username:application-password)`. WordPress tự
	 * xác thực nên plugin chỉ kiểm tra user đã đăng nhập và có capability xem đơn.
	 *
	 * - Chưa đăng nhập            → 401 kc_not_authenticated
	 * - Đã đăng nhập, thiếu quyền  → 403 kc_cannot_view_orders
	 *
	 * @return true|WP_Error
	 */
	public static function permission_orders() {
		if ( ! is_user_logged_in() ) {
			return new WP_Error(
				'kc_not_authenticated',
				'Cần đăng nhập để xem đơn hàng.',
				array( 'status' => 401 )
			);
		}

		if ( ! self::can_view_orders() ) {
			return new WP_Error(
				'kc_cannot_view_orders',
				'Tài khoản không có quyền xem đơn hàng.',
				array( 'status' => 403 )
			);
		}

		return true;
	}

	/**
	 * Capability tối thiểu để xem đơn WooCommerce.
	 *
	 * Ưu tiên `manage_woocommerce`. Nếu tài khoản không có capability này thì
	 * chấp nhận `edit_shop_orders` hoặc `read_private_shop_orders` của WooCommerce.
	 *
	 * @return bool
	 */
	private static function can_view_orders() {
		if ( current_user_can( 'manage_woocommerce' ) ) {
			return true;
		}

		if ( current_user_can( 'edit_shop_orders' ) ) {
			return true;
		}

		return current_user_can( 'read_private_shop_orders' );
	}

	/* ---------------------------------------------------------------------
	 * Validate callbacks
	 *
	 * Lưu ý quan trọng về mã lỗi: WordPress LUÔN bọc mọi lỗi trả ra từ
	 * validate_callback (kể cả WP_Error có mã custom) thành WP_Error mã
	 * `rest_invalid_param` với HTTP 400. Vì vậy hợp đồng chuẩn của API là:
	 *   - HTTP 400 + code `rest_invalid_param` cho mọi lỗi tham số.
	 *   - `data.details[tên_tham_số].code` giữ mã chi tiết hơn (nếu có).
	 * App Flutter chỉ cần bắt theo HTTP status là đủ.
	 * ------------------------------------------------------------------ */

	/**
	 * Kiểm tra một tham số phải là số nguyên trong khoảng [min, max].
	 *
	 * Cố ý KHÔNG dùng absint()/intval() trước khi kiểm tra: absint('-5') trả về
	 * 5 nên giá trị âm sẽ bị biến thành giá trị hợp lệ. Giá trị thô từ query
	 * string luôn là string, nên ta kiểm tra bằng regex chỉ chấp nhận chữ số.
	 *
	 * @param mixed  $value       Giá trị thô.
	 * @param int    $min         Giá trị nhỏ nhất.
	 * @param int    $max         Giá trị lớn nhất.
	 * @param string $param_name  Tên tham số để hiển thị trong message.
	 * @return true|WP_Error
	 */
	private static function validate_integer_in_range( $value, $min, $max, $param_name ) {
		if ( is_int( $value ) ) {
			$number = $value;
		} elseif ( is_string( $value ) && 1 === preg_match( '/^[0-9]+$/', $value ) ) {
			$number = (int) $value;
		} else {
			$number = null;
		}

		if ( null === $number || $number < $min || $number > $max ) {
			return new WP_Error(
				'kc_invalid_param',
				sprintf(
					'Tham số "%1$s" phải là số nguyên từ %2$d đến %3$d.',
					$param_name,
					$min,
					$max
				),
				array( 'status' => 400 )
			);
		}

		return true;
	}

	/**
	 * per_page phải là số nguyên từ 1 đến 50.
	 *
	 * @param mixed $value Giá trị thô.
	 * @return true|WP_Error
	 */
	public static function validate_per_page( $value ) {
		return self::validate_integer_in_range( $value, 1, self::MAX_PER_PAGE, 'per_page' );
	}

	/**
	 * page phải là số nguyên từ 1 trở lên.
	 *
	 * @param mixed $value Giá trị thô.
	 * @return true|WP_Error
	 */
	public static function validate_page( $value ) {
		return self::validate_integer_in_range( $value, 1, PHP_INT_MAX, 'page' );
	}

	/**
	 * Kiểm tra chéo date_from/date_to cho route /orders.
	 *
	 * Đây là validate_callback cấp route nên chạy cùng lúc với các validate
	 * tham số khác, tức là TRƯỚC permission_callback. Nhờ vậy khoảng ngày bị
	 * ngược trả 400 ngay cả khi người gọi chưa xác thực, thay vì 401.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return true|WP_Error
	 */
	public static function validate_orders_date_range( $request ) {
		$from = trim( (string) $request->get_param( 'date_from' ) );
		$to   = trim( (string) $request->get_param( 'date_to' ) );

		if ( '' === $from || '' === $to ) {
			return true;
		}

		if ( strtotime( $from ) <= strtotime( $to ) ) {
			return true;
		}

		return new WP_Error(
			'kc_invalid_date_range',
			'date_from phải nhỏ hơn hoặc bằng date_to.',
			array( 'status' => 400 )
		);
	}

	/**
	 * id trong path phải là số nguyên dương, nếu không coi như không tồn tại.
	 *
	 * @param mixed $value Raw value.
	 * @return true|WP_Error
	 */
	public static function validate_resource_id( $value ) {
		$check = self::validate_integer_in_range( $value, 1, PHP_INT_MAX, 'id' );

		if ( true === $check ) {
			return true;
		}

		// id không hợp lệ trong path không phải lỗi tham số mà là "không tồn tại".
		return new WP_Error(
			'kc_not_found',
			'Không tìm thấy dữ liệu.',
			array( 'status' => 404 )
		);
	}

	/**
	 * id trong query string: bỏ trống thì được, có thì phải là số nguyên dương.
	 *
	 * @param mixed $value Raw value.
	 * @return true|WP_Error
	 */
	public static function validate_optional_id( $value ) {
		if ( null === $value || '' === $value ) {
			return true;
		}

		return self::validate_integer_in_range( $value, 1, PHP_INT_MAX, 'product_id' );
	}

	/**
	 * Ngày phải đúng định dạng YYYY-MM-DD.
	 *
	 * @param mixed $value Raw value.
	 * @return true|WP_Error
	 */
	public static function validate_date_param( $value ) {
		$value = trim( (string) $value );

		if ( '' === $value ) {
			return true;
		}

		$date = DateTime::createFromFormat( 'Y-m-d', $value );
		if ( $date && $date->format( 'Y-m-d' ) === $value ) {
			return true;
		}

		return new WP_Error(
			'kc_invalid_date',
			'Định dạng ngày phải là YYYY-MM-DD, ví dụ 2026-09-01.',
			array( 'status' => 400 )
		);
	}

	/**
	 * Trạng thái đơn phải nằm trong whitelist.
	 *
	 * @param mixed $value Raw value.
	 * @return true|WP_Error
	 */
	public static function validate_order_status( $value ) {
		$status = sanitize_key( (string) $value );

		if ( '' === $status || in_array( $status, self::allowed_order_statuses(), true ) ) {
			return true;
		}

		return new WP_Error(
			'kc_invalid_status',
			sprintf(
				'Trạng thái "%1$s" không hợp lệ. Chỉ nhận: any, %2$s.',
				esc_html( $status ),
				esc_html( implode( ', ', self::allowed_order_statuses() ) )
			),
			array( 'status' => 400 )
		);
	}

	/* ---------------------------------------------------------------------
	 * Handlers
	 * ------------------------------------------------------------------ */

	/**
	 * Health check. Public, không chứa dữ liệu nhạy cảm.
	 *
	 * @return WP_REST_Response
	 */
	public static function handle_health() {
		return rest_ensure_response(
			array(
				'ok'                 => true,
				'plugin'             => 'mypham-kim-cuong-manager',
				'version'            => MKC_MANAGER_VERSION,
				'wordpress'          => get_bloginfo( 'version' ),
				'woocommerce_active' => self::wc_ready(),
			)
		);
	}

	/**
	 * Danh sách sản phẩm WooCommerce (chỉ sản phẩm đang publish).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_products( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$per_page = self::per_page( $request );
		$page     = self::page( $request );
		$search   = self::search_term( $request );

		$args = array(
			// Chỉ sản phẩm thật, không lấy biến thể (variation).
			'type'    => array( 'simple', 'variable', 'grouped', 'external' ),
			'status'  => 'publish',
			'limit'   => $per_page,
			'page'    => $page,
			'orderby' => 'date',
			'order'   => 'DESC',
			'return'  => 'objects',
		);

		if ( '' !== $search ) {
			$args['s'] = $search;
		}

		$items = array();
		foreach ( wc_get_products( $args ) as $product ) {
			if ( $product instanceof WC_Product ) {
				$items[] = self::serialize_product( $product );
			}
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Chi tiết một sản phẩm.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_product_detail( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$product_id = absint( $request->get_param( 'id' ) );
		$product    = wc_get_product( $product_id );

		// Endpoint public: chỉ trả sản phẩm đang publish, không lộ sản phẩm nháp.
		if ( ! $product instanceof WC_Product || 'publish' !== $product->get_status() ) {
			return self::not_found_error( 'Không tìm thấy sản phẩm.' );
		}

		$payload = self::serialize_product( $product );

		$payload['wc_active']       = true;
		$payload['permalink']       = get_permalink( $product_id );
		$payload['date_created']    = self::format_date( $product->get_date_created() );
		$payload['date_modified']   = self::format_date( $product->get_date_modified() );
		$payload['description']     = $product->get_description();
		$payload['short_description'] = $product->get_short_description();
		$payload['virtual']         = $product->is_virtual();
		$payload['downloadable']    = $product->is_downloadable();
		$payload['manage_stock']    = $product->managing_stock();
		$payload['attributes']      = self::serialize_product_attributes( $product );

		return rest_ensure_response( $payload );
	}

	/**
	 * Danh mục sản phẩm WooCommerce.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_categories( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$per_page = self::per_page( $request );
		$page     = self::page( $request );
		$search   = self::search_term( $request );

		$query_args = array(
			'taxonomy'   => 'product_cat',
			'hide_empty' => false,
			'number'     => $per_page,
			'offset'     => ( $page - 1 ) * $per_page,
			'orderby'    => 'name',
			'order'      => 'ASC',
		);

		if ( '' !== $search ) {
			$query_args['search'] = $search;
		}

		$terms = get_terms( $query_args );
		if ( is_wp_error( $terms ) ) {
			return new WP_Error(
				'kc_terms_error',
				'Không đọc được danh mục sản phẩm.',
				array( 'status' => 500 )
			);
		}

		$items = array();
		foreach ( $terms as $term ) {
			$items[] = array(
				'id'     => (int) $term->term_id,
				'name'   => $term->name,
				'slug'   => $term->slug,
				'parent' => (int) $term->parent,
				'count'  => (int) $term->count,
			);
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Biến thể sản phẩm. Có thể lọc theo product_id.
	 *
	 * CHỈ trả biến thể thuộc sản phẩm cha đang `publish`. Trạng thái của
	 * sản phẩm cha được kiểm tra bằng WooCommerce CRUD (`wc_get_product`),
	 * không dùng SQL trực tiếp. Nếu không kiểm tra, biến thể của sản phẩm
	 * nháp sẽ bị lộ công khai qua endpoint public này (biến thể luôn có
	 * post_status `publish` riêng, nên lọc theo trạng thái của chính biến thể
	 * là không đủ).
	 *
	 * Lưu ý: tham số `search` được áp dụng SAU khi lấy dữ liệu từ database
	 * (WooCommerce không hỗ trợ search chuẩn cho biến thể). Khi dùng search
	 * nên đặt per_page cao (tối đa 50) để giảm khả năng bị lọc mất kết quả.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_variations( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$per_page   = self::per_page( $request );
		$page       = self::page( $request );
		$product_id = (int) $request->get_param( 'product_id' );
		$search     = self::search_term( $request );

		// product_id trỏ tới sản phẩm cha chưa publish (draft, private,
		// pending) hoặc không tồn tại: không trả biến thể nào.
		if ( $product_id > 0 && ! self::is_published_parent( $product_id ) ) {
			return self::not_found_error( 'Không tìm thấy sản phẩm.' );
		}

		$args = array(
			'type'     => 'variation',
			'status'   => 'publish',
			'limit'    => $per_page,
			'page'     => $page,
			'orderby'  => 'id',
			'order'    => 'ASC',
			'return'   => 'objects',
		);

		if ( $product_id > 0 ) {
			$args['parent'] = $product_id;
		}

		$items = array();
		foreach ( wc_get_products( $args ) as $variation ) {
			if ( ! $variation instanceof WC_Product_Variation ) {
				continue;
			}

			// Bỏ biến thể của sản phẩm cha không publish. Khi đã lọc theo
			// product_id thì bước này thừa nhưng giữ nguyên để mọi nhánh đều
			// an toàn.
			if ( ! self::is_published_parent( $variation->get_parent_id() ) ) {
				continue;
			}

			$items[] = self::serialize_variation( $variation );
		}

		if ( '' !== $search ) {
			$needle  = function_exists( 'mb_strtolower' ) ? mb_strtolower( $search ) : strtolower( $search );
			$items   = array_values(
				array_filter(
					$items,
					function ( $item ) use ( $needle ) {
						$haystack = strtolower(
							(string) $item['name'] . ' '
							. (string) $item['sku'] . ' '
							. self::attributes_text( $item['attributes'] )
						);
						return ( '' !== $needle ) && ( false !== strpos( $haystack, $needle ) );
					}
				)
			);
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Danh sách đơn hàng WooCommerce (HPOS-safe, yêu cầu xác thực).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_orders( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$per_page = self::per_page( $request );
		$page     = self::page( $request );
		$search   = self::search_term( $request );
		$status   = sanitize_key( (string) $request->get_param( 'status' ) );
		$from     = trim( (string) $request->get_param( 'date_from' ) );
		$to       = trim( (string) $request->get_param( 'date_to' ) );

		// Khoảng ngày ngược (date_from > date_to) bị validate_orders_date_range()
		// chặn trước ở cấp route và trả HTTP 400 với mã `kc_invalid_date_range`.
		// Nhánh dưới đây chỉ là lưới an toàn cho chuỗi ngày mà strtotime() không
		// phân tích được (ví dụ 2026-02-30) nên validate cấp route bỏ qua; nhánh này
		// trả mã chuẩn `rest_invalid_param` của WordPress. Cả hai đều là HTTP 400.
		if ( '' !== $from && '' !== $to && $from > $to ) {
			return new WP_Error(
				'rest_invalid_param',
				'Tham số "date_from" phải nhỏ hơn hoặc bằng "date_to".',
				array( 'status' => 400 )
			);
		}

		$query_args = array(
			'limit'   => $per_page,
			'paged'   => $page,
			'orderby' => 'date',
			'order'   => 'DESC',
			'status'  => self::order_statuses( $status ),
		);

		if ( '' !== $search ) {
			$query_args['s'] = $search;
		}

		$date_query = array();
		if ( '' !== $from && '' !== $to ) {
			$date_query[] = array(
				'date_created' => array(
					'gte' => $from . ' 00:00:00',
					'lte' => $to . ' 23:59:59',
				),
			);
		} elseif ( '' !== $from ) {
			$date_query[] = array(
				'date_created' => array( 'gte' => $from . ' 00:00:00' ),
			);
		} elseif ( '' !== $to ) {
			$date_query[] = array(
				'date_created' => array( 'lte' => $to . ' 23:59:59' ),
			);
		}
		if ( ! empty( $date_query ) ) {
			$query_args['date_query'] = $date_query;
		}

		$items = array();
		foreach ( wc_get_orders( $query_args ) as $order ) {
			if ( $order instanceof WC_Order ) {
				$items[] = self::serialize_order( $order );
			}
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Chi tiết một đơn hàng (yêu cầu xác thực).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_order_detail( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$order_id = absint( $request->get_param( 'id' ) );
		$order    = wc_get_order( $order_id );

		if ( ! $order instanceof WC_Order ) {
			return self::not_found_error( 'Không tìm thấy đơn hàng.' );
		}

		try {
			$payload                    = self::serialize_order( $order );
			$payload['wc_active']       = true;
			$payload['customer_note']   = self::order_text_field( $order, 'get_customer_note' );
			$payload['subtotal']        = self::order_float_field( $order, 'get_subtotal' );
			$payload['discount_total']  = self::order_float_field( $order, 'get_discount_total' );
			$payload['shipping_total']  = self::order_float_field( $order, 'get_shipping_total' );
			$payload['fee_total']       = self::order_float_field( $order, 'get_fee_total' );
			$payload['refunded_total']  = self::order_float_field( $order, 'get_total_refunded' );
			$payload['created_via']     = self::order_text_field( $order, 'get_created_via' );
		} catch ( \Throwable $e ) {
			return new \WP_Error(
				'kc_order_detail_failed',
				'Không đọc được chi tiết đơn hàng.',
				array( 'status' => 500 )
			);
		}

		return rest_ensure_response( $payload );
	}

	/* ---------------------------------------------------------------------
	 * Serializers
	 * ------------------------------------------------------------------ */

	/**
	 * Chuyển WC_Product thành payload read-only.
	 *
	 * @param WC_Product $product Product object.
	 * @return array
	 */
	private static function serialize_product( WC_Product $product ) {
		$image_url = null;
		$image_id  = $product->get_image_id();
		if ( $image_id ) {
			$image_url = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );
		}

		$categories = array();
		foreach ( $product->get_category_ids() as $term_id ) {
			$term = get_term( absint( $term_id ) );
			if ( $term instanceof WP_Term ) {
				$categories[] = array(
					'id'   => (int) $term->term_id,
					'name' => $term->name,
					'slug' => $term->slug,
				);
			}
		}

		return array(
			'id'             => $product->get_id(),
			'name'           => $product->get_name(),
			'sku'            => self::text_or_null( $product->get_sku() ),
			'barcode'        => self::product_barcode( $product ),
			'price'          => self::price_or_zero( $product->get_price() ),
			'regular_price'  => self::price_or_null( $product->get_regular_price() ),
			'sale_price'     => self::price_or_null( $product->get_sale_price() ),
			'stock_quantity' => $product->get_stock_quantity(),
			'stock_status'   => $product->get_stock_status(),
			'image_url'      => $image_url,
			'categories'     => $categories,
			'type'           => $product->get_type(),
		);
	}

	/**
	 * Chuyển WC_Product_Variation thành payload read-only.
	 *
	 * @param WC_Product_Variation $variation Variation object.
	 * @return array
	 */
	private static function serialize_variation( WC_Product_Variation $variation ) {
		$image_id = $variation->get_image_id();
		if ( ! $image_id ) {
			$image_id = $variation->get_parent_id();
		}

		$image_url = null;
		if ( $image_id ) {
			$image_url = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );
		}

		$attributes = array();
		foreach ( $variation->get_attributes() as $name => $value ) {
			$attributes[] = array(
				'name'   => wc_attribute_label( $name, $variation ),
				'option' => self::text_or_null( $value ),
			);
		}

		return array(
			'id'             => $variation->get_id(),
			'product_id'     => $variation->get_parent_id(),
			'name'           => $variation->get_name(),
			'sku'            => self::text_or_null( $variation->get_sku() ),
			'barcode'        => self::product_barcode( $variation ),
			'price'          => self::price_or_zero( $variation->get_price() ),
			'regular_price'  => self::price_or_null( $variation->get_regular_price() ),
			'sale_price'     => self::price_or_null( $variation->get_sale_price() ),
			'stock_quantity' => $variation->get_stock_quantity(),
			'stock_status'   => $variation->get_stock_status(),
			'image_url'      => $image_url,
			'attributes'     => $attributes,
		);
	}

	/**
	 * Thuộc tính ở cấp sản phẩm (dùng cho /products/{id}).
	 *
	 * @param WC_Product $product Product object.
	 * @return array
	 */
	private static function serialize_product_attributes( WC_Product $product ) {
		$attributes = array();

		foreach ( $product->get_attributes() as $attribute ) {
			if ( ! $attribute instanceof WC_Product_Attribute ) {
				continue;
			}

			$attributes[] = array(
				'id'        => (int) $attribute->get_id(),
				'name'      => wc_attribute_label( $attribute->get_name(), $product ),
				'options'   => array_values( (array) $attribute->get_options() ),
				'visible'   => (bool) $attribute->get_visible(),
				'variation' => (bool) $attribute->get_variation(),
			);
		}

		return $attributes;
	}

	/**
	 * Chuyển WC_Order thành payload read-only.
	 *
	 * Chỉ trả dữ liệu app cần: không có password, secret, token, dữ liệu quản trị.
	 *
	 * @param WC_Order $order Order object.
	 * @return array
	 */
	private static function serialize_order( WC_Order $order ) {
		$customer_id = (int) $order->get_customer_id();
		$name        = trim( $order->get_billing_first_name() . ' ' . $order->get_billing_last_name() );

		if ( '' === $name && $customer_id > 0 ) {
			$user  = get_userdata( $customer_id );
			$name  = $user ? trim( $user->display_name ) : '';
		}

		$payment_method = (string) $order->get_payment_method();

		$payment_status = 'unpaid';
		if ( method_exists( $order, 'get_payment_status' ) ) {
			$payment_status = (string) $order->get_payment_status();
		} elseif ( $order->get_date_paid() ) {
			$payment_status = 'paid';
		}

		return array(
			'id'                   => $order->get_id(),
			'number'               => (string) $order->get_order_number(),
			'status'               => $order->get_status(),
			'status_label'         => self::order_status_label( $order->get_status() ),
			'date_created'         => self::format_date( $order->get_date_created() ),
			'date_paid'            => self::format_date( $order->get_date_paid() ),
			'payment_method'       => self::text_or_null( $payment_method ),
			'payment_method_label' => self::text_or_null( self::order_payment_label( $payment_method ) ),
			'payment_status'       => $payment_status,
			'currency'             => $order->get_currency(),
			'total'                => (float) $order->get_total(),
			'customer'             => array(
				'id'       => $customer_id,
				'is_guest' => ( 0 === $customer_id ),
				'name'     => self::text_or_null( $name ),
				'phone'    => self::text_or_null( $order->get_billing_phone() ),
				'email'    => self::text_or_null( $order->get_billing_email() ),
			),
			'billing'              => self::serialize_address( $order, 'billing' ),
			'shipping'             => self::serialize_address( $order, 'shipping' ),
			'line_items'           => self::serialize_order_items( $order ),
		);
	}

	/**
	 * Địa chỉ của đơn hàng (billing hoặc shipping).
	 *
	 * @param WC_Order $order Order object.
	 * @param string   $type  'billing' hoặc 'shipping'.
	 * @return array
	 */
	private static function serialize_address( WC_Order $order, $type ) {
		$address = $order->get_address( $type );
		if ( ! is_array( $address ) ) {
			$address = array();
		}

		return array(
			'first_name' => self::text_or_null( isset( $address['first_name'] ) ? $address['first_name'] : '' ),
			'last_name'  => self::text_or_null( isset( $address['last_name'] ) ? $address['last_name'] : '' ),
			'address_1'  => self::text_or_null( isset( $address['address_1'] ) ? $address['address_1'] : '' ),
			'address_2'  => self::text_or_null( isset( $address['address_2'] ) ? $address['address_2'] : '' ),
			'city'       => self::text_or_null( isset( $address['city'] ) ? $address['city'] : '' ),
			'state'      => self::text_or_null( isset( $address['state'] ) ? $address['state'] : '' ),
			'postcode'   => self::text_or_null( isset( $address['postcode'] ) ? $address['postcode'] : '' ),
			'country'    => self::text_or_null( isset( $address['country'] ) ? $address['country'] : '' ),
			'phone'      => self::text_or_null( isset( $address['phone'] ) ? $address['phone'] : '' ),
			'email'      => self::text_or_null( isset( $address['email'] ) ? $address['email'] : '' ),
		);
	}

	/**
	 * Sản phẩm trong đơn hàng.
	 *
	 * @param WC_Order $order Order object.
	 * @return array
	 */
	private static function serialize_order_items( WC_Order $order ) {
		$items = array();

		foreach ( $order->get_items() as $item_id => $item ) {
			if ( ! $item instanceof WC_Order_Item_Product ) {
				continue;
			}

			try {
				$product    = $item->get_product();
				$quantity   = (float) $item->get_quantity();
				$subtotal   = (float) $order->get_item_subtotal( $item );
				$unit_price = ( $quantity > 0 ) ? ( $subtotal / $quantity ) : $subtotal;

				$items[] = array(
					'id'           => (int) $item_id,
					'product_id'   => (int) $item->get_product_id(),
					'variation_id' => (int) $item->get_variation_id(),
					'name'         => (string) $item->get_name(),
					'sku'          => ( $product instanceof WC_Product ) ? self::text_or_null( $product->get_sku() ) : null,
					'quantity'     => $quantity,
					'price'        => $unit_price,
					'subtotal'     => $subtotal,
					'total'        => (float) $item->get_total(),
				);
			} catch ( \Throwable $e ) {
				// Line item hỏng dữ liệu vẫn phải xuất hiện với giá trị null.
				$items[] = array(
					'id'           => (int) $item_id,
					'product_id'   => (int) $item->get_product_id(),
					'variation_id' => (int) $item->get_variation_id(),
					'name'         => null,
					'sku'          => null,
					'quantity'     => 0.0,
					'price'        => null,
					'subtotal'     => 0.0,
					'total'        => 0.0,
				);
			}
		}

		return $items;
	}

	/* ---------------------------------------------------------------------
	 * WooCommerce helpers
	 * ------------------------------------------------------------------ */

	/**
	 * Barcode lưu ở meta, hỗ trợ cả key của plugin lẫn key phổ biến.
	 *
	 * @param WC_Product $product Product hoặc variation.
	 * @return string|null
	 */
	private static function product_barcode( $product ) {
		$barcode = $product->get_meta( '_mkc_barcode' );

		if ( '' === $barcode ) {
			$barcode = $product->get_meta( '_barcode' );
		}

		return self::text_or_null( $barcode );
	}

	/**
	 * Nhãn tiếng Việt cho trạng thái đơn hàng.
	 *
	 * @param string $status WooCommerce status.
	 * @return string
	 */
	private static function order_status_label( $status ) {
		$labels = array(
			'pending'    => 'Chờ xử lý',
			'processing' => 'Đang xử lý',
			'on-hold'    => 'Chờ thanh toán',
			'completed'  => 'Hoàn tất',
			'cancelled'  => 'Đã huỷ',
			'refunded'   => 'Đã hoàn',
			'failed'     => 'Thất bại',
		);

		return isset( $labels[ $status ] ) ? $labels[ $status ] : $status;
	}

	/**
	 * Nhãn phương thức thanh toán.
	 *
	 * @param string $method Payment method key.
	 * @return string
	 */
	private static function order_payment_label( $method ) {
		$labels = array(
			'cod'            => 'COD',
			'bacs'           => 'Chuyển khoản',
			'bank_transfer'  => 'Chuyển khoản',
			'cheque'         => 'Séc',
			'paypal'         => 'PayPal',
			'cash'           => 'Tiền mặt',
		);

		return isset( $labels[ $method ] ) ? $labels[ $method ] : $method;
	}

	/**
	 * Whitelist trạng thái đơn hàng được phép lọc.
	 *
	 * @return array
	 */
	private static function allowed_order_statuses() {
		return array( 'pending', 'processing', 'on-hold', 'completed', 'cancelled', 'refunded', 'failed' );
	}

	/**
	 * Chuyển tham số status thành giá trị cho wc_get_orders().
	 *
	 * Tham số đã được whitelist ở validate_order_status(), nên ở đây chỉ
	 * cần xử lý rỗng và 'any' (không lọc).
	 *
	 * @param string $status Tham số từ query.
	 * @return array
	 */
	private static function order_statuses( $status ) {
		$status = sanitize_key( (string) $status );

		if ( '' === $status || 'any' === $status ) {
			return array();
		}

		return in_array( $status, self::allowed_order_statuses(), true ) ? array( $status ) : array();
	}

	/**
	 * WooCommerce đã sẵn sàng để đọc dữ liệu chưa.
	 *
	 * @return bool
	 */
	private static function wc_ready() {
		return class_exists( 'WooCommerce' )
			&& function_exists( 'wc_get_products' )
			&& function_exists( 'wc_get_orders' );
	}

	/**
	 * Trả về WP_Error 503 nếu WooCommerce chưa active, ngược lại null.
	 *
	 * @return WP_Error|null
	 */
	private static function require_wc() {
		if ( self::wc_ready() ) {
			return null;
		}

		return new WP_Error(
			'kc_woocommerce_unavailable',
			'WooCommerce chưa active nên không đọc được dữ liệu.',
			array( 'status' => 503 )
		);
	}

	/* ---------------------------------------------------------------------
	 * Response helpers
	 * ------------------------------------------------------------------ */

	/**
	 * Lỗi 404 chuẩn.
	 *
	 * @param string $message Thông báo.
	 * @return WP_Error
	 */
	private static function not_found_error( $message ) {
		return new WP_Error(
			'kc_not_found',
			$message,
			array( 'status' => 404 )
		);
	}

	/**
	 * Bọc danh sách item thành response chuẩn.
	 *
	 * `count` là số item TRONG TRANG HIỆN TẠI, không phải tổng số bản ghi.
	 *
	 * @param array $items    Danh sách item.
	 * @param int   $page     Trang hiện tại.
	 * @param int   $per_page Số item mỗi trang.
	 * @return WP_REST_Response
	 */
	private static function list_response( $items, $page, $per_page ) {
		return rest_ensure_response(
			array(
				'wc_active' => true,
				'count'     => count( $items ),
				'page'      => (int) $page,
				'per_page'  => (int) $per_page,
				'data'      => $items,
			)
		);
	}

	/**
	 * per_page đã được validate_per_page() kiểm tra nằm trong 1–50 trước khi
	 * tới handler, nên ở đây chỉ đọc giá trị, KHÔNG tự sửa cho hợp lệ.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return int
	 */
	private static function per_page( $request ) {
		return (int) $request->get_param( 'per_page' );
	}

	/**
	 * page đã được validate_page() kiểm tra là số nguyên từ 1 trở lên.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return int
	 */
	private static function page( $request ) {
		return (int) $request->get_param( 'page' );
	}

	/**
	 * Sản phẩm cha có đang publish hay không.
	 *
	 * Dùng WooCommerce CRUD `wc_get_product()` (đọc trực tiếp post, không lọc
	 * theo trạng thái) nên nhận diện được cả draft/private/pending. Kết quả
	 * được ghi nhớ trong phạm vi một request để tránh gọi lặp khi một trang có
	 * nhiều biến thể cùng cha.
	 *
	 * @param int $parent_id ID sản phẩm cha.
	 * @return bool
	 */
	private static function is_published_parent( $parent_id ) {
		$parent_id = (int) $parent_id;

		if ( $parent_id <= 0 ) {
			return false;
		}

		if ( ! array_key_exists( $parent_id, self::$parent_status_cache ) ) {
			$parent = wc_get_product( $parent_id );

			self::$parent_status_cache[ $parent_id ] = ( $parent instanceof WC_Product )
				&& ( 'publish' === $parent->get_status() );
		}

		return self::$parent_status_cache[ $parent_id ];
	}

	/**
	 * Tham số search đã trim và giới hạn độ dài.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return string
	 */
	private static function search_term( $request ) {
		$term = trim( (string) $request->get_param( 'search' ) );

		if ( '' === $term ) {
			return '';
		}

		return function_exists( 'mb_substr' )
			? mb_substr( $term, 0, self::MAX_SEARCH_LENGTH )
			: substr( $term, 0, self::MAX_SEARCH_LENGTH );
	}

	/* ---------------------------------------------------------------------
	 * Value helpers
	 * ------------------------------------------------------------------ */

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

	/**
	 * Getter số của order, an toàn khi method không tồn tại hoặc trả rỗng.
	 *
	 * Dùng is_callable() thay vì method_exists() để chỉ gọi method public thật,
	 * tránh rơi vào __call() và tránh fatal trên PHP 8.
	 *
	 * @param WC_Order $order  Order object.
	 * @param string   $method Tên getter.
	 * @return float
	 */
	private static function order_float_field( WC_Order $order, $method ) {
		if ( ! is_callable( array( $order, $method ) ) ) {
			return 0.0;
		}

		$value = $order->{$method}();

		return is_numeric( $value ) ? (float) $value : 0.0;
	}

	/**
	 * Getter chuỗi của order, an toàn khi method không tồn tại hoặc trả rỗng.
	 *
	 * @param WC_Order $order  Order object.
	 * @param string   $method Tên getter.
	 * @return string|null
	 */
	private static function order_text_field( WC_Order $order, $method ) {
		if ( ! is_callable( array( $order, $method ) ) ) {
			return null;
		}

		$value = $order->{$method}();

		return is_scalar( $value ) ? self::text_or_null( $value ) : null;
	}

	/**
	 * Format WC_DateTime thành chuỗi, null nếu chưa có.
	 *
	 * @param mixed $date_time WC_DateTime|null.
	 * @return string|null
	 */
	private static function format_date( $date_time ) {
		if ( $date_time instanceof WC_DateTime ) {
			return $date_time->date( 'Y-m-d H:i:s' );
		}

		return null;
	}

	/**
	 * Gom option của biến thể thành chuỗi để hỗ trợ search.
	 *
	 * @param array $attributes Danh sách attributes đã serialize.
	 * @return string
	 */
	private static function attributes_text( $attributes ) {
		$parts = array();

		foreach ( (array) $attributes as $attribute ) {
			if ( isset( $attribute['option'] ) && is_scalar( $attribute['option'] ) ) {
				$parts[] = (string) $attribute['option'];
			}
		}

		return implode( ' ', $parts );
	}
}

add_action( 'rest_api_init', array( 'MKC_REST_API', 'register_routes' ) );
