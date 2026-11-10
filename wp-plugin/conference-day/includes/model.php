<?php
if (!defined('ABSPATH')) {
    exit;
}

function cd_get_event_by_code($code) {
    global $wpdb;
    return $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('events') . ' WHERE code = %s', $code), ARRAY_A);
}

function cd_get_event($id) {
    global $wpdb;
    return $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('events') . ' WHERE id = %d', $id), ARRAY_A);
}

function cd_all_events() {
    global $wpdb;
    return $wpdb->get_results('SELECT * FROM ' . cd_table('events') . ' ORDER BY start_date DESC, id DESC', ARRAY_A);
}

function cd_bump_config($event_id) {
    global $wpdb;
    $wpdb->query($wpdb->prepare(
        'UPDATE ' . cd_table('events') . ' SET config_version = config_version + 1, updated_at = %s WHERE id = %d',
        cd_now(),
        $event_id
    ));
}

/** نگاشت code → id برای جدول‌های نوع ثبت‌نام، نقش یا وعده. */
function cd_code_map($table, $event_id) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare('SELECT id, code FROM ' . cd_table($table) . ' WHERE event_id = %d', $event_id), ARRAY_A);
    $map = [];
    foreach ($rows as $r) {
        $map[$r['code']] = (int) $r['id'];
    }
    return $map;
}

function cd_search_key(array $a) {
    return cd_normalize(implode(' ', [
        $a['first_name'] ?? '',
        $a['last_name'] ?? '',
        $a['mobile'] ?? '',
        $a['email'] ?? '',
        $a['organization'] ?? '',
        $a['reg_code'] ?? '',
    ]));
}

/**
 * درج یا به‌روزرسانی یک شرکت‌کننده. $a باید شناسه‌های عددی نوع و نقش را داشته باشد.
 * $only_insert = true یعنی اگر بود دست نزن (برای ثبت‌نام در محل که از گوشی می‌آید).
 */
function cd_upsert_attendee($event_id, array $a, $source, $only_insert = false) {
    global $wpdb;
    $now = cd_now();
    $row = [
        'id' => strtolower($a['id']),
        'event_id' => (int) $event_id,
        'title' => cd_str($a['title'] ?? '', 64),
        'first_name' => cd_str($a['first_name'] ?? ''),
        'last_name' => cd_str($a['last_name'] ?? ''),
        'email' => sanitize_email((string) ($a['email'] ?? '')),
        'mobile' => cd_normalize_mobile($a['mobile'] ?? ''),
        'organization' => cd_str($a['organization'] ?? ''),
        'country' => cd_str($a['country'] ?? '', 64),
        'registration_type_id' => (int) $a['registration_type_id'],
        'presentation_kind' => cd_str($a['presentation_kind'] ?? '', 16),
        'role_id' => isset($a['role_id']) && $a['role_id'] ? (int) $a['role_id'] : null,
        'source' => $source,
        // null یعنی «طبق تنظیم رویداد»؛ ستون «اشتراک اطلاعات تماس» اکسل برای هر نفر مقدم است.
        'share_contact' => isset($a['share_contact']) && $a['share_contact'] !== null && $a['share_contact'] !== '' ? (int) (bool) $a['share_contact'] : null,
        'website' => esc_url_raw(cd_str($a['website'] ?? '', 255)),
        'created_at' => $now,
        'updated_at' => $now,
    ];
    // ستون‌های دیگر اکسل ورود، برای متن‌های دلخواه کارت. ثبت‌نام در محل این را نمی‌فرستد و چیزی را پاک نمی‌کند.
    if (array_key_exists('extra', $a)) {
        $extra = cd_sanitize_extra($a['extra']);
        $row['extra'] = $extra ? wp_json_encode($extra) : null;
    }
    foreach (['extra_meals', 'onsite_note', 'reg_code'] as $k) {
        if (array_key_exists($k, $a)) {
            $row[$k] = cd_str($a[$k], $k === 'extra_meals' ? 1024 : 255);
        }
    }
    if (array_key_exists('onsite_due', $a)) {
        $row['onsite_due'] = max(0, (int) $a['onsite_due']);
    }
    $row['search_key'] = cd_search_key($row);

    $table = cd_table('attendees');
    $cols = array_keys($row);
    $placeholders = [];
    $values = [];
    foreach ($row as $k => $v) {
        if ($v === null) {
            $placeholders[] = 'NULL';
        } else {
            $placeholders[] = is_int($v) ? '%d' : '%s';
            $values[] = $v;
        }
    }
    $sql = "INSERT INTO $table (" . implode(',', $cols) . ') VALUES (' . implode(',', $placeholders) . ')';
    if ($only_insert) {
        $sql = str_replace('INSERT INTO', 'INSERT IGNORE INTO', $sql);
    } else {
        $updates = [];
        foreach ($cols as $col) {
            if (in_array($col, ['id', 'event_id', 'created_at', 'source'], true)) {
                continue;
            }
            // خانه‌ی خالی اکسل اطلاعاتی را که نیروها روز اجرا تکمیل کرده‌اند پاک نمی‌کند.
            if (in_array($col, ['first_name', 'last_name', 'mobile', 'email'], true)) {
                $updates[] = "$col = IF(VALUES($col) = '', $col, VALUES($col))";
            } else {
                $updates[] = "$col = VALUES($col)";
            }
        }
        $sql .= ' ON DUPLICATE KEY UPDATE ' . implode(', ', $updates);
    }
    return $wpdb->query($wpdb->prepare($sql, $values)) !== false;
}

