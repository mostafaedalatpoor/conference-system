<?php
if (!defined('ABSPATH')) {
    exit;
}

const CD_EVENT_KINDS = ['checkin', 'checkin_undo', 'walkin_register', 'meal_served', 'meal_undo', 'onsite_settled'];
const CD_PULL_LIMIT = 1000;
const CD_PUSH_LIMIT = 500;

/**
 * کل داده‌ای که یک گوشی برای کار آفلاین لازم دارد.
 * گوشی فقط افراد فعال و کارت‌هایشان و وعده‌های فعال را می‌گیرد؛ اپ مدیریت ($for_admin)
 * غیرفعال‌ها را هم با وضعیتشان می‌بیند. حذف‌شده‌ها (حذف نرم) هیچ‌جا نمی‌آیند.
 */
function cd_build_snapshot(array $event, $for_admin = false) {
    global $wpdb;
    $eid = (int) $event['id'];

    $status_sql = $for_admin ? "status <> 'deleted'" : "status = 'active'";
    $attendees = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('attendees') . " WHERE event_id = %d AND $status_sql", $eid), ARRAY_A);
    $cards = $wpdb->get_results($wpdb->prepare(
        'SELECT c.token, c.attendee_id, c.serial, c.is_reserve FROM ' . cd_table('cards') . ' c
         LEFT JOIN ' . cd_table('attendees') . ' a ON a.id = c.attendee_id
         WHERE c.event_id = %d AND c.revoked_at IS NULL AND (c.attendee_id IS NULL OR a.' . $status_sql . ')',
        $eid
    ), ARRAY_A);
    // نام همه‌ی نیروها (حتی غیرفعال) لازم است تا تاریخچه بگوید چه کسی کار را کرد.
    $staff = $wpdb->get_results($wpdb->prepare(
        'SELECT id, name, active, can_checkin, can_serve, is_admin, (pin_hash <> \'\') AS has_pin, updated_at, updated_by FROM ' . cd_table('staff') . ' WHERE event_id = %d ORDER BY id',
        $eid
    ), ARRAY_A);
    $log = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('event_log') . ' WHERE event_id = %d ORDER BY seq', $eid), ARRAY_A);
    $cursor = 0;
    foreach ($log as $l) {
        $cursor = max($cursor, (int) $l['seq']);
    }

    $config = cd_event_config($eid);
    if (!$for_admin) {
        $config['meals'] = array_values(array_filter($config['meals'], function ($m) {
            return $m['active'];
        }));
    }

    return array_merge(
        ['event' => cd_event_out($event)],
        $config,
        [
            'attendees' => array_map('cd_attendee_out', $attendees),
            'cards' => array_map(function ($c) {
                return [
                    'token' => $c['token'],
                    'attendee_id' => $c['attendee_id'],
                    'serial' => (int) $c['serial'],
                    'is_reserve' => (bool) $c['is_reserve'],
                ];
            }, $cards),
            'staff' => array_map($for_admin ? 'cd_staff_out' : function ($s) {
                return ['id' => (int) $s['id'], 'name' => $s['name'], 'active' => (bool) $s['active']];
            }, $staff),
            // کارت‌های باطل‌شده تا گوشی بگوید «این کارت باطل شده» نه «در لیست نیست».
            'revoked_cards' => $wpdb->get_col($wpdb->prepare('SELECT token FROM ' . cd_table('cards') . ' WHERE event_id = %d AND revoked_at IS NOT NULL', $eid)),
            'log' => array_map('cd_log_out', $log),
            'cursor' => $cursor,
            'server_time' => gmdate('c'),
        ]
    );
}

/** رخدادهای بعد از $since برای این رویداد. */
function cd_pull_events($event_id, $since) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        'SELECT * FROM ' . cd_table('event_log') . ' WHERE event_id = %d AND seq > %d ORDER BY seq LIMIT %d',
        $event_id,
        $since,
        CD_PULL_LIMIT + 1
    ), ARRAY_A);
    $more = count($rows) > CD_PULL_LIMIT;
    if ($more) {
        array_pop($rows);
    }
    $cursor = $since;
    foreach ($rows as $r) {
        $cursor = max($cursor, (int) $r['seq']);
    }
    return ['events' => array_map('cd_log_out', $rows), 'cursor' => $cursor, 'more' => $more];
}

