<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * صفحه‌ی عمومی شناسایی: /c/<token>
 * با اسکن QR کارت باز می‌شود و نام، نقش و برنامه‌ی کنفرانس را نشان می‌دهد.
 * اطلاعات تماس (موبایل، ایمیل) هرگز اینجا نمایش داده نمی‌شود.
 */

function cd_add_rewrite() {
    add_rewrite_rule('^c/([A-Za-z0-9_-]{16,64})/?$', 'index.php?cd_card=$matches[1]', 'top');
}
add_action('init', 'cd_add_rewrite');

add_filter('query_vars', function ($vars) {
    $vars[] = 'cd_card';
    return $vars;
});

add_action('template_redirect', function () {
    $token = get_query_var('cd_card');
    if ((!is_string($token) || $token === '') && isset($_GET['c'])) {
        // اگر پیوند یکتا خاموش شود، QR با ?c= هم کار کند.
        $token = sanitize_text_field(wp_unslash($_GET['c']));
    }
    if (!is_string($token) || $token === '') {
        return;
    }
    header('X-Robots-Tag: noindex, nofollow');

    // درخواست‌های پشت‌سرهم با توکن نامعتبر از یک IP محدود می‌شوند.
    $ip_key = 'cd_pub_bad_' . md5(cd_client_ip());
    $bad = (int) get_transient($ip_key);
    if ($bad >= 30) {
        cd_send_nocache_headers();
        status_header(429);
        header('Content-Type: text/html; charset=utf-8');
        echo cd_render_public_page(null, null, ['icon' => 'wait', 'text' => 'درخواست زیاد بود. چند دقیقه بعد دوباره امتحان کنید.']);
        exit;
    }
    $reject = function ($text) use ($ip_key, $bad) {
        set_transient($ip_key, $bad + 1, 600);
        cd_send_nocache_headers();
        status_header(404);
        header('Content-Type: text/html; charset=utf-8');
        echo cd_render_public_page(null, null, ['icon' => 'stop', 'text' => $text]);
        exit;
    };

    if (!cd_is_card_token($token)) {
        $reject('این کارت معتبر نیست.');
    }

    global $wpdb;
    $card = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('cards') . ' WHERE token = %s', $token), ARRAY_A);
    if (!$card) {
        $reject('این کارت معتبر نیست.');
    }
    $event = cd_get_event((int) $card['event_id']);
    $settings = cd_event_settings($event);

    // صفحه برای همه یکسان است و اطلاعات خصوصی ندارد؛ LiteSpeed می‌تواند ۶۰ ثانیه کشش کند.
    cd_send_public_cache_headers();

    if (!$card['attendee_id']) {
        header('Content-Type: text/html; charset=utf-8');
        echo cd_render_public_page($event, null, ['icon' => 'idle', 'text' => 'این کارت رزرو هنوز به کسی وصل نشده.'], $settings);
        exit;
    }
    $person = $wpdb->get_row($wpdb->prepare(
        'SELECT a.title, a.first_name, a.last_name, a.organization, a.presentation_kind, a.email, a.mobile, a.country,
                a.registration_type_id, a.share_contact, a.website, t.name AS type_name, r.name AS role_name
         FROM ' . cd_table('attendees') . ' a
         LEFT JOIN ' . cd_table('registration_types') . ' t ON t.id = a.registration_type_id
         LEFT JOIN ' . cd_table('roles') . ' r ON r.id = a.role_id
         WHERE a.id = %s',
        $card['attendee_id']
    ), ARRAY_A);
    if (!$person) {
        $reject('این کارت معتبر نیست.');
    }

    // «ذخیره در مخاطبین»: فایل vCard فقط با فیلدهای مجاز.
    if (isset($_GET['vcf'])) {
        $base = untrailingslashit($event['base_url'] ?: home_url());
        header('Content-Type: text/vcard; charset=utf-8');
        header('Content-Disposition: attachment; filename="contact.vcf"');
        echo cd_build_vcard($person, $settings, $event, $base . '/c/' . $token); // phpcs:ignore WordPress.Security.EscapeOutput
        exit;
    }

    // «انتقال به یک آدرس»: اگر مقصد خالی یا خراب باشد، صفحه‌ی فرد نمایش داده می‌شود.
    if ($settings['qr_behavior'] === 'redirect' && wp_http_validate_url($settings['qr_redirect_url'])) {
        wp_redirect($settings['qr_redirect_url'], 302, 'RoydadYar');
        exit;
    }

    header('Content-Type: text/html; charset=utf-8');
    echo cd_render_public_page($event, $person, null, $settings, $token);
    exit;
});

