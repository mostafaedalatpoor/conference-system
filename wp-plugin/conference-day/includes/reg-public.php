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
    if ($file && !empty($file['tmp_name']) && is_uploaded_file($file['tmp_name'])) {
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
    if (!@move_uploaded_file($file['tmp_name'], cd_reg_receipts_dir() . '/' . $name)) {
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
    $p = $dark
        ? ['bg' => '#0D1015', 'surface' => '#161A21', 'sunken' => '#0A0C10', 'line' => '#2A313C', 'ink' => '#EDF0F4', 'muted' => '#A0A9B6', 'stop' => '#FF8A80', 'stop_soft' => '#3A1512', 'go' => '#5BD08A', 'go_soft' => '#10301C', 'wait' => '#F5B83D', 'wait_soft' => '#33260A']
        : ['bg' => '#F4F5F7', 'surface' => '#FFFFFF', 'sunken' => '#E9ECF0', 'line' => '#DCE0E6', 'ink' => '#10141A', 'muted' => '#505966', 'stop' => '#B42318', 'stop_soft' => '#FDE8E6', 'go' => '#127A3B', 'go_soft' => '#E1F5E8', 'wait' => '#8A5300', 'wait_soft' => '#FFF1D1'];
    $accent = $theme['accent'];
    $vars = [
        '--bg' => $p['bg'], '--surface' => $p['surface'], '--sunken' => $p['sunken'], '--line' => $p['line'],
        '--ink' => $p['ink'], '--muted' => $p['muted'],
        '--accent' => $accent, '--on-accent' => cd_reg_on_color($accent),
        '--accent-text' => cd_reg_readable($accent, $p['surface']),
        '--accent-soft' => $accent . ($dark ? '29' : '1A'),
        '--highlight' => cd_reg_readable($theme['highlight'], $p['bg']),
        '--stop' => $p['stop'], '--stop-soft' => $p['stop_soft'], '--go' => $p['go'], '--go-soft' => $p['go_soft'],
        '--wait' => $p['wait'], '--wait-soft' => $p['wait_soft'],
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
    $font = plugins_url('assets/fonts/', CD_DIR . 'conference-day.php');
    return '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>' . esc_html($title) . '</title>'
        . '<style>@font-face{font-family:Vazirmatn;font-weight:400;font-display:swap;src:url("' . esc_url($font . 'Vazirmatn-Regular.woff2') . '") format("woff2")}'
        . '@font-face{font-family:Vazirmatn;font-weight:800;font-display:swap;src:url("' . esc_url($font . 'Vazirmatn-ExtraBold.woff2') . '") format("woff2")}'
        . $css . cd_reg_base_css() . '</style></head>';
}

function cd_reg_base_css() {
    return <<<'CSS'
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:Vazirmatn,Tahoma,"Segoe UI",sans-serif;line-height:1.8;font-size:15px}
a{color:var(--accent-text)}
.top{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:10px max(16px,env(safe-area-inset-left,0px));border-bottom:1px solid var(--line);background:var(--surface)}
.top .brand{display:flex;align-items:center;gap:10px;font-weight:800;min-width:0}
.top .brand img{width:32px;height:32px;object-fit:contain}
.top .brand span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.btn-ghost{display:inline-flex;align-items:center;min-height:44px;padding:0 14px;border:1.5px solid var(--accent-text);border-radius:10px;color:var(--accent-text);text-decoration:none;font-weight:800;font-size:14px;white-space:nowrap}
.wrap{max-width:720px;margin:0 auto;padding:0 max(16px,env(safe-area-inset-left,0px)) 40px}
.hero{padding:28px 0 20px;display:flex;flex-direction:column;gap:12px;text-align:center;align-items:center}
.hero .sub{font-weight:800;color:var(--muted)}
.hero h1{margin:0;font-size:clamp(24px,6vw,36px);line-height:1.5;font-weight:800;color:var(--highlight);text-wrap:balance}
.hero .cover{width:100%;max-height:280px;object-fit:cover;border-radius:14px}
.meta{display:flex;flex-direction:column;gap:8px;align-self:stretch;text-align:right;background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:14px 16px}
.meta div{display:flex;gap:10px;align-items:flex-start}
.meta svg{flex:none;margin-top:4px}
.desc{white-space:pre-line;color:var(--ink);text-align:right;align-self:stretch}
.card{background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:22px 18px;display:flex;flex-direction:column;gap:26px}
.steps{display:grid;grid-template-columns:1fr 1fr;gap:6px;font-size:12px}
.steps span{display:block;height:4px;border-radius:4px;background:var(--sunken);margin-bottom:4px}
.steps .on span{background:var(--accent)}
.steps .on{font-weight:800}
h2{margin:0;font-size:17px;font-weight:800;display:flex;align-items:center;gap:8px;color:var(--accent-text)}
.group{display:flex;flex-direction:column;gap:14px}
.choice{display:flex;gap:12px;align-items:flex-start;padding:14px 16px;border:1.5px solid var(--line);border-radius:14px;background:var(--surface);cursor:pointer;text-align:right;width:100%;font:inherit;color:inherit}
.choice:has(input:checked){border-color:var(--accent);background:var(--accent-soft)}
.choice input{flex:none;width:20px;height:20px;margin-top:4px;accent-color:var(--accent)}
.choice .body{flex:1;display:flex;flex-direction:column;gap:2px;min-width:0}
.choice .t{font-weight:800}
.choice .d{font-size:13px;color:var(--muted)}
.choice .p{flex:none;font-weight:800;color:var(--highlight);white-space:nowrap}
.choice.closed{border-style:dashed;cursor:not-allowed;color:var(--muted);background:var(--sunken)}
.pill{display:inline-block;font-size:11px;font-weight:800;border-radius:999px;padding:0 8px;background:var(--sunken);color:var(--muted);margin-inline-start:6px}
.field{display:flex;flex-direction:column;gap:6px}
.field label{font-weight:800;font-size:14px}
.field .opt{font-weight:400;color:var(--muted)}
.field input[type=text],.field input[type=tel],.field input[type=email],.field select,.field input[type=file]{width:100%;min-height:48px;padding:0 14px;border:1.5px solid var(--line);border-radius:12px;background:var(--bg);color:var(--ink);font:inherit;font-size:16px}
.field input[type=file]{padding:10px}
.field input:focus,.field select:focus,.choice:focus-within{outline:2px solid var(--accent);outline-offset:1px}
.field .help{font-size:13px;color:var(--muted)}
.field .err{display:none;font-size:13px;color:var(--stop);font-weight:800}
.field.bad input,.field.bad select{border-color:var(--stop);background:var(--stop-soft)}
.field.bad label{color:var(--stop)}
.field.bad .err{display:block}
.group.bad .err{display:block}
.ltr{direction:ltr;text-align:right}
.total{border-top:1px dashed var(--line);padding-top:18px;display:flex;flex-direction:column;gap:10px}
.total .row{display:flex;justify-content:space-between;align-items:baseline;gap:12px}
.total .sum{font-size:20px;font-weight:800;color:var(--highlight)}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:54px;border:0;border-radius:14px;background:var(--accent);color:var(--on-accent);font:inherit;font-size:17px;font-weight:800;text-decoration:none;cursor:pointer}
.btn[disabled]{opacity:.6;cursor:progress}
.btn.outline{background:transparent;color:var(--ink);border:1.5px solid var(--line)}
.alert{display:flex;gap:12px;padding:14px 16px;border-radius:14px;background:var(--stop-soft);color:var(--ink)}
.alert.wait{background:var(--wait-soft)}.alert.go{background:var(--go-soft)}.alert.info{background:var(--accent-soft)}
.alert b{display:block}
.alert a{color:var(--stop);font-weight:800}
.state{display:flex;flex-direction:column;gap:14px;align-items:stretch;text-align:center}
.state .ic{align-self:center;width:72px;height:72px;border-radius:50%;display:flex;align-items:center;justify-content:center}
.state h1{margin:0;font-size:22px;font-weight:800}
.code{border:2px dashed var(--highlight);border-radius:14px;padding:12px;display:flex;flex-direction:column}
.code b{font-size:26px;letter-spacing:2px;color:var(--highlight);direction:ltr}
.rows{border:1px solid var(--line);border-radius:14px;padding:0 16px;text-align:right}
.rows div{display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-bottom:1px solid var(--line);font-size:14px}
.rows div:last-child{border-bottom:0}
.rows span:first-child{color:var(--muted);flex:none}
.bank{display:flex;flex-direction:column;gap:8px;text-align:right;background:var(--sunken);border-radius:14px;padding:14px}
.bank .num{font-size:20px;font-weight:800;direction:ltr;text-align:right;letter-spacing:1px}
.copy{border:0;background:none;color:var(--accent-text);font:inherit;font-weight:800;cursor:pointer;padding:4px 0}
.foot{margin-top:28px;padding:18px max(16px,env(safe-area-inset-left,0px));border-top:2px solid var(--highlight);background:var(--surface);display:flex;flex-wrap:wrap;gap:6px 18px;justify-content:center}
.foot a{min-height:44px;display:inline-flex;align-items:center;color:var(--ink);text-decoration:none;font-weight:800;font-size:14px}
.maker{display:block;text-align:center;padding:14px;color:var(--muted);font-size:12px;text-decoration:none}
.hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.track{font-size:14px;text-align:center}
[hidden]{display:none!important}
@media (prefers-reduced-motion:no-preference){.btn,.choice{transition:background-color .15s,border-color .15s}}
CSS;
}