/** یک ردیف نیرو برای اپ مدیریت. updated_at برای تشخیص تعارض ذخیره است. */
function cd_staff_out(array $s) {
    return [
        'id' => (int) $s['id'],
        'name' => $s['name'],
        'active' => (bool) $s['active'],
        'can_checkin' => (bool) $s['can_checkin'],
        'can_serve' => (bool) $s['can_serve'],
        'is_admin' => (bool) $s['is_admin'],
        'has_pin' => (bool) $s['has_pin'],
        'updated_at' => $s['updated_at'] ? cd_iso($s['updated_at']) : null,
        'updated_by' => $s['updated_by'] ?? '',
    ];
}

/**
 * آیا این فرد الان پذیرش‌شده است؟ (آخرین checkin/checkin_undo او checkin است)
 * با $day (حضور روزانه) فقط رخدادهای همان روز حساب می‌شوند.
 */
function cd_is_checked_in($event_id, $attendee_id, $day = null) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT kind, day, device_time FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id = %s AND kind IN ('checkin','checkin_undo')
         ORDER BY seq DESC",
        $event_id,
        $attendee_id
    ), ARRAY_A);
    foreach ($rows as $r) {
        if ($day !== null && cd_log_day($r) !== $day) {
            continue;
        }
        return $r['kind'] === 'checkin';
    }
    return false;
}

/** شمار تحویل فعلی یک وعده به یک نفر (تحویل منهای برگردان)، پیش از seq اگر داده شود. */
function cd_meal_count($event_id, $attendee_id, $meal_id, $before_seq = null) {
    global $wpdb;
    $n = $wpdb->get_var($wpdb->prepare(
        "SELECT COALESCE(SUM(CASE kind WHEN 'meal_served' THEN 1 WHEN 'meal_undo' THEN -1 ELSE 0 END), 0) FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id = %s AND meal_id = %d AND kind IN ('meal_served','meal_undo')" . ($before_seq !== null ? ' AND seq < %d' : ''),
        array_values(array_filter([$event_id, $attendee_id, (int) $meal_id, $before_seq], function ($v) {
            return $v !== null;
        }))
    ));
    return max(0, (int) $n);
}

/**
 * آیا نیروی این گوشی اجازه‌ی این کار را دارد؟ اجازه‌ها همان لحظه‌ی رسیدن به سرور سنجیده می‌شوند.
 * لغو پذیرش: مدیر، یا نیروی پذیرشی که آخرین پذیرش همان فرد را خودش زده (برگرداندن کار خودش).
 */
function cd_staff_may(array $device, $kind, $event_id, $attendee_id) {
    switch ($kind) {
        case 'checkin':
        case 'walkin_register':
            return (bool) (int) $device['can_checkin'];
        case 'meal_served':
            return (bool) (int) $device['can_serve'];
        case 'meal_undo':
            return (int) $device['can_serve'] || (int) $device['is_admin'];
        case 'onsite_settled':
            // تسویه‌ی پرداخت در محل: نیروی پذیرش یا مدیر.
            return (int) $device['can_checkin'] || (int) $device['is_admin'];
        case 'checkin_undo':
            if ((int) $device['is_admin']) {
                return true;
            }
            if (!(int) $device['can_checkin'] || $attendee_id === null) {
                return false;
            }
            global $wpdb;
            $by = $wpdb->get_var($wpdb->prepare(
                "SELECT staff_id FROM " . cd_table('event_log') . "
                 WHERE event_id = %d AND attendee_id = %s AND kind = 'checkin' ORDER BY seq DESC LIMIT 1",
                $event_id,
                $attendee_id
            ));
            return $by !== null && (int) $by === (int) $device['staff_id'];
    }
    return true;
}

