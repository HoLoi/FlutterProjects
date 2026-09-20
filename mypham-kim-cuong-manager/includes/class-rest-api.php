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