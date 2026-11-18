<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * اتصال‌ها و پیام‌های ثبت‌نام:
 * - «اتصال دلخواه»: هر درگاه پرداخت یا سرویس پیامکی که با یک درخواست HTTP کار می‌کند، بدون برنامه‌نویسی.
 *   تنظیم آن برای کل سایت است (گزینه‌ی cd_reg_connections)؛ هدرها و بدنه رمزشده ذخیره می‌شوند.
 * - پیام به ثبت‌نام‌کننده (پیامک و ایمیل) با هر تغییر وضعیت، با گزارش «آخرین ارسال‌ها» و «تلاش دوباره».
 * - گزارش مالی و بایگانی و حذف ثبت‌نام.
 * سرویس پیامک دیگر را برنامه‌نویس با قلاب roydadyar_sms_providers اضافه می‌کند (همان شکل درگاه‌ها).
 */

const CD_REG_TRIGGERS = [
    'created' => 'ثبت شد (بدون پرداخت)',
    'pending_payment' => 'منتظر پرداخت',
    'pending_review' => 'رسید رسید؛ منتظر بررسی',
    'pending_approval' => 'منتظر تأیید مدیر',
    'confirmed' => 'تأیید شد',
    'rejected' => 'رد شد',
    'expired' => 'منقضی شد',
];

// ---------------------------------------------------------------- تنظیم اتصال‌ها

function cd_conn_secret() {
    return hash('sha256', 'cd-conn-enc|' . wp_salt('auth'), true);
}

function cd_conn_default() {
    return [
        'gateway' => [
            'name' => '',
            'unit' => 'toman',
            'start_url' => '', 'start_method' => 'POST', 'start_headers' => '', 'start_body' => '',
            'redirect_field' => '', 'authority_field' => '',
            'verify_url' => '', 'verify_method' => 'POST', 'verify_headers' => '', 'verify_body' => '',
            'verify_field' => '', 'callback_param' => '', 'success_value' => '',
            'test_mode' => false,
        ],
        'sms' => [
            'provider' => 'custom',
            'url' => '', 'method' => 'POST', 'headers' => '', 'body' => '',
            'sender' => '', 'success' => 'http200', 'success_text' => '',
        ],
    ];
}

/** تنظیم اتصال‌ها با هدر و بدنه‌ی بازشده (فقط برای مدیر). */
function cd_conn_get() {
    $d = cd_conn_default();
    $raw = get_option('cd_reg_connections', []);
    $raw = is_array($raw) ? $raw : [];
    $out = $d;
    foreach (['gateway', 'sms'] as $k) {
        $out[$k] = array_merge($d[$k], is_array($raw[$k] ?? null) ? $raw[$k] : []);
    }
    foreach (['start_headers', 'start_body', 'verify_headers', 'verify_body'] as $k) {
        $out['gateway'][$k] = (string) (cd_secretbox_decrypt((string) $out['gateway'][$k], cd_conn_secret()) ?? '');
    }
    foreach (['headers', 'body'] as $k) {
        $out['sms'][$k] = (string) (cd_secretbox_decrypt((string) $out['sms'][$k], cd_conn_secret()) ?? '');
    }
    return $out;
}

function cd_conn_text($v, $max = 4000) {
    $v = str_replace("\r\n", "\n", (string) $v);
    return function_exists('mb_substr') ? mb_substr($v, 0, $max) : substr($v, 0, $max);
}

function cd_conn_url($v) {
    return esc_url_raw(trim((string) $v), ['https', 'http']);
}

