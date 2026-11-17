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
        cd_admin_actor('اپ مدیریت');
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
                cd_admin_actor((string) ($k['label'] ?? 'گوشی مدیر'));
                return true;
            }
        }
    }
    return cd_error('cd_admin_auth', 'کلید مدیریت نامعتبر است.', 401);
}

/** برچسب کلیدی که درخواست فعلی با آن آمده؛ «فاعل» کارهای مدیریتی در دفتر و نیروها. */
function cd_admin_actor($set = null) {
    static $actor = '';
    if ($set !== null) {
        $actor = $set;
    }
    return $actor;
}

/** رویداد برای کارهای تغییردهنده؛ رویداد بایگانی‌شده فقط خواندنی است. */
function cd_event_for_write(WP_REST_Request $request) {
    $event = cd_event_from_request($request);
    if (!is_wp_error($event) && cd_event_is_archived($event)) {
        return cd_error('cd_event_archived', 'این رویداد بایگانی شده و فقط خواندنی است. اول آن را از بایگانی برگردانید.', 409);
    }
    return $event;
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
            'callback' => function (WP_REST_Request $request) {
                return array_map('cd_event_out', cd_all_events((bool) $request->get_param('include_archived')));
            },
        ],
        [
            'methods' => 'POST',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_upsert_event',
        ],
    ]);

    register_rest_route(CD_NS, "/admin/events/$code", [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_delete_event',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/impact", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            $event = cd_event_from_request($request);
            return is_wp_error($event) ? $event : cd_event_impact((int) $event['id']);
        },
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/archive", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_archive_event',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/config", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_config',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/staff", [
        [
            'methods' => 'GET',
            'permission_callback' => $admin,
            'callback' => function (WP_REST_Request $request) {
                $event = cd_event_from_request($request);
                return is_wp_error($event) ? $event : cd_staff_list((int) $event['id']);
            },
        ],
        [
            'methods' => 'POST',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_staff',
        ],
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/attendees", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_attendees',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/reserve-cards", [
        [
            'methods' => 'POST',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_reserve_cards',
        ],
        [
            // حذف رزروهای آزاد (کارتی که به کسی وصل نشده و در دفتر هم نیامده).
            'methods' => 'DELETE',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_delete_free_reserves',
        ],
    ]);

    // کارت این افراد چاپ شد (ساخت PDF نهایی و تحویل به چاپخانه).
    register_rest_route(CD_NS, "/admin/events/$code/attendees/printed", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_mark_printed',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/attendees/status", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_attendees_status',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/imports", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_imports',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/imports/(?P<batch>[0-9a-fA-F-]{36})", [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_delete_import',
    ]);

    $item = '(?P<item>[A-Za-z0-9_-]{1,64})';
    register_rest_route(CD_NS, "/admin/events/$code/registration-types/$item", [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            return cd_rest_delete_config_item($request, 'registration_types');
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/roles/$item", [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            return cd_rest_delete_config_item($request, 'roles');
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/meals/$item", [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            return cd_rest_delete_config_item($request, 'meals');
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/meals/$item/active", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_meal_active',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/lock", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            global $wpdb;
            $event = cd_event_for_write($request);
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
            $day = $request->get_param('day');
            return is_wp_error($event) ? $event : cd_build_report($event, is_string($day) && $day !== '' ? $day : null);
        },
    ]);

    $aid = '(?P<attendee>[0-9a-fA-F-]{36})';

    // تاریخچه‌ی یک نفر (PersonTimeline) برای تب «افراد» اپ مدیریت.
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/timeline", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_timeline',
    ]);

    // حذف یک نفر (حذف نرم). اگر پذیرش یا وعده دارد، بدون force=1 پاسخ 409 با شمارش می‌دهد.
    // «کارت گم شد»: کارت رزرو آزاد یا کارت تازه با همان شماره؛ کارت قبلی باطل می‌شود.
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/replace-card", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_replace_card',
    ]);

    // ادغام: تاریخچه، کارت و فیلدهای خالی فرد from به این فرد منتقل و from حذف (نرم) می‌شود.
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/merge", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_merge_attendees',
    ]);

    // برگرداندن یک تحویل وعده از اپ مدیریت («لغو تحویل…»).
    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid/meal-undo", [
        'methods' => 'POST',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_admin_meal_undo',
    ]);

    // «دیدن فهرست» یک وعده: افراد فعالِ دارای حق، و هر کس تحویل گرفته، با زمان تحویل.
    register_rest_route(CD_NS, "/admin/events/$code/meals/(?P<item>[A-Za-z0-9_-]{1,64})/people", [
        'methods' => 'GET',
        'permission_callback' => $admin,
        'callback' => 'cd_rest_meal_people',
    ]);

    register_rest_route(CD_NS, "/admin/events/$code/attendees/$aid", [
        [
            'methods' => 'PATCH',
            'permission_callback' => $admin,
            'callback' => 'cd_rest_patch_attendee',
        ],
        [
        'methods' => 'DELETE',
        'permission_callback' => $admin,
        'callback' => function (WP_REST_Request $request) {
            $event = cd_event_for_write($request);
            if (is_wp_error($event)) {
                return $event;
            }
            $aid = strtolower((string) $request['attendee']);
            $r = cd_set_attendees_status((int) $event['id'], [$aid], 'deleted', (bool) $request->get_param('force'));
            if ($r['missing']) {
                return cd_error('cd_no_attendee', 'این نفر در این رویداد نیست.', 404);
            }
            if ($r['kept']) {
                return cd_error('cd_person_has_activity', 'این نفر پذیرش یا وعده‌ی ثبت‌شده دارد.', 409, ['activity' => $r['kept'][0]]);
            }
            return $r;
        },
        ],
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

/**
 * تاریخ میلادی YYYY-MM-DD که واقعاً هست. ذخیره همیشه میلادی است و اپ‌ها تقویم شمسی را خودشان تبدیل می‌کنند؛
 * سال بیرون از ۱۹۰۰ تا ۲۱۹۹ (مثل 1405-08-20 که شمسی تایپ شده) و روز ناموجود (2026-02-30) رد می‌شود.
 */
function cd_valid_date($s) {
    if (!is_string($s) || preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $s, $m) !== 1) {
        return false;
    }
    $y = (int) $m[1];
    return $y >= 1900 && $y <= 2199 && checkdate((int) $m[2], (int) $m[3], $y);
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
        return cd_error('cd_bad_date', 'تاریخ باید میلادی و به شکل YYYY-MM-DD باشد (مثلاً 2026-11-11)؛ تاریخ شمسی را اپ مدیریت خودش تبدیل می‌کند.');
    }
    $base = $base === '' ? untrailingslashit(home_url()) : untrailingslashit(esc_url_raw($base));
    if (strpos($base, 'https://') !== 0 && strpos($base, 'http://') !== 0) {
        return cd_error('cd_bad_base_url', 'آدرس پایه نامعتبر است.');
    }

    $existing = cd_get_event_by_code($code);
    // mode: create = فقط ساخت (کد تکراری 409)، update = فقط ویرایش. بدون mode (اپ قدیمی) همان upsert قبلی.
    // کد رویداد بعد از ساخت عوض نمی‌شود؛ ویرایش هرگز رویداد تازه نمی‌سازد.
    $mode = (string) $request->get_param('mode');
    if ($mode === 'create' && $existing) {
        return cd_error('cd_code_taken', 'رویدادی با این کد هست. کد دیگری انتخاب کنید.', 409);
    }
    if ($mode === 'update' && !$existing) {
        return cd_error('cd_no_event', 'رویداد پیدا نشد. کد رویداد بعد از ساخت قابل تغییر نیست.', 404);
    }
    if ($existing && cd_event_is_archived($existing)) {
        return cd_error('cd_event_archived', 'این رویداد بایگانی شده و فقط خواندنی است. اول آن را از بایگانی برگردانید.', 409);
    }
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
    $event = cd_event_for_write($request);
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
            // active فقط وقتی فرستاده شود عوض می‌شود (اپ قدیمی آن را نمی‌فرستد).
            $has_active = array_key_exists('active', $m);
            $wpdb->query($wpdb->prepare(
                'INSERT INTO ' . cd_table('meals') . ' (event_id, code, day, name, sort, active) VALUES (%d, %s, ' . ($day ? '%s' : 'NULL') . ', %s, %d, %d)
                 ON DUPLICATE KEY UPDATE day = VALUES(day), name = VALUES(name), sort = VALUES(sort)' . ($has_active ? ', active = VALUES(active)' : ''),
                array_values(array_filter([$eid, $c, $day ?: null, $n, (int) ($m['sort'] ?? $i), $has_active ? (int) (bool) $m['active'] : 1], function ($v) {
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
        'SELECT l.seq, l.kind, l.flag, l.day, l.device_time, l.meal_id, l.payload, m.name AS meal_name, d.label AS device_label, s.name AS staff_name
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
            $p = $r['payload'] ? json_decode($r['payload'], true) : null;
            $undo = in_array($r['kind'], ['checkin_undo', 'meal_undo'], true);
            $actor = is_array($p) && $undo ? (string) ($p['actor'] ?? '') : '';
            return [
                'seq' => (int) $r['seq'],
                'day' => cd_log_day($r),
                'meal_id' => $r['meal_id'] !== null ? (int) $r['meal_id'] : null,
                'reason' => is_array($p) && $undo ? (string) ($p['reason'] ?? '') : '',
                'actor' => $actor,
                'kind' => $r['kind'],
                'meal_name' => $r['meal_name'],
                'device_time' => cd_iso($r['device_time']),
                'device_label' => $r['device_label'] ?? 'اپ مدیریت',
                'staff' => $r['staff_name'] ?? ($actor !== '' ? $actor : null),
                'flag' => $r['flag'],
                'flag_label' => $r['flag'] ? (CD_FLAG_LABELS[$r['flag']] ?? $r['flag']) : null,
            ];
        }, $rows),
        'server_time' => gmdate('c'),
    ];
}

function cd_rest_admin_undo_checkin(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $aid = strtolower((string) $request['attendee']);
    $exists = $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d', $aid, $eid));
    if (!(int) $exists) {
        return cd_error('cd_no_attendee', 'این نفر در این رویداد نیست.', 404);
    }
    // لغو فقط برای کسی که الان پذیرش‌شده است؛ دلیل و فاعل در payload می‌ماند.
    // حضور روزانه: لغو پذیرش روز داده‌شده، وگرنه امروز (وقت سایت).
    $now = cd_now();
    $daily = !empty(cd_event_settings($event)['daily_attendance']);
    $day = $request->get_param('day');
    $day = is_string($day) && cd_valid_date($day) ? $day : cd_event_day($now);
    if (!cd_is_checked_in($eid, $aid, $daily ? $day : null)) {
        return cd_error('cd_not_checked_in', 'این نفر هنوز پذیرش نشده است.', 409);
    }
    $wpdb->insert(cd_table('event_log'), [
        'day' => $day,
        'uuid' => wp_generate_uuid4(),
        'event_id' => $eid,
        'kind' => 'checkin_undo',
        'attendee_id' => $aid,
        'payload' => wp_json_encode([
            'reason' => cd_str($request->get_param('reason') ?? '', 191),
            'actor' => cd_admin_actor(),
            'actor_type' => 'admin',
        ]),
        'device_time' => $now,
        'received_at' => $now,
    ]);
    return ['ok' => true, 'seq' => (int) $wpdb->insert_id];
}

/** کلیدهای چیدمان یک قالب کارت (جای نام و QR، اندازه‌ی قلم، رنگ). */
function cd_card_layout_clean(array $t) {
    $clean = [];
    foreach (['name_x', 'name_y', 'name_size', 'qr_x', 'qr_y', 'qr_size_mm'] as $k) {
        if (isset($t[$k]) && is_numeric($t[$k])) {
            $clean[$k] = (float) $t[$k];
        }
    }
    if (isset($t['name_color']) && preg_match('/^#?[0-9a-fA-F]{6}$/', (string) $t['name_color'])) {
        $clean['name_color'] = ltrim((string) $t['name_color'], '#');
    }
    foreach (['show_role', 'show_serial'] as $k) {
        if (array_key_exists($k, $t)) {
            $clean[$k] = (bool) $t[$k];
        }
    }
    return $clean;
}

/** فهرست کد نقش یا نوع ثبت‌نام برای قاعده‌ی قالب. */
function cd_card_codes($list) {
    $out = [];
    foreach (is_array($list) ? $list : [] as $c) {
        if (cd_is_code($c) && !in_array($c, $out, true)) {
            $out[] = $c;
        }
    }
    return $out;
}

/**
 * قالب‌های کارت. مسیر تصویرهای طرح محلی است و ذخیره نمی‌شود.
 * نسخه‌ی ۲: `templates` با قاعده‌ی نقش/نوع، اندازه و حاشیه‌ی برش مشترک؛ کلیدهای سطح بالا
 * همان قالب پیش‌فرض‌اند تا اپ قدیمی یک قالب درست ببیند.
 * قالب تکی (اپ قدیمی): اگر قالب‌های نسخه‌ی ۲ ذخیره شده‌اند، فقط قالب پیش‌فرض و اندازه عوض می‌شود.
 */
function cd_rest_save_card_template(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $t = $request->get_param('template');
    if (!is_array($t)) {
        return cd_error('cd_bad_template', 'قالب کارت لازم است.');
    }
    $shared = [];
    foreach (['width_mm', 'height_mm', 'bleed_mm'] as $k) {
        if (isset($t[$k]) && is_numeric($t[$k])) {
            $shared[$k] = (float) $t[$k];
        }
    }
    if (array_key_exists('crop_marks', $t)) {
        $shared['crop_marks'] = (bool) $t['crop_marks'];
    }

    if (isset($t['templates'])) {
        $list = [];
        $ids = [];
        foreach (is_array($t['templates']) ? $t['templates'] : [] as $x) {
            $id = is_array($x) ? ($x['id'] ?? null) : null;
            if (!cd_is_code($id) || isset($ids[$id])) {
                continue;
            }
            $ids[$id] = true;
            $name = cd_str($x['name'] ?? '', 80);
            $list[] = [
                'id' => $id,
                'name' => $name !== '' ? $name : $id,
                'is_default' => !empty($x['is_default']),
                'roles' => cd_card_codes($x['roles'] ?? []),
                'types' => cd_card_codes($x['types'] ?? []),
            ] + cd_card_layout_clean($x);
        }
        if (!$list) {
            return cd_error('cd_bad_template', 'دست‌کم یک قالب کارت لازم است.');
        }
        // درست یک قالب پیش‌فرض: اولی که علامت دارد، وگرنه اولین قالب.
        $def = 0;
        foreach ($list as $i => $x) {
            if ($x['is_default']) {
                $def = $i;
                break;
            }
        }
        foreach ($list as $i => $x) {
            $list[$i]['is_default'] = $i === $def;
        }
        $reserve = (string) ($t['reserve_template'] ?? '');
        $clean = ['version' => 2] + $shared + [
            'separate' => !empty($t['separate']),
            'reserve_template' => isset($ids[$reserve]) ? $reserve : $list[$def]['id'],
        ];
        $legacy = $list[$def];
        unset($legacy['id'], $legacy['name'], $legacy['is_default'], $legacy['roles'], $legacy['types']);
        $clean = $clean + $legacy + ['templates' => $list];
    } else {
        $clean = $shared + cd_card_layout_clean($t);
        $old = !empty($event['card_template']) ? json_decode($event['card_template'], true) : null;
        if (is_array($old) && !empty($old['templates']) && is_array($old['templates'])) {
            foreach ($old['templates'] as $i => $x) {
                if (!empty($x['is_default'])) {
                    $old['templates'][$i] = array_merge($x, cd_card_layout_clean($t));
                }
            }
            $clean = array_merge($old, $clean);
        }
    }
    $wpdb->update(cd_table('events'), ['card_template' => wp_json_encode($clean), 'updated_at' => cd_now()], ['id' => (int) $event['id']]);
    return ['template' => $clean];
}

/** فهرست نیروهای رویداد برای اپ مدیریت (بدون PIN). */
function cd_staff_list($event_id) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        'SELECT id, name, active, can_checkin, can_serve, is_admin, (pin_hash <> \'\') AS has_pin, updated_at, updated_by FROM ' . cd_table('staff') . ' WHERE event_id = %d ORDER BY id',
        $event_id
    ), ARRAY_A);
    return array_map('cd_staff_out', $rows);
}

