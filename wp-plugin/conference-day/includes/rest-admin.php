<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * API مدیریت، برای اپ دسکتاپ. احراز هویت با هدر X-Conf-Admin
 * (کلیدی که در پیشخوان وردپرس، صفحه‌ی «کنفرانس ← تنظیمات» ساخته می‌شود).
 * از هدر Authorization استفاده نمی‌شود چون بعضی هاست‌ها آن را حذف می‌کنند.
 */

function cd_admin_permission(WP_REST_Request $request) {
    $key = (string) $request->get_header('x-conf-admin');
    if ($key === '') {
        return cd_error('cd_admin_auth', 'کلید مدیریت نامعتبر است.', 401);
    }
    $given = hash('sha256', $key);
    $hash = (string) get_option('cd_admin_key_hash', '');
    if ($hash !== '' && hash_equals($hash, $given)) {
        return true;
    }
    // کلیدهای جدای گوشی مدیر؛ هر کدام در پیشخوان جدا باطل می‌شود (M1).
    $keys = get_option('cd_mobile_keys', []);
    if (is_array($keys)) {
        foreach ($keys as $id => $k) {
            if (empty($k['revoked']) && hash_equals((string) $k['hash'], $given)) {
                if (empty($k['last_used']) || strtotime($k['last_used'] . ' UTC') < time() - 300) {
                    $keys[$id]['last_used'] = cd_now();
                    update_option('cd_mobile_keys', $keys, false);
                }
                return true;
            }
        }
    }
    return cd_error('cd_admin_auth', 'کلید مدیریت نامعتبر است.', 401);
}

function cd_event_from_request(WP_REST_Request $request) {
    $event = cd_get_event_by_code((string) $request['code']);
    if (!$event) {
        return cd_error('cd_no_event', 'رویداد پیدا نشد.', 404);
    }
    return $event;
}

add_action('rest_api_init', function () {
    $code = '(?P<code>[A-Za-z0-9_-]{1,64})';
    $admin = 'cd_admin_permission';

    register_rest_route(CD_NS, '/admin/ping', [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => function () {
            return ['ok' => true, 'version' => CD_VERSION, 'server_time' => gmdate('c')];
        },
    ]);

    register_rest_route(CD_NS, '/admin/events', [
        [
            'methods' => 'GET',
            'permission_callback' => $admin,
            'callback' => function () {
                return array_map('cd_event_out', cd_all_events());
            },
        ],
        [
            'methods' => 'POST',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_upsert_event',
        ],
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/config", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_config',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/staff", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_staff',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/attendees", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_attendees',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/reserve-cards", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_reserve_cards',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/lock", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            global $wpdb;
            $event = cd_event_from_request($request);
            if (is_wp_error($event)) {
                return $event;
            }
            $locked = $request->get_param('locked');
            $locked = $locked === null ? true : (bool) $locked;
            $wpdb->update(cd_table('events'), ['base_url_locked' => $locked ? 1 : 0, 'updated_at' => cd_now()], ['id' => (int) $event['id']]);
            return cd_event_out(cd_get_event((int) $event['id']));
        },
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/snapshot", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            $event = cd_event_from_request($request);
            if (is_wp_error($event)) {
                return $event;
            }
            $snap = cd_build_snapshot($event, true);
            $t = !empty($event['card_template']) ? json_decode($event['card_template'], true) : null;
            $snap['card_template'] = is_array($t) ? $t : null;
            return $snap;
        },
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/report", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            $event = cd_event_from_request($request);
            return is_wp_error($event) ? $event : cd_build_report($event);
        },
    ]);

    $aid = '(?P<attendee>[0-9a-fA-F-]{36})';

    // تاریخچه‌ی یک نفر (PersonTimeline) برای تب «افراد» اپ مدیریت.
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/timeline", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_timeline',
    ]);

    // لغو پذیرش از اپ مدیریت؛ مثل رخداد checkin_undo گوشی در دفتر ثبت می‌شود.
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/checkin-undo", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_admin_undo_checkin',
    ]);

    // قالب کارت روی سرور تا اپ مدیریت ویندوز و موبایل یک قالب ببینند.
    register_rest_route(CD_NS, "/admin/events/$code/card-template", [
        [
            'methods' => 'GET',
            'permission_callback' => $admin,
            'callback' => function (WP_REST_Request $request) {
                $event = cd_event_from_request($request);
                if (is_wp_error($event)) {
                    return $event;
                }
                $t = !empty($event['card_template']) ? json_decode($event['card_template'], true) : null;
                return ['template' => is_array($t) ? $t : null];
            },
        ],
        [
            'methods' => 'POST',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_save_card_template',
        ],
    ]);

    register_rest_route(CD_NS, '/admin/devices/(?P<id>\d+)/revoke', [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            global $wpdb;
            $n = $wpdb->update(cd_table('devices'), ['revoked' => 1], ['id' => (int) $request['id']]);
            return ['revoked' => (bool) $n];
        },
    ]);
});