/** ذخیره‌ی اتصال‌ها از اپ مدیریت یا پیشخوان. */
function cd_conn_save($in) {
    $in = is_array($in) ? $in : [];
    $cur = cd_conn_get();
    $g = is_array($in['gateway'] ?? null) ? array_merge($cur['gateway'], $in['gateway']) : $cur['gateway'];
    $s = is_array($in['sms'] ?? null) ? array_merge($cur['sms'], $in['sms']) : $cur['sms'];
    $method = function ($v) {
        return in_array(strtoupper((string) $v), ['GET', 'POST'], true) ? strtoupper((string) $v) : 'POST';
    };
    $field = function ($v) {
        return preg_match('/^[A-Za-z0-9_.\-]{0,80}$/', (string) $v) ? (string) $v : '';
    };
    $enc = function ($v) {
        $v = cd_conn_text($v);
        return $v === '' ? '' : cd_secretbox_encrypt($v, cd_conn_secret());
    };
    $store = [
        'gateway' => [
            'name' => cd_str($g['name'] ?? '', 60),
            'unit' => ($g['unit'] ?? '') === 'rial' ? 'rial' : 'toman',
            'start_url' => cd_conn_url($g['start_url'] ?? ''),
            'start_method' => $method($g['start_method'] ?? 'POST'),
            'start_headers' => $enc($g['start_headers'] ?? ''),
            'start_body' => $enc($g['start_body'] ?? ''),
            'redirect_field' => $field($g['redirect_field'] ?? ''),
            'authority_field' => $field($g['authority_field'] ?? ''),
            'verify_url' => cd_conn_url($g['verify_url'] ?? ''),
            'verify_method' => $method($g['verify_method'] ?? 'POST'),
            'verify_headers' => $enc($g['verify_headers'] ?? ''),
            'verify_body' => $enc($g['verify_body'] ?? ''),
            'verify_field' => $field($g['verify_field'] ?? ''),
            'callback_param' => $field($g['callback_param'] ?? ''),
            'success_value' => cd_str($g['success_value'] ?? '', 80),
            'test_mode' => !empty($g['test_mode']),
        ],
        'sms' => [
            'provider' => cd_reg_id($s['provider'] ?? '') ?: 'custom',
            'url' => cd_conn_url($s['url'] ?? ''),
            'method' => $method($s['method'] ?? 'POST'),
            'headers' => $enc($s['headers'] ?? ''),
            'body' => $enc($s['body'] ?? ''),
            'sender' => cd_str($s['sender'] ?? '', 40),
            'success' => ($s['success'] ?? '') === 'text' ? 'text' : 'http200',
            'success_text' => cd_str($s['success_text'] ?? '', 80),
        ],
    ];
    update_option('cd_reg_connections', $store, false);
    return cd_conn_get();
}

/** «Name: value» در هر خط ← آرایه‌ی هدر. متغیرها جایگزین می‌شوند. */
function cd_conn_headers($text, array $vars) {
    $out = [];
    foreach (preg_split('/\n/', (string) $text) as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, ':') === false) {
            continue;
        }
        [$k, $v] = array_map('trim', explode(':', $line, 2));
        if (preg_match('/^[A-Za-z0-9-]{1,64}$/', $k)) {
            $out[$k] = cd_conn_fill($v, $vars, false);
        }
    }
    return $out;
}

/** جایگزینی {متغیر}ها. در بدنه‌ی JSON مقدارها escape می‌شوند. */
function cd_conn_fill($tpl, array $vars, $json = false) {
    return preg_replace_callback('/\{([a-z_]{1,30})\}/', function ($m) use ($vars, $json) {
        if (!array_key_exists($m[1], $vars)) {
            return $m[0];
        }
        $v = (string) $vars[$m[1]];
        return $json ? substr(wp_json_encode($v), 1, -1) : $v;
    }, (string) $tpl);
}

/** مقدار یک مسیر «data.url» از پاسخ JSON. */
function cd_conn_pick($data, $path) {
    if ($path === '') {
        return null;
    }
    foreach (explode('.', $path) as $k) {
        if (is_array($data) && array_key_exists($k, $data)) {
            $data = $data[$k];
        } else {
            return null;
        }
    }
    return is_scalar($data) ? (string) $data : null;
}

/** یک درخواست HTTP از روی تنظیم. خروجی: [کد HTTP، متن پاسخ، JSON یا null] یا WP_Error. */
function cd_conn_request($url, $method, $headers_tpl, $body_tpl, array $vars) {
    $url = cd_conn_fill($url, array_map('rawurlencode', $vars));
    $headers = cd_conn_headers($headers_tpl, $vars);
    $is_json = stripos(implode(' ', array_keys($headers)) . ' ' . implode(' ', $headers), 'json') !== false
        || preg_match('/^\s*[\[{]/', (string) $body_tpl);
    $body = cd_conn_fill($body_tpl, $vars, $is_json);
    if ($is_json && !isset($headers['Content-Type'])) {
        $headers['Content-Type'] = 'application/json';
    }
    $args = ['timeout' => 20, 'headers' => $headers, 'redirection' => 2];
    if ($method === 'GET') {
        $r = wp_remote_get($url, $args);
    } else {
        $args['body'] = $body;
        $r = wp_remote_post($url, $args);
    }
    if (is_wp_error($r)) {
        return $r;
    }
    $text = (string) wp_remote_retrieve_body($r);
    $json = json_decode($text, true);
    return [(int) wp_remote_retrieve_response_code($r), $text, is_array($json) ? $json : null];
}

// ---------------------------------------------------------------- درگاه دلخواه