/**
 * ذخیره‌ی نیروها.
 * - هر ردیف با id (اگر هست) یا نام پیدا می‌شود؛ با id می‌شود نام را عوض کرد.
 * - active فقط با مقدار صریح عوض می‌شود. نیروی غیرفعال با ذخیره‌ی دوباره فعال نمی‌شود (فلوی غلط قبلی).
 * - partial=true (اپ جدید): فقط ردیف‌های فرستاده‌شده دست می‌خورند. بدون آن (اپ قدیمی): نیرویی که در لیست
 *   نیست مثل قبل غیرفعال و گوشی‌هایش باطل می‌شود.
 * - اگر ردیف updated_at بفرستد و روی سرور عوض شده باشد، هیچ چیز ذخیره نمی‌شود و 409 با ردیف‌های فعلی
 *   برمی‌گردد (تعارض ذخیره). force=true یعنی «تغییر من را بگذار».
 */
function cd_rest_staff(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $items = $request->get_param('staff');
    if (!is_array($items)) {
        return cd_error('cd_bad_staff', 'لیست staff لازم است.');
    }
    $partial = (bool) $request->get_param('partial');
    $force = (bool) $request->get_param('force');

    $existing = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('staff') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $by_id = [];
    $by_name = [];
    foreach ($existing as $s) {
        $by_id[(int) $s['id']] = $s;
        $by_name[$s['name']] = $s;
    }

    // PIN تکراری بین نیروها مجاز نیست، چون ورود فقط با PIN است.
    $pins = [];
    $names = [];
    $errors = [];
    $targets = [];
    foreach ($items as $i => $s) {
        if (!is_array($s)) {
            $errors[] = ['index' => $i, 'reason' => 'not_object'];
            continue;
        }
        $name = cd_str($s['name'] ?? '');
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
        if ($name === '') {
            $errors[] = ['index' => $i, 'reason' => 'missing_name'];
        } elseif (isset($names[$name])) {
            $errors[] = ['index' => $i, 'reason' => 'duplicate_name'];
        } else {
            $names[$name] = $i;
        }
        $row = null;
        if (!empty($s['id'])) {
            $row = $by_id[(int) $s['id']] ?? null;
            if ($row === null) {
                $errors[] = ['index' => $i, 'reason' => 'unknown_staff'];
            } elseif ($name !== '' && $name !== $row['name'] && isset($by_name[$name])) {
                $errors[] = ['index' => $i, 'reason' => 'duplicate_name'];
            }
        } elseif ($name !== '') {
            $row = $by_name[$name] ?? null;
        }
        $targets[$i] = $row;
    }
    if ($errors) {
        return cd_error('cd_bad_staff', 'لیست نیروها خطا دارد.', 400, ['errors' => $errors]);
    }

    // تعارض: کسی دیگر بعد از آخرین خواندن این ردیف را ذخیره کرده.
    if (!$force) {
        $conflicts = [];
        foreach ($items as $i => $s) {
            $row = $targets[$i];
            if ($row === null || !array_key_exists('updated_at', $s)) {
                continue;
            }
            $seen = $s['updated_at'] ? gmdate('Y-m-d H:i:s', strtotime((string) $s['updated_at'])) : null;
            if ($seen !== ($row['updated_at'] ?: null)) {
                $row['has_pin'] = $row['pin_hash'] !== '';
                $conflicts[] = cd_staff_out($row);
            }
        }
        if ($conflicts) {
            return cd_error('cd_staff_conflict', 'این فهرست را شخص دیگری عوض کرده.', 409, ['conflicts' => $conflicts]);
        }
    }

    // PIN جدید نباید با PIN فعلی نیروی دیگری که PIN جدید نگرفته یکی باشد.
    $ids_with_new_pin = [];
    foreach ($items as $i => $s) {
        if (!empty($s['pin']) && $targets[$i] !== null) {
            $ids_with_new_pin[(int) $targets[$i]['id']] = true;
        }
    }
    foreach ($pins as $pin => $i) {
        foreach ($existing as $s) {
            if (isset($ids_with_new_pin[(int) $s['id']]) || $s['pin_hash'] === '') {
                continue;
            }
            if (wp_check_password($pin, $s['pin_hash'])) {
                return cd_error('cd_bad_staff', 'PIN تکراری است.', 400, ['errors' => [['index' => $i, 'reason' => 'duplicate_pin']]]);
            }
        }
    }

    $now = cd_now();
    $actor = cd_admin_actor();
    $touched = [];
    foreach ($items as $i => $s) {
        $old = $targets[$i];
        $data = ['name' => cd_str($s['name'])];
        foreach (['can_checkin' => 1, 'can_serve' => 1, 'is_admin' => 0, 'active' => 1] as $k => $default) {
            if (array_key_exists($k, $s) && $s[$k] !== null) {
                $data[$k] = (int) (bool) $s[$k];
            } else {
                $data[$k] = $old !== null ? (int) $old[$k] : $default;
            }
        }
        if (!empty($s['pin'])) {
            $data['pin_hash'] = wp_hash_password(cd_latin_digits((string) $s['pin']));
        }
        if ($old === null) {
            $data['event_id'] = $eid;
            $data['updated_at'] = $now;
            $data['updated_by'] = $actor;
            $wpdb->insert(cd_table('staff'), $data);
            $touched[(int) $wpdb->insert_id] = true;
            continue;
        }
        $id = (int) $old['id'];
        $touched[$id] = true;
        $changed = isset($data['pin_hash']);
        foreach (['name', 'can_checkin', 'can_serve', 'is_admin', 'active'] as $k) {
            if ((string) $data[$k] !== (string) $old[$k]) {
                $changed = true;
            }
        }
        if (!$changed) {
            continue;
        }
        $data['updated_at'] = $now;
        $data['updated_by'] = $actor;
        $wpdb->update(cd_table('staff'), $data, ['id' => $id]);
        if ((int) $old['active'] && !$data['active']) {
            $wpdb->update(cd_table('devices'), ['revoked' => 1], ['staff_id' => $id]);
        }
    }
    if (!$partial) {
        foreach ($existing as $s) {
            if (!isset($touched[(int) $s['id']]) && (int) $s['active']) {
                $wpdb->update(cd_table('staff'), ['active' => 0, 'updated_at' => $now, 'updated_by' => $actor], ['id' => (int) $s['id']]);
                $wpdb->update(cd_table('devices'), ['revoked' => 1], ['staff_id' => (int) $s['id']]);
            }
        }
    }

    cd_bump_config($eid);
    return cd_staff_list($eid);
}

