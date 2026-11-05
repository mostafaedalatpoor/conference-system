<?php
if (!defined('ABSPATH')) {
    exit;
}

const CD_EVENT_KINDS = ['checkin', 'checkin_undo', 'walkin_register', 'meal_served'];
const CD_PULL_LIMIT = 1000;
const CD_PUSH_LIMIT = 500;

/** کل داده‌ای که یک گوشی برای کار آفلاین لازم دارد. */
function cd_build_snapshot(array $event) {
    global $wpdb;
    $eid = (int) $event['id'];

    $attendees = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('attendees') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $cards = $wpdb->get_results($wpdb->prepare('SELECT token, attendee_id, serial, is_reserve FROM ' . cd_table('cards') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $staff = $wpdb->get_results($wpdb->prepare('SELECT id, name FROM ' . cd_table('staff') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $log = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('event_log') . ' WHERE event_id = %d ORDER BY seq', $eid), ARRAY_A);
    $cursor = 0;
    foreach ($log as $l) {
        $cursor = max($cursor, (int) $l['seq']);
    }

    return array_merge(
        ['event' => cd_event_out($event)],
        cd_event_config($eid),
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
            'staff' => array_map(function ($s) {
                return ['id' => (int) $s['id'], 'name' => $s['name']];
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

    $accepted = 0;
    $duplicates = 0;
    $rejected = [];

    foreach (array_slice($items, 0, CD_PUSH_LIMIT) as $i => $e) {
        $reason = cd_validate_event_item($e, $meals);
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
            $flag = cd_apply_walkin($eid, $payload['attendee'], $card, $type_ids);
        } elseif ($kind === 'checkin') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_checkin_flag($eid, $attendee_id, $seq);
        } elseif ($kind === 'meal_served') {
            $flag = $attendee_id === null ? 'unknown_attendee' : cd_meal_flag($eid, $attendee_id, $meals[$meal_id], $seq);
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

function cd_validate_event_item($e, array $meals) {
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
        case 'walkin_register':
            $a = $e['payload']['attendee'] ?? null;
            if (!is_array($a) || !cd_is_uuid($a['id'] ?? null)) {
                return 'bad_walkin_attendee';
            }
            if (cd_str($a['first_name'] ?? '') === '' || cd_str($a['last_name'] ?? '') === '') {
                return 'walkin_missing_name';
            }
            if (!$has_card) {
                return 'walkin_missing_card';
            }
            break;
    }
    return null;
}

/** ساخت شرکت‌کننده‌ی ثبت‌نام در محل و وصل‌کردن کارت رزرو. خروجی: flag یا null. */
function cd_apply_walkin($event_id, array $a, array $card, array $type_ids) {
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
    if (!(int) $card['is_reserve']) {
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
    return $flag;
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
        'SELECT registration_type_id, role_id FROM ' . cd_table('attendees') . ' WHERE id = %s AND event_id = %d',
        $attendee_id,
        $event_id
    ), ARRAY_A);
    if (!$a) {
        return 'unknown_attendee';
    }
    if (!cd_is_entitled($meal['rules'], $a['registration_type_id'], $a['role_id'] !== null ? (int) $a['role_id'] : null)) {
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