/** ثبت کار ردشده تا در گزارش و صفحه‌ی امروز مدیر دیده شود. ارسال دوباره (همان uuid) تکرار نمی‌شود. */
function cd_store_rejection($event_id, array $device, array $e, $reason, $attendee_id) {
    global $wpdb;
    $row = [
        'uuid' => strtolower($e['uuid']),
        'event_id' => (int) $event_id,
        'device_id' => (int) $device['id'],
        'staff_id' => (int) $device['staff_id'],
        'kind' => $e['kind'],
        'reason' => $reason,
        'device_time' => cd_to_utc_datetime($e['device_time'] ?? null),
        'received_at' => cd_now(),
    ];
    if ($attendee_id !== null) {
        $row['attendee_id'] = $attendee_id;
    }
    if (!empty($e['card_token'])) {
        $row['card_token'] = $e['card_token'];
    }
    if (isset($e['meal_id'])) {
        $row['meal_id'] = (int) $e['meal_id'];
    }
    $wpdb->suppress_errors(true);
    $wpdb->insert(cd_table('rejected_events'), $row);
    $wpdb->suppress_errors(false);
}

function cd_card_for_event($token, $event_id) {
    global $wpdb;
    return $wpdb->get_row($wpdb->prepare(
        'SELECT * FROM ' . cd_table('cards') . ' WHERE token = %s AND event_id = %d',
        $token,
        $event_id
    ), ARRAY_A);
}

/**
 * ثبت یک دسته رخداد از گوشی. هر رخداد با UUID یکتاست، پس ارسال دوباره بی‌خطر است.
 * خروجی: [accepted, duplicates, rejected[]]
 */
