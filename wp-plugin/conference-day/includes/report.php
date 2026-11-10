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
    'meal_override' => 'تحویل با مجوز شفاهی',
    'staff_note' => 'خبر از نیرو',
    'walkin_no_card' => 'ثبت‌نام در محل بدون کارت (کارت رزرو تمام شده بود)',
    'attendee_has_card' => 'این فرد از قبل کارت دارد',
];

const CD_KIND_LABELS = [
    'checkin' => 'پذیرش',
    'checkin_undo' => 'لغو پذیرش',
    'walkin_register' => 'ثبت‌نام در محل',
    'meal_served' => 'تحویل وعده',
    'attendee_update' => 'تکمیل اطلاعات',
    'card_link' => 'وصل‌کردن کارت رزرو',
    'onsite_settled' => 'تسویه در روز اجرا',
    'staff_note' => 'خبر به مدیر',
];

/**
 * وضعیت لحظه‌ای هر نفر از روی دفتر رخدادها:
 * [attendee_id => ['checked_in_at' => ?, 'meals' => [meal_id => count]]]
 */
function cd_attendee_states($event_id) {
    global $wpdb;
    $rows = $wpdb->get_results($wpdb->prepare(
        "SELECT kind, attendee_id, meal_id, device_time FROM " . cd_table('event_log') . "
         WHERE event_id = %d AND attendee_id IS NOT NULL ORDER BY seq",
        $event_id
    ), ARRAY_A);

    $state = [];
    foreach ($rows as $r) {
        $aid = $r['attendee_id'];
        if (!isset($state[$aid])) {
            $state[$aid] = ['checked_in_at' => null, 'meals' => []];
        }
        if ($r['kind'] === 'checkin' && $state[$aid]['checked_in_at'] === null) {
            $state[$aid]['checked_in_at'] = $r['device_time'];
        } elseif ($r['kind'] === 'checkin_undo') {
            $state[$aid]['checked_in_at'] = null;
        } elseif ($r['kind'] === 'meal_served') {
            $mid = (int) $r['meal_id'];
            $state[$aid]['meals'][$mid] = ($state[$aid]['meals'][$mid] ?? 0) + 1;
        }
    }
    return $state;
}

