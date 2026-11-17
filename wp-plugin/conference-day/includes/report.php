<?php
if (!defined('ABSPATH')) {
    exit;
}

const CD_FLAG_LABELS = [
    'duplicate_checkin' => 'پذیرش تکراری',
    'duplicate_meal' => 'دریافت تکراری وعده',
    'not_entitled' => 'بدون حق این وعده',
    'card_conflict' => 'کارت رزرو قبلاً به فرد دیگری وصل شده',
    'card_not_reserve' => 'کارت رزرو نیست',
    'possible_duplicate' => 'موبایل تکراری (احتمالاً ثبت دوباره)',
    'unknown_attendee' => 'کارت به کسی وصل نیست',
    'bad_registration_type' => 'نوع ثبت‌نام نامعتبر',
    'not_permitted' => 'کار بدون اجازه (سرور نپذیرفت)',
    'not_checked_in' => 'لغو پذیرش برای فرد پذیرش‌نشده (سرور نپذیرفت)',
    'not_served' => 'برگرداندن وعده‌ای که تحویل نشده بود (سرور نپذیرفت)',
    'card_revoked' => 'کارت باطل‌شده (سرور نپذیرفت)',
    'bad_role' => 'نقش نامعتبر در ثبت‌نام در محل (بی‌نقش ثبت شد)',
];

const CD_KIND_LABELS = [
    'checkin' => 'پذیرش',
    'checkin_undo' => 'لغو پذیرش',
    'walkin_register' => 'ثبت‌نام در محل',
    'meal_served' => 'تحویل وعده',
    'meal_undo' => 'برگرداندن وعده',
];

/**
 * وضعیت لحظه‌ای هر نفر از روی دفتر رخدادها:
 * [attendee_id => ['checked_in_at' => ?, 'days' => [day => checked_in_at], 'meals' => [meal_id => count]]]
 * checked_in_at همان رفتار قبلی است (روزها جدا نیستند)؛ days برای حضور روزانه است.
 * meal_undo یک تحویل را برمی‌گرداند.
 */
function cd_attendee_states($event_id) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT kind, attendee_id, meal_id, day, device_time FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id IS NOT NULL ORDER BY seq",
        $event_id
    ), ARRAY_A);

    $state = [];
    foreach ($rows as $r) {
        $aid = $r['attendee_id'];
        if (!isset($state[$aid])) {
            $state[$aid] = ['checked_in_at' => null, 'days' => [], 'meals' => []];
        }
        if ($r['kind'] === 'checkin' || $r['kind'] === 'checkin_undo') {
            $day = cd_log_day($r);
            if ($r['kind'] === 'checkin') {
                if ($state[$aid]['checked_in_at'] === null) {
                    $state[$aid]['checked_in_at'] = $r['device_time'];
                }
                if (empty($state[$aid]['days'][$day])) {
                    $state[$aid]['days'][$day] = $r['device_time'];
                }
            } else {
                $state[$aid]['checked_in_at'] = null;
                unset($state[$aid]['days'][$day]);
            }
        } elseif ($r['kind'] === 'meal_served') {
            $mid = (int) $r['meal_id'];
            $state[$aid]['meals'][$mid] = ($state[$aid]['meals'][$mid] ?? 0) + 1;
        } elseif ($r['kind'] === 'meal_undo') {
            $mid = (int) $r['meal_id'];
            $state[$aid]['meals'][$mid] = max(0, ($state[$aid]['meals'][$mid] ?? 0) - 1);
        }
    }
    return $state;
}

/** آیا این حالت فرد «پذیرش‌شده» است؟ حضور روزانه: در $day یا (بدون $day) دست‌کم یک روز. */
function cd_state_checked_in(?array $st, $daily, $day = null) {
    if ($st === null) {
        return false;
    }
    if (!$daily) {
        return $st['checked_in_at'] !== null;
    }
    return $day !== null ? !empty($st['days'][$day]) : !empty($st['days']);
}

/**
 * گزارش رویداد. $day (YYYY-MM-DD) در حضور روزانه یعنی پذیرش همان روز؛ وعده‌ها همیشه کل رویداد.
 */
