<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * فونت‌های کارت: فایل‌های TTF که اپ مدیریت بارگذاری می‌کند تا ویندوز و گوشی یک فونت داشته باشند.
 * فایل‌ها در uploads/roydadyar-fonts ذخیره می‌شوند و فقط از راه API مدیریت (با کلید) خوانده می‌شوند.
 * فهرست در گزینه‌ی cd_fonts است: شناسه → نام، اندازه، زمان.
 */

const CD_FONT_MAX_BYTES = 8 * 1024 * 1024;
const CD_FONT_MAX_COUNT = 30;

function cd_fonts_dir() {
    $up = wp_upload_dir();
    $dir = rtrim($up['basedir'], '/') . '/roydadyar-fonts';
    if (!is_dir($dir)) {
        wp_mkdir_p($dir);
    }
    // خواندن مستقیم از وب بسته است (مجوز فونت‌ها)؛ اپ از API می‌گیرد.
    if (!file_exists("$dir/.htaccess")) {
        @file_put_contents("$dir/.htaccess", "Require all denied\nDeny from all\n");
    }
    if (!file_exists("$dir/index.php")) {
        @file_put_contents("$dir/index.php", "<?php\n// Silence.\n");
    }
    return $dir;
}

function cd_fonts_list() {
    $fonts = get_option('cd_fonts', []);
    return is_array($fonts) ? $fonts : [];
}

function cd_font_id_ok($id) {
    return is_string($id) && preg_match('/^[a-f0-9]{32}$/', $id);
}

/** null یعنی فایل TTF پذیرفتنی است؛ وگرنه پیام خطا. بررسی کامل‌تر (حروف فارسی) در اپ انجام می‌شود. */
function cd_check_ttf($bytes) {
    $n = strlen($bytes);
    if ($n < 1024) {
        return 'فایل فونت خیلی کوچک است.';
    }
    if ($n > CD_FONT_MAX_BYTES) {
        return 'فایل فونت بزرگ‌تر از ۸ مگابایت است.';
    }
    $sig = substr($bytes, 0, 4);
    if ($sig !== "\x00\x01\x00\x00" && $sig !== 'true') {
        return $sig === 'OTTO' ? 'فونت OTF (CFF) پشتیبانی نمی‌شود؛ نسخه‌ی TTF را بارگذاری کنید.' : 'این فایل TTF نیست.';
    }
    return null;
}

function cd_rest_fonts_list() {
    $out = [];
    foreach (cd_fonts_list() as $id => $f) {
        $out[] = ['id' => $id, 'name' => $f['name'], 'size' => (int) $f['size']];
    }
    return ['fonts' => $out];
}

function cd_rest_font_upload(WP_REST_Request $request) {
    $name = cd_str($request->get_param('name'), 80);
    $data = $request->get_param('data');
    if ($name === '' || !is_string($data)) {
        return cd_error('cd_bad_font', 'نام و فایل فونت لازم است.');
    }
    $bytes = base64_decode($data, true);
    if ($bytes === false) {
        return cd_error('cd_bad_font', 'فایل فونت خراب رسید.');
    }
    $problem = cd_check_ttf($bytes);
    if ($problem !== null) {
        return cd_error('cd_bad_font', $problem);
    }
    $fonts = cd_fonts_list();
    if (count($fonts) >= CD_FONT_MAX_COUNT) {
        return cd_error('cd_too_many_fonts', 'حداکثر ۳۰ فونت؛ یکی را حذف کنید.');
    }
    $id = bin2hex(random_bytes(16));
    if (@file_put_contents(cd_fonts_dir() . "/$id.ttf", $bytes) === false) {
        return cd_error('cd_font_write', 'ذخیره‌ی فونت روی سرور ناموفق بود (دسترسی پوشه‌ی uploads).', 500);
    }
    $fonts[$id] = ['name' => $name, 'size' => strlen($bytes), 'created_at' => cd_now()];
    update_option('cd_fonts', $fonts, false);
    return ['font' => ['id' => $id, 'name' => $name, 'size' => strlen($bytes)]];
}

function cd_rest_font_get(WP_REST_Request $request) {
    $id = (string) $request['fid'];
    $fonts = cd_fonts_list();
    if (!cd_font_id_ok($id) || !isset($fonts[$id])) {
        return cd_error('cd_no_font', 'فونت پیدا نشد.', 404);
    }
    $bytes = @file_get_contents(cd_fonts_dir() . "/$id.ttf");
    if ($bytes === false) {
        return cd_error('cd_no_font', 'فایل فونت روی سرور نیست.', 404);
    }
    return ['id' => $id, 'name' => $fonts[$id]['name'], 'data' => base64_encode($bytes)];
}

function cd_rest_font_delete(WP_REST_Request $request) {
    $id = (string) $request['fid'];
    $fonts = cd_fonts_list();
    if (!cd_font_id_ok($id) || !isset($fonts[$id])) {
        return cd_error('cd_no_font', 'فونت پیدا نشد.', 404);
    }
    @unlink(cd_fonts_dir() . "/$id.ttf");
    unset($fonts[$id]);
    update_option('cd_fonts', $fonts, false);
    return ['ok' => true];
}

add_action('rest_api_init', function () {
    $admin = 'cd_admin_permission';
    $fid = '(?P<fid>[a-f0-9]{32})';
    register_rest_route(CD_NS, '/admin/fonts', [
        ['methods' => 'GET', 'permission_callback' => $admin, 'callback' => 'cd_rest_fonts_list'],
        ['methods' => 'POST', 'permission_callback' => $admin, 'callback' => 'cd_rest_font_upload'],
    ]);
    register_rest_route(CD_NS, "/admin/fonts/$fid", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_font_get',
    ]);
    register_rest_route(CD_NS, "/admin/fonts/$fid/delete", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_font_delete',
    ]);
});