/** درگاهی که از روی «اتصال دلخواه» ساخته می‌شود. */
class CD_Gateway_Custom implements CD_Payment_Gateway {
    public function name() {
        $g = cd_conn_get()['gateway'];
        return $g['name'] !== '' ? $g['name'] : 'درگاه دلخواه';
    }

    public function fields() {
        return []; // تنظیم در «اتصال‌ها»، نه در صفحه‌ی ثبت‌نام.
    }

    private function amount($toman, array $g) {
        return $g['unit'] === 'rial' ? (int) $toman * 10 : (int) $toman;
    }

    public function start(array $settings, $amount, $callback_url, array $reg) {
        $g = cd_conn_get()['gateway'];
        if ($g['start_url'] === '' || $g['redirect_field'] === '') {
            return new WP_Error('cd_pay', 'درگاه دلخواه کامل تنظیم نشده است (آدرس شروع و فیلد آدرس رفتن به درگاه).');
        }
        $vars = [
            'amount' => $this->amount($amount, $g),
            'callback' => $callback_url,
            'code' => $reg['code'],
            'mobile' => $reg['mobile'],
            'email' => $reg['email'] ?? '',
            'description' => 'ثبت‌نام ' . $reg['code'],
        ];
        $r = cd_conn_request($g['start_url'], $g['start_method'], $g['start_headers'], $g['start_body'], $vars);
        if (is_wp_error($r)) {
            return new WP_Error('cd_pay', 'به درگاه نرسیدیم: ' . $r->get_error_message());
        }
        [$http, , $json] = $r;
        $url = cd_conn_pick($json, $g['redirect_field']);
        if ($http >= 400 || !$url || !preg_match('#^https?://#', $url)) {
            return new WP_Error('cd_pay', 'درگاه پرداخت را شروع نکرد (HTTP ' . $http . ').');
        }
        $authority = cd_conn_pick($json, $g['authority_field']) ?? $reg['code'];
        return ['url' => $url, 'authority' => $authority];
    }

    public function verify(array $settings, $amount, array $reg, array $q) {
        $g = cd_conn_get()['gateway'];
        // ۱) پارامتر برگشت: اگر تعیین شده، باید با «مقدار موفق» یکی باشد.
        if ($g['callback_param'] !== '' && $g['verify_url'] === '') {
            $ok = isset($q[$g['callback_param']]) && (string) $q[$g['callback_param']] === $g['success_value'];
            return ['ok' => $ok, 'ref' => (string) ($q['ref'] ?? $q['RefID'] ?? $reg['pay_authority']), 'message' => $ok ? '' : 'پرداخت انجام نشد یا لغو شد.'];
        }
        if ($g['callback_param'] !== '' && isset($q[$g['callback_param']]) && $g['success_value'] !== ''
            && (string) $q[$g['callback_param']] !== $g['success_value']) {
            return ['ok' => false, 'ref' => '', 'message' => 'پرداخت انجام نشد یا لغو شد.'];
        }
        if ($g['verify_url'] === '') {
            return ['ok' => false, 'ref' => '', 'message' => 'تأیید پرداخت در درگاه دلخواه تنظیم نشده است.'];
        }
        // ۲) استعلام از درگاه.
        $vars = [
            'amount' => $this->amount($amount, $g),
            'authority' => $reg['pay_authority'],
            'code' => $reg['code'],
        ];
        foreach ($q as $k => $v) {
            if (is_scalar($v) && preg_match('/^[a-z_]{1,30}$/', (string) $k) && !isset($vars[$k])) {
                $vars[$k] = cd_str($v, 191);
            }
        }
        $r = cd_conn_request($g['verify_url'], $g['verify_method'], $g['verify_headers'], $g['verify_body'], $vars);
        if (is_wp_error($r)) {
            return ['ok' => false, 'ref' => '', 'message' => 'استعلام از درگاه ناموفق بود؛ اگر پولی کم شده با دبیرخانه تماس بگیرید.'];
        }
        [$http, $text, $json] = $r;
        $val = $g['verify_field'] !== '' ? cd_conn_pick($json, $g['verify_field']) : null;
        $ok = $http < 400 && ($g['verify_field'] === '' ? strpos($text, $g['success_value']) !== false : $val === $g['success_value']);
        return [
            'ok' => $ok,
            'ref' => (string) (cd_conn_pick($json, 'ref_id') ?? cd_conn_pick($json, 'data.ref_id') ?? $reg['pay_authority']),
            'message' => $ok ? '' : 'بانک پرداخت را تأیید نکرد؛ اگر پولی کم شده تا ۷۲ ساعت برمی‌گردد.',
        ];
    }
}