function cd_build_report(array $event, $day = null) {
    global $wpdb;
    $eid = (int) $event['id'];
    $daily = !empty(cd_event_settings($event)['daily_attendance']);
    if ($day !== null && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $day)) {
        $day = null;
    }
    $config = cd_event_config($eid);
    $attendees = $wpdb->get_results($wpdb->prepare(
        'SELECT id, first_name, last_name, registration_type_id, role_id, source FROM ' . cd_table('attendees') . " WHERE event_id = %d AND status = 'active'",
        $eid
    ), ARRAY_A);
    $states = cd_attendee_states($eid);

    $checked_in = 0;
    $walkins = 0;
    $by_type = [];
    foreach ($config['registration_types'] as $t) {
        $by_type[$t['id']] = ['name' => $t['name'], 'total' => 0, 'checked_in' => 0];
    }
    foreach ($attendees as $a) {
        $tid = (int) $a['registration_type_id'];
        $in = cd_state_checked_in($states[$a['id']] ?? null, $daily, $day);
        if ($in) {
            $checked_in++;
        }
        if ($a['source'] === 'walkin') {
            $walkins++;
        }
        if (isset($by_type[$tid])) {
            $by_type[$tid]['total']++;
            if ($in) {
                $by_type[$tid]['checked_in']++;
            }
        }
    }

    // پذیرش به تفکیک روز (برای حضور روزانه و رویداد چندروزه).
    $by_day = [];
    foreach ($attendees as $a) {
        foreach (array_keys($states[$a['id']]['days'] ?? []) as $d) {
            $by_day[$d] = ($by_day[$d] ?? 0) + 1;
        }
    }
    ksort($by_day);

    $meals = [];
    foreach ($config['meals'] as $m) {
        $entitled = 0;
        $served = 0;
        $extra = 0;
        foreach ($attendees as $a) {
            $role = $a['role_id'] !== null ? (int) $a['role_id'] : null;
            if (cd_is_entitled($m['rules'], $a['registration_type_id'], $role)) {
                $entitled++;
            }
            $count = $states[$a['id']]['meals'][$m['id']] ?? 0;
            if ($count > 0) {
                $served++;
                $extra += $count - 1;
            }
        }
        $not_entitled = (int) $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM " . cd_table('event_log') . " WHERE event_id = %d AND meal_id = %d AND flag = 'not_entitled'",
            $eid,
            $m['id']
        ));
        $meals[] = [
            'id' => $m['id'],
            'name' => $m['name'],
            'day' => $m['day'],
            'active' => $m['active'],
            'entitled' => $entitled,
            'served' => $served,
            'duplicates' => $extra,
            'not_entitled' => $not_entitled,
        ];
    }

    $flagged = $wpdb->get_results($wpdb->prepare(
        'SELECT l.seq, l.kind, l.flag, l.device_time, l.card_token, a.first_name, a.last_name, s.name AS staff_name
         FROM ' . cd_table('event_log') . ' l
         LEFT JOIN ' . cd_table('attendees') . ' a ON a.id = l.attendee_id
         LEFT JOIN ' . cd_table('staff') . ' s ON s.id = l.staff_id
         WHERE l.event_id = %d AND l.flag IS NOT NULL
         ORDER BY l.seq DESC LIMIT 100',
        $eid
    ), ARRAY_A);

    // کارهایی که سرور نپذیرفت (بدون اجازه، لغو بی‌مورد) هم در موارد مشکوک می‌آیند.
    $rejected = $wpdb->get_results($wpdb->prepare(
        'SELECT 0 AS seq, r.kind, r.reason AS flag, r.device_time, r.card_token, a.first_name, a.last_name, s.name AS staff_name, 1 AS rejected
         FROM ' . cd_table('rejected_events') . ' r
         LEFT JOIN ' . cd_table('attendees') . ' a ON a.id = r.attendee_id
         LEFT JOIN ' . cd_table('staff') . ' s ON s.id = r.staff_id
         WHERE r.event_id = %d ORDER BY r.id DESC LIMIT 100',
        $eid
    ), ARRAY_A);
    $rejected_total = (int) $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('rejected_events') . ' WHERE event_id = %d', $eid));
    if ($rejected) {
        $flagged = array_merge($flagged, $rejected);
        usort($flagged, function ($a, $b) {
            return strcmp($b['device_time'], $a['device_time']);
        });
        $flagged = array_slice($flagged, 0, 100);
    }

    $devices = $wpdb->get_results($wpdb->prepare(
        'SELECT d.id, d.label, d.last_sync_at, d.revoked, s.name AS staff_name
         FROM ' . cd_table('devices') . ' d LEFT JOIN ' . cd_table('staff') . ' s ON s.id = d.staff_id
         WHERE d.event_id = %d ORDER BY d.last_sync_at DESC',
        $eid
    ), ARRAY_A);

    $reserve_free = (int) $wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM ' . cd_table('cards') . ' WHERE event_id = %d AND is_reserve = 1 AND attendee_id IS NULL',
        $eid
    ));

    return [
        'event' => cd_event_out($event),
        'totals' => [
            'attendees' => count($attendees),
            'checked_in' => $checked_in,
            'walkins' => $walkins,
            'reserve_cards_free' => $reserve_free,
            'rejected' => $rejected_total,
        ],
        'daily_attendance' => $daily,
        'day' => $day,
        'by_day' => array_map(function ($d, $n) {
            return ['day' => $d, 'checked_in' => $n];
        }, array_keys($by_day), array_values($by_day)),
        'by_registration_type' => array_values($by_type),
        'meals' => $meals,
        'flagged' => array_map(function ($f) {
            return [
                'seq' => (int) $f['seq'],
                'kind' => $f['kind'],
                'flag' => $f['flag'],
                'flag_label' => CD_FLAG_LABELS[$f['flag']] ?? $f['flag'],
                'name' => trim(($f['first_name'] ?? '') . ' ' . ($f['last_name'] ?? '')),
                'staff' => $f['staff_name'],
                'card_token' => $f['card_token'],
                'device_time' => cd_iso($f['device_time']),
                'rejected' => !empty($f['rejected']),
            ];
        }, $flagged),
        'devices' => array_map(function ($d) {
            return [
                'id' => (int) $d['id'],
                'label' => $d['label'],
                'staff' => $d['staff_name'],
                'last_sync_at' => cd_iso($d['last_sync_at']),
                'revoked' => (bool) $d['revoked'],
            ];
        }, $devices),
        'generated_at' => gmdate('c'),
    ];
}