function cd_valid_date($s) {
    return is_string($s) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $s) === 1;
}

function cd_rest_upsert_event(WP_REST_Request $request) {
    global $wpdb;
    $code = (string) $request->get_param('code');
    $name = cd_str($request->get_param('name'));
    $start = $request->get_param('start_date');
    $end = $request->get_param('end_date');
    $base = (string) $request->get_param('base_url');

    if (!cd_is_code($code)) {
        return cd_error('cd_bad_code', 'کد رویداد فقط حروف لاتین، رقم، - و _ می‌تواند باشد.');
    }
    if ($name === '') {
        return cd_error('cd_bad_name', 'نام رویداد لازم است.');
    }
    if (($start !== null && $start !== '' && !cd_valid_date($start)) || ($end !== null && $end !== '' && !cd_valid_date($end))) {
        return cd_error('cd_bad_date', 'تاریخ باید به شکل YYYY-MM-DD (میلادی) باشد.');
    }
    $base = $base === '' ? untrailingslashit(home_url()) : untrailingslashit(esc_url_raw($base));
    if (strpos($base, 'https://') !== 0 && strpos($base, 'http://') !== 0) {
        return cd_error('cd_bad_base_url', 'آدرس پایه نامعتبر است.');
    }

    $existing = cd_get_event_by_code($code);
    $now = cd_now();
    $data = [
        'name' => $name,
        'start_date' => $start ?: null,
        'end_date' => $end ?: null,
        'base_url' => $base,
        'updated_at' => $now,
    ];
    if ($existing) {
        if ((int) $existing['base_url_locked'] && $existing['base_url'] !== $base) {
            return cd_error('cd_base_url_locked', 'آدرس پایه قفل است چون کارت‌ها ساخته شده‌اند. اول قفل را بردارید.', 409);
        }
        $wpdb->update(cd_table('events'), $data, ['id' => (int) $existing['id']]);
        cd_bump_config((int) $existing['id']);
        $id = (int) $existing['id'];
    } else {
        $data['code'] = $code;
        $data['created_at'] = $now;
        $wpdb->insert(cd_table('events'), $data);
        $id = (int) $wpdb->insert_id;
    }
    return cd_event_out(cd_get_event($id));
}

