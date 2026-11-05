<?php
if (!defined('ABSPATH')) {
    exit;
}

/** نام کامل جدول با پیشوند وردپرس. */
function cd_table($name) {
    global $wpdb;
    return $wpdb->prefix . 'cd_' . $name;
}

/** زمان فعلی به UTC در قالب MySQL. */
function cd_now() {
    return gmdate('Y-m-d H:i:s');
}

/** تبدیل زمان ISO 8601 یا میلی‌ثانیه‌ی epoch به DATETIME در UTC. */
function cd_to_utc_datetime($value) {
    if (is_int($value) || (is_string($value) && ctype_digit($value))) {
        $ts = (int) $value;
        if ($ts > 100000000000) {
            $ts = (int) floor($ts / 1000);
        }
        return gmdate('Y-m-d H:i:s', $ts);
    }
    if (is_string($value) && $value !== '') {
        $ts = strtotime($value);
        if ($ts !== false) {
            return gmdate('Y-m-d H:i:s', $ts);
        }
    }
    return cd_now();
}

/** DATETIME ذخیره‌شده (UTC) به ISO 8601. */
function cd_iso($datetime) {
    if (!$datetime) {
        return null;
    }
    return gmdate('c', strtotime($datetime . ' UTC'));
}

/** رشته‌ی تصادفی امن base64url. */
function cd_random_token($bytes = 24) {
    return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
}

function cd_is_uuid($s) {
    return is_string($s) && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $s) === 1;
}

function cd_is_card_token($s) {
    return is_string($s) && preg_match('/^[A-Za-z0-9_-]{16,64}$/', $s) === 1;
}

function cd_is_code($s) {
    return is_string($s) && preg_match('/^[A-Za-z0-9_-]{1,64}$/', $s) === 1;
}

/** ارقام فارسی و عربی به لاتین. */
function cd_latin_digits($s) {
    return strtr((string) $s, [
        '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
        '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
        '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
        '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
    ]);
}

/**
 * نرمال‌سازی متن برای جستجو: ی/ك عربی، اعراب، نیم‌فاصله، ارقام و حروف بزرگ.
 * اپ نیروها همین قاعده را پیاده می‌کند تا نتیجه‌ها یکی باشد.
 */
function cd_normalize($s) {
    $s = cd_latin_digits($s);
    $s = strtr($s, [
        'ي' => 'ی', 'ى' => 'ی', 'ئ' => 'ی', 'ك' => 'ک', 'ة' => 'ه', 'ۀ' => 'ه',
        'أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ؤ' => 'و', 'ـ' => '',
        "\u{200C}" => ' ', "\u{200D}" => '', "\u{200E}" => '', "\u{200F}" => '',
    ]);
    $s = preg_replace('/[\x{064B}-\x{0652}\x{0670}]/u', '', $s);
    $s = function_exists('mb_strtolower') ? mb_strtolower($s, 'UTF-8') : strtolower($s);
    $s = preg_replace('/\s+/u', ' ', $s);
    return trim((string) $s);
}

/** موبایل فقط رقم، با پیش‌شماره‌ی ایران به 09... تبدیل می‌شود. */
function cd_normalize_mobile($s) {
    $d = preg_replace('/\D+/', '', cd_latin_digits($s));
    if ($d === '' || $d === null) {
        return '';
    }
    if (strpos($d, '0098') === 0) {
        $d = '0' . substr($d, 4);
    } elseif (strpos($d, '98') === 0 && strlen($d) === 12) {
        $d = '0' . substr($d, 2);
    } elseif (strlen($d) === 10 && $d[0] === '9') {
        $d = '0' . $d;
    }
    return $d;
}

/** رشته‌ی کوتاه‌شده و تمیز از ورودی، یا خالی. */
function cd_str($value, $max = 191) {
    if (!is_scalar($value)) {
        return '';
    }
    $s = trim(wp_strip_all_tags((string) $value));
    if (function_exists('mb_substr')) {
        return mb_substr($s, 0, $max);
    }
    return substr($s, 0, $max);
}

function cd_error($code, $message, $status = 400, $extra = []) {
    return new WP_Error($code, $message, array_merge(['status' => $status], $extra));
}

/** جلوگیری از کش شدن صفحه‌های غیر REST (صفحه‌ی عمومی /c/). */
function cd_send_nocache_headers() {
    if (!headers_sent()) {
        nocache_headers();
        header('X-LiteSpeed-Cache-Control: no-cache');
    }
    do_action('litespeed_control_set_nocache', 'conference-day');
}

function cd_client_ip() {
    return isset($_SERVER['REMOTE_ADDR']) ? sanitize_text_field(wp_unslash($_SERVER['REMOTE_ADDR'])) : '0.0.0.0';
}