add_filter('roydadyar_payment_gateways', function ($list) {
    $list['custom'] = new CD_Gateway_Custom();
    return $list;
}, 5);

// ---------------------------------------------------------------- پیامک و ایمیل

/** سرویس‌های پیامک: «دلخواه» و هر چه برنامه‌نویس با قلاب اضافه کند. هر سرویس: callable($mobile, $text) → [ok, پاسخ]. */
function cd_sms_providers() {
    $list = apply_filters('roydadyar_sms_providers', [
        'custom' => ['name' => 'اتصال دلخواه', 'send' => 'cd_sms_send_custom'],
    ]);
    return is_array($list) ? $list : [];
}

function cd_sms_send_custom($mobile, $text) {
    $s = cd_conn_get()['sms'];
    if ($s['url'] === '') {
        return [false, 'سرویس پیامک تنظیم نشده است.'];
    }
    $r = cd_conn_request($s['url'], $s['method'], $s['headers'], $s['body'], [
        'mobile' => $mobile,
        'sender' => $s['sender'],
        'text' => $text,
    ]);
    if (is_wp_error($r)) {
        return [false, $r->get_error_message()];
    }
    [$http, $body] = $r;
    $ok = $s['success'] === 'text'
        ? ($s['success_text'] !== '' && strpos($body, $s['success_text']) !== false)
        : ($http >= 200 && $http < 300);
    return [$ok, 'HTTP ' . $http . ' · ' . cd_str($body, 300)];
}

/** ارسال یک پیام و ثبت در گزارش. خروجی: ردیف گزارش. */
function cd_msg_send($event_id, $reg_id, $channel, $recipient, $body, $trigger = '', $log_id = null) {
    global $wpdb;
    if ($channel === 'sms') {
        $p = cd_sms_providers()[cd_conn_get()['sms']['provider']] ?? (cd_sms_providers()['custom'] ?? null);
        [$ok, $resp] = $p && is_callable($p['send']) ? call_user_func($p['send'], $recipient, $body) : [false, 'سرویس پیامک پیدا نشد.'];
    } else {
        $event = cd_get_event((int) $event_id);
        $ok = $recipient !== '' && wp_mail($recipient, $event ? $event['name'] : 'ثبت‌نام', $body);
        $resp = $ok ? 'ایمیل فرستاده شد.' : 'ارسال ایمیل ناموفق بود (تنظیم ایمیل سایت را بررسی کنید).';
    }
    $row = [
        'ok' => $ok ? 1 : 0,
        'response' => cd_str($resp, 500),
        'created_at' => cd_now(),
    ];
    if ($log_id) {
        $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('reg_messages') . ' SET ok = %d, response = %s, tries = tries + 1, created_at = %s WHERE id = %d',
            $row['ok'], $row['response'], $row['created_at'], $log_id));
        $id = (int) $log_id;
    } else {
        $wpdb->insert(cd_table('reg_messages'), $row + [
            'event_id' => (int) $event_id,
            'registration_id' => $reg_id ? (int) $reg_id : null,
            'channel' => $channel,
            'trigger_key' => $trigger,
            'recipient' => cd_str($recipient, 191),
            'body' => $body,
        ]);
        $id = (int) $wpdb->insert_id;
    }
    return cd_msg_out($wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('reg_messages') . ' WHERE id = %d', $id), ARRAY_A));
}

function cd_msg_out($m) {
    if (!$m) {
        return null;
    }
    return [
        'id' => (int) $m['id'],
        'registration_id' => $m['registration_id'] !== null ? (int) $m['registration_id'] : null,
        'channel' => $m['channel'],
        'trigger' => $m['trigger_key'],
        'recipient' => $m['recipient'],
        'body' => $m['body'],
        'ok' => (bool) $m['ok'],
        'response' => $m['response'],
        'tries' => (int) $m['tries'],
        'at' => cd_iso($m['created_at']),
    ];
}

/** متن پیام با متغیرها: {name} {code} {event} {amount} {status} {link} {personal_link}. */
function cd_msg_render($tpl, array $page, array $reg) {
    $event = cd_get_event((int) $page['event_id']);
    $state = cd_reg_public_state($page, $reg);
    $link = add_query_arg(['code' => $reg['code'], 'k' => cd_reg_key($reg['code'])], cd_reg_page_url($page['config']));
    return strtr((string) $tpl, [
        '{name}' => trim($reg['first_name'] . ' ' . $reg['last_name']),
        '{code}' => $reg['code'],
        '{event}' => $event ? $event['name'] : '',
        '{amount}' => number_format((int) $reg['amount_online']) . ' تومان',
        '{status}' => cd_reg_statuses()[$reg['status']] ?? $reg['status'],
        '{link}' => $link,
        '{personal_link}' => $state['personal_url'] ?? '',
    ]);
}

