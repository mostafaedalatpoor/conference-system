<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * ماژول ثبت‌نام: تنظیم صفحه، ظرفیت، ثبت، پرداخت و ورود به لیست شرکت‌کننده‌ها.
 * مبلغ‌ها همه به تومان و همیشه روی سرور حساب می‌شوند.
 */

const CD_REG_RATE_LIMIT = 15;     // تلاش در هر ۱۰ دقیقه از هر IP
const CD_REG_GATEWAY_HOLD = 30;   // دقیقه، نگه‌داشتن جا تا برگشت از درگاه

function cd_reg_statuses() {
    return [
        'pending_payment' => 'در انتظار پرداخت',
        'pending_review' => 'در انتظار تأیید پرداخت',
        'pending_approval' => 'در انتظار تأیید مدیر',
        'confirmed' => 'تأییدشده',
        'rejected' => 'ردشده',
        'expired' => 'منقضی',
    ];
}

// ---------------------------------------------------------------- تنظیم صفحه

function cd_reg_default_config() {
    return [
        'path' => '',
        'use_prefix' => false,
        'status' => 'draft',
        'list_mode' => 'direct',
        'content' => [
            'title' => '', 'subtitle' => '', 'description' => '', 'logo_url' => '', 'cover_url' => '',
            'days' => [], 'venue' => [], 'site_url' => '', 'contact' => '', 'links' => [], 'closed_text' => '',
        ],
        'theme' => ['accent' => '#2A42D4', 'highlight' => '#B7791F', 'mode' => 'light', 'maker_credit' => true],
        'capacity_total' => 0,
        'deadline' => '',
        'types' => [],
        'fields' => ['email' => 'optional', 'organization' => 'required'],
        'custom_fields' => [],
        'addons' => [],
        'payment' => [
            'method' => 'gateway',
            'gateway' => 'zarinpal',
            'gateway_settings' => [],
            'link_url' => '', 'link_text' => '',
            'card' => ['number' => '', 'sheba' => '', 'holder' => '', 'bank' => '', 'text' => '', 'image_url' => '', 'require' => 'code'],
            'hold_hours' => 48,
        ],
        'success' => ['show_personal_link' => true, 'text' => ''],
    ];
}

/** مسیر صفحه: حروف کوچک لاتین، رقم و خط تیره. با پیشوند: register/<path>. */
function cd_reg_full_path(array $cfg) {
    return ($cfg['use_prefix'] ? 'register/' : '') . $cfg['path'];
}

function cd_reg_hex($v, $def) {
    $v = (string) $v;
    return preg_match('/^#[0-9a-fA-F]{6}$/', $v) ? strtoupper($v) : $def;
}

function cd_reg_id($v) {
    $v = (string) $v;
    return preg_match('/^[A-Za-z0-9_-]{1,40}$/', $v) ? $v : '';
}

function cd_reg_money($v) {
    return max(0, min(2000000000, (int) cd_latin_digits((string) $v)));
}

function cd_reg_url($v) {
    $v = trim((string) $v);
    return $v === '' ? '' : (string) esc_url_raw($v, ['http', 'https']);
}