function cd_send_public_cache_headers() {
    if (!headers_sent()) {
        header('Cache-Control: public, max-age=60');
        header('X-LiteSpeed-Cache-Control: public,max-age=60');
    }
}

/** فیلدهای تماسی که برای این نفر مجاز است (تنظیم رویداد، و «خیر» خود فرد بر آن مقدم). */
function cd_allowed_contact(array $person, array $settings) {
    $f = $settings['contact_fields'];
    $tid = isset($person['registration_type_id']) ? (string) (int) $person['registration_type_id'] : '';
    if ($tid !== '' && isset($settings['contact_by_type'][$tid])) {
        $f['mobile'] = (bool) $settings['contact_by_type'][$tid]['mobile'];
        $f['email'] = (bool) $settings['contact_by_type'][$tid]['email'];
    }
    if ($person['share_contact'] !== null && !(int) $person['share_contact']) {
        // کسی که «خیر» دارد فقط نام و سازمان را به اشتراک می‌گذارد.
        return ['name' => true, 'organization' => true, 'email' => false, 'mobile' => false, 'country' => false];
    }
    return $f;
}

/** vCard 3.0 با UTF-8. نام در N، سازمان در ORG، نقش کنفرانس در NOTE، TITLE خالی، URL همیشه /c/<token>. */
function cd_build_vcard(array $p, array $settings, array $event, $url) {
    $esc = function ($v) {
        return str_replace(["\\", ',', ';', "\n"], ["\\\\", '\\,', '\;', '\\n'], (string) $v);
    };
    $f = cd_allowed_contact($p, $settings);
    $full = trim($p['title'] . ' ' . $p['first_name'] . ' ' . $p['last_name']);
    $lines = ['BEGIN:VCARD', 'VERSION:3.0'];
    if ($f['name']) {
        $lines[] = 'N:' . $esc($p['last_name']) . ';' . $esc($p['first_name']) . ';;' . $esc($p['title']) . ';';
    }
    $lines[] = 'FN:' . $esc($f['name'] ? $full : ($p['organization'] !== '' ? $p['organization'] : 'شرکت‌کننده'));
    if ($f['organization'] && $p['organization'] !== '') {
        $lines[] = 'ORG:' . $esc($p['organization']);
    }
    if ($f['email'] && $p['email'] !== '') {
        $lines[] = 'EMAIL;TYPE=INTERNET:' . $esc($p['email']);
    }
    if ($f['mobile'] && $p['mobile'] !== '') {
        $lines[] = 'TEL;TYPE=CELL:' . $esc($p['mobile']);
    }
    if ($f['country'] && $p['country'] !== '') {
        $lines[] = 'ADR:;;;;;;' . $esc($p['country']);
    }
    $note = array_filter([(string) $p['role_name'], (string) $event['name']]);
    $lines[] = 'NOTE:' . $esc(implode(' · ', $note));
    $lines[] = 'URL:' . $url;
    $lines[] = 'END:VCARD';
    return implode("\r\n", $lines) . "\r\n";
}

function cd_presentation_label($kind) {
    $map = ['poster' => 'ارائه‌ی پوستری', 'oral' => 'ارائه‌ی شفاهی'];
    return $map[$kind] ?? '';
}

function cd_session_kind_label($kind) {
    $map = [
        'opening' => 'افتتاحیه',
        'keynote' => 'سخنرانی',
        'panel' => 'پنل',
        'paper' => 'سشن مقاله',
        'workshop' => 'کارگاه',
        'break' => 'پذیرایی',
    ];
    return $map[$kind] ?? $kind;
}

function cd_fa_digits($s) {
    return strtr((string) $s, ['0' => '۰', '1' => '۱', '2' => '۲', '3' => '۳', '4' => '۴', '5' => '۵', '6' => '۶', '7' => '۷', '8' => '۸', '9' => '۹']);
}

/** تاریخ میلادی YYYY-MM-DD به روز هفته و تاریخ شمسی برای عنوان روزها. */
function cd_day_label($ymd) {
    $ts = strtotime($ymd . ' 12:00:00 UTC');
    if ($ts === false) {
        return $ymd;
    }
    $weekdays = ['یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه', 'شنبه'];
    $w = $weekdays[(int) gmdate('w', $ts)];
    [$jy, $jm, $jd] = cd_gregorian_to_jalali((int) gmdate('Y', $ts), (int) gmdate('n', $ts), (int) gmdate('j', $ts));
    $months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
    return $w . ' ' . cd_fa_digits($jd) . ' ' . $months[$jm - 1];
}

