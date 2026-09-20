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