function cd_split_codes($s) {
    return array_values(array_filter(explode(',', (string) $s), 'strlen'));
}

/** ستون‌های اضافه‌ی یک نفر: حداکثر ۵۰ ستون، نام ستون ۱۰۰ و مقدار ۵۰۰ نویسه. */
function cd_sanitize_extra($in) {
    if (!is_array($in)) {
        return [];
    }
    $out = [];
    foreach ($in as $k => $v) {
        $k = cd_str($k, 100);
        $v = cd_str($v, 500);
        if ($k === '' || $v === '') {
            continue;
        }
        $out[$k] = $v;
        if (count($out) >= 50) {
            break;
        }
    }
    return $out;
}

/** $with_extra فقط برای اپ مدیریت؛ گوشی نیروها ستون‌های اضافه را لازم ندارد. */
function cd_attendee_out(array $r, $with_extra = false) {
    $out = [
        'id' => $r['id'],
        'title' => $r['title'],
        'first_name' => $r['first_name'],
        'last_name' => $r['last_name'],
        'email' => $r['email'],
        'mobile' => $r['mobile'],
        'organization' => $r['organization'],
        'country' => $r['country'],
        'registration_type_id' => (int) $r['registration_type_id'],
        'presentation_kind' => $r['presentation_kind'],
        'role_id' => $r['role_id'] !== null ? (int) $r['role_id'] : null,
        'source' => $r['source'],
        'share_contact' => isset($r['share_contact']) && $r['share_contact'] !== null ? (bool) $r['share_contact'] : null,
        'website' => $r['website'] ?? '',
        // از صفحه‌ی ثبت‌نام: وعده‌های گزینه‌های اضافه (کد وعده)، مبلغ تسویه در روز اجرا، کد ثبت‌نام.
        'extra_meals' => cd_split_codes($r['extra_meals'] ?? ''),
        'onsite_due' => (int) ($r['onsite_due'] ?? 0),
        'onsite_note' => $r['onsite_note'] ?? '',
        'reg_code' => $r['reg_code'] ?? '',
    ];
    if ($with_extra) {
        $extra = !empty($r['extra']) ? json_decode($r['extra'], true) : null;
        $out['extra'] = is_array($extra) ? (object) $extra : (object) [];
    }
    return $out;
}