/** الگوریتم استاندارد تبدیل میلادی به شمسی. */
function cd_gregorian_to_jalali($gy, $gm, $gd) {
    $g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    $gy2 = ($gm > 2) ? ($gy + 1) : $gy;
    $days = 355666 + (365 * $gy) + (int) (($gy2 + 3) / 4) - (int) (($gy2 + 99) / 100) + (int) (($gy2 + 399) / 400) + $gd + $g_d_m[$gm - 1];
    $jy = -1595 + (33 * (int) ($days / 12053));
    $days %= 12053;
    $jy += 4 * (int) ($days / 1461);
    $days %= 1461;
    if ($days > 365) {
        $jy += (int) (($days - 1) / 365);
        $days = ($days - 1) % 365;
    }
    if ($days < 186) {
        $jm = 1 + (int) ($days / 31);
        $jd = 1 + ($days % 31);
    } else {
        $jm = 7 + (int) (($days - 186) / 30);
        $jd = 1 + (($days - 186) % 30);
    }
    return [$jy, $jm, $jd];
}

/** «الان» به وقت تهران (برای ردیف «الان» و «بعدی» برنامه). */
function cd_tehran_now() {
    try {
        return new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran'));
    } catch (Exception $e) {
        return new DateTimeImmutable('now');
    }
}

/**
 * صفحه‌ی عمومی (PublicPass) با زبان طراحی «دفتر». HTML و CSS ساده، بدون جاوااسکریپت.
 * $message: ['icon' => go|wait|stop|idle, 'text' => '…'] برای حالت‌های خطا.
 */
