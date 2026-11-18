<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * «داشبورد روی صفحه‌ی وب» (حالت وب‌پیج، طراحی ۰۶-Public): همان داشبورد زنده روی یک آدرس دلخواه سایت،
 * مثلاً example.ir/ops-dashboard. پیشخوان وردپرس مثل قبل کار می‌کند.
 * - خاموش است تا مدیر روشنش کند و آدرس را خودش بدهد (آدرس تکراری با برگه‌ها رد می‌شود).
 * - دسترسی: «فقط مدیران واردشده» یا «با کلید داخل لینک» (مدیر واردشده همیشه می‌بیند).
 * - فقط می‌خواند، noindex است، کش نمی‌شود و بدون ورود یا کلید معتبر هیچ داده‌ای نشان نمی‌دهد.
 */

const CD_WEB_RESERVED = ['c', 'wp-admin', 'wp-json', 'wp-login', 'wp-login.php', 'wp-content', 'wp-includes', 'feed', 'admin', 'login', 'register', 'xmlrpc.php', 'sitemap', 'robots.txt'];

function cd_web_settings() {
    $s = get_option('cd_web_dashboard', []);
    return array_merge(['enabled' => false, 'slug' => '', 'access' => 'admins', 'key_enc' => '', 'key_hash' => ''], is_array($s) ? $s : []);
}

/** خطای آدرس پیشنهادی، یا null اگر آزاد است. */
function cd_web_slug_error($slug) {
    if ($slug === '') {
        return 'آدرس صفحه را بنویسید (فقط حروف لاتین، رقم و خط تیره).';
    }
    if (!preg_match('/^[a-z0-9][a-z0-9-]{1,62}$/', $slug)) {
        return 'آدرس فقط حروف کوچک لاتین، رقم و خط تیره می‌تواند باشد (دست‌کم ۲ نویسه).';
    }
    global $wpdb;
    $reg = $wpdb->get_var($wpdb->prepare('SELECT event_id FROM ' . cd_table('reg_pages') . ' WHERE path = %s', $slug));
    if (in_array($slug, CD_WEB_RESERVED, true) || $reg || get_page_by_path($slug, OBJECT, ['page', 'post'])) {
        return 'این آدرس با یک برگه‌ی دیگر سایت یکی است؛ آدرس دیگری بنویسید.';
    }
    return null;
}

/** پیوند کامل صفحه، با کلید در حالت «کلید داخل لینک». */
function cd_web_url($with_key = true) {
    $s = cd_web_settings();
    if (!$s['enabled'] || $s['slug'] === '') {
        return null;
    }
    $url = home_url('/' . $s['slug'] . '/');
    if ($with_key && $s['access'] === 'key') {
        $key = cd_key_decrypt((string) $s['key_enc']);
        if ($key) {
            $url = add_query_arg('k', $key, $url);
        }
    }
    return $url;
}

function cd_web_add_rewrite() {
    $s = cd_web_settings();
    if ($s['enabled'] && $s['slug'] !== '') {
        add_rewrite_rule('^' . preg_quote($s['slug'], '/') . '/?$', 'index.php?cd_ops=1', 'top');
    }
}
add_action('init', 'cd_web_add_rewrite');

add_filter('query_vars', function ($vars) {
    $vars[] = 'cd_ops';
    return $vars;
});

/** ذخیره‌ی تنظیم وب‌پیج از صفحه‌ی «صفحه‌های عمومی». خروجی: پیام خطا یا null. */
function cd_web_save(array $in) {
    $s = cd_web_settings();
    $enabled = !empty($in['enabled']);
    $slug = sanitize_title((string) ($in['slug'] ?? ''));
    if ($enabled) {
        $err = cd_web_slug_error($slug);
        if ($err !== null) {
            return $err;
        }
    }
    $s['enabled'] = $enabled;
    if ($slug !== '') {
        $s['slug'] = $slug;
    }
    $s['access'] = ($in['access'] ?? '') === 'key' ? 'key' : 'admins';
    if ($s['access'] === 'key' && ($s['key_hash'] === '' || !empty($in['new_key']))) {
        $key = cd_random_token(24);
        $s['key_hash'] = hash('sha256', $key);
        $s['key_enc'] = cd_key_encrypt($key);
    }
    update_option('cd_web_dashboard', $s, false);
    cd_add_rewrite();
    cd_web_add_rewrite();
    flush_rewrite_rules(false);
    return null;
}

