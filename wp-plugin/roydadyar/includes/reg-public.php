<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * صفحه‌ی عمومی ثبت‌نام: site.ir/<مسیر> (یا site.ir/register/<مسیر>).
 * بدون nonce وردپرس، چون با کش سایت بعد از یک روز خطا می‌داد؛ به جایش فیلد مخفی ضدربات و محدودیت تلاش از هر IP.
 * صفحه از کش سایت مستثناست.
 */

add_filter('query_vars', function ($vars) {
    $vars[] = 'cd_reg';
    return $vars;
});

add_action('template_redirect', function () {
    $path = get_query_var('cd_reg');
    if ((!is_string($path) || $path === '') && isset($_GET['cd_reg'])) {
        $path = sanitize_text_field(wp_unslash($_GET['cd_reg']));
    }
    if (!is_string($path) || $path === '') {
        return;
    }
    $path = rawurldecode($path);
    if (!defined('DONOTCACHEPAGE')) {
        define('DONOTCACHEPAGE', true);
    }
    do_action('litespeed_control_set_nocache', 'roydadyar registration');
    cd_send_nocache_headers();
    header('Content-Type: text/html; charset=utf-8');

    $page = cd_reg_get_page_by_path($path);
    // پیش‌نویس فقط برای مدیر وردپرس پیش‌نمایش دارد.
    if (!$page || ($page['status'] === 'draft' && !current_user_can('manage_options'))) {
        status_header(404);
        echo cd_reg_render_message('صفحه پیدا نشد', 'این آدرس صفحه‌ی ثبت‌نامی ندارد یا هنوز منتشر نشده است.'); // phpcs:ignore WordPress.Security.EscapeOutput
        exit;
    }
    echo cd_reg_render_page($page); // phpcs:ignore WordPress.Security.EscapeOutput
    exit;
}, 5);

// ---------------------------------------------------------------- API عمومی

add_action('rest_api_init', function () {
    $public = '__return_true';
    register_rest_route(CD_NS, '/reg/submit', ['methods' => 'POST', 'permission_callback' => $public, 'callback' => 'cd_rest_reg_submit']);
    register_rest_route(CD_NS, '/reg/status', ['methods' => 'POST', 'permission_callback' => $public, 'callback' => 'cd_rest_reg_status']);
    register_rest_route(CD_NS, '/reg/pay', ['methods' => 'POST', 'permission_callback' => $public, 'callback' => 'cd_rest_reg_pay']);
    register_rest_route(CD_NS, '/reg/proof', ['methods' => 'POST', 'permission_callback' => $public, 'callback' => 'cd_rest_reg_proof']);
    register_rest_route(CD_NS, '/reg/callback', ['methods' => 'GET', 'permission_callback' => $public, 'callback' => 'cd_reg_gateway_callback']);
});

function cd_reg_page_from_request(WP_REST_Request $r) {
    $page = cd_reg_get_page_by_path((string) $r->get_param('page'));
    if (!$page || $page['status'] === 'draft') {
        return cd_error('cd_reg_not_found', 'صفحه‌ی ثبت‌نام پیدا نشد.', 404);
    }
    return $page;
}

function cd_rest_reg_submit(WP_REST_Request $r) {
    if (!cd_reg_rate_ok('submit')) {
        return cd_error('cd_reg_rate', 'تلاش زیاد بود. ده دقیقه بعد دوباره امتحان کنید.', 429);
    }
    $page = cd_reg_page_from_request($r);
    if (is_wp_error($page)) {
        return $page;
    }
    // فیلد مخفی ضدربات: انسان آن را نمی‌بیند و پر نمی‌کند.
    if ((string) $r->get_param('website') !== '') {
        return ['state' => 'invalid', 'errors' => ['form' => 'ارسال پذیرفته نشد.']];
    }
    return cd_reg_submit($page, $r->get_params());
}

/** پیدا کردن ثبت‌نام با کد + موبایل (پیگیری) یا کد + کلید (لینک برگشت). */
function cd_reg_from_request(WP_REST_Request $r, array $page) {
    $reg = cd_reg_get_by_code((string) $r->get_param('code'));
    if (!$reg || (int) $reg['event_id'] !== (int) $page['event_id']) {
        return null;
    }
    $k = (string) $r->get_param('k');
    $mobile = cd_normalize_mobile($r->get_param('mobile') ?? '');
    if ($k !== '' && hash_equals(cd_reg_key($reg['code']), $k)) {
        return $reg;
    }
    return $mobile !== '' && $mobile === $reg['mobile'] ? $reg : null;
}