/** upsert نوع‌ها و نقش‌ها و وعده‌ها با کد؛ برنامه (sessions) اگر فرستاده شود کامل جایگزین می‌شود. */
function cd_rest_config(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $errors = [];

    foreach (['registration_types' => 'registration_types', 'roles' => 'roles'] as $param => $table) {
        $items = $request->get_param($param);
        if (!is_array($items)) {
            continue;
        }
        foreach ($items as $i => $it) {
            $c = $it['code'] ?? null;
            $n = cd_str($it['name'] ?? '');
            if (!cd_is_code($c) || $n === '') {
                $errors[] = ['section' => $param, 'index' => $i, 'reason' => 'bad_code_or_name'];
                continue;
            }
            $wpdb->query($wpdb->prepare(
                'INSERT INTO ' . cd_table($table) . ' (event_id, code, name) VALUES (%d, %s, %s) ON DUPLICATE KEY UPDATE name = VALUES(name)',
                $eid,
                $c,
                $n
            ));
        }
    }

    $meals = $request->get_param('meals');
    if (is_array($meals)) {
        $types = cd_code_map('registration_types', $eid);
        $roles = cd_code_map('roles', $eid);
        foreach ($meals as $i => $m) {
            $c = $m['code'] ?? null;
            $n = cd_str($m['name'] ?? '');
            $day = $m['day'] ?? null;
            if (!cd_is_code($c) || $n === '' || ($day !== null && $day !== '' && !cd_valid_date($day))) {
                $errors[] = ['section' => 'meals', 'index' => $i, 'reason' => 'bad_meal'];
                continue;
            }
            $wpdb->query($wpdb->prepare(
                'INSERT INTO ' . cd_table('meals') . ' (event_id, code, day, name, sort) VALUES (%d, %s, ' . ($day ? '%s' : 'NULL') . ', %s, %d)
                 ON DUPLICATE KEY UPDATE day = VALUES(day), name = VALUES(name), sort = VALUES(sort)',
                array_values(array_filter([$eid, $c, $day ?: null, $n, (int) ($m['sort'] ?? $i)], function ($v) {
                    return $v !== null;
                }))
            ));
            $meal_id = (int) $wpdb->get_var($wpdb->prepare('SELECT id FROM ' . cd_table('meals') . ' WHERE event_id = %d AND code = %s', $eid, $c));
            $wpdb->delete(cd_table('meal_rules'), ['meal_id' => $meal_id]);
            foreach ((array) ($m['registration_types'] ?? []) as $tc) {
                if (isset($types[$tc])) {
                    $wpdb->insert(cd_table('meal_rules'), ['meal_id' => $meal_id, 'registration_type_id' => $types[$tc]]);
                } else {
                    $errors[] = ['section' => 'meals', 'index' => $i, 'reason' => 'unknown_registration_type', 'code' => $tc];
                }
            }
            foreach ((array) ($m['roles'] ?? []) as $rc) {
                if (isset($roles[$rc])) {
                    $wpdb->insert(cd_table('meal_rules'), ['meal_id' => $meal_id, 'role_id' => $roles[$rc]]);
                } else {
                    $errors[] = ['section' => 'meals', 'index' => $i, 'reason' => 'unknown_role', 'code' => $rc];
                }
            }
        }
    }

    $sessions = $request->get_param('sessions');
    if (is_array($sessions)) {
        $wpdb->query('START TRANSACTION');
        $wpdb->delete(cd_table('sessions'), ['event_id' => $eid]);
        foreach ($sessions as $i => $s) {
            $day = $s['day'] ?? '';
            $st = $s['start_time'] ?? '';
            $et = $s['end_time'] ?? '';
            $title = cd_str($s['title'] ?? '', 255);
            if (!cd_valid_date($day) || !preg_match('/^\d{1,2}:\d{2}$/', (string) $st) || $title === '') {
                $errors[] = ['section' => 'sessions', 'index' => $i, 'reason' => 'bad_session'];
                continue;
            }
            $row = [
                'event_id' => $eid,
                'day' => $day,
                'start_time' => $st . ':00',
                'title' => $title,
                'hall' => cd_str($s['hall'] ?? ''),
                'kind' => cd_str($s['kind'] ?? '', 32),
                'sort' => $i,
            ];
            if (preg_match('/^\d{1,2}:\d{2}$/', (string) $et)) {
                $row['end_time'] = $et . ':00';
            }
            $wpdb->insert(cd_table('sessions'), $row);
        }
        $wpdb->query('COMMIT');
    }

    $settings = $request->get_param('settings');
    if (is_array($settings)) {
        $clean = cd_sanitize_settings($settings, cd_event_settings($event));
        $wpdb->update(cd_table('events'), ['settings' => wp_json_encode($clean), 'updated_at' => cd_now()], ['id' => $eid]);
    }

    cd_bump_config($eid);
    return array_merge(['errors' => $errors, 'settings' => cd_event_settings(cd_get_event($eid))], cd_event_config($eid));
}

