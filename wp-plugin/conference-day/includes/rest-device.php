<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * API گوشی نیروها. ورود با کد رویداد + PIN؛ بعد از آن هر درخواست هدر
 * X-Conf-Device را با توکنی که ورود برگردانده می‌فرستد.
 */

// قفل تلاش ناموفق (آ-۳): به‌ازای (IP، کد رویداد)، ۳۰ تلاش در ۱۰ دقیقه از اولین تلاش ناموفق.
// سالن همایش معمولاً یک IP بیرونی دارد؛ شمارنده‌ی جدا برای هر رویداد و آستانه‌ی بالاتر
// جلوی بسته‌شدن ورود همه‌ی نیروها با چند اشتباه را می‌گیرد، و حدس PIN همچنان کند می‌ماند.
const CD_LOGIN_MAX_FAILS = 30;
const CD_LOGIN_WINDOW = 600; // ثانیه

/** کلید شمارنده‌ی تلاش ناموفق برای این IP و این کد رویداد. */
function cd_login_fail_key($event_code) {
    return 'cd_login_fail_' . md5(cd_client_ip() . '|' . strtolower(trim((string) $event_code)));
}

/** وضعیت شمارنده: [شمار، زمان پایان پنجره]. */
function cd_login_fails($key) {
    $v = get_transient($key);
    if (!is_array($v) || (int) ($v['until'] ?? 0) <= time()) {
        return [0, 0];
    }
    return [(int) $v['n'], (int) $v['until']];
}

/** گوشی فعلی، بعد از عبور از permission_callback. */
function cd_current_device($set = null) {
    static $device = null;
    if ($set !== null) {
        $device = $set;
    }
    return $device;
}

function cd_device_permission(WP_REST_Request $request) {
    global $wpdb;
    $token = (string) $request->get_header('x-conf-device');
    if ($token === '') {
        return cd_error('cd_device_auth', 'توکن گوشی لازم است.', 401);
    }
    $device = $wpdb->get_row($wpdb->prepare(
        'SELECT d.*, s.active AS staff_active, s.name AS staff_name, s.can_checkin, s.can_serve, s.is_admin
         FROM ' . cd_table('devices') . ' d JOIN ' . cd_table('staff') . ' s ON s.id = d.staff_id
         WHERE d.token_hash = %s',
        hash('sha256', $token)
    ), ARRAY_A);
    if (!$device || (int) $device['revoked'] || !(int) $device['staff_active']) {
        return cd_error('cd_device_revoked', 'این گوشی دیگر مجاز نیست. دوباره وارد شوید.', 401);
    }
    cd_current_device($device);
    return true;
}

add_action('rest_api_init', function () {
    register_rest_route(CD_NS, '/device/login', [
        'methods' => 'POST',
        'permission_callback' => '__return_true',
        'callback' => 'cd_rest_device_login',
    ]);

    register_rest_route(CD_NS, '/device/snapshot', [
        'methods' => 'GET',
        'permission_callback' => 'cd_device_permission',
        'callback' => function () {
            $device = cd_current_device();
            $event = cd_get_event((int) $device['event_id']);
            $snap = cd_build_snapshot($event);
            $snap['me'] = cd_device_me($device);
            return $snap;
        },
    ]);

    register_rest_route(CD_NS, '/device/sync', [
        'methods' => 'POST',
        'permission_callback' => 'cd_device_permission',
        'callback' => 'cd_rest_device_sync',
    ]);
});

function cd_device_me(array $device) {
    return [
        'device_id' => (int) $device['id'],
        'staff_id' => (int) $device['staff_id'],
        'staff_name' => $device['staff_name'],
        'can_checkin' => (bool) $device['can_checkin'],
        'can_serve' => (bool) $device['can_serve'],
        'is_admin' => (bool) $device['is_admin'],
    ];
}

function cd_rest_device_login(WP_REST_Request $request) {
    global $wpdb;
    $ip_key = cd_login_fail_key($request->get_param('event_code'));
    [$fails, $until] = cd_login_fails($ip_key);
    if ($fails >= CD_LOGIN_MAX_FAILS) {
        $left = max(60, $until - time());
        $minutes = (int) ceil($left / 60);
        return cd_error(
            'cd_login_locked',
            'تلاش ناموفق زیاد بود. ' . cd_fa_digits((string) $minutes) . ' دقیقه دیگر دوباره امتحان کنید.',
            429,
            ['retry_after' => $left]
        );
    }

    $event = cd_get_event_by_code((string) $request->get_param('event_code'));
    $pin = cd_latin_digits((string) $request->get_param('pin'));
    $label = cd_str($request->get_param('label') ?? '');

    if ($event && cd_event_is_archived($event)) {
        return cd_error('cd_event_archived', 'این رویداد بایگانی شده است و ورود به آن ممکن نیست.', 403);
    }

    $staff = null;
    if ($event && preg_match('/^\d{4,8}$/', $pin)) {
        $rows = $wpdb->get_results($wpdb->prepare(
            'SELECT * FROM ' . cd_table('staff') . " WHERE event_id = %d AND active = 1 AND pin_hash <> ''",
            (int) $event['id']
        ), ARRAY_A);
        foreach ($rows as $s) {
            if (wp_check_password($pin, $s['pin_hash'])) {
                $staff = $s;
                break;
            }
        }
    }

    if (!$staff) {
        $until = $fails === 0 ? time() + CD_LOGIN_WINDOW : $until;
        set_transient($ip_key, ['n' => $fails + 1, 'until' => $until], max(1, $until - time()));
        return cd_error('cd_login_failed', 'کد رویداد یا PIN اشتباه است.', 401);
    }

    $token = cd_random_token(32);
    $wpdb->insert(cd_table('devices'), [
        'event_id' => (int) $event['id'],
        'staff_id' => (int) $staff['id'],
        'label' => $label,
        'token_hash' => hash('sha256', $token),
        'created_at' => cd_now(),
    ]);
    $device = [
        'id' => (int) $wpdb->insert_id,
        'staff_id' => (int) $staff['id'],
        'staff_name' => $staff['name'],
        'can_checkin' => $staff['can_checkin'],
        'can_serve' => $staff['can_serve'],
        'is_admin' => $staff['is_admin'],
    ];
    delete_transient($ip_key);

    return [
        'token' => $token,
        'event' => cd_event_out($event),
        'me' => cd_device_me($device),
    ];
}

/**
 * یک دور همگام‌سازی: رخدادهای جدید گوشی را می‌گیرد و رخدادهای بعد از since را برمی‌گرداند.
 * اگر config_version عوض شده باشد، گوشی باید snapshot را دوباره بگیرد.
 */
function cd_rest_device_sync(WP_REST_Request $request) {
    $device = cd_current_device();
    $event = cd_get_event((int) $device['event_id']);

    $items = $request->get_param('events');
    $push = ['accepted' => 0, 'duplicates' => 0, 'rejected' => []];
    if (is_array($items) && $items) {
        $push = cd_push_events($event, $device, $items);
    } else {
        global $wpdb;
        $wpdb->update(cd_table('devices'), ['last_sync_at' => cd_now()], ['id' => (int) $device['id']]);
    }

    $since = max(0, (int) $request->get_param('since'));
    $pull = cd_pull_events((int) $event['id'], $since);

    return array_merge($push, $pull, [
        'config_version' => (int) $event['config_version'],
        'server_time' => gmdate('c'),
    ]);
}