/** خروجی CSV: هر نفر با زمان پذیرش و وعده‌های گرفته‌شده. */
function cd_export_csv(array $event) {
    global $wpdb;
    $eid = (int) $event['id'];
    $config = cd_event_config($eid);
    $types = [];
    foreach ($config['registration_types'] as $t) {
        $types[$t['id']] = $t['name'];
    }
    $roles = [];
    foreach ($config['roles'] as $r) {
        $roles[$r['id']] = $r['name'];
    }
    $attendees = $wpdb->get_results($wpdb->prepare(
        'SELECT a.*, c.serial FROM ' . cd_table('attendees') . ' a
         LEFT JOIN ' . cd_table('cards') . ' c ON c.attendee_id = a.id
         WHERE a.event_id = %d AND a.status = \'active\' ORDER BY a.last_name, a.first_name',
        $eid
    ), ARRAY_A);
    $states = cd_attendee_states($eid);

    $out = fopen('php://temp', 'r+');
    fwrite($out, "\xEF\xBB\xBF"); // BOM تا اکسل فارسی را درست باز کند
    $header = ['نام', 'نام خانوادگی', 'موبایل', 'ایمیل', 'سازمان', 'نوع ثبت‌نام', 'نقش', 'منبع', 'شماره کارت', 'زمان پذیرش'];
    foreach ($config['meals'] as $m) {
        $header[] = $m['name'];
    }
    fputcsv($out, $header);
    foreach ($attendees as $a) {
        $st = $states[$a['id']] ?? ['checked_in_at' => null, 'meals' => []];
        $row = [
            $a['first_name'],
            $a['last_name'],
            $a['mobile'],
            $a['email'],
            $a['organization'],
            $types[(int) $a['registration_type_id']] ?? '',
            $a['role_id'] !== null ? ($roles[(int) $a['role_id']] ?? '') : '',
            $a['source'] === 'walkin' ? 'ثبت در محل' : 'اکسل',
            $a['serial'] !== null ? (string) $a['serial'] : '',
            $st['checked_in_at'] ? get_date_from_gmt($st['checked_in_at'], 'Y-m-d H:i') : '',
        ];
        foreach ($config['meals'] as $m) {
            $row[] = (string) ($st['meals'][$m['id']] ?? 0);
        }
        fputcsv($out, $row);
    }
    rewind($out);
    $csv = stream_get_contents($out);
    fclose($out);
    return $csv;
}