/** تاریخچه‌ی یک نفر به ترتیب زمان، با نام وعده، دستگاه، نیرو و توضیح مورد مشکوک. */
function cd_rest_timeline(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $rows = $wpdb->get_results($wpdb->prepare(
        'SELECT l.seq, l.kind, l.flag, l.device_time, l.meal_id, m.name AS meal_name, d.label AS device_label, s.name AS staff_name
         FROM ' . cd_table('event_log') . ' l
         LEFT JOIN ' . cd_table('meals') . ' m ON m.id = l.meal_id
         LEFT JOIN ' . cd_table('devices') . ' d ON d.id = l.device_id
         LEFT JOIN ' . cd_table('staff') . ' s ON s.id = l.staff_id
         WHERE l.event_id = %d AND l.attendee_id = %s
         ORDER BY l.seq',
        (int) $event['id'],
        strtolower((string) $request['attendee'])
    ), ARRAY_A);
    return [
        'events' => array_map(function ($r) {
            return [
                'seq' => (int) $r['seq'],
                'kind' => $r['kind'],
                'meal_name' => $r['meal_name'],
                'device_time' => cd_iso($r['device_time']),
                'device_label' => $r['device_label'] ?? 'اپ مدیریت',
                'staff' => $r['staff_name'],
                'flag' => $r['flag'],
                'flag_label' => $r['flag'] ? (CD_FLAG_LABELS[$r['flag']] ?? $r['flag']) : null,
            ];
        }, $rows),
        'server_time' => gmdate('c'),
    ];
}

function cd_rest_admin_undo_checkin(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $aid = strtolower((string) $request['attendee']);
    $exists = $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d', $aid, $eid));
    if (!(int) $exists) {
        return cd_error('cd_no_attendee', 'این نفر در این رویداد نیست.', 404);
    }
    $now = cd_now();
    $wpdb->insert(cd_table('event_log'), [
        'uuid' => wp_generate_uuid4(),
        'event_id' => $eid,
        'kind' => 'checkin_undo',
        'attendee_id' => $aid,
        'device_time' => $now,
        'received_at' => $now,
    ]);
    return ['ok' => true, 'seq' => (int) $wpdb->insert_id];
}

/** قالب کارت (نوع کارت، QR، متن‌ها، بوم چاپ). مسیر تصویر طرح و فایل اکسل جدا محلی است و ذخیره نمی‌شود. */
function cd_rest_save_card_template(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $t = $request->get_param('template');
    if (!is_array($t)) {
        return cd_error('cd_bad_template', 'قالب کارت لازم است.');
    }
    $clean = cd_sanitize_card_template($t);
    $wpdb->update(cd_table('events'), ['card_template' => wp_json_encode($clean), 'updated_at' => cd_now()], ['id' => (int) $event['id']]);
    return ['template' => $clean];
}