/** پیام خودکار با هر تغییر وضعیت (اگر در صفحه‌ی ثبت‌نام روشن باشد). */
add_action('roydadyar_registration_status', function ($reg, $old, $page) {
    if (!is_array($reg) || !is_array($page)) {
        return;
    }
    $m = $page['config']['messages'] ?? null;
    if (!is_array($m)) {
        return;
    }
    $trigger = $old === null && $reg['status'] === 'confirmed' ? 'confirmed' : $reg['status'];
    if ($old === null && $reg['status'] === 'pending_approval') {
        $trigger = 'pending_approval';
    }
    $tpl = (string) ($m['templates'][$trigger] ?? '');
    if ($tpl === '') {
        return;
    }
    $text = cd_msg_render($tpl, $page, $reg);
    if (!empty($m['sms']) && $reg['mobile'] !== '') {
        cd_msg_send((int) $page['event_id'], (int) $reg['id'], 'sms', $reg['mobile'], $text, $trigger);
    }
    if (!empty($m['email']) && $reg['email'] !== '') {
        cd_msg_send((int) $page['event_id'], (int) $reg['id'], 'email', $reg['email'], $text, $trigger);
    }
}, 10, 3);

function cd_msg_default_templates() {
    return [
        'created' => '{name} عزیز، ثبت‌نام شما در «{event}» انجام شد. کد پیگیری: {code}',
        'pending_payment' => '{name} عزیز، ثبت‌نام «{event}» منتظر پرداخت {amount} است: {link}',
        'pending_review' => 'رسید پرداخت شما برای «{event}» رسید و بررسی می‌شود. کد: {code}',
        'pending_approval' => 'ثبت‌نام شما در «{event}» ثبت شد و منتظر تأیید است. کد: {code}',
        'confirmed' => '{name} عزیز، ثبت‌نام شما در «{event}» تأیید شد. کد: {code} {personal_link}',
        'rejected' => 'ثبت‌نام شما در «{event}» تأیید نشد. برای پیگیری: {link}',
        'expired' => 'مهلت پرداخت ثبت‌نام «{event}» تمام شد. برای ثبت دوباره: {link}',
    ];
}

/** تنظیم پیام‌ها در صفحه‌ی ثبت‌نام. */
function cd_sanitize_reg_messages($in) {
    $in = is_array($in) ? $in : [];
    $tpl = is_array($in['templates'] ?? null) ? $in['templates'] : [];
    $out = ['sms' => !empty($in['sms']), 'email' => !empty($in['email']), 'templates' => []];
    foreach (array_keys(CD_REG_TRIGGERS) as $k) {
        $v = array_key_exists($k, $tpl) ? (string) $tpl[$k] : (cd_msg_default_templates()[$k] ?? '');
        $out['templates'][$k] = function_exists('mb_substr') ? mb_substr(trim(wp_strip_all_tags($v)), 0, 500) : substr($v, 0, 500);
    }
    return $out;
}

// ---------------------------------------------------------------- گزارش مالی

