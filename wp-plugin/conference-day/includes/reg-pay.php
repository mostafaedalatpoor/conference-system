<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * درگاه پرداخت. هر درگاه یک کلاس با دو کار است: start (رفتن به بانک) و verify (استعلام بعد از برگشت).
 * زرین‌پال همراه افزونه است. درگاه دیگر را با قلاب roydadyar_payment_gateways اضافه کنید:
 *
 *   add_filter('roydadyar_payment_gateways', function ($gateways) {
 *       $gateways['mypay'] = new My_Pay_Gateway(); // implements CD_Payment_Gateway
 *       return $gateways;
 *   });
 *
 * راهنمای کامل و یک نمونه در README افزونه است.
 */

interface CD_Payment_Gateway {
    /** نام فارسی برای فهرست درگاه‌ها. */
    public function name();

    /** فیلدهای تنظیم: [['key' => 'merchant_id', 'label' => 'کد مرچنت', 'secret' => true], ...]. */
    public function fields();

    /**
     * شروع پرداخت. $amount به تومان. خروجی: ['url' => آدرس رفتن به بانک, 'authority' => شناسه‌ی تراکنش] یا WP_Error.
     */
    public function start(array $settings, $amount, $callback_url, array $reg);

    /**
     * استعلام بعد از برگشت. $query پارامترهای برگشت بانک است.
     * خروجی: ['ok' => bool, 'ref' => شماره‌ی پیگیری بانک, 'message' => متن برای کاربر].
     */
    public function verify(array $settings, $amount, array $reg, array $query);
}

/** زرین‌پال، API نسخه‌ی ۴. مبلغ به ریال فرستاده می‌شود. حالت آزمایشی با sandbox. */
class CD_Gateway_Zarinpal implements CD_Payment_Gateway {
    public function name() {
        return 'زرین‌پال';
    }

    public function fields() {
        return [
            ['key' => 'merchant_id', 'label' => 'کد مرچنت (۳۶ نویسه)', 'secret' => true],
            ['key' => 'sandbox', 'label' => 'حالت آزمایشی (بدون پول واقعی): 1 یا 0', 'secret' => false],
        ];
    }

    private function host(array $s) {
        return !empty($s['sandbox']) && $s['sandbox'] !== '0' ? 'https://sandbox.zarinpal.com' : 'https://payment.zarinpal.com';
    }

    private function post($url, array $body) {
        $r = wp_remote_post($url, [
            'timeout' => 20,
            'headers' => ['Content-Type' => 'application/json', 'Accept' => 'application/json'],
            'body' => wp_json_encode($body),
        ]);
        if (is_wp_error($r)) {
            return $r;
        }
        $j = json_decode(wp_remote_retrieve_body($r), true);
        return is_array($j) ? $j : new WP_Error('cd_pay', 'پاسخ درگاه خوانا نبود.');
    }

    public function start(array $s, $amount, $callback_url, array $reg) {
        if (empty($s['merchant_id'])) {
            return new WP_Error('cd_pay', 'کد مرچنت زرین‌پال تنظیم نشده است.');
        }
        $j = $this->post($this->host($s) . '/pg/v4/payment/request.json', [
            'merchant_id' => $s['merchant_id'],
            'amount' => (int) $amount * 10,
            'currency' => 'IRR',
            'callback_url' => $callback_url,
            'description' => 'ثبت‌نام ' . $reg['code'],
            'metadata' => array_filter(['mobile' => $reg['mobile'], 'email' => $reg['email']]),
        ]);
        if (is_wp_error($j)) {
            return $j;
        }
        $code = (int) ($j['data']['code'] ?? 0);
        $authority = (string) ($j['data']['authority'] ?? '');
        if ($code !== 100 || $authority === '') {
            return new WP_Error('cd_pay', 'درگاه پرداخت را شروع نکرد (کد ' . ($j['errors']['code'] ?? $code) . ').');
        }
        return ['url' => $this->host($s) . '/pg/StartPay/' . rawurlencode($authority), 'authority' => $authority];
    }

    public function verify(array $s, $amount, array $reg, array $q) {
        if (($q['Status'] ?? '') !== 'OK' || ($q['Authority'] ?? '') !== $reg['pay_authority']) {
            return ['ok' => false, 'ref' => '', 'message' => 'پرداخت انجام نشد یا لغو شد.'];
        }
        $j = $this->post($this->host($s) . '/pg/v4/payment/verify.json', [
            'merchant_id' => $s['merchant_id'] ?? '',
            'amount' => (int) $amount * 10,
            'authority' => $reg['pay_authority'],
        ]);
        if (is_wp_error($j)) {
            return ['ok' => false, 'ref' => '', 'message' => 'استعلام از درگاه ناموفق بود؛ اگر پولی کم شده تا ۷۲ ساعت برمی‌گردد.'];
        }
        $code = (int) ($j['data']['code'] ?? 0);
        // ۱۰۰ = موفق، ۱۰۱ = قبلاً تأیید شده
        if ($code === 100 || $code === 101) {
            return ['ok' => true, 'ref' => (string) ($j['data']['ref_id'] ?? ''), 'message' => ''];
        }
        return ['ok' => false, 'ref' => '', 'message' => 'بانک پرداخت را تأیید نکرد؛ اگر پولی کم شده تا ۷۲ ساعت برمی‌گردد.'];
    }
}

