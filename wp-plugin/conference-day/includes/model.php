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
            $updates[] = "$col = VALUES($col)";
        }
        $sql .= ' ON DUPLICATE KEY UPDATE ' . implode(', ', $updates);
    }
    return $wpdb->query($wpdb->prepare($sql, $values)) !== false;
}

function cd_attendee_out(array $r) {
    return [
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
    ];
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
function cd_is_entitled(array $meal_rules, $registration_type_id, $role_id) {
    if (in_array((int) $registration_type_id, $meal_rules['registration_type_ids'], true)) {
        return true;
    }
    return $role_id !== null && in_array((int) $role_id, $meal_rules['role_ids'], true);
}