function cd_rest_reg_status(WP_REST_Request $r) {
    if (!cd_reg_rate_ok('status')) {
        return cd_error('cd_reg_rate', 'تلاش زیاد بود. ده دقیقه بعد دوباره امتحان کنید.', 429);
    }
    $page = cd_reg_page_from_request($r);
    if (is_wp_error($page)) {
        return $page;
    }
    cd_reg_expire_holds((int) $page['event_id']);
    $reg = cd_reg_from_request($r, $page);
    if (!$reg) {
        return cd_error('cd_reg_not_found', 'ثبت‌نامی با این کد و موبایل پیدا نشد.', 404);
    }
    $out = cd_reg_public_state($page, $reg);
    $fail = get_transient('cd_reg_payfail_' . $reg['code']);
    if ($fail) {
        $out['pay_message'] = $fail;
    }
    return $out;
}

function cd_rest_reg_pay(WP_REST_Request $r) {
    $page = cd_reg_page_from_request($r);
    if (is_wp_error($page)) {
        return $page;
    }
    $reg = cd_reg_from_request($r, $page);
    if (!$reg) {
        return cd_error('cd_reg_not_found', 'ثبت‌نام پیدا نشد.', 404);
    }
    if ($reg['status'] === 'expired') {
        // جا آزاد شده بود؛ اگر هنوز جا هست دوباره نگه داشته می‌شود.
        $counts = cd_reg_counts((int) $page['event_id']);
        if (cd_reg_page_state($page, $counts) !== 'open') {
            return cd_error('cd_reg_closed', 'مهلت پرداخت تمام شد و ظرفیت هم پر شده است.', 409);
        }
        global $wpdb;
        $wpdb->update(cd_table('registrations'), ['status' => 'pending_payment'], ['id' => (int) $reg['id']]);
        $reg = cd_reg_get((int) $reg['id']);
    }
    $url = cd_reg_start_gateway($page, $reg);
    if (is_wp_error($url)) {
        return cd_error('cd_pay', $url->get_error_message(), 502);
    }
    return ['url' => $url];
}

/** شماره‌ی پیگیری و/یا تصویر رسید برای کارت‌به‌کارت یا لینک بیرونی. */
function cd_rest_reg_proof(WP_REST_Request $r) {
    if (!cd_reg_rate_ok('proof')) {
        return cd_error('cd_reg_rate', 'تلاش زیاد بود. ده دقیقه بعد دوباره امتحان کنید.', 429);
    }
    $page = cd_reg_page_from_request($r);
    if (is_wp_error($page)) {
        return $page;
    }
    $reg = cd_reg_from_request($r, $page);
    if (!$reg || !in_array($reg['status'], ['pending_payment', 'pending_review'], true) || $reg['pay_method'] === 'gateway') {
        return cd_error('cd_reg_proof', 'برای این ثبت‌نام رسید پذیرفته نمی‌شود.', 409);
    }
    $need = $page['config']['payment']['method'] === 'card' ? $page['config']['payment']['card']['require'] : 'code';
    $tracking = cd_str(cd_latin_digits((string) $r->get_param('tracking')), 100);
    $files = $r->get_file_params();
    $file = $files['receipt'] ?? null;
    $errors = [];
    if (in_array($need, ['code', 'both'], true) && $tracking === '' && $page['config']['payment']['method'] === 'card') {
        $errors['tracking'] = 'شماره‌ی پیگیری واریز را وارد کنید.';
    }
    $stored = '';
    if ($file && !empty($file['tmp_name']) && (is_uploaded_file($file['tmp_name']) || (defined('CD_TESTING') && is_file($file['tmp_name'])))) {
        $stored = cd_reg_store_receipt($file);
        if (is_wp_error($stored)) {
            $errors['receipt'] = $stored->get_error_message();
            $stored = '';
        }
    } elseif (in_array($need, ['receipt', 'both'], true) && $page['config']['payment']['method'] === 'card') {
        $errors['receipt'] = 'تصویر رسید را انتخاب کنید.';
    }
    if ($page['config']['payment']['method'] === 'link' && $tracking === '' && $stored === '') {
        $errors['tracking'] = 'شماره‌ی پیگیری یا تصویر رسید را بدهید.';
    }
    if ($errors) {
        return ['state' => 'invalid', 'errors' => $errors];
    }
    $set = ['hold_until' => null];
    if ($tracking !== '') {
        $set['pay_tracking'] = $tracking;
    }
    if ($stored !== '') {
        $set['receipt_file'] = $stored;
    }
    $reg = cd_reg_set_status($page, $reg, 'pending_review', $set);
    return cd_reg_public_state($page, $reg);
}

