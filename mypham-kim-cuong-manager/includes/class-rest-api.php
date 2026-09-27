<?php
/**
 * REST API for MyPham Kim Cuong Manager.
 *
 * @package mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class MKC_REST_API {

	const REST_NAMESPACE = 'kc/v1';

	/**
	 * Register REST routes.
	 */
	public static function register_routes() {
		register_rest_route(
			self::REST_NAMESPACE,
			'/health',
			array(
				'methods'             => 'GET',
				'callback'            => array( __CLASS__, 'handle_health' ),
				'permission_callback' => '__return_true',
			)
		);

		register_rest_route(
			self::REST_NAMESPACE,
			'/products',
			array(
				'methods'             => 'GET',
				'callback'            => array( __CLASS__, 'handle_products' ),
				'permission_callback' => array( __CLASS__, 'permission_products' ),
				'args'                => array(
					'search'   => array(
						'type'              => 'string',
						'required'          => false,
						'sanitize_callback' => 'sanitize_text_field',
					),
					'per_page' => array(
						'type'              => 'integer',
						'required'          => false,
						'default'           => 20,
						'sanitize_callback' => 'absint',
					),
					'page'     => array(
						'type'              => 'integer',
						'required'          => false,
						'default'           => 1,
						'sanitize_callback' => 'absint',
					),
				),
			)
		);

		self::register_read_only_route( '/categories', array( __CLASS__, 'handle_categories' ), true );
		self::register_read_only_route(
			'/variations',
			array( __CLASS__, 'handle_variations' ),
			true,
			array(
				'product_id' => array(
					'type'              => 'integer',
					'required'          => false,
					'sanitize_callback' => 'absint',
				),
				'parent_id'  => array(
					'type'              => 'integer',
					'required'          => false,
					'sanitize_callback' => 'absint',
				),
			)
		);
		self::register_read_only_route(
			'/orders',
			array( __CLASS__, 'handle_orders' ),
			true,
			array(
				'status'    => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_key',
				),
				'date_from' => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
				),
				'date_to'   => array(
					'type'              => 'string',
					'required'          => false,
					'sanitize_callback' => 'sanitize_text_field',
				),
			)
		);
		self::register_read_only_route( '/orders/(?P<id>\d+)', array( __CLASS__, 'handle_order_detail' ) );
	}

	/**
	 * Đăng ký một route GET read-only kèm tham số phân trang chuẩn.
	 *
	 * @param string   $path        Đường dẫn sau namespace.
	 * @param callable $callback    Handler.
	 * @param bool     $with_search Bật tham số search.
	 * @param array    $extra_args  Tham số riêng của từng route.
	 */
	private static function register_read_only_route( $path, $callback, $with_search = false, $extra_args = array() ) {
		$args = array(
			'methods'             => 'GET',
			'callback'            => $callback,
			'permission_callback' => array( __CLASS__, 'permission_public' ),
			'args'                => array(
				'per_page' => array(
					'type'              => 'integer',
					'required'          => false,
					'default'           => 20,
					'sanitize_callback' => 'absint',
				),
				'page'     => array(
					'type'              => 'integer',
					'required'          => false,
					'default'           => 1,
					'sanitize_callback' => 'absint',
				),
			),
		);

		if ( $with_search ) {
			$args['args']['search'] = array(
				'type'              => 'string',
				'required'          => false,
				'sanitize_callback' => 'sanitize_text_field',
			);
		}

		if ( ! empty( $extra_args ) ) {
			$args['args'] = array_merge( $args['args'], $extra_args );
		}

		register_rest_route( self::REST_NAMESPACE, $path, $args );
	}

	/**
	 * Read-only public access dùng cho MVP demo.
	 * TODO: trước khi lên production phải yêu cầu xác thực (ví dụ nonce + capability).
	 *
	 * @return true
	 */
	public static function permission_public() {
		return true;
	}

	/**
	 * Read-only public access dùng cho MVP demo.
	 * TODO: trước khi lên production phải yêu cầu xác thực (ví dụ nonce + capability).
	 *
	 * @return true
	 */
	public static function permission_products() {
		return true;
	}

	/**
	 * Danh sách sản phẩm WooCommerce (read-only).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response
	 */
	public static function handle_products( $request ) {
		if ( ! class_exists( 'WooCommerce' ) ) {
			return rest_ensure_response(
				array(
					'wc_active' => false,
					'count'     => 0,
					'data'      => array(),
					'message'   => 'WooCommerce chưa active, không đọc được sản phẩm.',
				)
			);
		}

		$per_page = min( (int) $request->get_param( 'per_page' ), 50 );
		$page     = max( (int) $request->get_param( 'page' ), 1 );
		$search   = (string) $request->get_param( 'search' );

		$args = array(
			'limit'   => $per_page,
			'page'    => $page,
			'orderby' => 'date',
			'order'   => 'DESC',
			'return'  => 'objects',
		);

		if ( '' !== trim( $search ) ) {
			$args['s'] = trim( $search );
		}

		$query = new WC_Product_Query( $args );
		$items = array();

		foreach ( $query->get_products() as $product ) {
			if ( ! $product instanceof WC_Product ) {
				continue;
			}
			$items[] = self::serialize_product( $product );
		}

		return rest_ensure_response(
			array(
				'wc_active' => true,
				'count'     => count( $items ),
				'page'      => $page,
				'per_page'  => $per_page,
				'data'      => $items,
			)
		);
	}

	/**
	 * Chuyển WC_Product thành payload read-only nhẹ. Không trả dữ liệu nhạy cảm.
	 *
	 * @param WC_Product $product Product object.
	 * @return array
	 */
	public static function serialize_product( WC_Product $product ) {
		$image_url = null;
		$image_id  = $product->get_image_id();
		if ( $image_id ) {
			$image_url = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );
		}

		$barcode = $product->get_meta( '_mkc_barcode' );
		if ( '' === $barcode ) {
			$barcode = $product->get_meta( '_barcode' );
		}
		if ( '' === $barcode ) {
			$barcode = null;
		}

		$categories = array();
		foreach ( $product->get_category_ids() as $term_id ) {
			$term = get_term( $term_id );
			if ( $term instanceof WP_Term ) {
				$categories[] = array(
					'id'   => $term->term_id,
					'name' => $term->name,
					'slug' => $term->slug,
				);
			}
		}

		$price         = ( '' !== $product->get_price() ) ? (float) $product->get_price() : 0;
		$regular_price = ( '' !== $product->get_regular_price() ) ? (float) $product->get_regular_price() : null;
		$sale_price    = ( '' !== $product->get_sale_price() ) ? (float) $product->get_sale_price() : null;

		return array(
			'id'             => $product->get_id(),
			'name'           => $product->get_name(),
			'sku'            => ( '' !== $product->get_sku() ) ? $product->get_sku() : null,
			'barcode'        => $barcode,
			'price'          => $price,
			'regular_price'  => $regular_price,
			'sale_price'     => $sale_price,
			'stock_quantity' => $product->get_stock_quantity(),
			'stock_status'   => $product->get_stock_status(),
			'image_url'      => $image_url,
			'categories'     => $categories,
			'type'           => $product->get_type(),
		);
	}

	/**
	 * Danh sách danh mục sản phẩm WooCommerce (read-only).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response
	 */
	public static function handle_categories( $request ) {
		if ( ! self::wc_ready() ) {
			return self::wc_inactive_response();
		}

		$per_page = self::per_page( $request );
		$page     = self::page( $request );
		$search   = trim( (string) $request->get_param( 'search' ) );

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

		$terms    = get_terms( $query_args );
		$items    = array();
		$is_error = is_wp_error( $terms );

		if ( ! $is_error ) {
			foreach ( $terms as $term ) {
				$items[] = array(
					'id'     => $term->term_id,
					'name'   => $term->name,
					'slug'   => $term->slug,
					'parent' => (int) $term->parent,
					'count'  => (int) $term->count,
				);
			}
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Danh sách biến thể của sản phẩm (read-only).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_variations( $request ) {
		if ( ! self::wc_ready() ) {
			return self::wc_inactive_response();
		}

		$product_id = (int) $request->get_param( 'product_id' );
		if ( $product_id <= 0 ) {
			$product_id = (int) $request->get_param( 'parent_id' );
		}

		$variations = array();
		if ( $product_id > 0 ) {
			$variations = wc_get_products(
				array(
					'type'   => 'variation',
					'parent' => $product_id,
					'limit'  => -1,
					'return' => 'objects',
					'status' => array( 'publish', 'private' ),
				)
			);
		}

		$items = array();
		foreach ( $variations as $variation ) {
			if ( $variation instanceof WC_Product_Variation ) {
				$items[] = self::serialize_variation( $variation );
			}
		}

		$search = trim( (string) $request->get_param( 'search' ) );
		if ( '' !== $search ) {
			$needle  = function_exists( 'mb_strtolower' ) ? mb_strtolower( $search ) : strtolower( $search );
			$items   = array_values(
				array_filter(
					$items,
					function ( $item ) use ( $needle ) {
						$haystack = strtolower( (string) $item['name'] . ' ' . (string) $item['sku'] );
						return false !== strpos( $haystack, $needle );
					}
				)
			);
		}

		return self::list_response( $items, 1, count( $items ) );
	}

	/**
	 * Danh sách đơn hàng WooCommerce (read-only, HPOS-safe).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response
	 */
	public static function handle_orders( $request ) {
		if ( ! self::wc_ready() ) {
			return self::wc_inactive_response();
		}

		$per_page = self::per_page( $request );
		$page     = self::page( $request );
		$search   = trim( (string) $request->get_param( 'search' ) );
		$status   = trim( (string) $request->get_param( 'status' ) );
		$from     = trim( (string) $request->get_param( 'date_from' ) );
		$to       = trim( (string) $request->get_param( 'date_to' ) );

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
		if ( '' !== $from ) {
			$date_query['date_created'] = ( '' !== $to )
				? array(
					'gte' => $from . ' 00:00:00',
					'lte' => $to . ' 23:59:59',
				)
				: array( 'gte' => $from . ' 00:00:00' );
		} elseif ( '' !== $to ) {
			$date_query['date_created'] = array( 'lte' => $to . ' 23:59:59' );
		}
		if ( ! empty( $date_query ) ) {
			$query_args['date_query'] = array( $date_query );
		}

		$orders = wc_get_orders( $query_args );
		$items  = array();
		foreach ( $orders as $order ) {
			if ( $order instanceof WC_Order ) {
				$items[] = self::serialize_order( $order );
			}
		}

		return self::list_response( $items, $page, $per_page );
	}

	/**
	 * Chi tiết một đơn hàng (read-only).
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response
	 */
	public static function handle_order_detail( $request ) {
		if ( ! self::wc_ready() ) {
			return self::wc_inactive_response();
		}

		$order_id = (int) $request->get_param( 'id' );
		$order    = wc_get_order( $order_id );

		if ( ! $order instanceof WC_Order ) {
			return new WP_Error(
				'kc_not_found',
				'Không tìm thấy đơn hàng.',
				array( 'status' => 404 )
			);
		}

		$payload                 = self::serialize_order( $order );
		$payload['wc_active']    = true;
		$payload['notes']        = $order->get_customer_note();
		$payload['subtotal']     = (float) $order->get_subtotal();
		$payload['discount_total'] = (float) $order->get_discount_total();
		$payload['shipping_total']  = (float) $order->get_shipping_total();

		$items = array();
		foreach ( $order->get_items() as $item_id => $item ) {
			if ( ! $item instanceof WC_Order_Item_Product ) {
				continue;
			}
			$product = $item->get_product();
			$items[] = array(
				'id'           => (int) $item_id,
				'product_id'   => (int) $item->get_product_id(),
				'variation_id' => (int) $item->get_variation_id(),
				'name'         => $item->get_name(),
				'sku'          => $product instanceof WC_Product ? (string) $product->get_sku() : null,
				'quantity'     => (float) $item->get_quantity(),
				'price'        => (float) $order->get_item_subtotal( $item ),
				'subtotal'     => (float) $item->get_total(),
			);
		}
		$payload['items'] = $items;

		return rest_ensure_response( $payload );
	}

	/**
	 * Chuyển WC_Product_Variation thành payload read-only.
	 *
	 * @param WC_Product_Variation $variation Variation object.
	 * @return array
	 */
	private static function serialize_variation( WC_Product_Variation $variation ) {
		$image_url = null;
		$image_id  = $variation->get_image_id();
		if ( ! $image_id ) {
			$image_id = $variation->get_parent_id();
		}
		if ( $image_id ) {
			$image_url = wp_get_attachment_image_url( $image_id, 'woocommerce_thumbnail' );
		}

		$barcode = $variation->get_meta( '_mkc_barcode' );
		if ( '' === $barcode ) {
			$barcode = $variation->get_meta( '_barcode' );
		}
		if ( '' === $barcode ) {
			$barcode = null;
		}

		$attributes = array();
		foreach ( $variation->get_attributes() as $name => $value ) {
			$attributes[] = array(
				'name'   => wc_attribute_label( $name, $variation ),
				'option' => $value,
			);
		}

		$price = ( '' !== $variation->get_price() ) ? (float) $variation->get_price() : 0;

		return array(
			'id'             => $variation->get_id(),
			'product_id'     => $variation->get_parent_id(),
			'name'           => $variation->get_name(),
			'sku'            => ( '' !== $variation->get_sku() ) ? $variation->get_sku() : null,
			'barcode'        => $barcode,
			'price'          => $price,
			'regular_price'  => ( '' !== $variation->get_regular_price() ) ? (float) $variation->get_regular_price() : null,
			'sale_price'     => ( '' !== $variation->get_sale_price() ) ? (float) $variation->get_sale_price() : null,
			'stock_quantity' => $variation->get_stock_quantity(),
			'stock_status'   => $variation->get_stock_status(),
			'image_url'      => $image_url,
			'attributes'     => $attributes,
		);
	}

	/**
	 * Chuyển WC_Order thành payload read-only nhẹ (không trả dữ liệu nhạy cảm).
	 *
	 * @param WC_Order $order Order object.
	 * @return array
	 */
	private static function serialize_order( WC_Order $order ) {
		$customer_name  = trim( $order->get_billing_first_name() . ' ' . $order->get_billing_last_name() );
		$payment_method = (string) $order->get_payment_method();

		return array(
			'id'                   => $order->get_id(),
			'number'               => $order->get_order_number(),
			'status'               => $order->get_status(),
			'status_label'         => self::order_status_label( $order->get_status() ),
			'created_at'           => $order->get_date_created() ? $order->get_date_created()->date( 'Y-m-d H:i:s' ) : null,
			'customer_name'        => ( '' !== $customer_name ) ? $customer_name : null,
			'customer_phone'       => ( '' !== $order->get_billing_phone() ) ? $order->get_billing_phone() : null,
			'items_count'          => (int) $order->get_item_count(),
			'total'                => (float) $order->get_total(),
			'payment_method'       => $payment_method,
			'payment_method_label' => ( '' !== $payment_method ) ? self::order_payment_label( $payment_method ) : null,
			'payment_status'       => $order->get_date_paid() ? 'paid' : 'unpaid',
		);
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
			'bank_transfer'  => 'Chuyển khoản',
			'cheque'         => 'Séc',
			'paypal'         => 'PayPal',
			'bacs'           => 'Chuyển khoản',
			'cash'           => 'Tiền mặt',
		);

		return isset( $labels[ $method ] ) ? $labels[ $method ] : $method;
	}

	/**
	 * Chuyển tham số status thành danh sách status hợp lệ cho wc_get_orders().
	 *
	 * @param string $status Tham số từ query.
	 * @return array
	 */
	private static function order_statuses( $status ) {
		$allowed = array( 'pending', 'processing', 'on-hold', 'completed', 'cancelled', 'refunded', 'failed' );
		$status  = trim( $status );

		if ( '' === $status || 'any' === $status ) {
			return array();
		}

		return in_array( $status, $allowed, true ) ? array( $status ) : array();
	}

	/**
	 * WooCommerce đã sẵn sàng để đọc dữ liệu chưa.
	 *
	 * @return bool
	 */
	private static function wc_ready() {
		return class_exists( 'WooCommerce' ) && function_exists( 'wc_get_orders' );
	}

	/**
	 * Phản hồi khi WooCommerce chưa active.
	 *
	 * @return WP_REST_Response
	 */
	private static function wc_inactive_response() {
		return rest_ensure_response(
			array(
				'wc_active' => false,
				'count'     => 0,
				'page'      => 1,
				'per_page'  => 0,
				'data'      => array(),
				'message'   => 'WooCommerce chưa active, không đọc được dữ liệu.',
			)
		);
	}

	/**
	 * per_page đã giới hạn tối đa 50.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return int
	 */
	private static function per_page( $request ) {
		return min( (int) $request->get_param( 'per_page' ), 50 );
	}

	/**
	 * page tối thiểu là 1.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return int
	 */
	private static function page( $request ) {
		return max( (int) $request->get_param( 'page' ), 1 );
	}

	/**
	 * Bọc danh sách item thành response chuẩn.
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
				'page'      => $page,
				'per_page'  => $per_page,
				'data'      => $items,
			)
		);
	}

	/**
	 * Health check. Read-only, safe to call without authentication.
	 *
	 * @return WP_REST_Response
	 */
	public static function handle_health() {
		return rest_ensure_response(
			array(
				'ok'                 => true,
				'plugin'             => 'mypham-kim-cuong-manager',
				'version'            => MKC_MANAGER_VERSION,
				'time'               => current_time( 'mysql' ),
				'wordpress'          => get_bloginfo( 'version' ),
				'woocommerce_active' => class_exists( 'WooCommerce' ),
			)
		);
	}
}

add_action( 'rest_api_init', array( 'MKC_REST_API', 'register_routes' ) );