/** گزارش مالی ثبت‌نام‌ها (تومان). بایگانی‌شده‌ها هم حساب می‌شوند؛ پول گرفته‌شده می‌ماند. */
function cd_reg_finance(array $event) {
    global $wpdb;
    $eid = (int) $event['id'];
    $rows = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE event_id = %d', $eid), ARRAY_A);
    $page = cd_reg_get_page_by_event($eid);
    $cfg = $page ? $page['config'] : cd_reg_default_config();
    $paid_states = ['pending_approval', 'confirmed'];
    $t = [
        'paid_online' => 0, 'paid_gateway' => 0, 'paid_card' => 0, 'paid_link' => 0, 'paid_count' => 0,
        'awaiting_payment' => 0, 'awaiting_review' => 0, 'rejected_paid' => 0,
        'onsite_due' => 0, 'onsite_settled' => 0, 'onsite_open' => 0,
        'registrations' => count($rows), 'confirmed' => 0,
    ];
    $by_type = [];
    $by_addon = [];
    $by_day = [];
    $settled = array_flip($wpdb->get_col($wpdb->prepare(
        "SELECT DISTINCT attendee_id FROM " . cd_table('event_log') . " WHERE event_id = %d AND kind = 'onsite_settled' AND attendee_id IS NOT NULL",
        $eid
    )));
    foreach ($rows as $r) {
        $online = (int) $r['amount_online'];
        $paid = $online > 0 && (in_array($r['status'], $paid_states, true) || ($r['status'] === 'rejected' && ($r['pay_ref'] !== '' || $r['pay_tracking'] !== '')));
        if ($r['status'] === 'confirmed') {
            $t['confirmed']++;
        }
        if ($r['status'] === 'pending_payment') {
            $t['awaiting_payment'] += $online;
        }
        if ($r['status'] === 'pending_review') {
            $t['awaiting_review'] += $online;
        }
        if ($paid) {
            if ($r['status'] === 'rejected') {
                $t['rejected_paid'] += $online; // پول گرفته شده ولی رد شد: باید برگردانده شود.
            } else {
                $t['paid_online'] += $online;
                $t['paid_count']++;
                $k = 'paid_' . (in_array($r['pay_method'], ['gateway', 'card', 'link'], true) ? $r['pay_method'] : 'gateway');
                $t[$k] += $online;
                $day = substr(cd_iso($r['paid_at'] ?: $r['updated_at']), 0, 10);
                $by_day[$day] = ($by_day[$day] ?? 0) + $online;
                $type = $r['type_code'];
                $by_type[$type] = $by_type[$type] ?? ['code' => $type, 'count' => 0, 'amount' => 0];
                $by_type[$type]['count']++;
            }
        }
        if ($r['status'] === 'confirmed' && (int) $r['amount_onsite'] > 0) {
            $t['onsite_due'] += (int) $r['amount_onsite'];
            if ($r['attendee_id'] && isset($settled[$r['attendee_id']])) {
                $t['onsite_settled'] += (int) $r['amount_onsite'];
            } else {
                $t['onsite_open']++;
            }
        }
        // تفکیک مبلغ: قیمت نوع و هر گزینه (فقط پرداخت‌شده‌ها).
        if ($paid && $r['status'] !== 'rejected') {
            $addons = (array) json_decode((string) $r['addons'], true);
            $type_price = 0;
            foreach ($cfg['types'] as $tp) {
                if ($tp['code'] === $r['type_code']) {
                    $type_price = (int) $tp['price'];
                }
            }
            $by_type[$r['type_code']]['amount'] += $type_price;
            foreach ($cfg['addons'] as $a) {
                if (in_array($a['id'], $addons, true) && $a['price_mode'] === 'online') {
                    $by_addon[$a['id']] = $by_addon[$a['id']] ?? ['id' => $a['id'], 'title' => $a['title'], 'count' => 0, 'amount' => 0];
                    $by_addon[$a['id']]['count']++;
                    $by_addon[$a['id']]['amount'] += (int) $a['price'];
                }
            }
        }
    }
    $names = cd_code_names('registration_types', $eid);
    foreach ($by_type as &$x) {
        $x['name'] = $names[$x['code']] ?? $x['code'];
    }
    unset($x);
    ksort($by_day);
    return [
        'totals' => $t,
        'by_type' => array_values($by_type),
        'by_addon' => array_values($by_addon),
        'by_day' => array_map(function ($d, $v) {
            return ['day' => $d, 'amount' => $v];
        }, array_keys($by_day), array_values($by_day)),
        'currency' => 'toman',
    ];
}

/** کد ← نام برای جدول‌های نوع و نقش. */
function cd_code_names($table, $event_id) {
    global $wpdb;
    $out = [];
    foreach ($wpdb->get_results($wpdb->prepare('SELECT code, name FROM ' . cd_table($table) . ' WHERE event_id = %d', $event_id), ARRAY_A) as $r) {
        $out[$r['code']] = $r['name'];
    }
    return $out;
}

// ---------------------------------------------------------------- بایگانی و حذف

/** آیا این ثبت‌نام پول یا ورود به لیست دارد (پس حذف کامل ممنوع است)؟ */
function cd_reg_has_history(array $reg) {
    return !empty($reg['attendee_id'])
        || $reg['pay_ref'] !== ''
        || $reg['pay_tracking'] !== ''
        || $reg['receipt_file'] !== ''
        || in_array($reg['status'], ['confirmed', 'pending_approval'], true) && (int) $reg['amount_online'] > 0;
}