function cd_reg_receipts_dir() {
    $up = wp_upload_dir();
    $dir = rtrim($up['basedir'], '/') . '/roydadyar-receipts';
    if (!is_dir($dir)) {
        wp_mkdir_p($dir);
    }
    if (!file_exists("$dir/.htaccess")) {
        @file_put_contents("$dir/.htaccess", "Require all denied\nDeny from all\n");
        @file_put_contents("$dir/index.php", "<?php\n// Silence.\n");
    }
    return $dir;
}

/** رسید: JPG، PNG یا PDF تا ۵ مگابایت؛ نوع از محتوای فایل، نه از نامش. */
function cd_reg_store_receipt(array $file) {
    if (!empty($file['error']) || (int) $file['size'] <= 0) {
        return new WP_Error('cd_receipt', 'فایل رسید نرسید؛ دوباره انتخابش کنید.');
    }
    if ((int) $file['size'] > 5 * 1024 * 1024) {
        return new WP_Error('cd_receipt', 'فایل رسید بزرگ‌تر از ۵ مگابایت است.');
    }
    $head = (string) file_get_contents($file['tmp_name'], false, null, 0, 8);
    $ext = strncmp($head, "\x89PNG", 4) === 0 ? 'png' : (strncmp($head, "\xFF\xD8\xFF", 3) === 0 ? 'jpg' : (strncmp($head, '%PDF', 4) === 0 ? 'pdf' : ''));
    if ($ext === '') {
        return new WP_Error('cd_receipt', 'رسید باید تصویر JPG یا PNG یا فایل PDF باشد.');
    }
    $name = bin2hex(random_bytes(16)) . '.' . $ext;
    $dest = cd_reg_receipts_dir() . '/' . $name;
    $moved = defined('CD_TESTING') ? @copy($file['tmp_name'], $dest) : @move_uploaded_file($file['tmp_name'], $dest);
    if (!$moved) {
        return new WP_Error('cd_receipt', 'ذخیره‌ی رسید روی سرور ناموفق بود.');
    }
    return $name;
}

// ---------------------------------------------------------------- نمایش

/** رنگ متن روی یک رنگ: سیاه یا سفید، هر کدام کنتراست بیشتری دارد. */
function cd_reg_on_color($hex) {
    return cd_reg_contrast($hex, '#FFFFFF') >= cd_reg_contrast($hex, '#10141A') ? '#FFFFFF' : '#10141A';
}

