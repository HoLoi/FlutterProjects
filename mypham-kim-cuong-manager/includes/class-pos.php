<?php
/**
 * POS sales API cho MyPham Kim Cuong Manager (namespace `kc/v1`).
 *
 * Đây là endpoint GHI DUY NHẤT của plugin: `POST /pos/sales`. Toàn bộ endpoint
 * còn lại trong `class-rest-api.php` là read-only và không bị file này đụng tới.
 *
 * Nguyên tắc bắt buộc:
 * - Tạo đơn bằng WooCommerce CRUD chính thức (`wc_create_order()`,
 *   `WC_Order::add_product()`, `WC_Order::calculate_totals()`). Không SQL, không
 *   tự sửa `_stock` bằng phép trừ số học, không tạo custom table.
 * - Server tự đọc lại sản phẩm và giá hiện tại từ WooCommerce; app KHÔNG gửi
 *   giá và giá gửi lên cũng bị bỏ qua.
 * - Xác thực bằng WordPress Application Password qua HTTPS + capability
 *   `manage_woocommerce`. Không JWT tự viết, không secret trong plugin, không
 *   token hard-code.
 * - `request_id` được lưu vào order meta `_mkc_pos_request_id`; gửi lại cùng
 *   `request_id` sẽ trả về đơn cũ (HTTP 200, `replayed: true`) thay vì tạo đơn
 *   mới, nên bấm thanh toán hai lần không sinh đơn trùng.
 *
 * @package mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class MKC_POS_API {

	/**
	 * Order meta giữ `request_id`, là nguồn sự thật cho idempotency.
	 *
	 * Meta có tiền tố `_` (WooCommerce/WordPress coi là protected) nhưng vẫn tra
	 * cứu được bằng `meta_query` (HPOS) hoặc `meta_key` (post storage).
	 */
	const REQUEST_ID_META = '_mkc_pos_request_id';

	/** Order meta giữ payment method mà POS yêu cầu (cash/bacs/vietqr). */
	const REQUESTED_PAYMENT_META = '_mkc_pos_payment_method';

	/** Ghi vào `created_via` để mọi đơn POS đều nhận diện được. */
	const CREATED_VIA = 'kc_pos';

	/** Số dòng sản phẩm tối đa trong một lần bán. */
	const MAX_ITEMS = 50;

	/** Số lượng tối đa cho một dòng sản phẩm. */
	const MAX_QUANTITY = 9999;

	/** Độ dài tối đa của `request_id`. */
	const MAX_REQUEST_ID_LENGTH = 64;

	/** Độ dài tối đa của `customer_note` sau khi làm sạch. */
	const MAX_NOTE_LENGTH = 500;

	/**
	 * Đăng ký route POS.
	 *
	 * `POST /wp-json/kc/v1/pos/sales` là route ghi duy nhất của plugin.
	 * Tham số không khai báo trong `args` vì body JSON được đọc thủ công trong
	 * handler, nhờ vậy JSON hỏng trả đúng HTTP 400 thay vì bị WordPress bọc
	 * thành `rest_invalid_param`.
	 */
	public static function register_routes() {
		register_rest_route(
			MKC_REST_API::REST_NAMESPACE,
			'/pos/sales',
			array(
				'methods'             => 'POST',
				'callback'            => array( __CLASS__, 'handle_create_sale' ),
				'permission_callback' => array( __CLASS__, 'permission_create_sale' ),
			)
		);
	}

	/* ---------------------------------------------------------------------
	 * Permission
	 * ------------------------------------------------------------------ */

	/**
	 * Quyền tạo đơn POS: bắt buộc đăng nhập, HTTPS và `manage_woocommerce`.
	 *
	 * WordPress tự xác thực Application Password và dựng `current_user`, nên
	 * plugin không parse header `Authorization` và không tự sinh token. Thứ tự
	 * trả lỗi cố định:
	 *
	 * - Chưa đăng nhập  → 401 kc_not_authenticated
	 * - Không phải HTTPS → 403 kc_https_required
	 * - Thiếu quyền     → 403 kc_cannot_create_sale
	 *
	 * @return true|WP_Error
	 */
	public static function permission_create_sale() {
		if ( ! is_user_logged_in() ) {
			return self::error( 'kc_not_authenticated', 'Cần đăng nhập để bán hàng tại cửa hàng.', 401 );
		}

		if ( ! self::is_secure_request() ) {
			return self::error(
				'kc_https_required',
				'Chỉ chấp nhận kết nối HTTPS vì header xác thực được gửi dạng chữ thường.',
				403
			);
		}

		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			return self::error( 'kc_cannot_create_sale', 'Tài khoản không có quyền tạo đơn POS.', 403 );
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
	 * Tạo một đơn bán tại cửa hàng.
	 *
	 * Luồng: đọc JSON → lấy `request_id` → tra xem đã bán với khoá này chưa →
	 * kiểm tra input còn lại và tồn kho → tạo đơn bằng WooCommerce CRUD → trả
	 * payload tối thiểu.
	 *
	 * @param WP_REST_Request $request Request instance.
	 * @return WP_REST_Response|WP_Error
	 */
	public static function handle_create_sale( $request ) {
		$wc_error = self::require_wc();
		if ( $wc_error ) {
			return $wc_error;
		}

		$payload = self::read_json_body( $request );
		if ( is_wp_error( $payload ) ) {
			return $payload;
		}

		$request_id = self::read_request_id( $payload );
		if ( is_wp_error( $request_id ) ) {
			return $request_id;
		}

		// Idempotency phải được tra TRƯỚC khi kiểm tra tồn kho. Nếu kiểm tra sau,
		// một lần gửi lại sau khi đơn cũ đã trừ kho sẽ bị từ chối với
		// "hết hàng" và app có thể bán lại lần nữa.
		$existing = self::find_orders_by_request_id( $request_id );
		if ( is_wp_error( $existing ) ) {
			return $existing;
		}

		if ( ! empty( $existing ) ) {
			$order = $existing[0];

			// Đơn do request khác đang tạo dở (đã claim request_id nhưng chưa có
			// dòng sản phẩm): trả 409 để app thử lại thay vì nhận đơn rỗng.
			if ( self::sale_in_progress( $order ) ) {
				return self::error( 'kc_sale_in_progress', 'Đơn cùng request_id đang được tạo, vui lòng thử lại.', 409 );
			}

			return self::sale_response( $order, true, 200 );
		}

		$payment_method = self::read_payment_method( $payload );
		if ( is_wp_error( $payment_method ) ) {
			return $payment_method;
		}

		$customer_id = self::read_customer_id( $payload );
		if ( is_wp_error( $customer_id ) ) {
			return $customer_id;
		}

		$note  = self::read_note( $payload );
		$lines = self::read_items( $payload );
		if ( is_wp_error( $lines ) ) {
			return $lines;
		}

		$items = self::validate_items( $lines );
		if ( is_wp_error( $items ) ) {
			return $items;
		}

		$products = self::resolve_products( $items );
		if ( is_wp_error( $products ) ) {
			return $products;
		}

		return self::create_order( $request_id, $payment_method, $customer_id, $note, $products );
	}

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
	 * `request_id`: bắt buộc, chuỗi không rỗng, giới hạn ký tự an toàn.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_request_id( $payload ) {
		$raw = isset( $payload['request_id'] ) ? $payload['request_id'] : '';

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_request_id', 'request_id phải là chuỗi.', 400 );
		}

		$request_id = trim( $raw );

		if ( '' === $request_id ) {
			return self::error( 'kc_invalid_request_id', 'Thiếu request_id để chống tạo đơn trùng.', 400 );
		}

		if ( strlen( $request_id ) > self::MAX_REQUEST_ID_LENGTH ) {
			return self::error(
				'kc_invalid_request_id',
				sprintf( 'request_id tối đa %d ký tự.', self::MAX_REQUEST_ID_LENGTH ),
				400
			);
		}

		// Chỉ nhận chữ, số và `. _ : -` để request_id luôn dùng được làm meta
		// và hiển thị được trên báo cáo.
		if ( ! preg_match( '/^[A-Za-z0-9._:-]+$/', $request_id ) ) {
			return self::error(
				'kc_invalid_request_id',
				'request_id chỉ gồm chữ cái, chữ số và các ký tự . _ : -',
				400
			);
		}

		return $request_id;
	}

	/**
	 * `payment_method`: bắt buộc và nằm trong whitelist.
	 *
	 * @param array $payload Body đã decode.
	 * @return string|WP_Error
	 */
	private static function read_payment_method( $payload ) {
		$raw = isset( $payload['payment_method'] ) ? $payload['payment_method'] : '';

		if ( ! is_string( $raw ) ) {
			return self::error( 'kc_invalid_payment_method', 'payment_method phải là chuỗi.', 400 );
		}

		$method = strtolower( trim( $raw ) );
		$allowed = self::allowed_payment_methods();

		if ( ! in_array( $method, $allowed, true ) ) {
			return self::error(
				'kc_invalid_payment_method',
				sprintf(
					'payment_method không hợp lệ. Chỉ nhận: %s.',
					implode( ', ', $allowed )
				),
				400
			);
		}

		return $method;
	}

	/**
	 * Whitelist phương thức thanh toán POS.
	 *
	 * @return array
	 */
	private static function allowed_payment_methods() {
		return array( 'cash', 'bacs', 'vietqr' );
	}

	/**
	 * `customer_id`: 0 (khách vãng lai) hoặc id khách hàng có thật.
	 *
	 * @param array $payload Body đã decode.
	 * @return int|WP_Error
	 */
	private static function read_customer_id( $payload ) {
		$raw = isset( $payload['customer_id'] ) ? $payload['customer_id'] : 0;

		if ( null === $raw || '' === $raw ) {
			return 0;
		}

		$customer_id = self::positive_integer( $raw );

		if ( null === $customer_id ) {
			return self::error( 'kc_invalid_customer', 'customer_id phải là số nguyên dương hoặc 0.', 400 );
		}

		if ( ! get_userdata( $customer_id ) ) {
			return self::error( 'kc_invalid_customer', sprintf( 'Không tìm thấy khách hàng #%d.', $customer_id ), 400 );
		}

		return $customer_id;
	}

	/**
	 * `customer_note`: tuỳ chọn, cắt bớt nếu quá dài.
	 *
	 * @param array $payload Body đã decode.
	 * @return string
	 */
	private static function read_note( $payload ) {
		$raw = isset( $payload['customer_note'] ) ? $payload['customer_note'] : '';

		if ( ! is_string( $raw ) ) {
			$raw = is_scalar( $raw ) ? (string) $raw : '';
		}

		$note = sanitize_textarea_field( $raw );

		return function_exists( 'mb_substr' )
			? mb_substr( $note, 0, self::MAX_NOTE_LENGTH )
			: substr( $note, 0, self::MAX_NOTE_LENGTH );
	}

	/**
	 * `items`: bắt buộc là mảng không rỗng và không vượt quá giới hạn.
	 *
	 * @param array $payload Body đã decode.
	 * @return array|WP_Error Danh sách row đã chuẩn hoá chỉ số.
	 */
	private static function read_items( $payload ) {
		$items = isset( $payload['items'] ) ? $payload['items'] : null;

		if ( ! is_array( $items ) || array() === $items ) {
			return self::error( 'kc_invalid_items', 'items phải là mảng và không được rỗng.', 400 );
		}

		if ( count( $items ) > self::MAX_ITEMS ) {
			return self::error(
				'kc_too_many_items',
				sprintf( 'Mỗi lần bán tối đa %d dòng sản phẩm.', self::MAX_ITEMS ),
				400
			);
		}

		return array_values( $items );
	}

	/**
	 * Kiểm tra cấu trúc từng dòng `items` trước khi đụng WooCommerce.
	 *
	 * Chỉ kiểm hình thức (số nguyên dương, không trùng dòng). Việc sản phẩm có
	 * tồn tại, bán được, đủ kho do `resolve_products()` đảm nhiệm.
	 *
	 * @param array $lines Danh sách row thô.
	 * @return array|WP_Error
	 */
	private static function validate_items( $lines ) {
		$prepared = array();
		$seen     = array();

		foreach ( $lines as $index => $row ) {
			if ( ! is_array( $row ) ) {
				return self::error( 'kc_invalid_items', sprintf( 'items[%d] phải là object.', $index ), 400 );
			}

			$product_id = self::positive_integer(
				isset( $row['product_id'] ) ? $row['product_id'] : null
			);

			if ( null === $product_id ) {
				return self::error(
					'kc_invalid_request',
					sprintf( 'items[%d].product_id phải là số nguyên dương.', $index ),
					400
				);
			}

			$variation_id = 0;
			$raw_variation = isset( $row['variation_id'] ) ? $row['variation_id'] : 0;

			if ( null !== $raw_variation && '' !== $raw_variation ) {
				$variation_id = self::positive_integer( $raw_variation );

				if ( null === $variation_id ) {
					return self::error(
						'kc_invalid_variation',
						sprintf( 'items[%d].variation_id phải là số nguyên dương.', $index ),
						400
					);
				}
			}

			$quantity = self::positive_integer( isset( $row['quantity'] ) ? $row['quantity'] : null );

			if ( null === $quantity ) {
				return self::error(
					'kc_invalid_quantity',
					sprintf( 'items[%d].quantity phải là số nguyên dương.', $index ),
					400
				);
			}

			if ( $quantity > self::MAX_QUANTITY ) {
				return self::error(
					'kc_invalid_quantity',
					sprintf( 'items[%d].quantity tối đa %d.', $index, self::MAX_QUANTITY ),
					400
				);
			}

			// Chặn trùng sản phẩm/variation trong cùng một lần bán để số lượng
			// và tồn kho không bị tính hai lần.
			$key = $product_id . ':' . $variation_id;

			if ( isset( $seen[ $key ] ) ) {
				return self::error(
					'kc_duplicate_item',
					sprintf(
						'items[%d] trùng với items[%d]. Mỗi sản phẩm chỉ được xuất hiện một lần.',
						$index,
						$seen[ $key ]
					),
					400
				);
			}

			$seen[ $key ] = $index;

			$prepared[] = array(
				'product_id'   => $product_id,
				'variation_id' => $variation_id,
				'quantity'     => $quantity,
			);
		}

		return $prepared;
	}

	/**
	 * Chuyển số bất kỳ thành số nguyên dương, hoặc null nếu không hợp lệ.
	 *
	 * Cố ý không dùng `absint()`: `absint('-5')` trả 5 nên giá trị âm sẽ lọt qua.
	 * Số thực nguyên (1.0) và chuỗi "1" được chấp nhận cho tiện; 1.5, true, null,
	 * mảng đều bị từ chối.
	 *
	 * @param mixed $value Giá trị thô.
	 * @return int|null
	 */
	private static function positive_integer( $value ) {
		if ( is_int( $value ) ) {
			return ( $value > 0 ) ? $value : null;
		}

		if ( is_float( $value ) ) {
			if ( $value > 0 && floor( $value ) === $value && $value <= PHP_INT_MAX ) {
				return (int) $value;
			}

			return null;
		}

		if ( is_string( $value ) ) {
			$value = trim( $value );

			if ( preg_match( '/^[0-9]+(\.0+)?$/', $value ) ) {
				$number = (float) $value;

				if ( $number > 0 ) {
					return (int) $number;
				}
			}
		}

		return null;
	}

	/* ---------------------------------------------------------------------
	 * Sản phẩm và tồn kho
	 * ------------------------------------------------------------------ */

	/**
	 * Kiểm tra từng dòng với WooCommerce và trả về object sản phẩm để thêm vào
	 * đơn.
	 *
	 * - Sản phẩm không tồn tại            → 404
	 * - Variation không thuộc sản phẩm    → 400
	 * - Sản phẩm biến thể thiếu variation → 400
	 * - Sản phẩm không bán được           → 400
	 * - Hết hàng / thiếu tồn kho          → 409
	 *
	 * Trả về object `WC_Product`/`WC_Product_Variation` đã được kiểm tra để
	 * `add_product()` dùng luôn, không phải tra cửa hàng lần nữa.
	 *
	 * @param array $items Danh sách dòng đã kiểm tra hình thức.
	 * @return array|WP_Error
	 */
	private static function resolve_products( $items ) {
		$resolved = array();

		foreach ( $items as $item ) {
			$product = wc_get_product( $item['product_id'] );

			if ( ! $product instanceof WC_Product ) {
				return self::error(
					'kc_product_not_found',
					sprintf( 'Không tìm thấy sản phẩm #%d.', $item['product_id'] ),
					404
				);
			}

			// POS chỉ bán sản phẩm đang publish, tránh bán nhầm bản nháp.
			if ( 'publish' !== $product->get_status() ) {
				return self::error(
					'kc_product_not_purchasable',
					sprintf( 'Sản phẩm #%d không ở trạng thái publish.', $item['product_id'] ),
					400
				);
			}

			$target = $product;

			if ( $item['variation_id'] > 0 ) {
				$variation = wc_get_product( $item['variation_id'] );

				if ( ! $variation instanceof WC_Product_Variation
					|| (int) $variation->get_parent_id() !== (int) $product->get_id() ) {
					return self::error(
						'kc_invalid_variation',
						sprintf(
							'Variation #%d không thuộc sản phẩm #%d.',
							$item['variation_id'],
							$item['product_id']
						),
						400
					);
				}

				$target = $variation;
			} elseif ( $product->is_type( 'variable' ) ) {
				return self::error(
					'kc_invalid_variation',
					sprintf( 'Sản phẩm #%d là sản phẩm biến thể, bắt buộc gửi variation_id.', $item['product_id'] ),
					400
				);
			}

			$stock_error = self::check_purchasable( $target, $item['quantity'] );
			if ( $stock_error ) {
				return $stock_error;
			}

			$resolved[] = array(
				'product'  => $target,
				'quantity' => $item['quantity'],
			);
		}

		return $resolved;
	}

	/**
	 * Sản phẩm/variation có bán được và đủ tồn kho hay không.
	 *
	 * Tồn kho chỉ kiểm tra khi sản phẩm đang quản lý kho (`managing_stock()`).
	 * Bản này cố ý KHÔNG dựa vào backorder: số lượng phải có thật trong kho,
	 * tránh bán quá số hàng đang tồn.
	 *
	 * @param WC_Product $product  Sản phẩm hoặc variation cần bán.
	 * @param int        $quantity Số lượng cần bán.
	 * @return WP_Error|null
	 */
	private static function check_purchasable( WC_Product $product, $quantity ) {
		$label = sprintf( '%s (#%d)', $product->get_name(), $product->get_id() );

		// Sản phẩm ngoài bán qua website, không có giá/kho để ghi vào đơn POS.
		if ( $product->is_type( 'external' ) ) {
			return self::error(
				'kc_product_not_purchasable',
				sprintf( 'Sản phẩm %s là sản phẩm ngoài, POS không bán được.', $label ),
				400
			);
		}

		if ( '' === (string) $product->get_price() ) {
			return self::error(
				'kc_product_not_purchasable',
				sprintf( 'Sản phẩm %s chưa có giá.', $label ),
				400
			);
		}

		if ( ! $product->is_in_stock() ) {
			return self::error( 'kc_out_of_stock', sprintf( 'Sản phẩm %s đã hết hàng.', $label ), 409 );
		}

		if ( ! $product->is_purchasable() ) {
			return self::error(
				'kc_product_not_purchasable',
				sprintf( 'Sản phẩm %s không bán được.', $label ),
				400
			);
		}

		if ( $product->managing_stock() ) {
			$stock = $product->get_stock_quantity();

			// `null` nghĩa là kho chưa khai báo số lượng: WooCommerce sẽ coi là 0
			// khi trừ kho, nên ở đây cũng từ chối để không bán quá tồn.
			if ( ! is_numeric( $stock ) || (float) $stock < (float) $quantity ) {
				return self::error(
					'kc_out_of_stock',
					sprintf(
						'Sản phẩm %s chỉ còn %s, không đủ %d.',
						$label,
						is_numeric( $stock ) ? (string) (int) $stock : '0',
						$quantity
					),
					409
				);
			}
		}

		return null;
	}

	/* ---------------------------------------------------------------------
	 * Idempotency
	 * ------------------------------------------------------------------ */

	/**
	 * Tìm đơn đã tạo với `request_id` này.
	 *
	 * Truy vấn phụ thuộc cách site lưu đơn hàng, nên phải chọn đúng cơ chế:
	 *
	 * - HPOS (mặc định từ WooCommerce 8.2): `meta_query` của `wc_get_orders()`,
	 *   đây là cách tra order meta chính thức.
	 * - Post storage: `meta_query` KHÔNG được hỗ trợ (WordPress bỏ qua âm thầm),
	 *   nên đọc bằng `get_posts()` với `meta_key`/`meta_value` trên postmeta.
	 *
	 * Cả hai đường đều dùng API chính thức, không SQL thô.
	 *
	 * @param string $request_id Khóa idempotency.
	 * @return array|WP_Error Danh sách WC_Order (đã sort tăng dần theo id).
	 */
	private static function find_orders_by_request_id( $request_id ) {
		try {
			if ( self::hpos_enabled() ) {
				$orders = wc_get_orders(
					array(
						'limit'      => 1,
						'orderby'    => 'id',
						'order'      => 'ASC',
						'return'     => 'objects',
						'meta_query' => array(
							array(
								'key'   => self::REQUEST_ID_META,
								'value' => $request_id,
							),
						),
					)
				);

				return self::keep_real_orders( $orders );
			}

			$order_ids = get_posts(
				array(
					'post_type'        => array_keys( wc_get_order_types() ),
					'post_status'      => 'any',
					'fields'           => 'ids',
					'numberposts'      => 1,
					'orderby'          => 'ID',
					'order'            => 'ASC',
					'no_found_rows'    => true,
					'suppress_filters' => false,
					'meta_key'         => self::REQUEST_ID_META,
					'meta_value'       => $request_id,
				)
			);

			$orders = array();

			foreach ( (array) $order_ids as $order_id ) {
				$order = wc_get_order( $order_id );

				if ( $order instanceof WC_Order ) {
					$orders[] = $order;
				}
			}

			return $orders;
		} catch ( \Throwable $e ) {
			// KHÔNG tạo đơn khi không tra được idempotency, nếu không bấm thanh
			// toán hai lần sẽ sinh ra đơn trùng.
			return self::error(
				'kc_idempotency_unavailable',
				'Không kiểm tra được request_id đã dùng hay chưa, vui lòng thử lại.',
				500
			);
		}
	}

	/**
	 * Site đang lưu đơn bằng HPOS hay không.
	 *
	 * @return bool
	 */
	private static function hpos_enabled() {
		if ( ! class_exists( 'Automattic\WooCommerce\Utilities\OrderUtil' ) ) {
			return false;
		}

		return (bool) \Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled();
	}

	/**
	 * Lọc bỏ kết quả không phải WC_Order.
	 *
	 * @param mixed $orders Kết quả wc_get_orders().
	 * @return array
	 */
	private static function keep_real_orders( $orders ) {
		$list = array();

		foreach ( (array) $orders as $order ) {
			if ( $order instanceof WC_Order ) {
				$list[] = $order;
			}
		}

		return $list;
	}

	/**
	 * Đơn đang được tạo dở bởi một request khác hay không.
	 *
	 * @param WC_Order $order Order cần kiểm tra.
	 * @return bool
	 */
	private static function sale_in_progress( WC_Order $order ) {
		return ( 'pending' === $order->get_status() )
			&& ( 0 === count( $order->get_items( 'line_item' ) ) );
	}

	/* ---------------------------------------------------------------------
	 * Tạo đơn
	 * ------------------------------------------------------------------ */

	/**
	 * Tạo WooCommerce order bằng CRUD chính thức.
	 *
	 * Thứ tự thao tác quan trọng:
	 * 1. Tạo đơn ở trạng thái `pending` và ghi `request_id` ngay để chống trùng.
	 * 2. Thêm line item bằng `add_product()` — không truyền `subtotal`/`total`
	 *    nên WooCommerce tự lấy giá hiện tại của sản phẩm.
	 * 3. `calculate_totals()` để WooCommerce tính tổng tiền và thuế.
	 * 4. Chuyển trạng thái sang trạng thái cuối SAU khi đã có line item: hook
	 *    `wc_maybe_reduce_stock_levels` chạy đúng một lần và WooCommerce tự trừ
	 *    kho. Plugin không đụng `_stock`.
	 *
	 * @param string $request_id     Khóa idempotency.
	 * @param string $payment_method cash|bacs|vietqr.
	 * @param int    $customer_id    0 hoặc id khách hàng.
	 * @param string $note           Ghi chú khách hàng.
	 * @param array  $products       Danh sách đã kiểm tra, có object sản phẩm.
	 * @return WP_REST_Response|WP_Error
	 */
	private static function create_order( $request_id, $payment_method, $customer_id, $note, $products ) {
		try {
			$order = wc_create_order(
				array(
					'created_via' => self::CREATED_VIA,
					'customer_id' => $customer_id,
					// Trạng thái cuối được đặt sau khi đã có line item, xem ghi
					// chú ở trên. `wc_create_order()` chỉ gán giá trị, không chạy
					// hook chuyển trạng thái.
					'status'      => 'pending',
				)
			);
		} catch ( \Throwable $e ) {
			return self::error( 'kc_sale_failed', 'Không tạo được đơn hàng.', 500 );
		}

		if ( is_wp_error( $order ) || ! $order instanceof WC_Order ) {
			return self::error( 'kc_sale_failed', 'Không tạo được đơn hàng.', 500 );
		}

		$gateway = self::payment_gateway( $payment_method );

		try {
			// Claim request_id ngay: nếu request sau đến trong lúc đơn này còn
			// đang tạo thì nó thấy đơn này thay vì tạo đơn thứ hai.
			$order->update_meta_data( self::REQUEST_ID_META, $request_id );
			$order->update_meta_data( self::REQUESTED_PAYMENT_META, $payment_method );
			$order->save();

			foreach ( $products as $entry ) {
				// Không truyền giá: WooCommerce lấy giá sản phẩm hiện tại.
				$order->add_product( $entry['product'], $entry['quantity'] );
			}

			$order->set_payment_method( $gateway['id'] );
			$order->set_payment_method_title( $gateway['title'] );
			$order->set_customer_note( $note );

			$order->calculate_totals();
			$order->save();

			if ( $gateway['paid'] ) {
				$order->set_date_paid( time() );
				$order->save();
			}

			$order->update_status( $gateway['status'], 'Bán tại cửa hàng (POS)' );

			// Đọc lại từ database để response phản ánh đúng dữ liệu vừa lưu.
			$order = wc_get_order( $order->get_id() );
		} catch ( \Throwable $e ) {
			self::discard_order( $order );

			return self::error( 'kc_sale_failed', 'Không hoàn tất được đơn hàng.', 500 );
		}

		return self::sale_response( $order, false, 201 );
	}

	/**
	 * Ánh xạ payment method của POS sang gateway và trạng thái đơn.
	 *
	 * Tiền mặt tại quầy thì đơn hoàn tất và đã thanh toán ngay. Chuyển khoản và
	 * VietQR để trạng thái "chờ thanh toán" đúng như luồng BACS của WooCommerce:
	 * cửa hàng đối soát sau. Cả hai trạng thái cuối đều kích hoạt trừ kho.
	 *
	 * @param string $payment_method cash|bacs|vietqr.
	 * @return array
	 */
	private static function payment_gateway( $payment_method ) {
		$gateways = array(
			'cash'   => array(
				'id'     => 'cash',
				'title'  => 'Tiền mặt',
				'status' => 'completed',
				'paid'   => true,
			),
			'bacs'   => array(
				'id'     => 'bacs',
				'title'  => 'Chuyển khoản',
				'status' => 'on-hold',
				'paid'   => false,
			),
			'vietqr' => array(
				'id'     => 'vietqr',
				'title'  => 'VietQR',
				'status' => 'on-hold',
				'paid'   => false,
			),
		);

		$gateway = $gateways[ $payment_method ];

		// Site chưa cài cổng VietQR thì ghi nhận dưới dạng chuyển khoản để vẫn
		// đối soát được; method gốc vẫn lưu ở order meta.
		if ( 'vietqr' === $gateway['id'] && ! self::gateway_exists( $gateway['id'] ) ) {
			$gateway['id'] = 'bacs';
		}

		return $gateway;
	}

	/**
	 * Cổng thanh toán có đang được đăng ký trong WooCommerce hay không.
	 *
	 * @param string $gateway_id Id gateway.
	 * @return bool
	 */
	private static function gateway_exists( $gateway_id ) {
		if ( ! function_exists( 'WC' ) ) {
			return false;
		}

		try {
			$gateways = WC()->payment_gateways();
		} catch ( \Throwable $e ) {
			return false;
		}

		if ( ! $gateways ) {
			return false;
		}

		$registered = $gateways->payment_gateways();

		return isset( $registered[ $gateway_id ] );
	}

	/**
	 * Xoá đơn tạo dở khi có lỗi giữa chừng.
	 *
	 * Chỉ dọn đơn do chính request này vừa tạo và chưa chuyển sang trạng thái cuối,
	 * nên chưa có tồn kho nào bị trừ. Xoá thay vì để lại giúp danh sách đơn
	 * không bị nhiễu bởi đơn rỗng.
	 *
	 * @param mixed $order Order cần dọn, có thể null.
	 * @return void
	 */
	private static function discard_order( $order ) {
		if ( ! $order instanceof WC_Order || ! $order->get_id() ) {
			return;
		}

		try {
			$order->delete( true );
		} catch ( \Throwable $e ) {
			// Nuốt lỗi: nguyên nhân gốc đã được caller trả về cho app.
		}
	}

	/* ---------------------------------------------------------------------
	 * Response
	 * ------------------------------------------------------------------ */

	/**
	 * Bọc kết quả thành response thành công.
	 *
	 * @param WC_Order $order    Đơn vừa tạo hoặc đơn cũ tìm lại được.
	 * @param bool     $replayed Đơn có phải do request trước tạo hay không.
	 * @param int      $status   HTTP status (201 tạo mới, 200 trả đơn cũ).
	 * @return WP_REST_Response|WP_Error
	 */
	private static function sale_response( $order, $replayed, $status ) {
		try {
			$payload = self::serialize_sale( $order );
		} catch ( \Throwable $e ) {
			// Đơn đã tạo thật rồi. App gửi lại cùng request_id sẽ nhận lại
			// đơn này, nên thông báo cho app biết phải thử lại.
			return self::error(
				'kc_sale_response_failed',
				'Đơn đã được tạo nhưng không đọc lại được chi tiết. Gửi lại cùng request_id để nhận đơn.',
				500
			);
		}

		$response = rest_ensure_response(
			array(
				'success'  => true,
				'replayed' => (bool) $replayed,
				'order'    => $payload,
			)
		);

		$response->set_status( $status );

		return $response;
	}

	/**
	 * Payload tối thiểu của đơn POS, không có password/secret/dữ liệu thừa.
	 *
	 * @param WC_Order $order Order cần trả.
	 * @return array
	 */
	private static function serialize_sale( $order ) {
		$line_items = array();

		foreach ( $order->get_items( 'line_item' ) as $item_id => $item ) {
			if ( ! $item instanceof WC_Order_Item_Product ) {
				continue;
			}

			$quantity = (float) $item->get_quantity();
			$subtotal = (float) $order->get_item_subtotal( $item );

			$line_items[] = array(
				'id'           => (int) $item_id,
				'product_id'   => (int) $item->get_product_id(),
				'variation_id' => (int) $item->get_variation_id(),
				'name'         => (string) $item->get_name(),
				'sku'          => self::line_item_sku( $item ),
				'quantity'     => $quantity,
				'price'        => ( $quantity > 0 ) ? ( $subtotal / $quantity ) : 0.0,
				'subtotal'     => $subtotal,
				'total'        => (float) $item->get_total(),
				'image_url'    => self::line_item_image( $item ),
			);
		}

		return array(
			'id'             => $order->get_id(),
			'number'         => (string) $order->get_order_number(),
			'status'         => $order->get_status(),
			'created_via'    => (string) $order->get_created_via(),
			'payment_method' => (string) $order->get_payment_method(),
			'currency'       => $order->get_currency(),
			'total'          => (float) $order->get_total(),
			'request_id'     => (string) $order->get_meta( self::REQUEST_ID_META ),
			'line_items'     => $line_items,
		);
	}

	/**
	 * SKU của line item, null nếu sản phẩm đã bị xoá hoặc không có SKU.
	 *
	 * @param WC_Order_Item_Product $item Line item.
	 * @return string|null
	 */
	private static function line_item_sku( $item ) {
		$product = $item->get_product();

		if ( ! $product instanceof WC_Product ) {
			return null;
		}

		$sku = trim( (string) $product->get_sku() );

		return ( '' !== $sku ) ? $sku : null;
	}

	/**
	 * URL ảnh của sản phẩm trong line item.
	 *
	 * Variation chưa có ảnh thì dùng ảnh sản phẩm cha. Chỉ trả URL http/https để
	 * app không phải xử lý đường dẫn filesystem.
	 *
	 * @param WC_Order_Item_Product $item Line item.
	 * @return string|null
	 */
	private static function line_item_image( $item ) {
		$product = $item->get_product();

		if ( ! $product instanceof WC_Product ) {
			return null;
		}

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
	 * `WP_Error` + `data.status` cho ra đúng:
	 * `{"code":"...","message":"...","data":{"status":400}}`
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
			&& function_exists( 'wc_create_order' )
			&& function_exists( 'wc_get_product' )
			&& function_exists( 'wc_get_orders' )
			&& function_exists( 'wc_get_order_types' );

		if ( $ready ) {
			return null;
		}

		return self::error(
			'kc_woocommerce_unavailable',
			'WooCommerce chưa active nên không bán hàng được.',
			503
		);
	}
}

add_action( 'rest_api_init', array( 'MKC_POS_API', 'register_routes' ) );
