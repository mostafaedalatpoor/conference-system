<?php
/**
 * Plugin Name: Conference Day
 * Description: سامانه‌ی مدیریت روز اجرای کنفرانس: API همگام‌سازی برای اپ نیروها و اپ مدیریت، صفحه‌ی عمومی شناسایی /c/&lt;token&gt;، و داشبورد زنده.
 * Version: 0.1.0
 * Requires at least: 5.6
 * Requires PHP: 7.4
 * Text Domain: conference-day
 */

if (!defined('ABSPATH')) {
    exit;
}

define('CD_VERSION', '0.1.0');
define('CD_DB_VERSION', '1');
define('CD_NS', 'conf/v1');
define('CD_DIR', plugin_dir_path(__FILE__));

require_once CD_DIR . 'includes/util.php';
require_once CD_DIR . 'includes/db.php';
require_once CD_DIR . 'includes/model.php';
require_once CD_DIR . 'includes/sync.php';
require_once CD_DIR . 'includes/report.php';
require_once CD_DIR . 'includes/rest-admin.php';
require_once CD_DIR . 'includes/rest-device.php';
require_once CD_DIR . 'includes/public-page.php';
require_once CD_DIR . 'includes/admin-ui.php';

register_activation_hook(__FILE__, function () {
    cd_install_tables();
    cd_add_rewrite();
    flush_rewrite_rules();
});

register_deactivation_hook(__FILE__, function () {
    // قوانین بازنویسی بدون این افزونه در بارگذاری بعدی از نو ساخته می‌شوند.
    delete_option('rewrite_rules');
});

add_action('plugins_loaded', function () {
    if (get_option('cd_db_version') !== CD_DB_VERSION) {
        cd_install_tables();
    }
});

/*
 * همه‌ی پاسخ‌های REST این افزونه نباید کش شوند (LiteSpeed Cache روی این هاست
 * پاسخ REST را حتی با Cache-Control: no-store کش می‌کند).
 */
add_filter('rest_post_dispatch', function ($response, $server, $request) {
    if (strpos($request->get_route(), '/' . CD_NS) === 0 && $response instanceof WP_REST_Response) {
        $response->header('Cache-Control', 'no-store, private');
        $response->header('X-LiteSpeed-Cache-Control', 'no-cache');
        do_action('litespeed_control_set_nocache', 'conference-day');
    }
    return $response;
}, 10, 3);