/** درج یا به‌روزرسانی شرکت‌کننده‌ها همراه کارتشان؛ حداکثر ۵۰۰ ردیف در هر درخواست. */
function cd_rest_attendees(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
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

    // «افزودن فرد» در اپ مدیریت با source=manual؛ پیش‌فرض همان import.
    $source = $request->get_param('source') === 'manual' ? 'manual' : 'import';

    // ورودی اکسل (اختیاری): {id, file_name}. هر فرد شناسه‌ی آخرین ورودی‌ای که آورده‌اش را می‌گیرد.
    $batch_id = '';
    $batch = $request->get_param('batch');
    if (is_array($batch) && cd_is_uuid($batch['id'] ?? null)) {
        $batch_id = strtolower($batch['id']);
        $wpdb->query($wpdb->prepare(
            'INSERT IGNORE INTO ' . cd_table('import_batches') . ' (id, event_id, file_name, created_at) VALUES (%s, %d, %s, %s)',
            $batch_id,
            $eid,
            cd_str($batch['file_name'] ?? '', 255),
            cd_now()
        ));
    }

    // کسی که حذف شده، با ورود دوباره‌ی اکسل بی‌صدا برنمی‌گردد؛ در خطاها گزارش می‌شود.
    $deleted = [];
    $ids = [];
    foreach ($items as $a) {
        if (is_array($a) && cd_is_uuid($a['id'] ?? null)) {
            $ids[] = strtolower($a['id']);
        }
    }
    if ($ids) {
        $in = implode(',', array_fill(0, count($ids), '%s'));
        $rows = $wpdb->get_col($wpdb->prepare(
            'SELECT id FROM ' . cd_table('attendees') . " WHERE event_id = %d AND status = 'deleted' AND id IN ($in)",
            array_merge([$eid], $ids)
        ));
        $deleted = array_flip($rows);
    }

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

        if (isset($deleted[strtolower($a['id'])])) {
            $errors[] = ['index' => $i, 'reason' => 'deleted_person'];
            continue;
        }

        $a['registration_type_id'] = $types[$tc];
        $a['role_id'] = ($rc !== null && $rc !== '') ? $roles[$rc] : null;
        $a['import_batch'] = $batch_id;
        if (!cd_upsert_attendee($eid, $a, $source)) {
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
    $event = cd_event_for_write($request);
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


// ---------------------------------------------------------------- بایگانی و حذف رویداد

function cd_rest_archive_event(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $archived = $request->get_param('archived');
    $archived = $archived === null ? true : (bool) $archived;
    $wpdb->query($wpdb->prepare(
        'UPDATE ' . cd_table('events') . ' SET archived_at = ' . ($archived ? '%s' : 'NULL') . ', updated_at = %s WHERE id = %d',
        array_values(array_filter([$archived ? cd_now() : null, cd_now(), (int) $event['id']], function ($v) {
            return $v !== null;
        }))
    ));
    cd_bump_config((int) $event['id']);
    return cd_event_out(cd_get_event((int) $event['id']));
}

/**
 * حذف واقعی رویداد: تأیید با تایپ کد (confirm) و فقط وقتی هیچ کار ثبت‌شده‌ای (دفتر رخداد) ندارد؛
 * وگرنه 409 با خلاصه‌ی پیامد، تا مدیر خروجی بگیرد یا بایگانی کند.
 */
function cd_rest_delete_event(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $impact = cd_event_impact($eid);
    if ((string) $request->get_param('confirm') !== $event['code']) {
        return cd_error('cd_confirm_required', 'برای حذف، کد رویداد را برای تأیید بفرستید.', 400, ['impact' => $impact]);
    }
    if ($impact['log'] > 0) {
        return cd_error('cd_event_has_activity', 'این رویداد کار ثبت‌شده دارد و حذف نمی‌شود. خروجی بگیرید و بایگانی کنید.', 409, ['impact' => $impact]);
    }
    $meal_ids = $wpdb->get_col($wpdb->prepare('SELECT id FROM ' . cd_table('meals') . ' WHERE event_id = %d', $eid));
    if ($meal_ids) {
        $wpdb->query('DELETE FROM ' . cd_table('meal_rules') . ' WHERE meal_id IN (' . implode(',', array_map('intval', $meal_ids)) . ')');
    }
    foreach (['registration_types', 'roles', 'meals', 'sessions', 'attendees', 'cards', 'staff', 'devices', 'event_log', 'import_batches', 'rejected_events'] as $t) {
        $wpdb->delete(cd_table($t), ['event_id' => $eid]);
    }
    $wpdb->delete(cd_table('events'), ['id' => $eid]);
    return ['deleted' => true, 'impact' => $impact];
}

// ---------------------------------------------------------------- وضعیت افراد و ورودی‌ها

/** شمار پذیرش و وعده‌ی ثبت‌شده‌ی هر فرد (برای «به‌جای حذف غیرفعال کن»). */
function cd_attendee_activity($event_id, array $ids) {
    global $wpdb;
    if (!$ids) {
        return [];
    }
    $in = implode(',', array_fill(0, count($ids), '%s'));
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT attendee_id, SUM(kind = 'checkin') AS checkins, SUM(kind = 'meal_served') AS meals FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id IN ($in) AND kind IN ('checkin','meal_served') GROUP BY attendee_id",
        array_merge([(int) $event_id], $ids)
    ), ARRAY_A);
    $out = [];
    foreach ($rows as $r) {
        $out[$r['attendee_id']] = ['checkins' => (int) $r['checkins'], 'meals' => (int) $r['meals']];
    }
    return $out;
}