function cd_render_public_page($event, $person, $message, $settings = null, $token = '') {
    $e = function ($s) {
        return esc_html((string) $s);
    };
    $settings = $settings ?: cd_default_settings();
    $title = $event ? $event['name'] : get_bloginfo('name');
    $font = plugins_url('assets/fonts/', CD_DIR . 'conference-day.php');
    $contact = $person ? cd_allowed_contact($person, $settings) : null;
    $full = $person ? trim($person['first_name'] . ' ' . $person['last_name']) : '';

    // برنامه: امروز با «الان» و «بعدی»؛ روزهای دیگر جمع‌شده.
    $by_day = [];
    $now_id = null;
    $next_id = null;
    $today = null;
    if ($event) {
        $config = cd_event_config((int) $event['id']);
        foreach ($config['sessions'] as $s) {
            $by_day[$s['day']][] = $s;
        }
        $now = cd_tehran_now();
        $today = $now->format('Y-m-d');
        $hm = $now->format('H:i');
        foreach ($by_day[$today] ?? [] as $s) {
            $end = $s['end_time'] ?: $s['start_time'];
            if ($s['start_time'] <= $hm && $hm < $end) {
                $now_id = $s['id'];
            } elseif ($s['start_time'] > $hm && $next_id === null) {
                $next_id = $s['id'];
            }
        }
    }
    $open_day = isset($by_day[$today]) ? $today : null;
    if ($open_day === null) {
        foreach (array_keys($by_day) as $d) {
            if ($today === null || $d >= $today) {
                $open_day = $d;
                break;
            }
        }
    }

    $icons = [
        'stop' => '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm3.5 13.1-1.4 1.4L12 14.4l-2.1 2.1-1.4-1.4 2.1-2.1-2.1-2.1 1.4-1.4L12 11.6l2.1-2.1 1.4 1.4-2.1 2.1Z"/>',
        'idle' => '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm1 15h-2v-2h2v2Zm1.6-6.2-.9.9c-.7.7-1.2 1.3-1.2 2.8h-2v-.5c0-1.1.5-2.1 1.2-2.8l1.2-1.3a1.7 1.7 0 1 0-2.9-1.2H8a4 4 0 1 1 6.6 3.1Z"/>',
        'wait' => '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm1 11h-2V7h2v6Zm0 4h-2v-2h2v2Z"/>',
    ];

    ob_start();
    ?>
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?php echo $e($person ? $full . ' — ' . $title : $title); ?></title>
<style>
@font-face { font-family: Vazirmatn; font-weight: 400; font-display: swap; src: url("<?php echo esc_url($font . 'Vazirmatn-Regular.woff2'); ?>") format("woff2"); }
@font-face { font-family: Vazirmatn; font-weight: 800; font-display: swap; src: url("<?php echo esc_url($font . 'Vazirmatn-ExtraBold.woff2'); ?>") format("woff2"); }
:root { --paper:#F4F5F7; --surface:#FFFFFF; --sunken:#E9ECF0; --line:#DCE0E6; --line-strong:#7E8796; --ink:#10141A; --muted:#505966; --stamp:#2A42D4; --stamp-soft:#E6E9FC; --action:#10141A; --on-action:#FFFFFF; --stop:#B42318; --stop-soft:#FDE8E6; --wait:#8A5300; --wait-soft:#FFF1D1; }
@media (prefers-color-scheme: dark) { :root { --paper:#0D1015; --surface:#161A21; --sunken:#08090C; --line:#262C36; --line-strong:#6E7888; --ink:#EDF0F4; --muted:#A0A9B6; --stamp:#8E9CFF; --stamp-soft:#1E2552; --action:#EDF0F4; --on-action:#0D1015; --stop:#FF8A80; --stop-soft:#3A1513; --wait:#F5B83D; --wait-soft:#33260A; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--paper); color:var(--ink); font-family: Vazirmatn, Tahoma, "Segoe UI", sans-serif; line-height:1.6; letter-spacing:0; }
main { max-width:480px; margin:0 auto; padding:18px 18px 40px; }
.event { color:var(--muted); font-size:14px; margin:4px 0 12px; }
.card { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:20px; }
.honor { color:var(--muted); font-size:15px; }
h1 { margin:0; font-size:34px; line-height:46px; font-weight:800; }
.org { color:var(--muted); margin-top:4px; font-size:15px; }
.tags { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
.tag { background:var(--sunken); color:var(--ink); border-radius:4px; padding:2px 8px; font-size:13px; font-weight:800; }
.tag.stamp { background:var(--stamp-soft); color:var(--stamp); }
.contact { margin-top:14px; font-size:15px; }
.contact div { direction:ltr; text-align:right; }
.btn { display:block; text-align:center; text-decoration:none; border-radius:8px; padding:14px 16px; font-weight:800; font-size:16px; margin-top:12px; }
.btn.primary { background:var(--action); color:var(--on-action); }
.btn.outline { border:1.5px solid var(--line-strong); color:var(--ink); background:var(--surface); }
.msg { display:flex; gap:12px; align-items:flex-start; background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:20px; font-size:17px; }
.msg svg { width:28px; height:28px; flex:none; fill:var(--muted); }
.msg.stop svg { fill:var(--stop); } .msg.wait svg { fill:var(--wait); }
h2 { font-size:20px; margin:28px 0 8px; }
.day h3 { font-size:15px; color:var(--muted); margin:16px 0 6px; font-weight:800; }
details.day > summary { cursor:pointer; color:var(--muted); font-weight:800; font-size:15px; padding:8px 0; }
.s { display:flex; gap:12px; padding:10px 8px; border-top:1px solid var(--line); border-radius:8px; }
.s.now { background:var(--stamp-soft); border-top-color:transparent; }
.t { min-width:92px; color:var(--muted); font-variant-numeric: tabular-nums; direction:ltr; text-align:right; }
.what { flex:1; }
.hall, .kind { color:var(--muted); font-size:13px; }
.badge { display:inline-block; font-size:12px; font-weight:800; border-radius:4px; padding:0 6px; margin-inline-start:6px; }
.badge.now { background:var(--stamp); color:var(--surface); }
.badge.next { border:1px solid var(--line-strong); color:var(--ink); }
.organizer { margin-top:28px; text-align:center; font-size:14px; }
.organizer a { color:inherit; }
.maker { margin-top:32px; text-align:center; color:var(--muted); font-size:12px; }
</style>
</head>
<body>
<main>
<?php if ($event) : ?>
  <p class="event"><?php echo $e($event['name']); ?></p>
<?php endif; ?>

<?php if ($message) : ?>
  <div class="msg <?php echo esc_attr($message['icon']); ?>">
    <svg viewBox="0 0 24 24" aria-hidden="true"><?php echo $icons[$message['icon']] ?? $icons['idle']; // phpcs:ignore WordPress.Security.EscapeOutput ?></svg>
    <div><?php echo $e($message['text']); ?></div>
  </div>
<?php else : ?>
  <section class="card">
    <?php if ($person['title'] !== '') : ?><div class="honor"><?php echo $e($person['title']); ?></div><?php endif; ?>
    <h1><?php echo $e($full); ?></h1>
    <?php if ($person['organization'] !== '') : ?>
      <div class="org"><?php echo $e($person['organization']); ?></div>
    <?php endif; ?>
    <div class="tags">
      <?php if ($person['role_name']) : ?><span class="tag stamp"><?php echo $e($person['role_name']); ?></span><?php endif; ?>
      <?php if ($person['type_name']) : ?><span class="tag"><?php echo $e($person['type_name']); ?></span><?php endif; ?>
      <?php $pk = cd_presentation_label($person['presentation_kind']); if ($pk) : ?><span class="tag"><?php echo $e($pk); ?></span><?php endif; ?>
    </div>
    <?php if (($contact['email'] && $person['email'] !== '') || ($contact['mobile'] && $person['mobile'] !== '')) : ?>
      <div class="contact">
        <?php if ($contact['email'] && $person['email'] !== '') : ?><div><?php echo $e($person['email']); ?></div><?php endif; ?>
        <?php if ($contact['mobile'] && $person['mobile'] !== '') : ?><div><?php echo $e(cd_fa_digits($person['mobile'])); ?></div><?php endif; ?>
      </div>
    <?php endif; ?>
    <?php if ($token !== '') : ?>
      <a class="btn primary" href="<?php echo esc_url(add_query_arg('vcf', '1')); ?>">ذخیره در مخاطبین</a>
    <?php endif; ?>
    <?php if (!empty($person['website'])) : ?>
      <a class="btn outline" href="<?php echo esc_url($person['website']); ?>" rel="nofollow noopener">صفحه‌ی شخصی</a>
    <?php endif; ?>
  </section>
<?php endif; ?>

<?php if ($by_day) : ?>
  <h2>برنامه</h2>
    <?php foreach ($by_day as $day => $sessions) : ?>
        <?php $open = $day === $open_day; ?>
        <?php if ($open) : ?>
  <div class="day"><h3><?php echo $e(($day === $today ? 'امروز، ' : '') . cd_day_label($day)); ?></h3>
        <?php else : ?>
  <details class="day"><summary><?php echo $e(cd_day_label($day)); ?></summary>
        <?php endif; ?>
        <?php foreach ($sessions as $s) : ?>
            <?php $is_now = $s['id'] === $now_id; $is_next = $s['id'] === $next_id; ?>
    <div class="s<?php echo $is_now ? ' now' : ''; ?>">
      <div class="t"><?php echo $e(cd_fa_digits($s['start_time'] . ($s['end_time'] ? '–' . $s['end_time'] : ''))); ?></div>
      <div class="what">
        <?php if ($s['kind']) : ?><div class="kind"><?php echo $e(cd_session_kind_label($s['kind'])); ?></div><?php endif; ?>
        <div><?php echo $e($s['title']); ?><?php if ($is_now) : ?><span class="badge now">الان</span><?php elseif ($is_next) : ?><span class="badge next">بعدی</span><?php endif; ?></div>
        <?php if ($s['hall'] !== '') : ?><div class="hall"><?php echo $e($s['hall']); ?></div><?php endif; ?>
      </div>
    </div>
        <?php endforeach; ?>
        <?php echo $open ? '</div>' : '</details>'; ?>
    <?php endforeach; ?>
<?php endif; ?>

<?php if ($settings['organizer_email'] !== '' || $settings['organizer_url'] !== '') : ?>
  <p class="organizer">ارتباط با برگزارکننده:
    <?php if ($settings['organizer_email'] !== '') : ?><a href="mailto:<?php echo esc_attr($settings['organizer_email']); ?>" dir="ltr"><?php echo $e($settings['organizer_email']); ?></a><?php endif; ?>
    <?php if ($settings['organizer_email'] !== '' && $settings['organizer_url'] !== '') : ?> · <?php endif; ?>
    <?php if ($settings['organizer_url'] !== '') : ?><a href="<?php echo esc_url($settings['organizer_url']); ?>" rel="noopener">صفحه‌ی پشتیبانی</a><?php endif; ?>
  </p>
<?php endif; ?>
<?php if ($settings['show_maker_credit']) : ?>
  <p class="maker">ساخته‌شده با رویدادیار · نگاه جدید</p>
<?php endif; ?>
</main>
</body>
</html>
    <?php
    return ob_get_clean();
}