function cd_reg_render_message($title, $text) {
    $css = cd_reg_theme_css(cd_reg_default_config()['theme']);
    return cd_reg_head($title, $css) . '<body><main class="wrap"><div class="hero"><h1>' . esc_html($title) . '</h1><p>' . esc_html($text) . '</p></div></main></body></html>';
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
<header class="top">
  <div class="brand">
    <?php if ($c['logo_url']) : ?><img src="<?php echo esc_url($c['logo_url']); ?>" alt=""><?php endif; ?>
    <span>ثبت‌نام <?php echo $e($title); ?></span>
  </div>
  <?php if ($c['site_url']) : ?><a class="btn-ghost" href="<?php echo esc_url($c['site_url']); ?>">سایت رویداد</a><?php endif; ?>
</header>
<main class="wrap">
  <section class="hero">
    <?php if ($c['cover_url']) : ?><img class="cover" src="<?php echo esc_url($c['cover_url']); ?>" alt=""><?php endif; ?>
    <?php if ($c['subtitle']) : ?><span class="sub"><?php echo $e($c['subtitle']); ?></span><?php endif; ?>
    <h1><?php echo $e($title); ?></h1>
    <?php if ($c['days'] || $c['venue']) : ?>
    <div class="meta">
      <?php if ($c['days']) : ?><div><?php echo cd_reg_icon('calendar', 'var(--highlight)'); // phpcs:ignore ?><span><?php echo implode('<br>', array_map('esc_html', $c['days'])); // phpcs:ignore ?></span></div><?php endif; ?>
      <?php if ($c['venue']) : ?><div><?php echo cd_reg_icon('pin', 'var(--highlight)'); // phpcs:ignore ?><span><?php echo implode('<br>', array_map('esc_html', $c['venue'])); // phpcs:ignore ?></span></div><?php endif; ?>
    </div>
    <?php endif; ?>
    <?php if ($c['description']) : ?><p class="desc"><?php echo $e($c['description']); ?></p><?php endif; ?>
  </section>

  <div id="view" class="card" aria-live="polite">
    <?php if (!$open) : ?>
      <div class="state">
        <span class="ic" style="background:var(--wait-soft)"><?php echo cd_reg_icon('user', 'var(--wait)', 34); // phpcs:ignore ?></span>
        <h1>ثبت‌نام آنلاین بسته شد</h1>
        <p><?php echo $e($c['closed_text'] !== '' ? $c['closed_text'] : 'ظرفیت یا مهلت ثبت‌نام آنلاین تمام شده است. اگر جا باشد، روز رویداد در میز پذیرش ثبت‌نام می‌شوید.'); ?></p>
        <?php if ($c['contact']) : ?><p>دبیرخانه: <span class="ltr"><?php echo $e($c['contact']); ?></span></p><?php endif; ?>
        <button type="button" class="btn outline" data-go="track">پیگیری ثبت‌نام قبلی</button>
      </div>
    <?php else : ?>
      <noscript><div class="alert"><span><b>جاوااسکریپت مرورگر خاموش است.</b>برای ثبت‌نام آن را روشن کنید.</span></div></noscript>
      <p>در حال بارگذاری فرم…</p>
    <?php endif; ?>
  </div>
  <p class="track" id="track-link" <?php echo $open ? '' : 'hidden'; ?>>قبلاً ثبت‌نام کرده‌اید؟ <a href="#track" data-go="track">پیگیری ثبت‌نام</a></p>
</main>
<?php if ($c['links'] || $c['site_url']) : ?>
<footer class="foot" dir="ltr">
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