/** بایگانی، برگرداندن از بایگانی یا حذف. حذف با پول یا ورود به لیست فقط بایگانی می‌کند. */
function cd_reg_archive_action(array $reg, $action, $confirm_code = '') {
    global $wpdb;
    $id = (int) $reg['id'];
    if ($action === 'archive') {
        $wpdb->update(cd_table('registrations'), ['archived_at' => cd_now(), 'updated_at' => cd_now()], ['id' => $id]);
        return ['result' => 'archived', 'registration' => cd_reg_get($id)];
    }
    if ($action === 'unarchive') {
        $wpdb->query($wpdb->prepare('UPDATE ' . cd_table('registrations') . ' SET archived_at = NULL, updated_at = %s WHERE id = %d', cd_now(), $id));
        return ['result' => 'unarchived', 'registration' => cd_reg_get($id)];
    }
    if ($action === 'delete') {
        if ($confirm_code !== null && strtoupper(trim((string) $confirm_code)) !== $reg['code']) {
            return cd_error('cd_reg_confirm', 'برای حذف، کد پیگیری «' . $reg['code'] . '» را بنویسید.', 400);
        }
        if (cd_reg_has_history($reg)) {
            $wpdb->update(cd_table('registrations'), ['archived_at' => cd_now(), 'updated_at' => cd_now()], ['id' => $id]);
            return ['result' => 'archived_instead', 'registration' => cd_reg_get($id),
                'message' => 'این ثبت‌نام پرداخت یا ورود به لیست دارد؛ به‌جای حذف بایگانی شد.'];
        }
        if ($reg['receipt_file'] !== '') {
            @unlink(cd_reg_receipts_dir() . '/' . basename($reg['receipt_file']));
        }
        $wpdb->delete(cd_table('registrations'), ['id' => $id]);
        return ['result' => 'deleted', 'registration' => null];
    }
    return cd_error('cd_reg_action', 'کار نامعتبر.', 400);
}

// ---------------------------------------------------------------- API اپ مدیریت

add_action('rest_api_init', function () {
    $code = '(?P<code>[A-Za-z0-9_-]{1,64})';
    $admin = 'cd_admin_permission';
    register_rest_route(CD_NS, '/admin/connections', [
        ['methods' => 'GET', 'permission_callback' => $admin, 'callback' => 'cd_rest_connections_get'],
        ['methods' => 'POST', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            cd_conn_save($r->get_param('connections'));
            return cd_rest_connections_get();
        }],
    ]);
    register_rest_route(CD_NS, '/admin/connections/test-sms', [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            $mobile = cd_normalize_mobile((string) $r->get_param('mobile'));
            if ($mobile === '') {
                return cd_error('cd_sms_mobile', 'شماره‌ی موبایل را درست بنویسید.');
            }
            $msg = cd_msg_send(0, null, 'sms', $mobile, 'پیام آزمایشی رویدادیار. اگر این را می‌خوانید، اتصال پیامک درست است.', 'test');
            return ['message' => $msg];
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/reg-page/test-payment", [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => 'cd_rest_reg_test_payment',
    ]);
    register_rest_route(CD_NS, '/reg/test-callback', [
        'methods' => 'GET', 'permission_callback' => '__return_true', 'callback' => 'cd_reg_test_callback',
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/finance", [
        'methods' => 'GET', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            $event = cd_event_from_request($r);
            return is_wp_error($event) ? $event : cd_reg_finance($event);
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/messages", [
        'methods' => 'GET', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            global $wpdb;
            $event = cd_event_from_request($r);
            if (is_wp_error($event)) {
                return $event;
            }
            $rows = $wpdb->get_results($wpdb->prepare(
                'SELECT * FROM ' . cd_table('reg_messages') . ' WHERE event_id IN (%d, 0) ORDER BY id DESC LIMIT 100',
                $event['id']
            ), ARRAY_A);
            return ['messages' => array_map('cd_msg_out', $rows), 'triggers' => CD_REG_TRIGGERS];
        },
    ]);
    register_rest_route(CD_NS, '/admin/messages/(?P<id>\d+)/retry', [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            global $wpdb;
            $m = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('reg_messages') . ' WHERE id = %d', (int) $r['id']), ARRAY_A);
            if (!$m) {
                return cd_error('cd_msg_not_found', 'پیام پیدا نشد.', 404);
            }
            return ['message' => cd_msg_send((int) $m['event_id'], $m['registration_id'], $m['channel'], $m['recipient'], $m['body'], $m['trigger_key'], (int) $m['id'])];
        },
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/registrations/bulk", [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            $event = cd_event_from_request($r);
            if (is_wp_error($event)) {
                return $event;
            }
            $action = (string) $r->get_param('action');
            $ids = array_slice(array_map('intval', (array) $r->get_param('ids')), 0, 500);
            $done = ['archived' => 0, 'unarchived' => 0, 'deleted' => 0, 'archived_instead' => 0];
            foreach ($ids as $id) {
                $reg = cd_reg_get($id);
                if (!$reg || (int) $reg['event_id'] !== (int) $event['id']) {
                    continue;
                }
                // حذف گروهی: تأیید با شمار ثبت‌نام‌ها در اپ گرفته می‌شود، نه کد تک‌تک.
                $res = cd_reg_archive_action($reg, $action, null);
                if (!is_wp_error($res)) {
                    $done[$res['result']]++;
                }
            }
            return ['done' => $done];
        },
    ]);
});