/** نیروها با نام upsert می‌شوند؛ نیرویی که در لیست نیست غیرفعال و گوشی‌هایش باطل می‌شوند. */
function cd_rest_staff(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $items = $request->get_param('staff');
    if (!is_array($items)) {
        return cd_error('cd_bad_staff', 'لیست staff لازم است.');
    }

    $existing = $wpdb->get_results($wpdb->prepare('SELECT id, name, pin_hash FROM ' . cd_table('staff') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $by_name = [];
    foreach ($existing as $s) {
        $by_name[$s['name']] = $s;
    }

    // PIN تکراری بین نیروها مجاز نیست، چون ورود فقط با PIN است.
    $pins = [];
    $errors = [];
    foreach ($items as $i => $s) {
        $pin = isset($s['pin']) ? cd_latin_digits((string) $s['pin']) : '';
        if ($pin !== '') {
            if (!preg_match('/^\d{4,8}$/', $pin)) {
                $errors[] = ['index' => $i, 'reason' => 'bad_pin'];
            } elseif (isset($pins[$pin])) {
                $errors[] = ['index' => $i, 'reason' => 'duplicate_pin'];
            } else {
                $pins[$pin] = $i;
            }
        }
        if (cd_str($s['name'] ?? '') === '') {
            $errors[] = ['index' => $i, 'reason' => 'missing_name'];
        }
    }
    if ($errors) {
        return cd_error('cd_bad_staff', 'لیست نیروها خطا دارد.', 400, ['errors' => $errors]);
    }

    // PIN جدید نباید با PIN فعلی نیروی دیگری که PIN جدید نگرفته یکی باشد.
    $names_with_new_pin = [];
    foreach ($items as $s) {
        if (!empty($s['pin'])) {
            $names_with_new_pin[cd_str($s['name'])] = true;
        }
    }
    foreach ($pins as $pin => $i) {
        foreach ($existing as $s) {
            if (isset($names_with_new_pin[$s['name']]) || $s['pin_hash'] === '') {
                continue;
            }
            if (wp_check_password($pin, $s['pin_hash'])) {
                return cd_error('cd_bad_staff', 'PIN تکراری است.', 400, ['errors' => [['index' => $i, 'reason' => 'duplicate_pin']]]);
            }
        }
    }

    $seen = [];
    foreach ($items as $s) {
        $name = cd_str($s['name']);
        $seen[$name] = true;
        $row = [
            'can_checkin' => isset($s['can_checkin']) ? (int) (bool) $s['can_checkin'] : 1,
            'can_serve' => isset($s['can_serve']) ? (int) (bool) $s['can_serve'] : 1,
            'is_admin' => isset($s['is_admin']) ? (int) (bool) $s['is_admin'] : 0,
            'active' => 1,
        ];
        if (!empty($s['pin'])) {
            $row['pin_hash'] = wp_hash_password(cd_latin_digits((string) $s['pin']));
        }
        if (isset($by_name[$name])) {
            $wpdb->update(cd_table('staff'), $row, ['id' => (int) $by_name[$name]['id']]);
        } else {
            $row['event_id'] = $eid;
            $row['name'] = $name;
            $wpdb->insert(cd_table('staff'), $row);
        }
    }
    foreach ($existing as $s) {
        if (!isset($seen[$s['name']])) {
            $wpdb->update(cd_table('staff'), ['active' => 0], ['id' => (int) $s['id']]);
            $wpdb->update(cd_table('devices'), ['revoked' => 1], ['staff_id' => (int) $s['id']]);
        }
    }

    cd_bump_config($eid);
    $out = $wpdb->get_results($wpdb->prepare(
        'SELECT id, name, can_checkin, can_serve, is_admin, active, (pin_hash <> \'\') AS has_pin FROM ' . cd_table('staff') . ' WHERE event_id = %d ORDER BY id',
        $eid
    ), ARRAY_A);
    return array_map(function ($s) {
        return [
            'id' => (int) $s['id'],
            'name' => $s['name'],
            'can_checkin' => (bool) $s['can_checkin'],
            'can_serve' => (bool) $s['can_serve'],
            'is_admin' => (bool) $s['is_admin'],
            'active' => (bool) $s['active'],
            'has_pin' => (bool) $s['has_pin'],
        ];
    }, $out);
}

/** درج یا به‌روزرسانی شرکت‌کننده‌ها همراه کارتشان؛ حداکثر ۵۰۰ ردیف در هر درخواست. */
function cd_rest_attendees(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $items = $request->get_param('attendees');
    if (!is_array($items)) {
        return cd_error('cd_bad_attendees', 'لیست attendees لازم است.');
    }
    if (count($items) > 500) {
        return cd_error('cd_too_many', 'حداکثر ۵۰۰ ردیف در هر درخواست.');
    }

    $types = cd_code_map('registration_types', $eid);
    $roles = cd_code_map('roles', $eid);
    $saved = 0;
    $errors = [];

    foreach ($items as $i => $a) {
        if (!is_array($a) || !cd_is_uuid($a['id'] ?? null)) {
            $errors[] = ['index' => $i, 'reason' => 'bad_id'];
            continue;
        }
        if (cd_str($a['first_name'] ?? '') === '' || cd_str($a['last_name'] ?? '') === '') {
            $errors[] = ['index' => $i, 'reason' => 'missing_name'];
            continue;
        }
        $tc = $a['registration_type'] ?? '';
        if (!isset($types[$tc])) {
            $errors[] = ['index' => $i, 'reason' => 'unknown_registration_type', 'code' => $tc];
            continue;
        }
        $rc = $a['role'] ?? null;
        if ($rc !== null && $rc !== '' && !isset($roles[$rc])) {
            $errors[] = ['index' => $i, 'reason' => 'unknown_role', 'code' => $rc];
            continue;
        }
        $token = $a['card_token'] ?? null;
        if ($token !== null && $token !== '' && !cd_is_card_token($token)) {
            $errors[] = ['index' => $i, 'reason' => 'bad_card_token'];
            continue;
        }
        if ($token) {
            $other = $wpdb->get_var($wpdb->prepare('SELECT event_id FROM ' . cd_table('cards') . ' WHERE token = %s', $token));
            if ($other !== null && (int) $other !== $eid) {
                $errors[] = ['index' => $i, 'reason' => 'card_token_in_other_event'];
                continue;
            }
        }

        $a['registration_type_id'] = $types[$tc];
        $a['role_id'] = ($rc !== null && $rc !== '') ? $roles[$rc] : null;
        if (!cd_upsert_attendee($eid, $a, 'import')) {
            $errors[] = ['index' => $i, 'reason' => 'db_error', 'detail' => $wpdb->last_error];
            continue;
        }
        if ($token) {
            $wpdb->query($wpdb->prepare(
                'INSERT INTO ' . cd_table('cards') . ' (token, event_id, attendee_id, serial, is_reserve, created_at) VALUES (%s, %d, %s, %d, 0, %s)
                 ON DUPLICATE KEY UPDATE attendee_id = VALUES(attendee_id), serial = VALUES(serial), is_reserve = 0',
                $token,
                $eid,
                strtolower($a['id']),
                (int) ($a['card_serial'] ?? 0),
                cd_now()
            ));
        }
        $saved++;
    }

    cd_bump_config($eid);
    return ['saved' => $saved, 'errors' => $errors];
}

function cd_rest_reserve_cards(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $cards = $request->get_param('cards');
    if (!is_array($cards)) {
        return cd_error('cd_bad_cards', 'لیست cards لازم است.');
    }
    $saved = 0;
    $errors = [];
    foreach ($cards as $i => $c) {
        $token = $c['token'] ?? null;
        if (!cd_is_card_token($token)) {
            $errors[] = ['index' => $i, 'reason' => 'bad_card_token'];
            continue;
        }
        $n = $wpdb->query($wpdb->prepare(
            'INSERT IGNORE INTO ' . cd_table('cards') . ' (token, event_id, attendee_id, serial, is_reserve, created_at) VALUES (%s, %d, NULL, %d, 1, %s)',
            $token,
            $eid,
            (int) ($c['serial'] ?? 0),
            cd_now()
        ));
        if ($n) {
            $saved++;
        }
    }
    cd_bump_config($eid);
    return ['saved' => $saved, 'errors' => $errors];
}