function cd_reg_lum($hex) {
    $c = [];
    foreach ([1, 3, 5] as $i) {
        $v = hexdec(substr($hex, $i, 2)) / 255;
        $c[] = $v <= 0.03928 ? $v / 12.92 : pow(($v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2];
}

function cd_reg_contrast($a, $b) {
    $l1 = cd_reg_lum($a);
    $l2 = cd_reg_lum($b);
    return (max($l1, $l2) + 0.05) / (min($l1, $l2) + 0.05);
}

/** نسخه‌ی خوانای یک رنگ روی زمینه: تا کنتراست ۴٫۵ روشن یا تیره می‌شود. */
function cd_reg_readable($hex, $bg) {
    $dark_bg = cd_reg_lum($bg) < 0.3;
    for ($i = 0; $i < 20 && cd_reg_contrast($hex, $bg) < 4.5; $i++) {
        $rgb = [hexdec(substr($hex, 1, 2)), hexdec(substr($hex, 3, 2)), hexdec(substr($hex, 5, 2))];
        $rgb = array_map(function ($v) use ($dark_bg) {
            return $dark_bg ? (int) round($v + (255 - $v) * 0.15) : (int) round($v * 0.85);
        }, $rgb);
        $hex = sprintf('#%02X%02X%02X', $rgb[0], $rgb[1], $rgb[2]);
    }
    return $hex;
}

function cd_reg_theme_css(array $theme) {
    $dark = $theme['mode'] === 'dark';
    // پالت «فیروزه»؛ رنگ برند همان رنگ انتخابی صفحه است.
    $p = $dark
        ? ['bg' => '#0D1415', 'surface' => '#162022', 'sunken' => '#1E2A2C', 'line' => '#2A3A3C', 'ink' => '#EAF1F1', 'muted' => '#9FB0B1', 'stop' => '#FF8A80', 'stop_soft' => '#3A1513', 'go' => '#5CD68B', 'go_soft' => '#12301F', 'wait' => '#F5B83D', 'wait_soft' => '#33260A', 'wait_ink' => '#F5D79A', 'opt' => '#3A5052']
        : ['bg' => '#EEF2F2', 'surface' => '#FFFFFF', 'sunken' => '#F2F6F6', 'line' => '#E3EFEF', 'ink' => '#0F1C1D', 'muted' => '#5B6B6C', 'stop' => '#B3261E', 'stop_soft' => '#FDE9E7', 'go' => '#138A43', 'go_soft' => '#E3F5EA', 'wait' => '#8A5300', 'wait_soft' => '#FFF1D1', 'wait_ink' => '#4A3300', 'opt' => '#C9D8D8'];
    $accent = $theme['accent'];
    $vars = [
        '--bg' => $p['bg'], '--surface' => $p['surface'], '--sunken' => $p['sunken'], '--line' => $p['line'],
        '--ink' => $p['ink'], '--muted' => $p['muted'], '--opt' => $p['opt'],
        '--accent' => $accent, '--on-accent' => cd_reg_on_color($accent),
        '--accent-text' => cd_reg_readable($accent, $p['surface']),
        '--accent-soft' => $accent . ($dark ? '29' : '17'),
        '--highlight' => cd_reg_readable($theme['highlight'], $p['surface']),
        '--stop' => $p['stop'], '--stop-soft' => $p['stop_soft'], '--go' => $p['go'], '--go-soft' => $p['go_soft'],
        '--wait' => $p['wait'], '--wait-soft' => $p['wait_soft'], '--wait-ink' => $p['wait_ink'],
    ];
    $css = ':root{';
    foreach ($vars as $k => $v) {
        $css .= $k . ':' . $v . ';';
    }
    return $css . 'color-scheme:' . ($dark ? 'dark' : 'light') . '}';
}

/** داده‌ای که اسکریپت صفحه لازم دارد؛ بدون تنظیم‌های محرمانه‌ی درگاه. */
function cd_reg_public_config(array $page, array $counts) {
    global $wpdb;
    $cfg = $page['config'];
    $names = [];
    foreach ($wpdb->get_results($wpdb->prepare('SELECT code, name FROM ' . cd_table('registration_types') . ' WHERE event_id = %d', $page['event_id']), ARRAY_A) as $t) {
        $names[$t['code']] = $t['name'];
    }
    $types = [];
    foreach ($cfg['types'] as $t) {
        if ($t['visible'] && isset($names[$t['code']])) {
            $types[] = ['code' => $t['code'], 'name' => $names[$t['code']], 'description' => $t['description'], 'price' => $t['price'], 'closed' => cd_reg_type_closed($t, $counts)];
        }
    }
    $fields = [];
    foreach ($cfg['custom_fields'] as $f) {
        $f['options'] = array_map(function ($o) use ($f, $counts) {
            return ['id' => $o['id'], 'label' => $o['label'], 'full' => cd_reg_full($o['capacity'], $counts['options'][$f['id'] . '/' . $o['id']] ?? 0)];
        }, $f['options']);
        $fields[] = $f;
    }
    $addons = array_map(function ($a) use ($counts) {
        return ['id' => $a['id'], 'title' => $a['title'], 'description' => $a['description'], 'price' => $a['price'], 'price_mode' => $a['price_mode'], 'types' => $a['types'], 'full' => cd_reg_full($a['capacity'], $counts['addons'][$a['id']] ?? 0)];
    }, $cfg['addons']);
    $pay = $cfg['payment'];
    return [
        'page' => cd_reg_full_path($cfg),
        'api' => esc_url_raw(rest_url(CD_NS . '/reg/')),
        'types' => $types,
        'fields' => $cfg['fields'],
        'custom' => $fields,
        'addons' => $addons,
        'payment' => [
            'method' => $pay['method'],
            'link_url' => $pay['link_url'], 'link_text' => $pay['link_text'],
            'card' => $pay['card'],
            'hold_hours' => $pay['hold_hours'],
        ],
        'contact' => $cfg['content']['contact'],
        'success_text' => $cfg['success']['text'],
        'when' => implode('، ', $cfg['content']['days']),
        'where' => implode('، ', $cfg['content']['venue']),
    ];
}

function cd_reg_head($title, $css) {
    $font = plugins_url('assets/fonts/', CD_DIR . 'roydadyar.php');
    return '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>' . esc_html($title) . '</title>'
        . '<style>@font-face{font-family:Vazirmatn;font-weight:400;font-display:swap;src:url("' . esc_url($font . 'Vazirmatn-Regular.woff2') . '") format("woff2")}'
        . '@font-face{font-family:Vazirmatn;font-weight:800;font-display:swap;src:url("' . esc_url($font . 'Vazirmatn-ExtraBold.woff2') . '") format("woff2")}'
        . $css . cd_reg_base_css() . '</style></head>';
}

function cd_reg_base_css() {
    // طراحی «ثبت‌نام آنلاین» (بوم‌های ۰۷ تا ۱۱ صفحه‌ی شخصی): هدر خمیده، کارت‌های شناور، نوار پایین چسبان.
    return <<<'CSS'
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:Vazirmatn,Tahoma,"Segoe UI",sans-serif;line-height:1.7;font-size:15px}
a{color:var(--accent-text)}
.hero{background:var(--accent);color:var(--on-accent);padding:36px 20px 76px;border-radius:0 0 32px 32px;display:flex;flex-direction:column;gap:6px}
.hero .in{max-width:640px;margin:0 auto;width:100%;display:flex;flex-direction:column;gap:6px}
.hero .top{display:flex;align-items:center;gap:10px;justify-content:space-between}
.hero .top img{width:40px;height:40px;object-fit:contain;border-radius:12px;background:#fff}
.hero .sub{font-size:12px;opacity:.85}
.hero h1{margin:0;font-size:clamp(22px,6vw,30px);line-height:1.45;font-weight:800;text-wrap:balance}
.hero .meta{font-size:13px;opacity:.92;line-height:1.6}
.hero .site{display:inline-flex;align-items:center;height:36px;padding:0 14px;border-radius:18px;background:rgba(255,255,255,.18);color:inherit;text-decoration:none;font-size:13px;font-weight:700;white-space:nowrap}
.hero .cover{width:100%;max-height:240px;object-fit:cover;border-radius:18px;margin-top:8px}
.wrap{max-width:640px;margin:-48px auto 0;padding:0 16px 140px;position:relative}
.stack{display:flex;flex-direction:column;gap:14px}
.desc{white-space:pre-line;background:var(--surface);border-radius:22px;padding:16px;font-size:14px}
.sec{background:var(--surface);border-radius:22px;padding:16px;display:flex;flex-direction:column;gap:12px}
.float,.stack>.sec:first-child,.stack>.stepper:first-child{box-shadow:0 10px 30px rgba(11,122,123,.14)}
.stepper{background:var(--surface);border-radius:22px;padding:14px 16px;display:flex;align-items:center;gap:12px}
.stepper .st{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:14px}
.stepper .st.on{color:var(--ink);flex-grow:1}.stepper .st.done{color:var(--go);flex-grow:1}
.stepper .n{width:28px;height:28px;border-radius:14px;background:var(--bg);display:grid;place-items:center;font-size:13px;font-weight:800}
.stepper .on .n{background:var(--accent);color:var(--on-accent)}.stepper .done .n{background:var(--go);color:#fff}
.stepper .ln{height:2px;width:40px;background:var(--line)}.stepper .ln.done{background:var(--go)}
h2{margin:0;font-size:16px;font-weight:800}
.group{display:flex;flex-direction:column;gap:12px}
.choice{display:flex;gap:12px;align-items:center;padding:12px 14px;border-radius:16px;box-shadow:inset 0 0 0 1.5px var(--opt);min-height:56px;background:var(--surface);cursor:pointer;text-align:right;width:100%;font:inherit;color:inherit}
.choice:has(input:checked){background:var(--accent-soft);box-shadow:inset 0 0 0 2px var(--accent)}
.choice input{flex:none;width:22px;height:22px;margin:0;accent-color:var(--accent)}
.choice .body{flex:1;display:flex;flex-direction:column;min-width:0}
.choice .t{font-weight:800;font-size:15px}
.choice .d{font-size:12px;color:var(--muted)}
.choice .p{flex:none;font-weight:800;font-size:14px;white-space:nowrap}
.choice.closed{opacity:.6;cursor:not-allowed}
.pill{display:inline-flex;align-items:center;height:24px;padding:0 9px;border-radius:12px;font-size:11px;font-weight:800;background:var(--bg);color:var(--muted);margin-inline-start:6px}
.field{display:flex;flex-direction:column;gap:6px}
.field label{font-weight:700;font-size:13px}
.field .opt{font-weight:500;color:var(--muted)}
.field input[type=text],.field input[type=tel],.field input[type=email],.field select{width:100%;height:54px;padding:0 16px;border:0;border-radius:16px;background:var(--sunken);color:var(--ink);font:inherit;font-size:15px}
.field input[type=file]{width:100%;min-height:120px;padding:44px 16px 16px;border:1.5px dashed var(--opt);border-radius:16px;background:var(--sunken);font:inherit;font-size:13px;color:var(--muted)}
.field input:focus,.field select:focus{outline:2px solid var(--accent);outline-offset:0}
.choice:focus-within{outline:2px solid var(--accent);outline-offset:1px}
.field .help,.help{font-size:12px;color:var(--muted);line-height:1.6}
.field .err,.group .err{display:none;font-size:12px;color:var(--stop);font-weight:700}
.field.bad input,.field.bad select{box-shadow:inset 0 0 0 2px var(--stop)}
.field.bad .err,.group.bad .err{display:flex}
.ltr{direction:ltr;text-align:right}
.kv{display:flex;justify-content:space-between;gap:12px;font-size:14px}
.kv>span:first-child{color:var(--muted)}
.kv.big{font-size:17px;font-weight:800}.kv.big>span:first-child{color:var(--ink)}
.kv.small,.row.small{font-size:13px}
.hr{height:1px;background:var(--line)}
.bar{position:fixed;left:0;right:0;bottom:0;background:var(--surface);border-top:1px solid var(--line);padding:12px 16px calc(20px + env(safe-area-inset-bottom,0px));display:flex;flex-direction:column;gap:10px;z-index:5}
.bar>*{max-width:608px;width:100%;margin:0 auto}
.bar.two{display:grid;grid-template-columns:1fr 1.8fr;gap:10px}
.bar.two>*{max-width:none}
.total{display:flex;flex-direction:column;gap:2px}
.total .row{display:flex;justify-content:space-between;align-items:baseline;gap:12px}
.total .row>span:first-child{font-size:13px;color:var(--muted)}
.total .sum{font-size:20px;font-weight:800}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:58px;border:0;border-radius:18px;background:var(--accent);color:var(--on-accent);font:inherit;font-size:17px;font-weight:800;text-decoration:none;cursor:pointer}
.btn[disabled]{opacity:.6;cursor:progress}
.btn.outline,.btn.soft{background:var(--bg);color:var(--ink);font-size:15px;font-weight:700}
.alert{display:flex;gap:10px;padding:12px 14px;border-radius:16px;background:var(--stop-soft);color:var(--ink);font-size:13px;line-height:1.65}
.alert.wait{background:var(--wait-soft);color:var(--wait-ink)}.alert.go{background:var(--go-soft)}.alert.info{background:var(--accent-soft)}
.alert b{display:block}
.alert a{color:var(--stop);font-weight:800}
.state{background:var(--surface);border-radius:22px;padding:20px 16px;display:flex;flex-direction:column;gap:12px;align-items:stretch;text-align:center;box-shadow:0 10px 30px rgba(11,122,123,.14)}
.state .ic{align-self:center;width:64px;height:64px;border-radius:32px;display:grid;place-items:center}
.state h1{margin:0;font-size:22px;line-height:1.5;font-weight:800}
.state p{margin:0;color:var(--muted);font-size:14px}
.code{display:flex;flex-direction:column;align-items:center;gap:2px;padding:8px}
.code span{font-size:12px;color:var(--muted)}
.code b{font-size:26px;letter-spacing:3px;direction:ltr;font-variant-numeric:tabular-nums}
.rows{background:var(--sunken);border-radius:16px;padding:4px 14px;text-align:right}
.rows div{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-bottom:1px solid var(--line);font-size:14px}
.rows div:last-child{border-bottom:0}
.rows span:first-child{color:var(--muted);flex:none}
.bank{display:flex;flex-direction:column;gap:10px;text-align:right}
.bank>div{display:flex;align-items:center;gap:10px;min-height:54px;border-radius:16px;background:var(--sunken);padding:0 14px}
.bank>div>span:first-child{display:none}
.bank .num{flex-grow:1;direction:ltr;text-align:right;font-size:16px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:1px}
.copy{height:38px;padding:0 12px;border-radius:19px;border:0;background:var(--surface);box-shadow:inset 0 0 0 1px var(--opt);color:var(--accent-text);font:inherit;font-size:12px;font-weight:800;cursor:pointer}
.foot{margin:24px auto 0;max-width:640px;padding:0 16px;display:flex;flex-wrap:wrap;gap:6px 18px;justify-content:center}
.foot a{min-height:44px;display:inline-flex;align-items:center;color:var(--ink);text-decoration:none;font-weight:700;font-size:13px}
.maker{display:block;text-align:center;padding:14px 14px 120px;color:var(--muted);font-size:12px;text-decoration:none}
.hp{position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.track{font-size:13px;text-align:center;color:var(--muted)}
[hidden]{display:none!important}
@media (prefers-reduced-motion:no-preference){.btn,.choice{transition:background-color .15s,box-shadow .15s}}
CSS;
}

function cd_reg_render_message($title, $text) {
    $css = cd_reg_theme_css(cd_reg_default_config()['theme']);
    return cd_reg_head($title, $css) . '<body><header class="hero"><div class="in"><span class="sub">رویدادیار</span><h1>' . esc_html($title) . '</h1></div></header>'
        . '<main class="wrap"><div class="state"><p>' . esc_html($text) . '</p></div></main></body></html>';
}

function cd_reg_icon($name, $color = 'currentColor', $size = 22) {
    $paths = [
        'calendar' => '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/>',
        'pin' => '<path d="M12 21.5s-7-6.3-7-11.8A7 7 0 0 1 19 9.7c0 5.5-7 11.8-7 11.8z"/><circle cx="12" cy="9.7" r="2.6"/>',
        'user' => '<circle cx="12" cy="8" r="4"/><path d="M4 21c.8-4 4-6.5 8-6.5s7.2 2.5 8 6.5"/>',
        'id' => '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2.2"/><path d="M5.8 16c.5-1.7 1.7-2.6 3.2-2.6s2.7.9 3.2 2.6M14.5 10h3.5M14.5 13.5h3.5"/>',
        'list' => '<path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
        'plus' => '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>',
    ];
    return '<svg width="' . (int) $size . '" height="' . (int) $size . '" viewBox="0 0 24 24" fill="none" stroke="' . esc_attr($color) . '" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $paths[$name] . '</svg>';
}

function cd_reg_render_page(array $page) {
    $cfg = $page['config'];
    $c = $cfg['content'];
    $event = cd_get_event((int) $page['event_id']);
    $title = $c['title'] !== '' ? $c['title'] : ($event['name'] ?? 'ثبت‌نام');
    cd_reg_expire_holds((int) $page['event_id']);
    $counts = cd_reg_counts((int) $page['event_id']);
    $open = cd_reg_page_state($page, $counts) === 'open';
    $pub = cd_reg_public_config($page, $counts);
    $e = 'esc_html';

    ob_start();
    echo cd_reg_head('ثبت‌نام ' . $title, cd_reg_theme_css($cfg['theme'])); // phpcs:ignore WordPress.Security.EscapeOutput
    ?>
<body>
<header class="hero">
  <div class="in">
    <div class="top">
      <span class="sub"><?php echo $c['subtitle'] !== '' ? $e($c['subtitle']) : 'ثبت‌نام آنلاین'; ?></span>
      <?php if ($c['logo_url']) : ?><img src="<?php echo esc_url($c['logo_url']); ?>" alt=""><?php elseif ($c['site_url']) : ?><a class="site" href="<?php echo esc_url($c['site_url']); ?>">سایت رویداد</a><?php endif; ?>
    </div>
    <h1><?php echo $e($title); ?></h1>
    <?php if ($c['days'] || $c['venue']) : ?><span class="meta"><?php echo $e(implode(' · ', array_filter([implode('، ', $c['days']), implode('، ', $c['venue'])]))); ?></span><?php endif; ?>
    <?php if ($c['cover_url']) : ?><img class="cover" src="<?php echo esc_url($c['cover_url']); ?>" alt=""><?php endif; ?>
  </div>
</header>
<main class="wrap">
  <div id="view" class="stack" aria-live="polite">
    <?php if (!$open) : ?>
      <div class="state">
        <span class="ic" style="background:var(--bg)"><?php echo cd_reg_icon('calendar', 'var(--muted)', 32); // phpcs:ignore ?></span>
        <h1>ثبت‌نام آنلاین بسته شد</h1>
        <p><?php echo $e($c['closed_text'] !== '' ? $c['closed_text'] : 'ظرفیت یا مهلت تمام شده؛ اگر جا باشد روز رویداد در میز پذیرش ثبت‌نام می‌شوید.'); ?></p>
        <?php if ($c['contact']) : ?><p>دبیرخانه: <span class="ltr"><?php echo $e($c['contact']); ?></span></p><?php endif; ?>
        <button type="button" class="btn soft" data-go="track">پیگیری ثبت‌نام قبلی</button>
      </div>
    <?php else : ?>
      <noscript><div class="alert"><span><b>جاوااسکریپت مرورگر خاموش است.</b>برای ثبت‌نام آن را روشن کنید.</span></div></noscript>
      <div class="sec float"><p style="margin:0">در حال بارگذاری فرم…</p></div>
    <?php endif; ?>
  </div>
  <?php if ($c['description']) : ?><p class="desc" style="margin-top:14px"><?php echo $e($c['description']); ?></p><?php endif; ?>
  <p class="track" id="track-link" <?php echo $open ? '' : 'hidden'; ?>>قبلاً ثبت‌نام کرده‌اید؟ <a href="#track" data-go="track">پیگیری ثبت‌نام</a></p>
</main>
<?php if ($c['links'] || $c['site_url']) : ?>
<footer class="foot">
  <?php if ($c['site_url']) : ?><a href="<?php echo esc_url($c['site_url']); ?>"><?php echo $e(preg_replace('#^https?://#', '', untrailingslashit($c['site_url']))); ?></a><?php endif; ?>
  <?php foreach ($c['links'] as $l) : ?><a href="<?php echo esc_url($l['url']); ?>"><?php echo $e($l['label']); ?></a><?php endforeach; ?>
</footer>
<?php endif; ?>
<?php if ($cfg['theme']['maker_credit']) : ?>
<a class="maker" href="https://newvisionteam.ir/">ساخته‌شده با رویدادیار · راهکارهای نرم‌افزاری نگاه جدید</a>
<?php endif; ?>
<script>window.RY_REG = <?php echo wp_json_encode(array_merge($pub, ['open' => $open]), JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>;</script>
<script><?php echo cd_reg_script(); // phpcs:ignore ?></script>
</body></html>
    <?php
    return ob_get_clean();
}

/** همه‌ی منطق صفحه: فرم، اعتبارسنجی، ارسال، پرداخت، پیگیری. */
function cd_reg_script() {
    return file_get_contents(CD_DIR . 'assets/registration.js');
}