function cd_push_events(array $event, array $device, array $items) {
    global $wpdb;
    $eid = (int) $event['id'];
    $config = cd_event_config($eid);
    $meals = [];
    foreach ($config['meals'] as $m) {
        $meals[$m['id']] = $m;
    }
    $type_ids = array_map(function ($t) {
        return $t['id'];
    }, $config['registration_types']);
    $role_ids = array_map(function ($r) {
        return $r['id'];
    }, $config['roles']);
    $daily = !empty(cd_event_settings($event)['daily_attendance']);
    // در رویداد «بدون کارت» ثبت‌نام در محل کارت نمی‌خواهد.
    $cards_required = cd_event_settings($event)['identify_mode'] !== 'none';

    $accepted = 0;
    $duplicates = 0;
    $rejected = [];
    $archived = cd_event_is_archived($event);

    foreach (array_slice($items, 0, CD_PUSH_LIMIT) as $i => $e) {
        if ($archived) {
            $rejected[] = ['index' => $i, 'uuid' => is_array($e) ? ($e['uuid'] ?? null) : null, 'reason' => 'event_archived'];
            continue;
        }
        $reason = cd_validate_event_item($e, $meals, $cards_required);
        if ($reason !== null) {
            $rejected[] = ['index' => $i, 'uuid' => is_array($e) ? ($e['uuid'] ?? null) : null, 'reason' => $reason];
            continue;
        }

        $uuid = strtolower($e['uuid']);
        $kind = $e['kind'];
        $card_token = isset($e['card_token']) && $e['card_token'] !== '' ? $e['card_token'] : null;
        $attendee_id = isset($e['attendee_id']) && $e['attendee_id'] !== '' ? strtolower($e['attendee_id']) : null;
        $meal_id = isset($e['meal_id']) ? (int) $e['meal_id'] : null;
        $payload = isset($e['payload']) && is_array($e['payload']) ? $e['payload'] : null;
        $device_time = cd_to_utc_datetime($e['device_time'] ?? null);
        // روز رویداد: اپ جدید می‌فرستد؛ اپ قدیمی نه، پس از زمان دستگاه به وقت سایت ساخته می‌شود.
        $day = isset($e['day']) && is_string($e['day']) && cd_valid_date($e['day']) ? $e['day'] : cd_event_day($device_time);

        $card = null;
        if ($card_token !== null) {
            $card = cd_card_for_event($card_token, $eid);
            if (!$card) {
                $rejected[] = ['index' => $i, 'uuid' => $uuid, 'reason' => 'unknown_card'];
                continue;
            }
            // کارت باطل: کاری که بعد از باطل‌شدن با آن ثبت شده رد می‌شود (کار پیش از آن، آفلاین، می‌ماند).
            if (!empty($card['revoked_at']) && cd_to_utc_datetime($e['device_time'] ?? null) >= $card['revoked_at']) {
                if ($wpdb->get_var($wpdb->prepare('SELECT seq FROM ' . cd_table('event_log') . ' WHERE uuid = %s', strtolower($e['uuid'])))) {
                    $duplicates++; // پیش از باطل‌شدن پذیرفته شده بود
                    continue;
                }
                cd_store_rejection($eid, $device, $e, 'card_revoked', $attendee_id ?? $card['attendee_id']);
                $rejected[] = ['index' => $i, 'uuid' => strtolower($e['uuid']), 'reason' => 'card_revoked'];
                continue;
            }
            if ($attendee_id === null && $card['attendee_id']) {
                $attendee_id = $card['attendee_id'];
            }
        }
        if ($kind === 'walkin_register') {
            $attendee_id = strtolower($payload['attendee']['id']);
        }

        // رخداد تکراری (همان uuid) نباید دوباره سنجیده یا رد شود.
        $known = $wpdb->get_var($wpdb->prepare('SELECT seq FROM ' . cd_table('event_log') . ' WHERE uuid = %s', $uuid));
        if ($known !== null) {
            $duplicates++;
            continue;
        }

        $deny = null;
        if (!cd_staff_may($device, $kind, $eid, $attendee_id)) {
            $deny = 'not_permitted';
        } elseif ($kind === 'checkin_undo' && ($attendee_id === null || !cd_is_checked_in($eid, $attendee_id, $daily ? $day : null))) {
            $deny = 'not_checked_in';
        } elseif ($kind === 'meal_undo' && ($attendee_id === null || cd_meal_count($eid, $attendee_id, $meal_id) < 1)) {
            $deny = 'not_served';
        } elseif ($kind === 'onsite_settled' && ($attendee_id === null || cd_onsite_due($eid, $attendee_id) < 1)) {
            $deny = 'nothing_due';
        }
        if ($kind === 'onsite_settled' && $deny === null) {
            // مبلغ از سرور؛ گوشی فقط می‌گوید «گرفته شد». تسویه‌ی دوباره علامت می‌خورد.
            $payload = [
                'amount' => cd_onsite_due($eid, $attendee_id),
                'actor' => $device['staff_name'] ?? '',
            ];
        }
        if ($deny !== null) {
            cd_store_rejection($eid, $device, $e, $deny, $attendee_id);
            $rejected[] = ['index' => $i, 'uuid' => $uuid, 'reason' => $deny];
            continue;
        }
        if ($kind === 'checkin_undo' || $kind === 'meal_undo') {
            // فاعل لغو همیشه ثبت می‌شود؛ دلیل اگر گوشی فرستاده باشد.
            $payload = [
                'reason' => cd_str(is_array($payload) ? ($payload['reason'] ?? '') : '', 191),
                'actor' => $device['staff_name'] ?? '',
                'actor_type' => 'staff',
            ];
        }

        $wpdb->query('START TRANSACTION');
        $inserted = $wpdb->query($wpdb->prepare(
            'INSERT IGNORE INTO ' . cd_table('event_log') . '
                (uuid, event_id, device_id, staff_id, kind, card_token, attendee_id, meal_id, payload, flag, day, device_time, received_at)
             VALUES (%s, %d, %d, %d, %s, ' . ($card_token === null ? 'NULL' : '%s') . ', ' . ($attendee_id === null ? 'NULL' : '%s') . ', ' . ($meal_id === null ? 'NULL' : '%d') . ', ' . ($payload === null ? 'NULL' : '%s') . ', NULL, %s, %s, %s)',
            array_values(array_filter([
                $uuid,
                $eid,
                (int) $device['id'],
                (int) $device['staff_id'],
                $kind,
                $card_token,
                $attendee_id,
                $meal_id,
                $payload === null ? null : wp_json_encode($payload),
                $day,
                $device_time,
                cd_now(),
            ], function ($v) {
                return $v !== null;
            }))
        ));

        if (!$inserted) {
            $wpdb->query('COMMIT');
            $duplicates++;
            continue;
        }
        $seq = (int) $wpdb->insert_id;

        $flag = null;
        if ($kind === 'walkin_register') {
            $flag = cd_apply_walkin($eid, $payload['attendee'], $card, $type_ids, $role_ids);
        } elseif ($kind === 'checkin') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_checkin_flag($eid, $attendee_id, $seq, $daily ? $day : null);
        } elseif ($kind === 'meal_served') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_meal_flag($eid, $attendee_id, $meals[$meal_id], $seq);
        } elseif ($kind === 'onsite_settled') {
            $flag = cd_onsite_settled($eid, $attendee_id, $seq) ? 'duplicate_settle' : null;
        }

        if ($flag !== null) {
            $wpdb->update(cd_table('event_log'), ['flag' => $flag], ['seq' => $seq]);
        }
        $wpdb->query('COMMIT');
        $accepted++;
    }

    $wpdb->update(cd_table('devices'), ['last_sync_at' => cd_now()], ['id' => (int) $device['id']]);

    return ['accepted' => $accepted, 'duplicates' => $duplicates, 'rejected' => $rejected];
}