function cd_build_report(array $event) {
    global $wpdb;
    $eid = (int) $event['id'];
    $config = cd_event_config($eid);
    $attendees = $wpdb->get_results($wpdb->prepare(
        'SELECT id, first_name, last_name, registration_type_id, role_id, source, extra_meals, onsite_due FROM ' . cd_table('attendees') . ' WHERE event_id = %d',
        $eid
    ), ARRAY_A);
    $states = cd_attendee_states($eid);

    $checked_in = 0;
    $walkins = 0;
    $walkins_no_card = 0;
    // «تسویه در روز اجرا»: مبلغ کل و آنچه نیروها «تسویه شد» زده‌اند.
    $onsite_due = 0;
    $onsite_settled = 0;
    $settled_ids = array_flip($wpdb->get_col($wpdb->prepare(
        "SELECT DISTINCT attendee_id FROM " . cd_table('event_log') . " WHERE event_id = %d AND kind = 'onsite_settled' AND attendee_id IS NOT NULL",
        $eid
    )) ?: []);
    $with_card = array_flip($wpdb->get_col($wpdb->prepare(
        'SELECT attendee_id FROM ' . cd_table('cards') . ' WHERE event_id = %d AND attendee_id IS NOT NULL',
        $eid
    )) ?: []);
    $by_type = [];
    foreach ($config['registration_types'] as $t) {
        $by_type[$t['id']] = ['name' => $t['name'], 'total' => 0, 'checked_in' => 0];
    }
    foreach ($attendees as $a) {
        $tid = (int) $a['registration_type_id'];
        $in = isset($states[$a['id']]) && $states[$a['id']]['checked_in_at'] !== null;
        if ($in) {
            $checked_in++;
        }
        if ((int) $a['onsite_due'] > 0) {
            $onsite_due += (int) $a['onsite_due'];
            if (isset($settled_ids[$a['id']])) {
                $onsite_settled += (int) $a['onsite_due'];
            }
        }
        if ($a['source'] === 'walkin') {
            $walkins++;
            if (!isset($with_card[$a['id']])) {
                $walkins_no_card++;
            }
        }
        if (isset($by_type[$tid])) {
            $by_type[$tid]['total']++;
            if ($in) {
                $by_type[$tid]['checked_in']++;
            }
        }
    }

    $meals = [];
    foreach ($config['meals'] as $m) {
        $entitled = 0;
        $served = 0;
        $extra = 0;
        foreach ($attendees as $a) {
            $role = $a['role_id'] !== null ? (int) $a['role_id'] : null;
            if (cd_is_entitled($m['rules'], $a['registration_type_id'], $role, $m['code'], $a['extra_meals'])) {
                $entitled++;
            }
            $count = $states[$a['id']]['meals'][$m['id']] ?? 0;
            if ($count > 0) {
                $served++;
                $extra += $count - 1;
            }
        }
        $not_entitled = (int) $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM " . cd_table('event_log') . " WHERE event_id = %d AND meal_id = %d AND flag IN ('not_entitled', 'meal_override')",
            $eid,
            $m['id']
        ));
        $meals[] = [
            'id' => $m['id'],
            'name' => $m['name'],
            'day' => $m['day'],
            'entitled' => $entitled,
            'served' => $served,
            'duplicates' => $extra,
            'not_entitled' => $not_entitled,
        ];
    }

    $flagged = $wpdb->get_results($wpdb->prepare(
        'SELECT l.seq, l.kind, l.flag, l.device_time, l.card_token, l.payload, l.attendee_id, l.resolved_at, l.resolved_by, a.first_name, a.last_name, s.name AS staff_name, d.label AS device_label
         FROM ' . cd_table('event_log') . ' l
         LEFT JOIN ' . cd_table('devices') . ' d ON d.id = l.device_id
         LEFT JOIN ' . cd_table('attendees') . ' a ON a.id = l.attendee_id
         LEFT JOIN ' . cd_table('staff') . ' s ON s.id = l.staff_id
         WHERE l.event_id = %d AND l.flag IS NOT NULL
         ORDER BY (l.resolved_at IS NULL) DESC, l.seq DESC LIMIT 150',
        $eid
    ), ARRAY_A);

    $devices = $wpdb->get_results($wpdb->prepare(
        'SELECT d.id, d.label, d.last_sync_at, d.revoked, d.pending, d.app_version, s.name AS staff_name,
                s.can_checkin, s.can_serve, s.is_admin,
                (SELECT COUNT(*) FROM ' . cd_table('event_log') . ' l WHERE l.device_id = d.id AND l.received_at >= %s) AS today_count
         FROM ' . cd_table('devices') . ' d LEFT JOIN ' . cd_table('staff') . ' s ON s.id = d.staff_id
         WHERE d.event_id = %d ORDER BY d.last_sync_at DESC',
        cd_tehran_day_start_utc(),
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
            'onsite_due' => $onsite_due,
            'onsite_settled' => $onsite_settled,
            // در رویداد کارت‌دار: ثبت‌نام‌هایی که کارت رزرو نداشتند (هنوز کارتی وصل نشده).
            'walkins_no_card' => cd_event_settings($event)['identify_mode'] !== 'none' ? $walkins_no_card : 0,
            'reserve_cards_free' => $reserve_free,
        ],
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
                'attendee_id' => $f['attendee_id'],
                'device' => $f['device_label'],
                'device_time' => cd_iso($f['device_time']),
                // «بررسی شد»: مدیر دیده و علامت را برداشته؛ از «نیاز به توجه» بیرون می‌رود.
                'resolved_at' => cd_iso($f['resolved_at']),
                'resolved_by' => $f['resolved_by'],
                // جزئیات: نام اجازه‌دهنده‌ی مجوز شفاهی، یا متن «خبر به مدیر».
                'detail' => cd_flag_detail($f),
            ];
        }, $flagged),
        'devices' => array_map(function ($d) {
            return [
                'id' => (int) $d['id'],
                'label' => $d['label'],
                'staff' => $d['staff_name'],
                'last_sync_at' => cd_iso($d['last_sync_at']),
                'revoked' => (bool) $d['revoked'],
                'pending' => (int) $d['pending'],
                'app_version' => $d['app_version'],
                'today_count' => (int) $d['today_count'],
                'roles' => array_values(array_filter([
                    !empty($d['can_checkin']) ? 'پذیرش' : null,
                    !empty($d['can_serve']) ? 'پذیرایی' : null,
                    !empty($d['is_admin']) ? 'مدیر' : null,
                ])),
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
         WHERE a.event_id = %d ORDER BY a.last_name, a.first_name',
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

function cd_flag_detail(array $f) {
    $p = !empty($f['payload']) ? json_decode($f['payload'], true) : null;
    if (!is_array($p)) {
        return '';
    }
    if ($f['flag'] === 'meal_override') {
        return 'اجازه: ' . cd_str($p['override_by'] ?? '', 100);
    }
    if ($f['flag'] === 'staff_note') {
        return cd_str($p['text'] ?? '', 500);
    }
    return '';
}
