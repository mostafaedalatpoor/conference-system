<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * کلیدهای مدیریت (بند آ-۲ و مورد ۲۲): یک فهرست واحد در گزینه‌ی cd_admin_keys.
 * هر کلید: {id, label, role, hash, enc, created_at, last_used, revoked, legacy}
 * - role: owner (همه‌چیز)، manager (همه‌چیز جز حذف و بایگانی رویداد)، report (فقط خواندن گزارش).
 * - hash: sha256 کلید برای سنجش؛ enc: خود کلید رمزشده با sodium_crypto_secretbox تا مدیر وردپرس هر وقت
 *   خواست دوباره ببیند. کلید رمزگشایی از wp_salt('auth') مشتق می‌شود؛ هر کس به دیتابیس و wp-config.php
 *   دسترسی داشته باشد کلیدها را می‌خواند (پذیرفته‌شده در آ-۲).
 * - کلید قدیمی (cd_admin_key_hash) و کلیدهای گوشی (cd_mobile_keys) بار اول به این فهرست منتقل می‌شوند
 *   و همچنان کار می‌کنند؛ چون متن کلید قدیمی ذخیره نشده بود، enc خالی است و باید یک‌بار بازتولید شود.
 */

const CD_KEY_ROLES = [
    'owner' => 'مالک',
    'manager' => 'مدیر اجرایی',
    'report' => 'فقط گزارش',
];

function cd_keys_secret() {
    return hash('sha256', 'cd-admin-keys|' . wp_salt('auth'), true);
}

/** رمز کردن با sodium_crypto_secretbox؛ خروجی base64(nonce + متن رمزشده)، یا خالی اگر sodium نیست. */
function cd_secretbox_encrypt($plain, $secret) {
    if (!function_exists('sodium_crypto_secretbox')) {
        return '';
    }
    $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
    return base64_encode($nonce . sodium_crypto_secretbox($plain, $nonce, $secret));
}

function cd_secretbox_decrypt($enc, $secret) {
    if ($enc === '' || !function_exists('sodium_crypto_secretbox_open')) {
        return null;
    }
    $raw = base64_decode($enc, true);
    if ($raw === false || strlen($raw) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
        return null;
    }
    $plain = sodium_crypto_secretbox_open(
        substr($raw, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES),
        substr($raw, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES),
        $secret
    );
    return $plain === false ? null : $plain;
}

function cd_key_encrypt($plain) {
    return cd_secretbox_encrypt($plain, cd_keys_secret());
}

function cd_key_decrypt($enc) {
    return cd_secretbox_decrypt($enc, cd_keys_secret());
}

/*
 * پین نیروها (آ-۱): پین ۴ تا ۸ رقمی است و درهم‌سازی‌اش در عمل چند ثانیه‌ای شکسته می‌شود؛ محافظ واقعی قفل
 * تلاش ناموفق و کلید مدیریت است. پس پین رمزشده (pin_enc) نگه داشته می‌شود تا مدیر ببیند، و pin_lookup
 * (HMAC-SHA256 پین همراه شناسه‌ی رویداد) ورود را با یک کوئری پیدا می‌کند و تکراری‌بودن را می‌سنجد.
 * ریسک پذیرفته‌شده: هر کس به دیتابیس و wp-config.php دسترسی داشته باشد پین‌ها را می‌خواند.
 * پین هیچ‌جا در لاگ نوشته نمی‌شود.
 */
function cd_pin_secret() {
    return hash('sha256', 'cd-pin-enc|' . wp_salt('auth'), true);
}

function cd_pin_lookup($event_id, $pin) {
    return hash_hmac('sha256', (int) $event_id . '|' . $pin, hash('sha256', 'cd-pin-lookup|' . wp_salt('auth'), true));
}

/** ستون‌های ذخیره‌ی یک پین تازه (pin_hash هم برای سازگاری با نسخه‌ی قبلی افزونه نوشته می‌شود). */
function cd_pin_columns($event_id, $pin) {
    return [
        'pin_hash' => wp_hash_password($pin),
        'pin_enc' => cd_secretbox_encrypt($pin, cd_pin_secret()),
        'pin_lookup' => cd_pin_lookup($event_id, $pin),
    ];
}

/** پین قابل نمایش، یا null برای نیروی قدیمی که هنوز وارد نشده یا پین ندارد. */
function cd_pin_reveal(array $staff_row) {
    return cd_secretbox_decrypt((string) ($staff_row['pin_enc'] ?? ''), cd_pin_secret());
}