function cd_validate_event_item($e, array $meals, $cards_required = true) {
    if (!is_array($e)) {
        return 'not_object';
    }
    if (!cd_is_uuid($e['uuid'] ?? null)) {
        return 'bad_uuid';
    }
    if (!in_array($e['kind'] ?? '', CD_EVENT_KINDS, true)) {
        return 'bad_kind';
    }
    if (isset($e['card_token']) && $e['card_token'] !== '' && $e['card_token'] !== null && !cd_is_card_token($e['card_token'])) {
        return 'bad_card_token';
    }
    if (isset($e['attendee_id']) && $e['attendee_id'] !== '' && $e['attendee_id'] !== null && !cd_is_uuid($e['attendee_id'])) {
        return 'bad_attendee_id';
    }
    $has_card = !empty($e['card_token']);
    $has_att = !empty($e['attendee_id']);

    switch ($e['kind']) {
        case 'checkin':
        case 'checkin_undo':
            if (!$has_card && !$has_att) {
                return 'missing_target';
            }
            break;
        case 'meal_served':
        case 'meal_undo':
            if (!$has_card && !$has_att) {
                return 'missing_target';
            }
            if (!isset($e['meal_id']) || !isset($meals[(int) $e['meal_id']])) {
                return 'bad_meal';
            }
            break;
        case 'onsite_settled':
            if (!$has_att) {
                return 'missing_target';
            }
            break;
        case 'walkin_register':
            $a = $e['payload']['attendee'] ?? null;
            if (!is_array($a) || !cd_is_uuid($a['id'] ?? null)) {
                return 'bad_walkin_attendee';
            }
            if (cd_str($a['first_name'] ?? '') === '' || cd_str($a['last_name'] ?? '') === '') {
                return 'walkin_missing_name';
            }
            if (!$has_card && $cards_required) {
                return 'walkin_missing_card';
            }
            break;
    }
    return null;
}

