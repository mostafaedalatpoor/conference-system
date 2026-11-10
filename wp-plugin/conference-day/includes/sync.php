<?php
if (!defined('ABSPATH')) {
    exit;
}

const CD_EVENT_KINDS = ['checkin', 'checkin_undo', 'walkin_register', 'meal_served', 'attendee_update', 'card_link', 'onsite_settled', 'staff_note'];

/** فیلدهایی که نیرو می‌تواند برای فردِ ناقص تکمیل کند. */
const CD_COMPLETABLE_FIELDS = ['first_name', 'last_name', 'mobile', 'email'];
const CD_PULL_LIMIT = 1000;
const CD_PUSH_LIMIT = 500;

/** کل داده‌ای که یک گوشی برای کار آفلاین لازم دارد. */
function cd_build_snapshot(array $event, $for_admin = false) {
    global $wpdb;
    $eid = (int) $event['id'];

    $attendees = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('attendees') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $cards = $wpdb->get_results($wpdb->prepare('SELECT token, attendee_id, serial, is_reserve FROM ' . cd_table('cards') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $staff = $wpdb->get_results($wpdb->prepare('SELECT id, name, can_checkin, can_serve, is_admin, active, (pin_hash <> \'\') AS has_pin FROM ' . cd_table('staff') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $log = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('event_log') . ' WHERE event_id = %d ORDER BY seq', $eid), ARRAY_A);
    $cursor = 0;
    foreach ($log as $l) {
        $cursor = max($cursor, (int) $l['seq']);
    }

    return array_merge(
        ['event' => cd_event_out($event)],
        cd_event_config($eid),
        [
            'attendees' => array_map(function ($a) use ($for_admin) {
                return cd_attendee_out($a, $for_admin);
            }, $attendees),
            'cards' => array_map(function ($c) {
                return [
                    'token' => $c['token'],
                    'attendee_id' => $c['attendee_id'],
                    'serial' => (int) $c['serial'],
                    'is_reserve' => (bool) $c['is_reserve'],
                ];
            }, $cards),
            'staff' => array_map(function ($s) use ($for_admin) {
                $out = ['id' => (int) $s['id'], 'name' => $s['name']];
                // اپ مدیریت دسترسی‌ها را هم می‌گیرد تا ذخیره از دستگاه دیگر آن‌ها را عوض نکند.
                if ($for_admin) {
                    $out += [
                        'can_checkin' => (bool) $s['can_checkin'],
                        'can_serve' => (bool) $s['can_serve'],
                        'is_admin' => (bool) $s['is_admin'],
                        'active' => (bool) $s['active'],
                        'has_pin' => (bool) $s['has_pin'],
                    ];
                }
                return $out;
            }, $staff),
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
    // در رویداد «بدون کارت» ثبت‌نام در محل کارت نمی‌خواهد.
    $cards_required = cd_event_settings($event)['identify_mode'] !== 'none';

    $accepted = 0;
    $duplicates = 0;
    $rejected = [];

    foreach (array_slice($items, 0, CD_PUSH_LIMIT) as $i => $e) {
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

        $card = null;
        if ($card_token !== null) {
            $card = cd_card_for_event($card_token, $eid);
            if (!$card) {
                $rejected[] = ['index' => $i, 'uuid' => $uuid, 'reason' => 'unknown_card'];
                continue;
            }
            if ($attendee_id === null && $card['attendee_id']) {
                $attendee_id = $card['attendee_id'];
            }
        }
        if ($kind === 'walkin_register') {
            $attendee_id = strtolower($payload['attendee']['id']);
        }

        $wpdb->query('START TRANSACTION');
        $inserted = $wpdb->query($wpdb->prepare(
            'INSERT IGNORE INTO ' . cd_table('event_log') . '
                (uuid, event_id, device_id, staff_id, kind, card_token, attendee_id, meal_id, payload, flag, device_time, received_at)
             VALUES (%s, %d, %d, %d, %s, ' . ($card_token === null ? 'NULL' : '%s') . ', ' . ($attendee_id === null ? 'NULL' : '%s') . ', ' . ($meal_id === null ? 'NULL' : '%d') . ', ' . ($payload === null ? 'NULL' : '%s') . ', NULL, %s, %s)',
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
                cd_to_utc_datetime($e['device_time'] ?? null),
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
            $flag = cd_apply_walkin($eid, $payload['attendee'], $card, $type_ids, $cards_required);
        } elseif ($kind === 'checkin') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_checkin_flag($eid, $attendee_id, $seq);
        } elseif ($kind === 'card_link') {
            $flag = cd_apply_card_link($eid, $attendee_id, $card);
        } elseif ($kind === 'attendee_update') {
            $flag = cd_apply_attendee_update($eid, $attendee_id, $payload);
        } elseif ($kind === 'meal_served') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_meal_flag($eid, $attendee_id, $meals[$meal_id], $seq);
            // «تحویل با مجوز شفاهی»: نیرو می‌دانست شامل نیست و با اجازه‌ی کسی تحویل داد.
            if ($flag === 'not_entitled' && cd_str($payload['override_by'] ?? '', 100) !== '') {
                $flag = 'meal_override';
            }
        } elseif ($kind === 'staff_note') {
            // «خبر به مدیر» از گوشی نیرو؛ در موارد مشکوک گزارش می‌آید.
            $flag = 'staff_note';
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
            if (!$has_card && !$has_att) {
                return 'missing_target';
            }
            if (!isset($e['meal_id']) || !isset($meals[(int) $e['meal_id']])) {
                return 'bad_meal';
            }
            break;
        case 'attendee_update':
            // تکمیل اطلاعات فردی که در ثبت‌نام ناقص وارد شده؛ فقط فیلدهای مجاز.
            if (!$has_att) {
                return 'missing_target';
            }
            $f = $e['payload']['fields'] ?? null;
            if (!is_array($f) || !array_intersect(array_keys($f), CD_COMPLETABLE_FIELDS)) {
                return 'bad_update_fields';
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
            // کارت رزرو تمام شده باشد، بدون کارت هم ثبت می‌شود (با flag برای گزارش).
            break;
        case 'staff_note':
            if (cd_str($e['payload']['text'] ?? '', 500) === '') {
                return 'bad_note';
            }
            break;
        case 'onsite_settled':
            // «تسویه شد» برای مبلغ گزینه‌های «تسویه در روز اجرا».
            if (!$has_att) {
                return 'missing_target';
            }
            break;
        case 'card_link':
            // وصل‌کردن کارت رزرو به کسی که بدون کارت ثبت‌نام شده بود.
            if (!$has_card || !$has_att) {
                return 'missing_target';
            }
            break;
    }
    return null;
}

/** ساخت شرکت‌کننده‌ی ثبت‌نام در محل و وصل‌کردن کارت رزرو (اگر هست). خروجی: flag یا null. */
function cd_apply_walkin($event_id, array $a, ?array $card, array $type_ids, $cards_required = false) {
    global $wpdb;
    $type_id = (int) ($a['registration_type_id'] ?? 0);
    if (!in_array($type_id, $type_ids, true)) {
        return 'bad_registration_type';
    }

    $a['registration_type_id'] = $type_id;
    $a['role_id'] = null;
    cd_upsert_attendee($event_id, $a, 'walkin', true);
    $attendee_id = strtolower($a['id']);

    $flag = null;
    if ($card === null) {
        // رویداد بدون کارت: فقط ثبت فرد. رویداد کارت‌دار: کارت رزرو تمام شده بود.
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
    if ($flag === null && $card === null && $cards_required) {
        $flag = 'walkin_no_card';
    }
    return $flag;
}

/** کارت رزرو آزاد را به فردی که کارت ندارد وصل می‌کند. خروجی: flag یا null. */
function cd_apply_card_link($event_id, $attendee_id, ?array $card) {
    global $wpdb;
    if ($card === null) {
        return 'unknown_card';
    }
    if (!(int) $card['is_reserve']) {
        return 'card_not_reserve';
    }
    $exists = $wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d',
        $attendee_id,
        $event_id
    ));
    if (!(int) $exists) {
        return 'unknown_attendee';
    }
    $has = $wpdb->get_var($wpdb->prepare(
        'SELECT token FROM ' . cd_table('cards') . ' WHERE event_id = %d AND attendee_id = %s AND token <> %s LIMIT 1',
        $event_id,
        $attendee_id,
        $card['token']
    ));
    if ($has) {
        return 'attendee_has_card';
    }
    $linked = $wpdb->query($wpdb->prepare(
        'UPDATE ' . cd_table('cards') . ' SET attendee_id = %s WHERE token = %s AND event_id = %d AND attendee_id IS NULL',
        $attendee_id,
        $card['token'],
        $event_id
    ));
    if (!$linked && $card['attendee_id'] !== $attendee_id) {
        return 'card_conflict';
    }
    return null;
}

/** آیا این فرد پیش از این رخداد در وضعیت «پذیرش‌شده» بوده؟ */
function cd_checkin_flag($event_id, $attendee_id, $seq) {
    global $wpdb;
    $last = $wpdb->get_var($wpdb->prepare(
        "SELECT kind FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id = %s AND kind IN ('checkin','checkin_undo') AND seq < %d
         ORDER BY seq DESC LIMIT 1",
        $event_id,
        $attendee_id,
        $seq
    ));
    return $last === 'checkin' ? 'duplicate_checkin' : null;
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
    $before = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id = %s AND kind = 'meal_served' AND meal_id = %d AND seq < %d",
        $event_id,
        $attendee_id,
        (int) $meal['id'],
        $seq
    ));
    return (int) $before > 0 ? 'duplicate_meal' : null;
}

/**
 * تکمیل اطلاعات یک نفر از گوشی نیرو. فقط فیلدهای مجاز و غیرخالی عوض می‌شوند؛ چیزی پاک نمی‌شود.
 * رخداد در دفتر می‌ماند و گوشی‌های دیگر با pull همان را روی داده‌ی خودشان اعمال می‌کنند.
 */
function cd_apply_attendee_update($event_id, $attendee_id, $payload) {
    global $wpdb;
    $a = $wpdb->get_row($wpdb->prepare(
        'SELECT * FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d',
        $attendee_id,
        $event_id
    ), ARRAY_A);
    if (!$a) {
        return 'unknown_attendee';
    }
    $set = cd_completion_fields($payload['fields'] ?? []);
    if (!$set) {
        return null;
    }
    $row = array_merge($a, $set);
    $set['search_key'] = cd_search_key($row);
    $set['updated_at'] = cd_now();
    $wpdb->update(cd_table('attendees'), $set, ['id' => $attendee_id, 'event_id' => (int) $event_id]);
    return null;
}

/** فیلدهای تکمیل، پاک‌شده؛ مقدار خالی یعنی «دست نزن». */
function cd_completion_fields($fields) {
    $set = [];
    if (!is_array($fields)) {
        return $set;
    }
    foreach (CD_COMPLETABLE_FIELDS as $k) {
        if (!isset($fields[$k])) {
            continue;
        }
        if ($k === 'mobile') {
            $v = cd_normalize_mobile($fields[$k]);
        } elseif ($k === 'email') {
            $v = sanitize_email((string) $fields[$k]);
        } else {
            $v = cd_str($fields[$k]);
        }
        if ($v !== '') {
            $set[$k] = $v;
        }
    }
    return $set;
}