/**
 * تغییر وضعیت چند نفر: active، inactive یا deleted (حذف نرم؛ دفتر رخدادها دست نمی‌خورد).
 * حذف کسی که پذیرش یا وعده دارد فقط با $force؛ وگرنه در kept برمی‌گردد.
 */
function cd_set_attendees_status($event_id, array $ids, $status, $force) {
    global $wpdb;
    $ids = array_values(array_unique(array_map('strtolower', array_filter($ids, 'cd_is_uuid'))));
    $found = [];
    if ($ids) {
        $in = implode(',', array_fill(0, count($ids), '%s'));
        $found = $wpdb->get_col($wpdb->prepare(
            'SELECT id FROM ' . cd_table('attendees') . " WHERE event_id = %d AND id IN ($in)",
            array_merge([(int) $event_id], $ids)
        ));
    }
    $missing = array_values(array_diff($ids, $found));
    $kept = [];
    $change = $found;
    if ($status === 'deleted' && !$force) {
        $activity = cd_attendee_activity($event_id, $found);
        $change = [];
        foreach ($found as $id) {
            if (isset($activity[$id])) {
                $kept[] = array_merge(['id' => $id], $activity[$id]);
            } else {
                $change[] = $id;
            }
        }
    }
    if ($change) {
        $in = implode(',', array_fill(0, count($change), '%s'));
        $wpdb->query($wpdb->prepare(
            'UPDATE ' . cd_table('attendees') . " SET status = %s, updated_at = %s WHERE event_id = %d AND id IN ($in)",
            array_merge([$status, cd_now(), (int) $event_id], $change)
        ));
        cd_bump_config($event_id);
    }
    return ['changed' => count($change), 'kept' => $kept, 'missing' => $missing];
}