/** ساخت شرکت‌کننده‌ی ثبت‌نام در محل و وصل‌کردن کارت رزرو (اگر هست). خروجی: flag یا null. */
function cd_apply_walkin($event_id, array $a, ?array $card, array $type_ids, array $role_ids = []) {
    global $wpdb;
    $type_id = (int) ($a['registration_type_id'] ?? 0);
    if (!in_array($type_id, $type_ids, true)) {
        return 'bad_registration_type';
    }

    // نقش انتخاب‌شده در ثبت‌نام در محل ثبت می‌شود (قبلاً دور ریخته می‌شد). نقش ناشناخته: بی‌نقش و پرچم.
    $role_flag = null;
    $role_id = isset($a['role_id']) && $a['role_id'] !== null && $a['role_id'] !== '' ? (int) $a['role_id'] : null;
    if ($role_id !== null && !in_array($role_id, $role_ids, true)) {
        $role_id = null;
        $role_flag = 'bad_role';
    }
    $a['registration_type_id'] = $type_id;
    $a['role_id'] = $role_id;
    cd_upsert_attendee($event_id, $a, 'walkin', true);
    $attendee_id = strtolower($a['id']);

    $flag = null;
    if ($card === null) {
        // رویداد بدون کارت: فقط ثبت فرد.
    } elseif (!(int) $card['is_reserve']) {
        $flag = 'card_not_reserve';
    } else {
        $linked = $wpdb->query($wpdb->prepare(
            'UPDATE ' . cd_table('cards') . ' SET attendee_id = %s WHERE token = %s AND event_id = %d AND attendee_id IS NULL',
            $attendee_id,
            $card['token'],
            $event_id
        ));
        if (!$linked) {
            $current = $wpdb->get_var($wpdb->prepare('SELECT attendee_id FROM ' . cd_table('cards') . ' WHERE token = %s', $card['token']));
            if ($current !== $attendee_id) {
                $flag = 'card_conflict';
            }
        }
    }

    if ($flag === null) {
        $flag = $role_flag;
    }
    $mobile = cd_normalize_mobile($a['mobile'] ?? '');
    if ($flag === null && $mobile !== '') {
        $other = $wpdb->get_var($wpdb->prepare(
            'SELECT COUNT(*) FROM ' . cd_table('attendees') . ' WHERE event_id = %d AND mobile = %s AND id <> %s',
            $event_id,
            $mobile,
            $attendee_id
        ));
        if ((int) $other > 0) {
            $flag = 'possible_duplicate';
        }
    }
    return $flag;
}

/** آیا این فرد پیش از این رخداد در وضعیت «پذیرش‌شده» بوده؟ با $day فقط همان روز (حضور روزانه). */
function cd_checkin_flag($event_id, $attendee_id, $seq, $day = null) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT kind, day, device_time FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id = %s AND kind IN ('checkin','checkin_undo') AND seq < %d
         ORDER BY seq DESC",
        $event_id,
        $attendee_id,
        $seq
    ), ARRAY_A);
    foreach ($rows as $r) {
        if ($day !== null && cd_log_day($r) !== $day) {
            continue;
        }
        return $r['kind'] === 'checkin' ? 'duplicate_checkin' : null;
    }
    return null;
}

function cd_meal_flag($event_id, $attendee_id, array $meal, $seq) {
    global $wpdb;
    $a = $wpdb->get_row($wpdb->prepare(
        'SELECT registration_type_id, role_id, extra_meals FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d',
        $attendee_id,
        $event_id
    ), ARRAY_A);
    if (!$a) {
        return 'unknown_attendee';
    }
    if (!cd_is_entitled($meal['rules'], $a['registration_type_id'], $a['role_id'] !== null ? (int) $a['role_id'] : null, $meal['code'], $a['extra_meals'])) {
        return 'not_entitled';
    }
    // برگردان (meal_undo) تحویل قبلی را خنثی می‌کند.
    return cd_meal_count($event_id, $attendee_id, (int) $meal['id'], $seq) > 0 ? 'duplicate_meal' : null;
}

/** مبلغ «پرداخت در محل» یک نفر (تومان)، از صفحه‌ی ثبت‌نام. */
function cd_onsite_due($event_id, $attendee_id) {
    global $wpdb;
    return (int) $wpdb->get_var($wpdb->prepare(
        'SELECT onsite_due FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d',
        $attendee_id,
        $event_id
    ));
}

/** آیا تسویه‌ی در محل این نفر قبلاً ثبت شده؟ */
function cd_onsite_settled($event_id, $attendee_id, $before_seq = null) {
    global $wpdb;
    $sql = 'SELECT COUNT(*) FROM ' . cd_table('event_log') . " WHERE event_id = %d AND attendee_id = %s AND kind = 'onsite_settled'";
    $args = [$event_id, $attendee_id];
    if ($before_seq !== null) {
        $sql .= ' AND seq < %d';
        $args[] = (int) $before_seq;
    }
    return (int) $wpdb->get_var($wpdb->prepare($sql, $args)) > 0;
}