function cd_log_out(array $r) {
    return [
        'seq' => (int) $r['seq'],
        'uuid' => $r['uuid'],
        'kind' => $r['kind'],
        'device_id' => $r['device_id'] !== null ? (int) $r['device_id'] : null,
        'staff_id' => $r['staff_id'] !== null ? (int) $r['staff_id'] : null,
        'card_token' => $r['card_token'],
        'attendee_id' => $r['attendee_id'],
        'meal_id' => $r['meal_id'] !== null ? (int) $r['meal_id'] : null,
        'payload' => $r['payload'] ? json_decode($r['payload'], true) : null,
        'flag' => $r['flag'],
        'device_time' => cd_iso($r['device_time']),
        'received_at' => cd_iso($r['received_at']),
    ];
}

/** پیکربندی رویداد: نوع‌ها، نقش‌ها، وعده‌ها با قانون‌ها، و برنامه. */
function cd_event_config($event_id) {
    global $wpdb;
    $types = $wpdb->get_results($wpdb->prepare('SELECT id, code, name FROM ' . cd_table('registration_types') . ' WHERE event_id = %d ORDER BY id', $event_id), ARRAY_A);
    $roles = $wpdb->get_results($wpdb->prepare('SELECT id, code, name FROM ' . cd_table('roles') . ' WHERE event_id = %d ORDER BY id', $event_id), ARRAY_A);
    $meals = $wpdb->get_results($wpdb->prepare('SELECT id, code, day, name, sort FROM ' . cd_table('meals') . ' WHERE event_id = %d ORDER BY day, sort, id', $event_id), ARRAY_A);
    $sessions = $wpdb->get_results($wpdb->prepare('SELECT id, day, start_time, end_time, title, hall, kind FROM ' . cd_table('sessions') . ' WHERE event_id = %d ORDER BY day, start_time, sort, id', $event_id), ARRAY_A);

    $meal_ids = array_map(function ($m) {
        return (int) $m['id'];
    }, $meals);
    $rules_by_meal = [];
    if ($meal_ids) {
        $in = implode(',', $meal_ids);
        $rules = $wpdb->get_results('SELECT meal_id, registration_type_id, role_id FROM ' . cd_table('meal_rules') . " WHERE meal_id IN ($in)", ARRAY_A);
        foreach ($rules as $r) {
            $mid = (int) $r['meal_id'];
            if (!isset($rules_by_meal[$mid])) {
                $rules_by_meal[$mid] = ['registration_type_ids' => [], 'role_ids' => []];
            }
            if ($r['registration_type_id'] !== null) {
                $rules_by_meal[$mid]['registration_type_ids'][] = (int) $r['registration_type_id'];
            }
            if ($r['role_id'] !== null) {
                $rules_by_meal[$mid]['role_ids'][] = (int) $r['role_id'];
            }
        }
    }

    $int = function ($rows) {
        return array_map(function ($r) {
            $r['id'] = (int) $r['id'];
            return $r;
        }, $rows);
    };

    $meals_out = [];
    foreach ($meals as $m) {
        $mid = (int) $m['id'];
        $meals_out[] = [
            'id' => $mid,
            'code' => $m['code'],
            'day' => $m['day'],
            'name' => $m['name'],
            'rules' => $rules_by_meal[$mid] ?? ['registration_type_ids' => [], 'role_ids' => []],
        ];
    }

    return [
        'registration_types' => $int($types),
        'roles' => $int($roles),
        'meals' => $meals_out,
        'sessions' => array_map(function ($s) {
            return [
                'id' => (int) $s['id'],
                'day' => $s['day'],
                'start_time' => substr($s['start_time'], 0, 5),
                'end_time' => $s['end_time'] ? substr($s['end_time'], 0, 5) : null,
                'title' => $s['title'],
                'hall' => $s['hall'],
                'kind' => $s['kind'],
            ];
        }, $sessions),
    ];
}

/** تنظیم‌های پیش‌فرض رویداد (IdentifyMode، QrBehavior، خط سازنده). */
function cd_default_settings() {
    return [
        'identify_mode' => 'scan',
        'qr_behavior' => 'person',
        'qr_redirect_url' => '',
        'contact_fields' => ['name' => true, 'organization' => true, 'email' => false, 'mobile' => false, 'country' => false],
        'show_maker_credit' => true,
    ];
}