/** تنظیم صفحه از اپ مدیریت یا پیشخوان: فقط کلیدهای شناخته‌شده، در بازه. */
function cd_sanitize_reg_config($in) {
    $d = cd_reg_default_config();
    $in = is_array($in) ? $in : [];
    $out = $d;

    $path = strtolower(trim((string) ($in['path'] ?? ''), "/ \t"));
    $out['path'] = preg_match('/^[a-z0-9][a-z0-9-]{1,60}$/', $path) ? $path : '';
    $out['use_prefix'] = !empty($in['use_prefix']);
    $out['status'] = in_array($in['status'] ?? '', ['draft', 'open', 'closed'], true) ? $in['status'] : 'draft';
    $out['list_mode'] = in_array($in['list_mode'] ?? '', ['direct', 'approval', 'separate'], true) ? $in['list_mode'] : 'direct';

    $c = is_array($in['content'] ?? null) ? $in['content'] : [];
    $lines = function ($v, $max = 6) {
        $v = is_array($v) ? $v : preg_split('/\r?\n/', (string) $v);
        return array_slice(array_values(array_filter(array_map(function ($x) {
            return cd_str($x, 200);
        }, $v), 'strlen')), 0, $max);
    };
    $out['content'] = [
        'title' => cd_str($c['title'] ?? '', 200),
        'subtitle' => cd_str($c['subtitle'] ?? '', 200),
        'description' => mb_substr(trim(wp_strip_all_tags((string) ($c['description'] ?? ''))), 0, 3000),
        'logo_url' => cd_reg_url($c['logo_url'] ?? ''),
        'cover_url' => cd_reg_url($c['cover_url'] ?? ''),
        'days' => $lines($c['days'] ?? []),
        'venue' => $lines($c['venue'] ?? []),
        'site_url' => cd_reg_url($c['site_url'] ?? ''),
        'contact' => cd_str($c['contact'] ?? '', 100),
        'links' => array_slice(array_values(array_filter(array_map(function ($l) {
            $u = cd_reg_url(is_array($l) ? ($l['url'] ?? '') : '');
            return $u === '' ? null : ['label' => cd_str($l['label'] ?? '', 80) ?: $u, 'url' => $u];
        }, is_array($c['links'] ?? null) ? $c['links'] : []))), 0, 8),
        'closed_text' => mb_substr(trim(wp_strip_all_tags((string) ($c['closed_text'] ?? ''))), 0, 600),
    ];

    $t = is_array($in['theme'] ?? null) ? $in['theme'] : [];
    $out['theme'] = [
        'accent' => cd_reg_hex($t['accent'] ?? '', $d['theme']['accent']),
        'highlight' => cd_reg_hex($t['highlight'] ?? '', $d['theme']['highlight']),
        'mode' => ($t['mode'] ?? '') === 'dark' ? 'dark' : 'light',
        'maker_credit' => !array_key_exists('maker_credit', $t) || !empty($t['maker_credit']),
    ];

    $out['capacity_total'] = max(0, min(1000000, (int) ($in['capacity_total'] ?? 0)));
    $out['deadline'] = cd_reg_datetime($in['deadline'] ?? '');

    $out['types'] = [];
    foreach (array_slice(is_array($in['types'] ?? null) ? $in['types'] : [], 0, 20) as $x) {
        if (!is_array($x) || !cd_is_code($x['code'] ?? null)) {
            continue;
        }
        $out['types'][] = [
            'code' => $x['code'],
            'description' => cd_str($x['description'] ?? '', 300),
            'price' => cd_reg_money($x['price'] ?? 0),
            'capacity' => max(0, min(1000000, (int) ($x['capacity'] ?? 0))),
            'deadline' => cd_reg_datetime($x['deadline'] ?? ''),
            'visible' => !array_key_exists('visible', $x) || !empty($x['visible']),
        ];
    }

    $f = is_array($in['fields'] ?? null) ? $in['fields'] : [];
    foreach (['email', 'organization'] as $k) {
        $out['fields'][$k] = in_array($f[$k] ?? '', ['required', 'optional', 'hidden'], true) ? $f[$k] : $d['fields'][$k];
    }

    $out['custom_fields'] = [];
    foreach (array_slice(is_array($in['custom_fields'] ?? null) ? $in['custom_fields'] : [], 0, 15) as $x) {
        $id = is_array($x) ? cd_reg_id($x['id'] ?? '') : '';
        $label = is_array($x) ? cd_str($x['label'] ?? '', 120) : '';
        if ($id === '' || $label === '') {
            continue;
        }
        $kind = in_array($x['kind'] ?? '', ['text', 'select', 'multi'], true) ? $x['kind'] : 'text';
        $options = [];
        foreach (array_slice(is_array($x['options'] ?? null) ? $x['options'] : [], 0, 30) as $o) {
            $oid = is_array($o) ? cd_reg_id($o['id'] ?? '') : '';
            $ol = is_array($o) ? cd_str($o['label'] ?? '', 160) : '';
            if ($oid !== '' && $ol !== '') {
                $options[] = ['id' => $oid, 'label' => $ol, 'capacity' => max(0, (int) ($o['capacity'] ?? 0))];
            }
        }
        if ($kind !== 'text' && !$options) {
            continue;
        }
        $out['custom_fields'][] = [
            'id' => $id, 'label' => $label, 'kind' => $kind, 'required' => !empty($x['required']),
            'help' => cd_str($x['help'] ?? '', 200), 'options' => $kind === 'text' ? [] : $options,
            'types' => cd_reg_codes($x['types'] ?? []),
        ];
    }

    $out['addons'] = [];
    foreach (array_slice(is_array($in['addons'] ?? null) ? $in['addons'] : [], 0, 20) as $x) {
        $id = is_array($x) ? cd_reg_id($x['id'] ?? '') : '';
        $title = is_array($x) ? cd_str($x['title'] ?? '', 120) : '';
        if ($id === '' || $title === '') {
            continue;
        }
        $price = cd_reg_money($x['price'] ?? 0);
        $mode = in_array($x['price_mode'] ?? '', ['online', 'onsite', 'info'], true) ? $x['price_mode'] : 'online';
        $out['addons'][] = [
            'id' => $id, 'title' => $title, 'description' => cd_str($x['description'] ?? '', 300),
            'price' => $mode === 'info' ? 0 : $price, 'price_mode' => $price === 0 ? 'info' : $mode,
            'capacity' => max(0, (int) ($x['capacity'] ?? 0)),
            'meal_code' => cd_is_code($x['meal_code'] ?? null) ? $x['meal_code'] : '',
            'types' => cd_reg_codes($x['types'] ?? []),
        ];
    }

    $p = is_array($in['payment'] ?? null) ? $in['payment'] : [];
    $card = is_array($p['card'] ?? null) ? $p['card'] : [];
    $gs = [];
    foreach ((is_array($p['gateway_settings'] ?? null) ? $p['gateway_settings'] : []) as $k => $v) {
        if (cd_reg_id($k) !== '' && is_scalar($v)) {
            $gs[$k] = cd_str($v, 200);
        }
    }
    $out['payment'] = [
        'method' => in_array($p['method'] ?? '', ['gateway', 'link', 'card'], true) ? $p['method'] : 'gateway',
        'gateway' => cd_reg_id($p['gateway'] ?? '') ?: 'zarinpal',
        'gateway_settings' => $gs,
        'link_url' => cd_reg_url($p['link_url'] ?? ''),
        'link_text' => mb_substr(trim(wp_strip_all_tags((string) ($p['link_text'] ?? ''))), 0, 600),
        'card' => [
            'number' => preg_replace('/\D+/', '', cd_latin_digits((string) ($card['number'] ?? ''))),
            'sheba' => strtoupper(preg_replace('/[^A-Za-z0-9]+/', '', cd_latin_digits((string) ($card['sheba'] ?? '')))),
            'holder' => cd_str($card['holder'] ?? '', 120),
            'bank' => cd_str($card['bank'] ?? '', 60),
            'text' => mb_substr(trim(wp_strip_all_tags((string) ($card['text'] ?? ''))), 0, 800),
            'image_url' => cd_reg_url($card['image_url'] ?? ''),
            'require' => in_array($card['require'] ?? '', ['code', 'receipt', 'both'], true) ? $card['require'] : 'code',
        ],
        'hold_hours' => max(1, min(720, (int) ($p['hold_hours'] ?? 48))),
    ];

    $s = is_array($in['success'] ?? null) ? $in['success'] : [];
    $out['success'] = [
        'show_personal_link' => !array_key_exists('show_personal_link', $s) || !empty($s['show_personal_link']),
        'text' => mb_substr(trim(wp_strip_all_tags((string) ($s['text'] ?? ''))), 0, 600),
    ];
    return $out;
}