function cd_rest_attendees_status(WP_REST_Request $request) {
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $status = (string) $request->get_param('status');
    if (!in_array($status, ['active', 'inactive', 'deleted'], true)) {
        return cd_error('cd_bad_status', 'وضعیت باید active، inactive یا deleted باشد.');
    }
    $ids = $request->get_param('ids');
    if (!is_array($ids) || !$ids) {
        return cd_error('cd_bad_ids', 'لیست ids لازم است.');
    }
    return cd_set_attendees_status((int) $event['id'], $ids, $status, (bool) $request->get_param('force'));
}

/** «ورودی‌های قبلی»: هر فایل اکسل با شمار افرادش و آن‌هایی که کار ثبت‌شده دارند. */
function cd_rest_imports(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT b.id, b.file_name, b.created_at,
                COUNT(a.id) AS people,
                SUM(EXISTS (SELECT 1 FROM " . cd_table('event_log') . " l WHERE l.event_id = b.event_id AND l.attendee_id = a.id AND l.kind IN ('checkin','meal_served'))) AS with_activity
         FROM " . cd_table('import_batches') . " b
         LEFT JOIN " . cd_table('attendees') . " a ON a.import_batch = b.id AND a.event_id = b.event_id AND a.status <> 'deleted'
         WHERE b.event_id = %d GROUP BY b.id, b.file_name, b.created_at ORDER BY b.created_at DESC",
        $eid
    ), ARRAY_A);
    return array_map(function ($r) {
        return [
            'id' => $r['id'],
            'file_name' => $r['file_name'],
            'created_at' => cd_iso($r['created_at']),
            'people' => (int) $r['people'],
            'with_activity' => (int) $r['with_activity'],
        ];
    }, $rows);
}