function cd_rest_connections_get() {
    $c = cd_conn_get();
    $providers = [];
    foreach (cd_sms_providers() as $id => $p) {
        $providers[] = ['id' => $id, 'name' => (string) ($p['name'] ?? $id)];
    }
    return [
        'connections' => $c,
        'gateways' => cd_payment_gateways_out(),
        'sms_providers' => $providers,
        'callback_url' => rest_url(CD_NS . '/reg/callback'),
        'variables' => [
            'gateway' => ['{amount}', '{callback}', '{code}', '{mobile}', '{email}', '{description}', '{authority}'],
            'sms' => ['{mobile}', '{sender}', '{text}'],
            'messages' => ['{name}', '{code}', '{event}', '{amount}', '{status}', '{link}', '{personal_link}'],
        ],
    ];
}

/** «آزمون با ۱۰۰ تومان»: یک پرداخت واقعی کوچک با درگاه انتخاب‌شده، بدون ثبت‌نام. */
function cd_rest_reg_test_payment(WP_REST_Request $r) {
    $event = cd_event_from_request($r);
    if (is_wp_error($event)) {
        return $event;
    }
    $page = cd_reg_get_page_by_event((int) $event['id']);
    $cfg = $page ? $page['config'] : cd_sanitize_reg_config($r->get_param('config'));
    $gid = (string) ($r->get_param('gateway') ?: $cfg['payment']['gateway']);
    $g = cd_payment_gateways()[$gid] ?? null;
    if (!$g) {
        return cd_error('cd_pay', 'درگاه انتخاب‌شده پیدا نشد.');
    }
    $code = 'T' . strtoupper(wp_generate_password(7, false, false));
    $fake = ['code' => $code, 'mobile' => '', 'email' => '', 'pay_authority' => ''];
    $callback = add_query_arg(['t' => $code, 'k' => cd_reg_key($code)], rest_url(CD_NS . '/reg/test-callback'));
    $res = $g->start($cfg['payment']['gateway_settings'], 100, $callback, $fake);
    if (is_wp_error($res)) {
        return $res;
    }
    set_transient('cd_reg_test_' . $code, ['gateway' => $gid, 'event' => (int) $event['id'], 'authority' => (string) ($res['authority'] ?? '')], DAY_IN_SECONDS);
    return ['url' => $res['url'], 'code' => $code];
}

function cd_reg_test_callback(WP_REST_Request $request) {
    $code = (string) $request->get_param('t');
    $t = get_transient('cd_reg_test_' . $code);
    if (!$t || !hash_equals(cd_reg_key($code), (string) $request->get_param('k'))) {
        return cd_error('cd_reg_not_found', 'آزمون پیدا نشد.', 404);
    }
    $page = cd_reg_get_page_by_event((int) $t['event']);
    $cfg = $page ? $page['config'] : cd_reg_default_config();
    $g = cd_payment_gateways()[$t['gateway']] ?? null;
    $v = $g ? $g->verify($cfg['payment']['gateway_settings'], 100, ['code' => $code, 'pay_authority' => $t['authority']], $request->get_query_params())
        : ['ok' => false, 'message' => 'درگاه پیدا نشد.'];
    update_option('cd_reg_last_test', ['ok' => !empty($v['ok']), 'ref' => (string) ($v['ref'] ?? ''), 'at' => gmdate('c'), 'gateway' => $t['gateway']], false);
    header('Content-Type: text/html; charset=utf-8');
    echo cd_reg_render_message( // phpcs:ignore WordPress.Security.EscapeOutput
        !empty($v['ok']) ? 'آزمون پرداخت موفق بود' : 'آزمون پرداخت ناموفق بود',
        !empty($v['ok']) ? 'درگاه پرداخت درست کار می‌کند. شماره‌ی پیگیری: ' . ($v['ref'] ?? '') : (string) ($v['message'] ?? '')
    );
    exit;
}