/** تنظیم‌های ذخیره‌شده‌ی رویداد، با پیش‌فرض برای کلیدهای نبوده. */
function cd_event_settings(array $e) {
    $s = cd_default_settings();
    $saved = !empty($e['settings']) ? json_decode($e['settings'], true) : null;
    if (is_array($saved)) {
        $s = cd_sanitize_settings($saved, $s);
    }
    return $s;
}

/** فقط کلیدها و مقدارهای شناخته‌شده پذیرفته می‌شوند. */
function cd_sanitize_settings(array $in, ?array $base = null) {
    $s = $base ?? cd_default_settings();
    if (in_array($in['identify_mode'] ?? null, ['scan', 'card', 'none'], true)) {
        $s['identify_mode'] = $in['identify_mode'];
    }
    if (in_array($in['qr_behavior'] ?? null, ['person', 'redirect', 'vcard'], true)) {
        $s['qr_behavior'] = $in['qr_behavior'];
    }
    if (isset($in['qr_redirect_url'])) {
        $url = esc_url_raw(trim((string) $in['qr_redirect_url']), ['http', 'https']);
        $s['qr_redirect_url'] = $url;
    }
    if (isset($in['contact_fields']) && is_array($in['contact_fields'])) {
        foreach (array_keys($s['contact_fields']) as $k) {
            if (array_key_exists($k, $in['contact_fields'])) {
                $s['contact_fields'][$k] = (bool) $in['contact_fields'][$k];
            }
        }
    }
    if (array_key_exists('show_maker_credit', $in)) {
        $s['show_maker_credit'] = (bool) $in['show_maker_credit'];
    }
    return $s;
}

function cd_event_out(array $e) {
    return [
        'id' => (int) $e['id'],
        'code' => $e['code'],
        'name' => $e['name'],
        'start_date' => $e['start_date'],
        'end_date' => $e['end_date'],
        'base_url' => $e['base_url'],
        'base_url_locked' => (bool) $e['base_url_locked'],
        'config_version' => (int) $e['config_version'],
        'settings' => cd_event_settings($e),
    ];
}

/** آیا نوع ثبت‌نام یا نقش این فرد شامل این وعده است؟ */
function cd_is_entitled(array $meal_rules, $registration_type_id, $role_id, $meal_code = null, $extra_meals = '') {
    if (in_array((int) $registration_type_id, $meal_rules['registration_type_ids'], true)) {
        return true;
    }
    // گزینه‌ی اضافه‌ی صفحه‌ی ثبت‌نام (مثلاً «ناهار روز اول») که به این وعده وصل است.
    if ($meal_code !== null && in_array($meal_code, cd_split_codes($extra_meals), true)) {
        return true;
    }
    return $role_id !== null && in_array((int) $role_id, $meal_rules['role_ids'], true);
}