/** فهرست کلیدها؛ بار اول کلیدهای قدیمی را منتقل می‌کند. */
function cd_admin_keys() {
    $keys = get_option('cd_admin_keys', null);
    if (is_array($keys)) {
        return $keys;
    }
    $keys = [];
    $legacy = (string) get_option('cd_admin_key_hash', '');
    if ($legacy !== '') {
        $id = wp_generate_uuid4();
        $keys[$id] = [
            'id' => $id,
            'label' => 'قدیمی؛ یک‌بار بازتولید کنید',
            'role' => 'owner',
            'hash' => $legacy,
            'enc' => '',
            'created_at' => cd_now(),
            'last_used' => null,
            'revoked' => false,
            'legacy' => true,
        ];
    }
    $mobile = get_option('cd_mobile_keys', []);
    foreach (is_array($mobile) ? $mobile : [] as $id => $k) {
        // کلیدهای گوشی پیش از این دسترسی کامل داشتند؛ همان می‌ماند.
        $keys[$id] = [
            'id' => (string) $id,
            'label' => (string) ($k['label'] ?? 'گوشی مدیر'),
            'role' => 'owner',
            'hash' => (string) ($k['hash'] ?? ''),
            'enc' => '',
            'created_at' => $k['created_at'] ?? cd_now(),
            'last_used' => $k['last_used'] ?? null,
            'revoked' => !empty($k['revoked']),
            'legacy' => true,
        ];
    }
    update_option('cd_admin_keys', $keys, false);
    return $keys;
}

function cd_admin_keys_save(array $keys) {
    update_option('cd_admin_keys', $keys, false);
}

/** ساخت کلید تازه. کلیدهای دیگر باطل نمی‌شوند. خروجی: [id, متن کلید]. */
function cd_admin_key_create($label, $role) {
    $keys = cd_admin_keys();
    $role = isset(CD_KEY_ROLES[$role]) ? $role : 'manager';
    $token = 'cdk_' . cd_random_token(32);
    $id = wp_generate_uuid4();
    $keys[$id] = [
        'id' => $id,
        'label' => $label !== '' ? $label : CD_KEY_ROLES[$role],
        'role' => $role,
        'hash' => hash('sha256', $token),
        'enc' => cd_key_encrypt($token),
        'created_at' => cd_now(),
        'last_used' => null,
        'revoked' => false,
        'legacy' => false,
    ];
    cd_admin_keys_save($keys);
    return [$id, $token];
}

/** متن کلید برای «نمایش»، یا null (کلید قدیمی یا باطل). */
function cd_admin_key_reveal($id) {
    $keys = cd_admin_keys();
    if (!isset($keys[$id]) || !empty($keys[$id]['revoked'])) {
        return null;
    }
    return cd_key_decrypt((string) $keys[$id]['enc']);
}

function cd_admin_key_revoke($id) {
    $keys = cd_admin_keys();
    if (!isset($keys[$id])) {
        return false;
    }
    $keys[$id]['revoked'] = true;
    cd_admin_keys_save($keys);
    return true;
}

/** کلید فعال با این hash، و ثبت «آخرین استفاده» (هر ۵ دقیقه یک‌بار). */
function cd_admin_find_key($hash) {
    $keys = cd_admin_keys();
    foreach ($keys as $id => $k) {
        if (empty($k['revoked']) && $k['hash'] !== '' && hash_equals((string) $k['hash'], $hash)) {
            if (empty($k['last_used']) || strtotime($k['last_used'] . ' UTC') < time() - 300) {
                $keys[$id]['last_used'] = cd_now();
                cd_admin_keys_save($keys);
            }
            return $k;
        }
    }
    return null;
}

/**
 * آیا نقش اجازه‌ی این درخواست را دارد؟
 * report: فقط خواندن (GET) گزارش و فهرست‌هایی که صفحه‌های «امروز» و «افراد» حالت دسترسی محدود لازم دارند.
 * manager: همه‌چیز جز حذف و بایگانی رویداد.
 */
function cd_role_allows($role, $method, $route) {
    if ($role === 'owner') {
        return true;
    }
    $path = (string) preg_replace('#^/' . preg_quote(CD_NS, '#') . '#', '', (string) $route);
    if ($role === 'manager') {
        if ($method === 'DELETE' && preg_match('#^/admin/events/[^/]+$#', $path)) {
            return false;
        }
        return !preg_match('#^/admin/events/[^/]+/archive$#', $path);
    }
    if ($role === 'report') {
        return $method === 'GET' && (bool) preg_match(
            '#^/admin/(ping|events|events/[^/]+/(report|export|meals/[^/]+/people|attendees/[^/]+/timeline))$#',
            $path
        );
    }
    return false;
}
