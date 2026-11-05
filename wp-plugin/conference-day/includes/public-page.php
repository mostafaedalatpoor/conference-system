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
    cd_send_nocache_headers();
    header('Content-Type: text/html; charset=utf-8');
    header('X-Robots-Tag: noindex, nofollow');

    if (!cd_is_card_token($token)) {
        status_header(404);
        echo cd_render_public_page(null, null, 'کارت نامعتبر است.');
        exit;
    }

    global $wpdb;
    $card = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('cards') . ' WHERE token = %s', $token), ARRAY_A);
    if (!$card) {
        status_header(404);
        echo cd_render_public_page(null, null, 'این کارت در سامانه ثبت نشده است.');
        exit;
    }
    $event = cd_get_event((int) $card['event_id']);
    if (!$card['attendee_id']) {
        echo cd_render_public_page($event, null, 'این کارت رزرو هنوز به کسی وصل نشده است.');
        exit;
    }
    $person = $wpdb->get_row($wpdb->prepare(
        'SELECT a.title, a.first_name, a.last_name, a.organization, a.presentation_kind,
                t.name AS type_name, r.name AS role_name
         FROM ' . cd_table('attendees') . ' a
         LEFT JOIN ' . cd_table('registration_types') . ' t ON t.id = a.registration_type_id
         LEFT JOIN ' . cd_table('roles') . ' r ON r.id = a.role_id
         WHERE a.id = %s',
        $card['attendee_id']
    ), ARRAY_A);
    echo cd_render_public_page($event, $person, null);
    exit;
});

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

function cd_render_public_page($event, $person, $message) {
    $e = function ($s) {
        return esc_html((string) $s);
    };
    $title = $event ? $event['name'] : get_bloginfo('name');

    ob_start();
    ?>
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?php echo $e($title); ?></title>
<style>
:root { --bg:#f6f5f2; --card:#fff; --ink:#1d1d1b; --muted:#6b6a66; --line:#e4e2dc; --accent:#1f5fbf; --accent-soft:#e7effa; }
@media (prefers-color-scheme: dark) { :root { --bg:#151514; --card:#1f1f1d; --ink:#f1f0ec; --muted:#a3a19b; --line:#33322f; --accent:#7fb0ff; --accent-soft:#1f2b3d; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font-family: Vazirmatn, "Vazir", Tahoma, "Segoe UI", sans-serif; line-height:1.7; }
main { max-width:560px; margin:0 auto; padding:20px 16px 48px; }
.event { color:var(--muted); font-size:14px; margin:0 0 12px; }
.person { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:20px; }
.person h1 { margin:0; font-size:24px; line-height:1.4; }
.person .org { color:var(--muted); margin-top:4px; }
.badges { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
.badge { background:var(--accent-soft); color:var(--accent); border-radius:999px; padding:3px 12px; font-size:14px; font-weight:600; }
.msg { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:20px; font-size:17px; }
h2 { font-size:17px; margin:28px 0 8px; }
.day { margin-top:18px; }
.day h3 { font-size:15px; color:var(--muted); margin:0 0 6px; font-weight:600; }
.s { display:flex; gap:12px; padding:10px 0; border-top:1px solid var(--line); }
.s:first-of-type { border-top:0; }
.t { min-width:92px; color:var(--muted); font-variant-numeric: tabular-nums; direction:ltr; text-align:right; }
.s .what { flex:1; }
.s .hall { color:var(--muted); font-size:14px; }
.kind { font-size:12px; color:var(--accent); }
</style>
</head>
<body>
<main>
<?php if ($event) : ?>
  <p class="event"><?php echo $e($event['name']); ?></p>
<?php endif; ?>

<?php if ($message) : ?>
  <div class="msg"><?php echo $e($message); ?></div>
<?php else : ?>
  <section class="person">
    <h1><?php echo $e(trim($person['title'] . ' ' . $person['first_name'] . ' ' . $person['last_name'])); ?></h1>
    <?php if ($person['organization'] !== '') : ?>
      <div class="org"><?php echo $e($person['organization']); ?></div>
    <?php endif; ?>
    <div class="badges">
      <?php if ($person['role_name']) : ?><span class="badge"><?php echo $e($person['role_name']); ?></span><?php endif; ?>
      <?php if ($person['type_name']) : ?><span class="badge"><?php echo $e($person['type_name']); ?></span><?php endif; ?>
      <?php $pk = cd_presentation_label($person['presentation_kind']); if ($pk) : ?><span class="badge"><?php echo $e($pk); ?></span><?php endif; ?>
    </div>
  </section>
<?php endif; ?>

<?php
if ($event) :
    $config = cd_event_config((int) $event['id']);
    $by_day = [];
    foreach ($config['sessions'] as $s) {
        $by_day[$s['day']][] = $s;
    }
    if ($by_day) :
        ?>
  <h2>برنامه‌ی کنفرانس</h2>
        <?php foreach ($by_day as $day => $sessions) : ?>
  <div class="day">
    <h3><?php echo $e(cd_day_label($day)); ?></h3>
            <?php foreach ($sessions as $s) : ?>
    <div class="s">
      <div class="t"><?php echo $e(cd_fa_digits($s['start_time'] . ($s['end_time'] ? '–' . $s['end_time'] : ''))); ?></div>
      <div class="what">
        <?php if ($s['kind']) : ?><div class="kind"><?php echo $e(cd_session_kind_label($s['kind'])); ?></div><?php endif; ?>
        <div><?php echo $e($s['title']); ?></div>
        <?php if ($s['hall'] !== '') : ?><div class="hall"><?php echo $e($s['hall']); ?></div><?php endif; ?>
      </div>
    </div>
            <?php endforeach; ?>
  </div>
        <?php endforeach; ?>
    <?php endif; ?>
<?php endif; ?>
</main>
</body>
</html>
    <?php
    return ob_get_clean();
}