/** قالب کارت از اپ مدیریت: فقط کلیدهای شناخته‌شده با مقدارهای در بازه. */
function cd_sanitize_card_template(array $t) {
    $clean = [];
    foreach (['width_mm', 'height_mm', 'name_x', 'name_y', 'name_size', 'qr_x', 'qr_y', 'qr_size_mm'] as $k) {
        if (isset($t[$k]) && is_numeric($t[$k])) {
            $clean[$k] = (float) $t[$k];
        }
    }
    if (isset($t['name_color']) && preg_match('/^#?[0-9a-fA-F]{6}$/', (string) $t['name_color'])) {
        $clean['name_color'] = ltrim((string) $t['name_color'], '#');
    }
    foreach (['show_role', 'show_serial', 'sheet_mode', 'auto_rotate'] as $k) {
        if (array_key_exists($k, $t)) {
            $clean[$k] = (bool) $t[$k];
        }
    }
    // چیدن روی بوم چاپ: اندازه‌ی بوم و حاشیه (میلی‌متر)، و جهت برگشتن برگ در چاپ دورو.
    foreach (['sheet_w', 'sheet_h', 'sheet_margin'] as $k) {
        if (isset($t[$k]) && is_numeric($t[$k]) && (float) $t[$k] >= 0 && (float) $t[$k] <= 2000) {
            $clean[$k] = (float) $t[$k];
        }
    }
    if (isset($t['duplex']) && in_array($t['duplex'], ['long', 'short'], true)) {
        $clean['duplex'] = $t['duplex'];
    }
    if (isset($t['sheet_preset']) && preg_match('/^[A-Za-z0-9]{1,12}$/', (string) $t['sheet_preset'])) {
        $clean['sheet_preset'] = (string) $t['sheet_preset'];
    }
    // سه پرسش اول «کارت‌ها»: یک‌رو یا دورو، QR، سمت QR.
    foreach (['setup_done', 'double_sided', 'qr_enabled'] as $k) {
        if (array_key_exists($k, $t)) {
            $clean[$k] = (bool) $t[$k];
        }
    }
    if (isset($t['qr_side']) && in_array($t['qr_side'], ['front', 'back'], true)) {
        $clean['qr_side'] = $t['qr_side'];
    }
    if (isset($t['texts']) && is_array($t['texts'])) {
        $clean['texts'] = [];
        foreach (array_slice(array_values($t['texts']), 0, 40) as $x) {
            $one = is_array($x) ? cd_sanitize_card_text($x) : null;
            if ($one) {
                $clean['texts'][] = $one;
            }
        }
    }
    return $clean;
}

/** یک متن کارت. منبع: ثابت، فیلد سامانه، ستون اکسل شرکت‌کننده‌ها، یا ستون فایل جدا. */
function cd_sanitize_card_text(array $x) {
    $num = function ($k, $min, $max, $def) use ($x) {
        return isset($x[$k]) && is_numeric($x[$k]) ? max($min, min($max, (float) $x[$k])) : $def;
    };
    $id = (string) ($x['id'] ?? '');
    if (!preg_match('/^[A-Za-z0-9_-]{1,40}$/', $id)) {
        return null;
    }
    $source = in_array($x['source'] ?? '', ['static', 'field', 'column', 'file'], true) ? $x['source'] : 'static';
    $font = (string) ($x['font'] ?? '');
    $color = (string) ($x['color'] ?? '');
    return [
        'id' => $id,
        'side' => ($x['side'] ?? '') === 'back' ? 'back' : 'front',
        'source' => $source,
        'value' => cd_str($x['value'] ?? '', 200),
        // پیشوند و پسوند فاصله‌ی کناری‌شان را نگه می‌دارند («میز ۱۲»).
        'prefix' => cd_affix($x['prefix'] ?? ''),
        'suffix' => cd_affix($x['suffix'] ?? ''),
        'x' => $num('x', -50, 150, 50),
        'y' => $num('y', -50, 150, 50),
        'width_mm' => $num('width_mm', 1, 1000, 70),
        'align' => in_array($x['align'] ?? '', ['right', 'center', 'left'], true) ? $x['align'] : 'center',
        'font' => preg_match('/^[A-Za-z0-9_-]{1,64}$/', $font) ? $font : 'vazir-bold',
        'size' => $num('size', 1, 200, 12),
        'min_size' => $num('min_size', 1, 200, 8),
        'color' => preg_match('/^#?[0-9a-fA-F]{6}$/', $color) ? ltrim($color, '#') : '10141A',
        'max_lines' => (int) $num('max_lines', 1, 5, 1),
        'on_reserve' => !empty($x['on_reserve']),
    ];
}

function cd_affix($v) {
    if (!is_scalar($v)) {
        return '';
    }
    // wp_strip_all_tags فاصله‌ی دو سر را برمی‌دارد؛ strip_tags نه.
    $s = preg_replace('/[\x00-\x1F\x7F]/u', '', strip_tags((string) $v));
    return function_exists('mb_substr') ? mb_substr((string) $s, 0, 50) : substr((string) $s, 0, 50);
}