/** آیا درخواست فعلی اجازه‌ی دیدن وب‌پیج را دارد؟ */
function cd_web_allowed(array $s) {
    if (current_user_can('manage_options')) {
        return true;
    }
    if ($s['access'] !== 'key' || $s['key_hash'] === '') {
        return false;
    }
    $given = isset($_GET['k']) ? sanitize_text_field(wp_unslash($_GET['k'])) : '';
    return $given !== '' && hash_equals((string) $s['key_hash'], hash('sha256', $given));
}

add_action('template_redirect', function () {
    if (!get_query_var('cd_ops')) {
        return;
    }
    $s = cd_web_settings();
    if (!$s['enabled']) {
        return;
    }
    cd_send_nocache_headers();
    header('X-Robots-Tag: noindex, nofollow');
    if (!cd_web_allowed($s)) {
        if ($s['access'] === 'admins' && !is_user_logged_in()) {
            auth_redirect();
        }
        status_header(403);
        header('Content-Type: text/html; charset=utf-8');
        echo cd_web_page('<div class="cd-card pop" style="text-align:center;padding:40px"><h2>دسترسی ندارید</h2><p class="cd-mu">این صفحه فقط برای مدیران رویداد است. پیوند کامل را از مدیر سایت بگیرید.</p></div>', 'رویدادیار'); // phpcs:ignore WordPress.Security.EscapeOutput
        exit;
    }
    $events = cd_all_events();
    $current = isset($_GET['event']) ? cd_get_event((int) $_GET['event']) : ($events[0] ?? null);
    if ($current && cd_event_is_archived($current)) {
        $current = $events[0] ?? null;
    }
    header('Content-Type: text/html; charset=utf-8');
    if (!$current) {
        echo cd_web_page('<div class="cd-card pop"><p class="cd-mu">رویداد فعالی نیست.</p></div>', 'رویدادیار'); // phpcs:ignore WordPress.Security.EscapeOutput
        exit;
    }
    $keep = $s['access'] === 'key' && isset($_GET['k']) ? '<input type="hidden" name="k" value="' . esc_attr(sanitize_text_field(wp_unslash($_GET['k']))) . '">' : '';
    $select = '<form method="get" class="cd-chip">' . $keep . 'رویداد: <select name="event" onchange="this.form.submit()">';
    foreach ($events as $ev) {
        $select .= sprintf('<option value="%d"%s>%s</option>', (int) $ev['id'], selected((int) $ev['id'], (int) $current['id'], false), esc_html($ev['name']));
    }
    $select .= '</select></form>';
    $sub = 'رویدادیار · ' . cd_jalali_label($current['start_date'] ?? '') . ' · فقط خواندنی';
    echo cd_web_page(cd_dashboard_body($current, null), $current['name'], $sub, $select); // phpcs:ignore WordPress.Security.EscapeOutput
    exit;
});

/** صفحه‌ی کامل HTML وب‌پیج با سربرگ فیروزه‌ای و به‌روزرسانی خودکار ۳۰ ثانیه‌ای. */
function cd_web_page($body, $title, $sub = '', $extra = '') {
    ob_start();
    ?><!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?php echo esc_html($title); ?></title>
<link rel="stylesheet" href="<?php echo esc_url(includes_url('css/dashicons.min.css')); ?>">
<?php echo cd_ui_styles(); // phpcs:ignore WordPress.Security.EscapeOutput ?>
<style>body{margin:0;background:#F2F6F6}.cd-ui{margin:0}</style>
</head>
<body>
<div class="cd-ui">
  <div class="cd-hero"><div class="t"><div style="flex-grow:1"><div class="sub"><?php echo esc_html($sub); ?></div><h1><?php echo esc_html($title); ?></h1></div>
    <label class="cd-chip"><input type="checkbox" id="cd-auto" checked> به‌روزرسانی خودکار · <?php echo esc_html(cd_fa_digits(current_time('H:i'))); ?></label><?php echo $extra; // phpcs:ignore WordPress.Security.EscapeOutput ?></div></div>
  <div class="cd-body"><?php echo $body; // phpcs:ignore WordPress.Security.EscapeOutput ?>
    <div class="cd-foot">رویدادیار <?php echo esc_html(cd_fa_digits(CD_VERSION)); ?> · ساخته‌ی تیم راهکارهای نرم‌افزاری نگاه جدید</div></div>
</div>
<script>setTimeout(function(){var a=document.getElementById('cd-auto');if(a&&a.checked)location.reload();},30000);</script>
</body>
</html>
<?php
    return ob_get_clean();
}