/** فهرست درگاه‌ها: زرین‌پال + هر چه افزونه‌های دیگر اضافه کرده‌اند. */
function cd_payment_gateways() {
    $list = apply_filters('roydadyar_payment_gateways', ['zarinpal' => new CD_Gateway_Zarinpal()]);
    return array_filter(is_array($list) ? $list : [], function ($g) {
        return $g instanceof CD_Payment_Gateway;
    });
}

/** برای اپ مدیریت: نام و فیلدهای هر درگاه. */
function cd_payment_gateways_out() {
    $out = [];
    foreach (cd_payment_gateways() as $id => $g) {
        $out[] = ['id' => $id, 'name' => $g->name(), 'fields' => $g->fields()];
    }
    return $out;
}

/** شروع پرداخت درگاه برای یک ثبت‌نامِ در انتظار پرداخت. خروجی: آدرس بانک یا WP_Error. */
function cd_reg_start_gateway(array $page, array $reg) {
    global $wpdb;
    $cfg = $page['config'];
    if ($reg['status'] !== 'pending_payment' || $reg['pay_method'] !== 'gateway') {
        return new WP_Error('cd_pay', 'این ثبت‌نام پرداخت درگاه ندارد.');
    }
    $gateways = cd_payment_gateways();
    $g = $gateways[$cfg['payment']['gateway']] ?? null;
    if (!$g) {
        return new WP_Error('cd_pay', 'درگاه پرداخت این رویداد تنظیم نشده است. با دبیرخانه تماس بگیرید.');
    }
    // هر تلاش دوباره ۳۰ دقیقه‌ی تازه دارد.
    $wpdb->update(cd_table('registrations'), ['hold_until' => gmdate('Y-m-d H:i:s', time() + CD_REG_GATEWAY_HOLD * 60)], ['id' => (int) $reg['id']]);
    $callback = add_query_arg(['code' => $reg['code'], 'k' => cd_reg_key($reg['code'])], rest_url(CD_NS . '/reg/callback'));
    $r = $g->start($cfg['payment']['gateway_settings'], (int) $reg['amount_online'], $callback, $reg);
    if (is_wp_error($r)) {
        return $r;
    }
    $wpdb->update(cd_table('registrations'), ['pay_authority' => cd_str($r['authority'] ?? '', 191)], ['id' => (int) $reg['id']]);
    return (string) $r['url'];
}

/** برگشت از بانک: استعلام و هدایت به صفحه با نتیجه. */
function cd_reg_gateway_callback(WP_REST_Request $request) {
    $reg = cd_reg_get_by_code((string) $request->get_param('code'));
    if (!$reg || !hash_equals(cd_reg_key($reg['code']), (string) $request->get_param('k'))) {
        return cd_error('cd_reg_not_found', 'ثبت‌نام پیدا نشد.', 404);
    }
    $page = cd_reg_get_page_by_event((int) $reg['event_id']);
    if (!$page) {
        return cd_error('cd_reg_not_found', 'ثبت‌نام پیدا نشد.', 404);
    }
    $result = 'ok';
    if ($reg['status'] === 'pending_payment' || $reg['status'] === 'expired') {
        $g = cd_payment_gateways()[$page['config']['payment']['gateway']] ?? null;
        $v = $g ? $g->verify($page['config']['payment']['gateway_settings'], (int) $reg['amount_online'], $reg, $request->get_query_params())
            : ['ok' => false, 'message' => 'درگاه پیدا نشد.'];
        if (!empty($v['ok'])) {
            // پرداخت موفق بعد از انقضای نگه‌داشت هم پذیرفته می‌شود؛ پول گرفته شده.
            cd_reg_after_payment($page, $reg, ['pay_ref' => cd_str($v['ref'] ?? '', 191)]);
        } else {
            $result = 'fail';
            set_transient('cd_reg_payfail_' . $reg['code'], (string) ($v['message'] ?? ''), 900);
        }
    }
    $url = add_query_arg(['code' => $reg['code'], 'k' => cd_reg_key($reg['code']), 'pay' => $result], cd_reg_page_url($page['config']));
    wp_redirect($url, 302, 'RoydadYar');
    exit;
}