function cd_reg_codes($v) {
    return array_values(array_filter(is_array($v) ? $v : [], 'cd_is_code'));
}

/** «۱۴۰۵-۰۸-۲۰ ۱۸:۰۰» یا «2026-11-10 18:00» (وقت تهران) → «Y-m-d H:i» میلادی؛ نامعتبر: ''. */
function cd_reg_datetime($v) {
    $v = trim(cd_latin_digits((string) $v));
    if (!preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$/', $v, $m)) {
        return '';
    }
    [$y, $mo, $d] = [(int) $m[1], (int) $m[2], (int) $m[3]];
    if ($y < 1700) {
        [$y, $mo, $d] = cd_jalali_to_gregorian($y, $mo, $d);
    }
    if (!checkdate($mo, $d, $y)) {
        return '';
    }
    return sprintf('%04d-%02d-%02d %02d:%02d', $y, $mo, $d, (int) ($m[4] ?? 23), (int) ($m[5] ?? 59));
}

function cd_jalali_to_gregorian($jy, $jm, $jd) {
    $jy += 1595;
    $days = -355668 + (365 * $jy) + ((int) ($jy / 33) * 8) + (int) ((($jy % 33) + 3) / 4) + $jd + (($jm < 7) ? ($jm - 1) * 31 : (($jm - 7) * 30) + 186);
    $gy = 400 * (int) ($days / 146097);
    $days %= 146097;
    if ($days > 36524) {
        $gy += 100 * (int) (--$days / 36524);
        $days %= 36524;
        if ($days >= 365) {
            $days++;
        }
    }
    $gy += 4 * (int) ($days / 1461);
    $days %= 1461;
    if ($days > 365) {
        $gy += (int) (($days - 1) / 365);
        $days = ($days - 1) % 365;
    }
    $gd = $days + 1;
    $sal = [0, 31, (($gy % 4 == 0 && $gy % 100 != 0) || ($gy % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    for ($gm = 0; $gm < 13 && $gd > $sal[$gm]; $gm++) {
        $gd -= $sal[$gm];
    }
    return [$gy, $gm, $gd];
}

function cd_reg_past($deadline) {
    return $deadline !== '' && cd_tehran_now()->format('Y-m-d H:i') > $deadline;
}

/** پیوند صفحه برای یک مسیر. */
function cd_reg_page_url(array $cfg) {
    return home_url('/' . cd_reg_full_path($cfg) . '/');
}

function cd_reg_get_page_by_event($event_id) {
    global $wpdb;
    $r = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('reg_pages') . ' WHERE event_id = %d', $event_id), ARRAY_A);
    if (!$r) {
        return null;
    }
    $cfg = json_decode($r['config'], true);
    $r['config'] = array_replace_recursive(cd_reg_default_config(), is_array($cfg) ? $cfg : []);
    // فهرست‌ها جای هم را می‌گیرند، نه ادغام.
    foreach (['types', 'custom_fields', 'addons'] as $k) {
        $r['config'][$k] = is_array($cfg[$k] ?? null) ? $cfg[$k] : [];
    }
    foreach (['days', 'venue', 'links'] as $k) {
        $r['config']['content'][$k] = is_array($cfg['content'][$k] ?? null) ? $cfg['content'][$k] : [];
    }
    $r['config']['status'] = $r['status'];
    return $r;
}

function cd_reg_get_page_by_path($path) {
    global $wpdb;
    $eid = $wpdb->get_var($wpdb->prepare('SELECT event_id FROM ' . cd_table('reg_pages') . ' WHERE path = %s', $path));
    return $eid ? cd_reg_get_page_by_event((int) $eid) : null;
}

/** مسیر آزاد است؟ null یعنی بله؛ وگرنه دلیل. */
function cd_reg_path_problem($full_path, $event_id) {
    global $wpdb;
    if ($full_path === '' || substr($full_path, -1) === '/') {
        return 'آدرس فقط حروف کوچک انگلیسی، رقم و خط تیره، دست‌کم ۲ حرف.';
    }
    $first = explode('/', $full_path)[0];
    if (in_array($first, ['c', 'wp-admin', 'wp-json', 'wp-content', 'wp-includes', 'feed', 'page', 'category', 'tag', 'author', 'search'], true)) {
        return 'این آدرس برای وردپرس یا رویدادیار رزرو است؛ نام دیگری بگذارید.';
    }
    $other = $wpdb->get_var($wpdb->prepare('SELECT event_id FROM ' . cd_table('reg_pages') . ' WHERE path = %s AND event_id <> %d', $full_path, $event_id));
    if ($other) {
        return 'این آدرس برای صفحه‌ی ثبت‌نام رویداد دیگری است.';
    }
    if (function_exists('get_page_by_path') && (get_page_by_path($full_path) || get_page_by_path($full_path, OBJECT, 'post'))) {
        return 'برگه یا نوشته‌ای در سایت همین آدرس را دارد؛ نام دیگری بگذارید یا پیشوند register/ را روشن کنید.';
    }
    return null;
}

/** ذخیره‌ی تنظیم صفحه؛ مسیرها برای rewrite دوباره ساخته می‌شوند. */
function cd_reg_save_page($event_id, array $cfg) {
    global $wpdb;
    $full = cd_reg_full_path($cfg);
    $problem = cd_reg_path_problem($cfg['path'] === '' ? '' : $full, $event_id);
    if ($problem !== null) {
        return cd_error('cd_reg_path', $problem);
    }
    $status = $cfg['status'];
    unset($cfg['status']);
    $wpdb->replace(cd_table('reg_pages'), [
        'event_id' => (int) $event_id,
        'path' => $full,
        'status' => $status,
        'config' => wp_json_encode($cfg),
        'updated_at' => cd_now(),
    ]);
    cd_reg_refresh_routes();
    return true;
}

function cd_reg_refresh_routes() {
    global $wpdb;
    $paths = $wpdb->get_col('SELECT path FROM ' . cd_table('reg_pages'));
    update_option('cd_reg_routes', array_values($paths ?: []), true);
    cd_reg_add_rewrites();
    flush_rewrite_rules(false);
}

function cd_reg_add_rewrites() {
    foreach ((array) get_option('cd_reg_routes', []) as $p) {
        if (is_string($p) && preg_match('#^(register/)?[a-z0-9][a-z0-9-]{1,60}$#', $p)) {
            add_rewrite_rule('^' . preg_quote($p, '#') . '/?$', 'index.php?cd_reg=' . rawurlencode($p), 'top');
        }
    }
}
add_action('init', 'cd_reg_add_rewrites');

// ---------------------------------------------------------------- ظرفیت و مبلغ

/** ثبت‌نام‌هایی که جا نگه می‌دارند. اول مهلت‌گذشته‌ها منقضی می‌شوند. */
function cd_reg_expire_holds($event_id) {
    global $wpdb;
    $wpdb->query($wpdb->prepare(
        "UPDATE " . cd_table('registrations') . " SET status = 'expired', updated_at = %s
         WHERE event_id = %d AND status = 'pending_payment' AND hold_until IS NOT NULL AND hold_until < %s",
        cd_now(),
        $event_id,
        cd_now()
    ));
}

function cd_reg_holding_rows($event_id) {
    global $wpdb;
    return $wpdb->get_results($wpdb->prepare(
        "SELECT type_code, answers, addons FROM " . cd_table('registrations') . "
         WHERE event_id = %d AND status IN ('pending_payment','pending_review','pending_approval','confirmed')",
        $event_id
    ), ARRAY_A);
}

/** شمارش‌ها: کل، هر نوع، هر گزینه‌ی اضافه، هر گزینه‌ی فیلد دلخواه. */
function cd_reg_counts($event_id) {
    $c = ['total' => 0, 'types' => [], 'addons' => [], 'options' => []];
    foreach (cd_reg_holding_rows($event_id) as $r) {
        $c['total']++;
        $c['types'][$r['type_code']] = ($c['types'][$r['type_code']] ?? 0) + 1;
        foreach ((array) json_decode((string) $r['addons'], true) as $aid) {
            $c['addons'][$aid] = ($c['addons'][$aid] ?? 0) + 1;
        }
        foreach ((array) json_decode((string) $r['answers'], true) as $fid => $val) {
            foreach ((array) $val as $oid) {
                if (is_string($oid)) {
                    $key = $fid . '/' . $oid;
                    $c['options'][$key] = ($c['options'][$key] ?? 0) + 1;
                }
            }
        }
    }
    return $c;
}

function cd_reg_full($capacity, $used) {
    return $capacity > 0 && $used >= $capacity;
}

/** وضعیت باز بودن صفحه و نوع‌ها برای نمایش. */
function cd_reg_page_state(array $page, array $counts) {
    $cfg = $page['config'];
    if ($page['status'] === 'closed' || cd_reg_past($cfg['deadline']) || cd_reg_full($cfg['capacity_total'], $counts['total'])) {
        return 'closed';
    }
    $any = false;
    foreach ($cfg['types'] as $t) {
        if ($t['visible'] && !cd_reg_type_closed($t, $counts)) {
            $any = true;
        }
    }
    return $any ? 'open' : 'closed';
}

function cd_reg_type_closed(array $t, array $counts) {
    return cd_reg_past($t['deadline']) || cd_reg_full($t['capacity'], $counts['types'][$t['code']] ?? 0);
}

function cd_reg_applies(array $item, $type_code) {
    return empty($item['types']) || in_array($type_code, $item['types'], true);
}

/** مبلغ آنلاین و مبلغ روز اجرا برای یک نوع و گزینه‌ها. */
function cd_reg_amounts(array $cfg, $type_code, array $addon_ids) {
    $online = 0;
    $onsite = 0;
    foreach ($cfg['types'] as $t) {
        if ($t['code'] === $type_code) {
            $online += $t['price'];
        }
    }
    foreach ($cfg['addons'] as $a) {
        if (in_array($a['id'], $addon_ids, true) && cd_reg_applies($a, $type_code)) {
            if ($a['price_mode'] === 'online') {
                $online += $a['price'];
            } elseif ($a['price_mode'] === 'onsite') {
                $onsite += $a['price'];
            }
        }
    }
    return [$online, $onsite];
}

// ---------------------------------------------------------------- اعتبارسنجی و ثبت

function cd_reg_mask_mobile($m) {
    return strlen($m) === 11 ? substr($m, 0, 4) . ' ••• ••' . substr($m, -2) : '•••';
}

/** کلید دسترسی بدون موبایل (برای برگشت از درگاه و لینک‌های پیگیری). */
function cd_reg_key($code) {
    return substr(hash_hmac('sha256', 'reg:' . $code, wp_salt('auth')), 0, 20);
}

function cd_reg_new_code() {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $s = '';
    for ($i = 0; $i < 6; $i++) {
        $s .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
    return 'RY-' . $s;
}

/**
 * بررسی فرم. خروجی: [errors (فیلد → پیام), clean]. همان قواعد صفحه، دوباره روی سرور.
 */
function cd_reg_validate(array $cfg, array $in, array $counts) {
    $errors = [];
    $type_code = (string) ($in['type'] ?? '');
    $type = null;
    foreach ($cfg['types'] as $t) {
        if ($t['code'] === $type_code && $t['visible']) {
            $type = $t;
        }
    }
    if ($type === null) {
        $errors['type'] = 'نوع ثبت‌نام را انتخاب کنید.';
    } elseif (cd_reg_type_closed($type, $counts)) {
        $errors['type'] = 'ثبت‌نام این نوع بسته شده است.';
    }

    $first = cd_str($in['first_name'] ?? '', 100);
    $last = cd_str($in['last_name'] ?? '', 100);
    $mobile = cd_normalize_mobile($in['mobile'] ?? '');
    $email = strtolower(trim(cd_latin_digits((string) ($in['email'] ?? ''))));
    $org = cd_str($in['organization'] ?? '', 191);
    if (mb_strlen($first) < 2) {
        $errors['first_name'] = 'نام را وارد کنید.';
    }
    if (mb_strlen($last) < 2) {
        $errors['last_name'] = 'نام خانوادگی را وارد کنید.';
    }
    if (!preg_match('/^09\d{9}$/', $mobile)) {
        $errors['mobile'] = 'شماره موبایل باید ۱۱ رقم باشد و با ۰۹ شروع شود.';
    }
    $ef = $cfg['fields']['email'];
    if ($ef !== 'hidden') {
        if ($email === '' && $ef === 'required') {
            $errors['email'] = 'ایمیل را وارد کنید.';
        } elseif ($email !== '' && !is_email($email)) {
            $errors['email'] = 'قالب ایمیل درست نیست.';
        }
    } else {
        $email = '';
    }
    $of = $cfg['fields']['organization'];
    if ($of === 'hidden') {
        $org = '';
    } elseif ($org === '' && $of === 'required') {
        $errors['organization'] = 'دانشگاه یا سازمان را وارد کنید.';
    }

    $answers = [];
    $raw = is_array($in['answers'] ?? null) ? $in['answers'] : [];
    foreach ($cfg['custom_fields'] as $f) {
        if (!cd_reg_applies($f, $type_code)) {
            continue;
        }
        $v = $raw[$f['id']] ?? null;
        $ids = array_column($f['options'], 'id');
        if ($f['kind'] === 'text') {
            $v = cd_str(is_scalar($v) ? $v : '', 300);
            if ($v === '' && $f['required']) {
                $errors['f_' . $f['id']] = '«' . $f['label'] . '» را وارد کنید.';
            } elseif ($v !== '') {
                $answers[$f['id']] = $v;
            }
            continue;
        }
        $vals = array_values(array_unique(array_filter((array) $v, function ($x) use ($ids) {
            return is_string($x) && in_array($x, $ids, true);
        })));
        if ($f['kind'] === 'select') {
            $vals = array_slice($vals, 0, 1);
        }
        if (!$vals && $f['required']) {
            $errors['f_' . $f['id']] = $f['kind'] === 'select' ? 'یکی از گزینه‌ها را انتخاب کنید.' : 'دست‌کم یک گزینه را انتخاب کنید.';
            continue;
        }
        foreach ($f['options'] as $o) {
            if (in_array($o['id'], $vals, true) && cd_reg_full($o['capacity'], $counts['options'][$f['id'] . '/' . $o['id']] ?? 0)) {
                $errors['f_' . $f['id']] = 'ظرفیت «' . $o['label'] . '» تکمیل شده است.';
            }
        }
        if ($vals) {
            $answers[$f['id']] = $f['kind'] === 'select' ? $vals[0] : $vals;
        }
    }

    $addons = [];
    $raw_addons = is_array($in['addons'] ?? null) ? $in['addons'] : [];
    foreach ($cfg['addons'] as $a) {
        if (!in_array($a['id'], $raw_addons, true) || !cd_reg_applies($a, $type_code)) {
            continue;
        }
        if (cd_reg_full($a['capacity'], $counts['addons'][$a['id']] ?? 0)) {
            $errors['addons'] = 'ظرفیت «' . $a['title'] . '» تکمیل شده است.';
            continue;
        }
        $addons[] = $a['id'];
    }

    return [$errors, [
        'type_code' => $type_code, 'first_name' => $first, 'last_name' => $last, 'mobile' => $mobile,
        'email' => $email, 'organization' => $org, 'answers' => $answers, 'addons' => $addons,
    ]];
}

/** آیا این موبایل در همین رویداد ثبت‌نام فعال یا شرکت‌کننده دارد؟ */
function cd_reg_duplicate($event_id, $mobile) {
    global $wpdb;
    $reg = $wpdb->get_var($wpdb->prepare(
        "SELECT code FROM " . cd_table('registrations') . " WHERE event_id = %d AND mobile = %s AND status NOT IN ('rejected','expired') LIMIT 1",
        $event_id,
        $mobile
    ));
    if ($reg) {
        return true;
    }
    return (bool) $wpdb->get_var($wpdb->prepare(
        'SELECT id FROM ' . cd_table('attendees') . ' WHERE event_id = %d AND mobile = %s LIMIT 1',
        $event_id,
        $mobile
    ));
}

/**
 * ثبت یک فرم. خروجی آرایه‌ای برای صفحه:
 * ['state' => 'invalid'|'duplicate'|'closed'|'created', ...].
 */
function cd_reg_submit(array $page, array $in) {
    global $wpdb;
    $eid = (int) $page['event_id'];
    $cfg = $page['config'];

    $submit_id = strtolower((string) ($in['submit_id'] ?? ''));
    if (!cd_is_uuid($submit_id)) {
        return ['state' => 'invalid', 'errors' => ['form' => 'فرم را دوباره باز کنید.']];
    }
    // ارسال دوباره‌ی همان فرم (مثلاً بعد از قطع اینترنت) ثبت دوباره نمی‌سازد.
    $again = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE submit_id = %s', $submit_id), ARRAY_A);
    if ($again) {
        return cd_reg_public_state($page, $again);
    }

    // یک قفل برای هر رویداد تا دو نفر هم‌زمان آخرین جا را نگیرند.
    $lock = 'cd_reg_' . $eid;
    $wpdb->get_var($wpdb->prepare('SELECT GET_LOCK(%s, 10)', $lock));
    try {
        cd_reg_expire_holds($eid);
        $counts = cd_reg_counts($eid);
        if (cd_reg_page_state($page, $counts) !== 'open') {
            return ['state' => 'closed'];
        }
        [$errors, $r] = cd_reg_validate($cfg, $in, $counts);
        if ($errors) {
            return ['state' => 'invalid', 'errors' => $errors];
        }
        if (cd_reg_duplicate($eid, $r['mobile'])) {
            return ['state' => 'duplicate', 'masked' => cd_reg_mask_mobile($r['mobile'])];
        }
        [$online, $onsite] = cd_reg_amounts($cfg, $r['type_code'], $r['addons']);
        $method = $online > 0 ? $cfg['payment']['method'] : '';
        $hold = null;
        if ($online > 0) {
            $status = 'pending_payment';
            $minutes = $method === 'gateway' ? CD_REG_GATEWAY_HOLD : $cfg['payment']['hold_hours'] * 60;
            $hold = gmdate('Y-m-d H:i:s', time() + $minutes * 60);
        } else {
            $status = $cfg['list_mode'] === 'approval' ? 'pending_approval' : 'confirmed';
        }
        do {
            $code = cd_reg_new_code();
        } while ($wpdb->get_var($wpdb->prepare('SELECT id FROM ' . cd_table('registrations') . ' WHERE code = %s', $code)));
        $now = cd_now();
        $wpdb->insert(cd_table('registrations'), [
            'event_id' => $eid,
            'code' => $code,
            'submit_id' => $submit_id,
            'status' => $status,
            'type_code' => $r['type_code'],
            'first_name' => $r['first_name'],
            'last_name' => $r['last_name'],
            'mobile' => $r['mobile'],
            'email' => $r['email'],
            'organization' => $r['organization'],
            'answers' => wp_json_encode((object) $r['answers']),
            'addons' => wp_json_encode($r['addons']),
            'amount_online' => $online,
            'amount_onsite' => $onsite,
            'pay_method' => $method,
            'hold_until' => $hold,
            'ip' => cd_client_ip(),
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $id = (int) $wpdb->insert_id;
    } finally {
        $wpdb->get_var($wpdb->prepare('SELECT RELEASE_LOCK(%s)', $lock));
    }
    $reg = cd_reg_get($id);
    if ($status === 'confirmed') {
        cd_reg_enter_list($page, $reg);
        $reg = cd_reg_get($id);
    }
    do_action('roydadyar_registration_status', $reg, null, $page);
    return cd_reg_public_state($page, $reg);
}

function cd_reg_get($id) {
    global $wpdb;
    return $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE id = %d', $id), ARRAY_A);
}

function cd_reg_get_by_code($code) {
    global $wpdb;
    return $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE code = %s', strtoupper((string) $code)), ARRAY_A);
}

/** تغییر وضعیت با ثبت زمان؛ تأییدشده (در حالت مستقیم یا با تأیید) وارد لیست می‌شود. */
function cd_reg_set_status(array $page, array $reg, $status, array $extra = []) {
    global $wpdb;
    $old = $reg['status'];
    $wpdb->update(cd_table('registrations'), array_merge($extra, ['status' => $status, 'updated_at' => cd_now()]), ['id' => (int) $reg['id']]);
    $reg = cd_reg_get((int) $reg['id']);
    if ($status === 'confirmed') {
        cd_reg_enter_list($page, $reg);
        $reg = cd_reg_get((int) $reg['id']);
    }
    if ($old !== $status) {
        do_action('roydadyar_registration_status', $reg, $old, $page);
    }
    return $reg;
}

/** بعد از پرداخت (درگاه یا تأیید مدیر): تأیید مدیر لازم است یا مستقیم تأیید. */
function cd_reg_after_payment(array $page, array $reg, array $extra = []) {
    $next = $page['config']['list_mode'] === 'approval' ? 'pending_approval' : 'confirmed';
    return cd_reg_set_status($page, $reg, $next, array_merge($extra, ['hold_until' => null]));
}

/**
 * ثبت‌نامِ تأییدشده را شرکت‌کننده‌ی رویدادیار می‌کند (مگر حالت «جدا»): با کارت و شماره، ستون‌های اضافه،
 * وعده‌های گزینه‌ها و مبلغ روز اجرا. دوباره صدا زدن چیزی تکراری نمی‌سازد.
 */
function cd_reg_enter_list(array $page, array $reg) {
    global $wpdb;
    $cfg = $page['config'];
    if ($cfg['list_mode'] === 'separate' || !empty($reg['attendee_id'])) {
        return;
    }
    $eid = (int) $page['event_id'];
    $types = cd_code_map('registration_types', $eid);
    if (!isset($types[$reg['type_code']])) {
        return;
    }
    $answers = (array) json_decode((string) $reg['answers'], true);
    $addon_ids = (array) json_decode((string) $reg['addons'], true);
    $extra = [];
    foreach ($cfg['custom_fields'] as $f) {
        if (!isset($answers[$f['id']])) {
            continue;
        }
        $labels = [];
        foreach ((array) $answers[$f['id']] as $v) {
            $o = array_values(array_filter($f['options'], function ($o) use ($v) {
                return $o['id'] === $v;
            }));
            $labels[] = $o ? $o[0]['label'] : (string) $v;
        }
        $extra[$f['label']] = implode('، ', $labels);
    }
    $meals = [];
    $onsite = [];
    foreach ($cfg['addons'] as $a) {
        if (!in_array($a['id'], $addon_ids, true)) {
            continue;
        }
        $extra[$a['title']] = '✓';
        if ($a['meal_code'] !== '') {
            $meals[] = $a['meal_code'];
        }
        if ($a['price_mode'] === 'onsite') {
            $onsite[] = $a['title'];
        }
    }
    $extra['کد ثبت‌نام'] = $reg['code'];

    $id = wp_generate_uuid4();
    cd_upsert_attendee($eid, [
        'id' => $id,
        'first_name' => $reg['first_name'],
        'last_name' => $reg['last_name'],
        'mobile' => $reg['mobile'],
        'email' => $reg['email'],
        'organization' => $reg['organization'],
        'registration_type_id' => $types[$reg['type_code']],
        'role_id' => null,
        'extra' => $extra,
        'extra_meals' => implode(',', array_unique($meals)),
        'onsite_due' => (int) $reg['amount_onsite'],
        'onsite_note' => implode('، ', $onsite),
        'reg_code' => $reg['code'],
    ], 'register');
    $serial = (int) $wpdb->get_var($wpdb->prepare(
        'SELECT MAX(serial) FROM ' . cd_table('cards') . ' WHERE event_id = %d AND is_reserve = 0',
        $eid
    )) + 1;
    $wpdb->insert(cd_table('cards'), [
        'token' => cd_random_token(16),
        'event_id' => $eid,
        'attendee_id' => $id,
        'serial' => $serial,
        'is_reserve' => 0,
        'created_at' => cd_now(),
    ]);
    $wpdb->update(cd_table('registrations'), ['attendee_id' => $id], ['id' => (int) $reg['id']]);
    // گوشی‌ها با همگام‌سازی بعدی لیست را دوباره می‌گیرند.
    cd_bump_config($eid);
}

/** آنچه صفحه درباره‌ی یک ثبت‌نام نشان می‌دهد (بدون اطلاعات خصوصی دیگران). */
function cd_reg_public_state(array $page, array $reg) {
    global $wpdb;
    $cfg = $page['config'];
    $out = [
        'state' => 'created',
        'status' => $reg['status'],
        'status_label' => cd_reg_statuses()[$reg['status']] ?? $reg['status'],
        'code' => $reg['code'],
        'key' => cd_reg_key($reg['code']),
        'name' => trim($reg['first_name'] . ' ' . $reg['last_name']),
        'mobile' => cd_reg_mask_mobile($reg['mobile']),
        'type' => $reg['type_code'],
        'amount_online' => (int) $reg['amount_online'],
        'amount_onsite' => (int) $reg['amount_onsite'],
        'pay_method' => $reg['pay_method'],
        'has_proof' => $reg['pay_tracking'] !== '' || $reg['receipt_file'] !== '',
        'reject_reason' => $reg['reject_reason'],
        'addons' => (array) json_decode((string) $reg['addons'], true),
        'hold_until' => $reg['hold_until'] ? cd_iso($reg['hold_until']) : null,
    ];
    if ($reg['status'] === 'confirmed' && $cfg['success']['show_personal_link'] && $reg['attendee_id']) {
        $token = $wpdb->get_var($wpdb->prepare(
            'SELECT token FROM ' . cd_table('cards') . ' WHERE attendee_id = %s LIMIT 1',
            $reg['attendee_id']
        ));
        $event = cd_get_event((int) $page['event_id']);
        if ($token && $event) {
            $out['personal_url'] = untrailingslashit($event['base_url'] ?: home_url()) . '/c/' . $token;
        }
    }
    return $out;
}

/** محدودیت تلاش از هر IP. true یعنی مجاز. */
function cd_reg_rate_ok($bucket) {
    $key = 'cd_reg_rl_' . $bucket . '_' . md5(cd_client_ip());
    $n = (int) get_transient($key);
    if ($n >= CD_REG_RATE_LIMIT) {
        return false;
    }
    set_transient($key, $n + 1, 600);
    return true;
}