/** حذف یک ورودی: افرادش حذف نرم می‌شوند، جز آن‌هایی که پذیرش یا وعده دارند. */
function cd_rest_delete_import(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $bid = strtolower((string) $request['batch']);
    $exists = $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('import_batches') . ' WHERE id = %s AND event_id = %d', $bid, $eid));
    if (!(int) $exists) {
        return cd_error('cd_no_import', 'این ورودی پیدا نشد.', 404);
    }
    $ids = $wpdb->get_col($wpdb->prepare(
        'SELECT id FROM ' . cd_table('attendees') . " WHERE event_id = %d AND import_batch = %s AND status <> 'deleted'",
        $eid,
        $bid
    ));
    $r = cd_set_attendees_status($eid, $ids, 'deleted', false);
    return ['deleted' => $r['changed'], 'kept' => count($r['kept'])];
}

function cd_rest_delete_free_reserves(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $n = $wpdb->query($wpdb->prepare(
        'DELETE c FROM ' . cd_table('cards') . ' c
         WHERE c.event_id = %d AND c.is_reserve = 1 AND c.attendee_id IS NULL
           AND NOT EXISTS (SELECT 1 FROM ' . cd_table('event_log') . ' l WHERE l.event_id = c.event_id AND l.card_token = c.token)',
        $eid
    ));
    if ($n) {
        cd_bump_config($eid);
    }
    return ['deleted' => (int) $n];
}

// ---------------------------------------------------------------- حذف نوع، نقش و وعده

/**
 * نوع یا نقشی که افرادی دارد فقط با move_to (کد مقصد) حذف می‌شود؛ نقش با clear=1 هم (افراد بی‌نقش می‌شوند).
 * وعده‌ای که تحویل ثبت‌شده دارد حذف نمی‌شود؛ باید غیرفعال شود.
 */
function cd_rest_delete_config_item(WP_REST_Request $request, $table) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $map = cd_code_map($table, $eid);
    $code = (string) $request['item'];
    if (!isset($map[$code])) {
        return cd_error('cd_no_item', 'این مورد پیدا نشد.', 404);
    }
    $id = $map[$code];
    $att = cd_table('attendees');

    if ($table === 'meals') {
        $served = (int) $wpdb->get_var($wpdb->prepare(
            'SELECT COUNT(*) FROM ' . cd_table('event_log') . " WHERE event_id = %d AND meal_id = %d AND kind = 'meal_served'",
            $eid,
            $id
        ));
        if ($served > 0) {
            return cd_error('cd_in_use', 'این وعده تحویل ثبت‌شده دارد؛ به‌جای حذف غیرفعالش کنید.', 409, ['served' => $served]);
        }
        $wpdb->delete(cd_table('meal_rules'), ['meal_id' => $id]);
        $wpdb->delete(cd_table('meals'), ['id' => $id]);
        cd_bump_config($eid);
        return ['deleted' => true];
    }

    $col = $table === 'roles' ? 'role_id' : 'registration_type_id';
    $count = function ($status_sql) use ($wpdb, $att, $col, $eid, $id) {
        return (int) $wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM $att WHERE event_id = %d AND $col = %d AND $status_sql", $eid, $id));
    };
    $used = $count("status <> 'deleted'");
    $used_deleted = $count("status = 'deleted'");
    $move = $request->get_param('move_to');
    $clear = $table === 'roles' && (bool) $request->get_param('clear');
    if ($used + $used_deleted > 0) {
        if ($clear) {
            $wpdb->query($wpdb->prepare("UPDATE $att SET role_id = NULL WHERE event_id = %d AND role_id = %d", $eid, $id));
        } elseif (is_string($move) && $move !== '' && $move !== $code && isset($map[$move])) {
            $wpdb->query($wpdb->prepare("UPDATE $att SET $col = %d WHERE event_id = %d AND $col = %d", $map[$move], $eid, $id));
        } else {
            return cd_error('cd_in_use', 'این مورد افرادی دارد؛ اول آن‌ها را به مورد دیگری منتقل کنید.', 409, [
                'attendees' => $used,
                'deleted_attendees' => $used_deleted,
            ]);
        }
    }
    $meal_ids = array_values(cd_code_map('meals', $eid));
    if ($meal_ids) {
        $wpdb->query($wpdb->prepare(
            'DELETE FROM ' . cd_table('meal_rules') . ' WHERE ' . $col . ' = %d AND meal_id IN (' . implode(',', array_map('intval', $meal_ids)) . ')',
            $id
        ));
    }
    $wpdb->delete(cd_table($table), ['id' => $id]);
    cd_bump_config($eid);
    return ['deleted' => true, 'moved' => $used + $used_deleted];
}

function cd_rest_meal_active(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $map = cd_code_map('meals', $eid);
    $code = (string) $request['item'];
    if (!isset($map[$code])) {
        return cd_error('cd_no_item', 'این وعده پیدا نشد.', 404);
    }
    $active = $request->get_param('active');
    $active = $active === null ? true : (bool) $active;
    $wpdb->update(cd_table('meals'), ['active' => $active ? 1 : 0], ['id' => $map[$code]]);
    cd_bump_config($eid);
    return ['code' => $code, 'active' => $active];
}


// ---------------------------------------------------------------- ویرایش، ادغام، لغو تحویل

