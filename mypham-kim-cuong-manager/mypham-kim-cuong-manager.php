<?php
/**
 * Plugin Name: MyPham Kim Cuong Manager
 * Plugin URI: https://myphamkimcuong.id.vn
 * Description: Hệ thống quản lý sản phẩm, kho hàng, POS và API cho cửa hàng Mỹ Phẩm Kim Cương.
 * Version: 1.0.0
 * Author: MyPham Kim Cuong
 * Author URI: https://myphamkimcuong.id.vn
 * Requires at least: 6.0
 * Requires PHP: 8.1
 * Text Domain: mypham-kim-cuong-manager
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * Plugin constants
 */
define( 'MKC_MANAGER_VERSION', '1.0.0' );
define( 'MKC_MANAGER_FILE', __FILE__ );
define( 'MKC_MANAGER_DIR', plugin_dir_path( __FILE__ ) );
define( 'MKC_MANAGER_URL', plugin_dir_url( __FILE__ ) );

/**
 * Plugin activation
 */
function mkc_manager_activate() {
    // Database/API sẽ được thêm ở các phase tiếp theo.
}

register_activation_hook( __FILE__, 'mkc_manager_activate' );

/**
 * Plugin deactivation
 */
function mkc_manager_deactivate() {
    // Không xóa dữ liệu khi deactivate.
}

register_deactivation_hook( __FILE__, 'mkc_manager_deactivate' );