/** ویرایش جزئی یک نفر: فقط فیلدهای فرستاده‌شده عوض می‌شوند. نوع و نقش با کد. */
function cd_rest_patch_attendee(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $aid = strtolower((string) $request['attendee']);
    $row = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('attendees') . " WHERE id = %s AND event_id = %d AND status <> 'deleted'", $aid, $eid), ARRAY_A);
    if (!$row) {
        return cd_error('cd_no_attendee', 'این نفر در این رویداد نیست.', 404);
    }
    $data = [];
    $text = ['title' => 64, 'first_name' => 191, 'last_name' => 191, 'organization' => 191, 'country' => 64, 'presentation_kind' => 16];
    foreach ($text as $k => $max) {
        if ($request->has_param($k)) {
            $data[$k] = cd_str($request->get_param($k), $max);
        }
    }
    if (isset($data['first_name']) && $data['first_name'] === '' || isset($data['last_name']) && $data['last_name'] === '') {
        return cd_error('cd_bad_name', 'نام و نام خانوادگی خالی نمی‌شود.');
    }
    if ($request->has_param('email')) {
        $data['email'] = sanitize_email((string) $request->get_param('email'));
    }
    if ($request->has_param('mobile')) {
        $data['mobile'] = cd_normalize_mobile($request->get_param('mobile'));
    }
    if ($request->has_param('website')) {
        $data['website'] = esc_url_raw(cd_str($request->get_param('website'), 255));
    }
    if ($request->has_param('registration_type')) {
        $types = cd_code_map('registration_types', $eid);
        $tc = (string) $request->get_param('registration_type');
        if (!isset($types[$tc])) {
            return cd_error('cd_bad_type', 'نوع ثبت‌نام نامعتبر است.');
        }
        $data['registration_type_id'] = $types[$tc];
    }
    $role_null = false;
    if ($request->has_param('role')) {
        $rc = $request->get_param('role');
        if ($rc === null || $rc === '') {
            $role_null = true;
        } else {
            $roles = cd_code_map('roles', $eid);
            if (!isset($roles[$rc])) {
                return cd_error('cd_bad_role', 'نقش نامعتبر است.');
            }
            $data['role_id'] = $roles[$rc];
        }
    }
    $merged = array_merge($row, $data);
    $data['search_key'] = cd_search_key($merged);
    $data['updated_at'] = cd_now();
    $wpdb->update(cd_table('attendees'), $data, ['id' => $aid]);
    if ($role_null) {
        $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('attendees') . ' SET role_id = NULL WHERE id = %s', $aid));
    }
    cd_bump_config($eid);
    return cd_attendee_out($wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('attendees') . ' WHERE id = %s', $aid), ARRAY_A));
}

/**
 * ادغام فرد from در این فرد: رخدادهای دفتر و کارهای ردشده و کارت‌ها به این فرد منتقل می‌شوند،
 * فیلدهای خالی این فرد از from پر می‌شود و from حذف نرم می‌شود.
 */
function cd_rest_merge_attendees(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $keep = strtolower((string) $request['attendee']);
    $from = strtolower((string) $request->get_param('from'));
    if (!cd_is_uuid($from) || $from === $keep) {
        return cd_error('cd_bad_merge', 'فردی که باید ادغام شود نامعتبر است.');
    }
    $att = cd_table('attendees');
    $k = $wpdb->get_row($wpdb->prepare("SELECT * FROM $att WHERE id = %s AND event_id = %d AND status <> 'deleted'", $keep, $eid), ARRAY_A);
    $f = $wpdb->get_row($wpdb->prepare("SELECT * FROM $att WHERE id = %s AND event_id = %d AND status <> 'deleted'", $from, $eid), ARRAY_A);
    if (!$k || !$f) {
        return cd_error('cd_no_attendee', 'یکی از دو نفر در این رویداد نیست.', 404);
    }
    $fill = [];
    foreach (['title', 'email', 'mobile', 'organization', 'country', 'presentation_kind', 'website'] as $col) {
        if ((string) $k[$col] === '' && (string) $f[$col] !== '') {
            $fill[$col] = $f[$col];
        }
    }
    if ($k['role_id'] === null && $f['role_id'] !== null) {
        $fill['role_id'] = (int) $f['role_id'];
    }
    $wpdb->query('START TRANSACTION');
    $moved = (int) $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('event_log') . ' SET attendee_id = %s WHERE event_id = %d AND attendee_id = %s', $keep, $eid, $from));
    $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('rejected_events') . ' SET attendee_id = %s WHERE event_id = %d AND attendee_id = %s', $keep, $eid, $from));
    $cards = (int) $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('cards') . ' SET attendee_id = %s WHERE event_id = %d AND attendee_id = %s', $keep, $eid, $from));
    if ($fill) {
        $fill['search_key'] = cd_search_key(array_merge($k, $fill));
        $fill['updated_at'] = cd_now();
        $wpdb->update($att, $fill, ['id' => $keep]);
    }
    $wpdb->update($att, ['status' => 'deleted', 'updated_at' => cd_now()], ['id' => $from]);
    $wpdb->query('COMMIT');
    cd_bump_config($eid);
    return ['merged' => true, 'events_moved' => $moved, 'cards_moved' => $cards, 'filled' => array_keys($fill)];
}

function cd_rest_admin_meal_undo(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $aid = strtolower((string) $request['attendee']);
    $meals = cd_code_map('meals', $eid);
    $mc = (string) $request->get_param('meal');
    if (!isset($meals[$mc])) {
        return cd_error('cd_no_item', 'این وعده پیدا نشد.', 404);
    }
    if (cd_meal_count($eid, $aid, $meals[$mc]) < 1) {
        return cd_error('cd_not_served', 'این وعده به این نفر تحویل نشده است.', 409);
    }
    $now = cd_now();
    $wpdb->insert(cd_table('event_log'), [
        'uuid' => wp_generate_uuid4(),
        'event_id' => $eid,
        'kind' => 'meal_undo',
        'attendee_id' => $aid,
        'meal_id' => $meals[$mc],
        'payload' => wp_json_encode([
            'reason' => cd_str($request->get_param('reason') ?? '', 191),
            'actor' => cd_admin_actor(),
            'actor_type' => 'admin',
        ]),
        'day' => cd_event_day($now),
        'device_time' => $now,
        'received_at' => $now,
    ]);
    return ['ok' => true, 'seq' => (int) $wpdb->insert_id];
}

function cd_rest_meal_people(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_from_request($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $meal = null;
    foreach (cd_event_config($eid)['meals'] as $m) {
        if ($m['code'] === (string) $request['item']) {
            $meal = $m;
        }
    }
    if (!$meal) {
        return cd_error('cd_no_item', 'این وعده پیدا نشد.', 404);
    }
    $states = cd_attendee_states($eid);
    $served_at = [];
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT attendee_id, MIN(device_time) AS t FROM " . cd_table('event_log') . " WHERE event_id = %d AND meal_id = %d AND kind = 'meal_served' GROUP BY attendee_id",
        $eid,
        $meal['id']
    ), ARRAY_A);
    foreach ($rows as $r) {
        $served_at[$r['attendee_id']] = $r['t'];
    }
    $people = $wpdb->get_results($wpdb->prepare(
        'SELECT id, title, first_name, last_name, organization, registration_type_id, role_id FROM ' . cd_table('attendees') . " WHERE event_id = %d AND status = 'active' ORDER BY last_name, first_name",
        $eid
    ), ARRAY_A);
    $out = [];
    foreach ($people as $p) {
        $entitled = cd_is_entitled($meal['rules'], $p['registration_type_id'], $p['role_id'] !== null ? (int) $p['role_id'] : null);
        $count = $states[$p['id']]['meals'][$meal['id']] ?? 0;
        if (!$entitled && $count < 1) {
            continue;
        }
        $out[] = [
            'id' => $p['id'],
            'name' => trim($p['title'] . ' ' . $p['first_name'] . ' ' . $p['last_name']),
            'organization' => $p['organization'],
            'entitled' => $entitled,
            'served' => $count,
            'served_at' => $count > 0 && isset($served_at[$p['id']]) ? cd_iso($served_at[$p['id']]) : null,
        ];
    }
    return ['meal' => ['code' => $meal['code'], 'name' => $meal['name']], 'people' => $out];
}


// ---------------------------------------------------------------- چاپ و جایگزینی کارت

function cd_rest_mark_printed(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $ids = $request->get_param('ids');
    if (!is_array($ids)) {
        return cd_error('cd_bad_ids', 'لیست ids لازم است.');
    }
    $ids = array_values(array_unique(array_map('strtolower', array_filter($ids, 'cd_is_uuid'))));
    if (!$ids) {
        return ['printed' => 0];
    }
    $in = implode(',', array_fill(0, count($ids), '%s'));
    $n = $wpdb->query($wpdb->prepare(
        'UPDATE ' . cd_table('attendees') . " SET printed_at = %s, print_count = print_count + 1 WHERE event_id = %d AND id IN ($in)",
        array_merge([cd_now(), (int) $event['id']], $ids)
    ));
    return ['printed' => (int) $n];
}

/**
 * جایگزینی کارت گم‌شده. mode=reserve: کمترین شماره‌ی رزرو آزاد (یا token داده‌شده) به فرد وصل می‌شود.
 * mode=new: کارت تازه با همان شماره ساخته می‌شود و فرد «چاپ‌نشده» می‌شود تا در «چاپ‌نشده‌ها» بیاید.
 * کارت(های) قبلی فرد با revoked_at باطل می‌شوند و دیگر در گوشی‌ها و صفحه‌ی شخصی کار نمی‌کنند.
 */
function cd_rest_replace_card(WP_REST_Request $request) {
    global $wpdb;
    $event = cd_event_for_write($request);
    if (is_wp_error($event)) {
        return $event;
    }
    $eid = (int) $event['id'];
    $aid = strtolower((string) $request['attendee']);
    $cards = cd_table('cards');
    $exists = $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('attendees') . " WHERE id = %s AND event_id = %d AND status <> 'deleted'", $aid, $eid));
    if (!(int) $exists) {
        return cd_error('cd_no_attendee', 'این نفر در این رویداد نیست.', 404);
    }
    $old = $wpdb->get_results($wpdb->prepare("SELECT * FROM $cards WHERE event_id = %d AND attendee_id = %s AND revoked_at IS NULL ORDER BY created_at", $eid, $aid), ARRAY_A);
    $mode = (string) $request->get_param('mode');
    $now = cd_now();

    if ($mode === 'reserve') {
        $token = $request->get_param('token');
        $where = cd_is_card_token($token) ? $wpdb->prepare(' AND token = %s', $token) : '';
        $card = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM $cards WHERE event_id = %d AND is_reserve = 1 AND attendee_id IS NULL AND revoked_at IS NULL$where ORDER BY serial LIMIT 1",
            $eid
        ), ARRAY_A);
        if (!$card) {
            return cd_error('cd_no_reserve', 'کارت رزرو آزاد نمانده است.', 409);
        }
        $wpdb->query('START TRANSACTION');
        $linked = $wpdb->query($wpdb->prepare("UPDATE $cards SET attendee_id = %s WHERE token = %s AND attendee_id IS NULL", $aid, $card['token']));
        if (!$linked) {
            $wpdb->query('ROLLBACK');
            return cd_error('cd_no_reserve', 'این کارت رزرو همین حالا به کس دیگری وصل شد. دوباره امتحان کنید.', 409);
        }
        $new = ['token' => $card['token'], 'serial' => (int) $card['serial'], 'is_reserve' => true];
    } elseif ($mode === 'new') {
        $serial = $old ? (int) end($old)['serial'] : (int) $request->get_param('serial');
        $token = cd_random_token(16);
        $wpdb->query('START TRANSACTION');
        $wpdb->insert($cards, ['token' => $token, 'event_id' => $eid, 'attendee_id' => $aid, 'serial' => $serial, 'is_reserve' => 0, 'created_at' => $now]);
        // کارت تازه هنوز چاپ نشده.
        $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('attendees') . ' SET printed_at = NULL WHERE id = %s', $aid));
        $new = ['token' => $token, 'serial' => $serial, 'is_reserve' => false];
    } else {
        return cd_error('cd_bad_mode', 'mode باید reserve یا new باشد.');
    }
    foreach ($old as $c) {
        $wpdb->update($cards, ['revoked_at' => $now], ['token' => $c['token']]);
    }
    $wpdb->query('COMMIT');
    cd_bump_config($eid);
    return ['card' => $new, 'revoked' => count($old)];
}
