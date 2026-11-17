<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * ظاهر مشترک صفحه‌های افزونه (طراحی «افزونه‌ی وردپرس رویدادیار» در سیستم فیروزه):
 * سربرگ فیروزه‌ای با گوشه‌ی گرد، کارت‌های سفید، قلم وزیرمتن از خود افزونه، آیکن‌های dashicons وردپرس.
 * بدنه‌ی داشبورد هم در پیشخوان و هم در «حالت وب‌پیج» (web-dashboard.php) همین است.
 */

const CD_BRAND = '#0B7A7B';

/** تاریخ میلادی YYYY-MM-DD به «۱۴ آذر ۱۴۰۵». */
function cd_jalali_label($ymd) {
    if (!is_string($ymd) || !preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $ymd, $m)) {
        return '';
    }
    [$jy, $jm, $jd] = cd_gregorian_to_jalali((int) $m[1], (int) $m[2], (int) $m[3]);
    $months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
    return cd_fa_digits($jd) . ' ' . $months[$jm - 1] . ' ' . cd_fa_digits($jy);
}

/** زمان ISO (UTC) به «۱۰:۴۲» به وقت سایت. */
function cd_ui_hm($iso) {
    if (!$iso) {
        return '—';
    }
    return cd_fa_digits(get_date_from_gmt(gmdate('Y-m-d H:i:s', strtotime($iso)), 'H:i'));
}

/** «الان»، «۵ دقیقه پیش»، «دیروز ۱۶:۰۰». */
function cd_ui_ago($iso) {
    if (!$iso) {
        return '—';
    }
    $d = time() - strtotime($iso);
    if ($d < 90) {
        return 'الان';
    }
    if ($d < 3600) {
        return cd_fa_digits((string) floor($d / 60)) . ' دقیقه پیش';
    }
    if ($d < 86400) {
        return cd_fa_digits((string) floor($d / 3600)) . ' ساعت پیش';
    }
    return cd_jalali_label(get_date_from_gmt(gmdate('Y-m-d H:i:s', strtotime($iso)), 'Y-m-d')) . ' ' . cd_ui_hm($iso);
}

/** وضعیت رویداد برای فهرست: [متن، رنگ (go|wait|mute)]. */
function cd_event_phase(array $e) {
    if (!empty($e['archived_at'])) {
        return ['بایگانی‌شده', 'mute'];
    }
    $today = cd_event_day(cd_now());
    $start = $e['start_date'] ?: null;
    $end = $e['end_date'] ?: $start;
    if ($start && $today < $start) {
        return ['پیش رو', 'wait'];
    }
    if ($end && $today > $end) {
        return ['تمام شد', 'mute'];
    }
    if ($start) {
        return ['در حال برگزاری', 'go'];
    }
    return ['—', 'mute'];
}

/** استایل مشترک صفحه‌های افزونه. */
function cd_ui_styles() {
    $font = esc_url(plugins_url('assets/fonts/', CD_DIR . 'conference-day.php'));
    $b = CD_BRAND;
    return "<style>
@font-face{font-family:'Vazirmatn';src:url('{$font}Vazirmatn-Regular.woff2') format('woff2');font-weight:400 600;font-display:swap}
@font-face{font-family:'Vazirmatn';src:url('{$font}Vazirmatn-ExtraBold.woff2') format('woff2');font-weight:700 900;font-display:swap}
.cd-ui{--b:{$b};--bg:#F2F6F6;--sf:#FFFFFF;--sf2:#EAF1F1;--ink:#0F1C1D;--mu:#5B6B6C;--ln:#DCE7E7;--go:#138A43;--goBg:#E3F5EA;--wt:#8A5300;--wtBg:#FFF1D1;--st:#B3261E;--stBg:#FDE9E7;
 font-family:Vazirmatn,Tahoma,sans-serif;direction:rtl;text-align:right;color:var(--ink);background:var(--bg);margin:0 0 0 -20px;padding-bottom:32px;min-height:calc(100vh - 32px)}
.cd-ui *{box-sizing:border-box}
.cd-ui a{color:var(--b)}
.cd-hero{background:var(--b);color:#fff;padding:24px 36px 64px;border-radius:0 0 28px 28px;display:flex;flex-direction:column;gap:16px}
.cd-hero .t{display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.cd-hero .sub{font-size:13px;opacity:.85}
.cd-hero h1{color:#fff;font-size:28px;line-height:38px;font-weight:800;margin:0;padding:0}
.cd-tabs{display:flex;gap:8px;flex-wrap:wrap}
.cd-tab{height:40px;padding:0 16px;border-radius:20px;display:inline-flex;align-items:center;font-size:14px;font-weight:700;color:#fff!important;background:rgba(255,255,255,.16);text-decoration:none}
.cd-tab.on{background:#fff;color:var(--b)!important}
.cd-chip{display:inline-flex;align-items:center;gap:8px;height:40px;padding:0 14px;border-radius:20px;background:rgba(255,255,255,.16);font-size:13px;font-weight:700;color:#fff}
.cd-chip select{background:transparent;color:#fff;border:0;font:inherit;max-width:260px}
.cd-chip select option{color:#000}
.cd-body{margin:-36px 36px 0;display:flex;flex-direction:column;gap:16px;position:relative}
.cd-grid{display:grid;gap:14px}
.cd-g4{grid-template-columns:repeat(4,minmax(0,1fr))}.cd-g2{grid-template-columns:repeat(2,minmax(0,1fr))}.cd-g21{grid-template-columns:1.2fr 1fr}.cd-g31{grid-template-columns:1.7fr 1fr}
@media (max-width:960px){.cd-g4,.cd-g2,.cd-g21,.cd-g31{grid-template-columns:1fr}.cd-body{margin:-36px 12px 0}.cd-hero{padding:20px 16px 60px}}
.cd-card{background:var(--sf);border-radius:20px;padding:18px 20px}
.cd-card.pop{box-shadow:0 10px 30px rgba(11,122,123,.14)}
.cd-card h2{font-size:16px;font-weight:800;margin:0 0 6px;padding:0;color:var(--ink)}
.cd-mu{color:var(--mu);font-size:13px;line-height:21px}
.cd-big{font-size:32px;line-height:40px;font-weight:800}
.cd-bar{height:6px;border-radius:3px;background:var(--sf2);overflow:hidden}.cd-bar i{display:block;height:100%;background:var(--go)}
.cd-row{display:grid;gap:12px;align-items:center;min-height:48px;font-size:14px;border-bottom:1px solid var(--ln)}
.cd-row:last-child{border-bottom:0}
.cd-row.hd{font-size:12px;font-weight:700;color:var(--mu);min-height:36px}
.cd-pl{display:inline-flex;align-items:center;gap:4px;height:26px;padding:0 10px;border-radius:13px;font-size:12px;font-weight:700;white-space:nowrap;justify-self:start}
.cd-pl.go{background:var(--goBg);color:var(--go)}.cd-pl.wait{background:var(--wtBg);color:var(--wt)}.cd-pl.stop{background:var(--stBg);color:var(--st)}.cd-pl.mute{background:var(--sf2);color:var(--mu)}
.cd-ic{font-size:22px;width:22px;height:22px}.cd-ic.go{color:var(--go)}.cd-ic.wait{color:var(--wt)}.cd-ic.stop{color:var(--st)}.cd-ic.b{color:var(--b)}
.cd-btn{height:44px;padding:0 18px;border:0;border-radius:14px;background:var(--sf);color:var(--ink);box-shadow:inset 0 0 0 1px var(--ln);font:inherit;font-size:14px;font-weight:700;display:inline-flex;align-items:center;gap:8px;cursor:pointer;text-decoration:none}
.cd-btn.pri{background:var(--b);color:#fff!important;box-shadow:none;font-weight:800}
.cd-btn.sm{height:36px;padding:0 12px;border-radius:12px;font-size:12px;font-weight:800;background:var(--sf2);box-shadow:none}
.cd-btn.danger{color:var(--st);box-shadow:inset 0 0 0 1.5px var(--st);background:transparent}
.cd-field{height:48px;border-radius:14px;background:var(--sf2);padding:0 14px;display:flex;align-items:center;gap:10px}
.cd-field input,.cd-field select{flex-grow:1;background:transparent;border:0!important;box-shadow:none!important;font:inherit;font-size:14px;min-width:0}
.cd-ltr{direction:ltr;text-align:right}
.cd-note{display:flex;gap:10px;font-size:12px;line-height:20px;color:var(--mu);align-items:flex-start}
.cd-callout{border-radius:16px;padding:12px 16px;display:flex;gap:10px;align-items:flex-start;font-size:13px;line-height:21px}
.cd-callout.wait{background:var(--wtBg);color:var(--wt)}.cd-callout.stop{background:var(--stBg);color:var(--st)}.cd-callout.go{background:var(--goBg);color:var(--go)}
.cd-step{display:flex;gap:14px;align-items:flex-start}
.cd-dot{width:32px;height:32px;border-radius:16px;display:grid;place-items:center;flex-shrink:0;font-size:14px;font-weight:800;background:var(--sf2);color:var(--mu)}
.cd-dot.on{background:var(--b);color:#fff}.cd-dot.ok{background:var(--go);color:#fff}
.cd-foot{font-size:12px;color:var(--mu);text-align:center;padding-top:8px}
</style>";
}

/** دکمه‌ی کپی کنار یک متن (بی‌وابستگی). */
function cd_ui_copy($text, $label = '') {
    return sprintf(
        '<button type="button" class="cd-btn sm" onclick="var t=%s;(navigator.clipboard?navigator.clipboard.writeText(t):Promise.reject()).then(()=>{this.textContent=\'کپی شد\'},()=>{prompt(\'کپی کنید:\',t)})" title="کپی"><span class="dashicons dashicons-admin-page"></span>%s</button>',
        esc_attr(wp_json_encode((string) $text)),
        esc_html($label)
    );
}

/**
 * بدنه‌ی داشبورد زنده (۰۳-Dashboard). فقط می‌خواند؛ رسیدگی در اپ مدیریت است.
 * $csv_url: پیوند خروجی CSV یا null (در وب‌پیج با دسترسی کلیدی).
 */
function cd_dashboard_body(array $event, $csv_url = null) {
    global $wpdb;
    $eid = (int) $event['id'];
    $r = cd_build_report($event);
    $t = $r['totals'];
    $pct = $t['attendees'] ? (int) round(100 * $t['checked_in'] / $t['attendees']) : 0;
    $reserve_total = (int) $wpdb->get_var($wpdb->prepare(
        'SELECT COUNT(*) FROM ' . cd_table('cards') . ' WHERE event_id = %d AND is_reserve = 1 AND revoked_at IS NULL',
        $eid
    ));
    $flag_count = count(array_filter($r['flagged'], function ($f) {
        return empty($f['rejected']);
    }));

    // نیاز به توجه: موارد مشکوک تازه، کارهای ردشده، گوشی‌های ساکت.
    $attention = [];
    foreach ($r['flagged'] as $f) {
        if (count($attention) >= 4) {
            break;
        }
        $who = $f['name'] !== '' ? $f['name'] : 'بدون نام';
        if (!empty($f['rejected'])) {
            $attention[] = ['dashicons-shield', 'stop', $f['flag_label'] . ' · ' . ($f['staff'] ?? '') . ' · ' . (CD_KIND_LABELS[$f['kind']] ?? $f['kind']), 'رد شد', 'stop'];
        } else {
            $attention[] = ['dashicons-flag', 'stop', $f['flag_label'] . ' · ' . $who . ' · ' . cd_ui_hm($f['device_time']), 'مشکوک', 'stop'];
        }
    }
    foreach ($r['devices'] as $d) {
        if ($d['revoked'] || !$d['last_sync_at']) {
            continue;
        }
        $mins = (int) floor((time() - strtotime($d['last_sync_at'])) / 60);
        if ($mins >= 15 && $mins < 24 * 60) {
            $attention[] = ['dashicons-warning', 'wait', '«' . ($d['label'] !== '' ? $d['label'] : $d['staff']) . '» ' . cd_fa_digits((string) $mins) . ' دقیقه است ساکت است', 'آفلاین', 'wait'];
        }
    }
    if ($reserve_total > 0 && $t['reserve_cards_free'] <= max(2, (int) ceil($reserve_total / 5))) {
        $attention[] = ['dashicons-id', 'wait', 'کارت‌های رزرو کم است (' . cd_fa_digits($t['reserve_cards_free']) . ' از ' . cd_fa_digits($reserve_total) . ')', 'کم', 'wait'];
    }

    ob_start();
    ?>
    <div class="cd-grid cd-g4">
      <div class="cd-card pop"><span class="cd-mu">پذیرش‌شده</span><div><b class="cd-big" style="color:var(--go)"><?php echo esc_html(cd_fa_digits($t['checked_in'])); ?></b> <span class="cd-mu">از <?php echo esc_html(cd_fa_digits($t['attendees'])); ?> · <?php echo esc_html(cd_fa_digits($pct)); ?>٪</span></div><div class="cd-bar"><i style="width:<?php echo (int) $pct; ?>%"></i></div></div>
      <div class="cd-card pop"><span class="cd-mu">ثبت‌نام در محل</span><div class="cd-big"><?php echo esc_html(cd_fa_digits($t['walkins'])); ?></div><span class="cd-mu">تا الان</span></div>
      <div class="cd-card pop"><span class="cd-mu">کارت رزرو</span><div class="cd-big" style="color:var(--wt)"><?php echo esc_html(cd_fa_digits($t['reserve_cards_free'])); ?></div><span class="cd-mu">از <?php echo esc_html(cd_fa_digits($reserve_total)); ?> مانده</span></div>
      <div class="cd-card pop"><span class="cd-mu">موارد مشکوک</span><div class="cd-big" style="color:var(--st)"><?php echo esc_html(cd_fa_digits($flag_count)); ?></div><span class="cd-mu">در اپ بررسی کنید</span></div>
    </div>
    <div class="cd-grid cd-g21">
      <div class="cd-card">
        <div style="display:flex;align-items:center"><h2 style="flex-grow:1">نیاز به توجه</h2><?php if ($attention) : ?><span class="cd-pl wait"><?php echo esc_html(cd_fa_digits(count($attention))); ?> مورد</span><?php endif; ?></div>
        <?php foreach ($attention as $a) : ?>
          <div class="cd-row" style="grid-template-columns:28px 1fr auto"><span class="dashicons <?php echo esc_attr($a[0]); ?> cd-ic <?php echo esc_attr($a[1]); ?>"></span><span><?php echo esc_html($a[2]); ?></span><span class="cd-pl <?php echo esc_attr($a[4]); ?>"><?php echo esc_html($a[3]); ?></span></div>
        <?php endforeach; ?>
        <?php if (!$attention) : ?><p class="cd-mu">موردی نیست.</p><?php endif; ?>
        <p class="cd-mu" style="margin:8px 0 0">رسیدگی به موارد در اپ مدیریت انجام می‌شود؛ این صفحه فقط می‌خواند.</p>
      </div>
      <div class="cd-card">
        <h2>پذیرایی</h2>
        <div class="cd-row hd" style="grid-template-columns:1.2fr 1fr 1fr"><span>وعده</span><span>حق دارند</span><span>تحویل‌شده</span></div>
        <?php foreach ($r['meals'] as $m) : ?>
          <div class="cd-row" style="grid-template-columns:1.2fr 1fr 1fr;<?php echo empty($m['active']) ? 'color:var(--mu)' : ''; ?>"><b><?php echo esc_html($m['name']); ?><?php echo $m['day'] === cd_event_day(cd_now()) ? ' <span class="cd-pl go" style="height:22px">امروز</span>' : ''; ?></b><span><?php echo esc_html(cd_fa_digits($m['entitled'])); ?></span><span><?php echo esc_html(cd_fa_digits($m['served'])); ?></span></div>
        <?php endforeach; ?>
        <?php if (!$r['meals']) : ?><p class="cd-mu">وعده‌ای تعریف نشده است.</p><?php endif; ?>
      </div>
    </div>
    <div class="cd-grid cd-g2">
      <div class="cd-card">
        <h2>پذیرش بر اساس نوع</h2>
        <div class="cd-row hd" style="grid-template-columns:1.4fr 1fr 1fr"><span>نوع</span><span>کل</span><span>پذیرش‌شده</span></div>
        <?php foreach ($r['by_registration_type'] as $bt) : ?>
          <div class="cd-row" style="grid-template-columns:1.4fr 1fr 1fr"><b><?php echo esc_html($bt['name']); ?></b><span><?php echo esc_html(cd_fa_digits($bt['total'])); ?></span><span><?php echo esc_html(cd_fa_digits($bt['checked_in'])); ?></span></div>
        <?php endforeach; ?>
      </div>
      <div class="cd-card">
        <h2>گوشی‌ها</h2>
        <div class="cd-row hd" style="grid-template-columns:1.2fr 1fr 1fr auto"><span>گوشی</span><span>نیرو</span><span>آخرین همگام‌سازی</span><span></span></div>
        <?php foreach ($r['devices'] as $d) :
            $online = $d['last_sync_at'] && time() - strtotime($d['last_sync_at']) < 15 * 60;
            ?>
          <div class="cd-row" style="grid-template-columns:1.2fr 1fr 1fr auto"><b><?php echo esc_html($d['label'] !== '' ? $d['label'] : '—'); ?></b><span><?php echo esc_html((string) $d['staff']); ?></span><span><?php echo esc_html(cd_ui_ago($d['last_sync_at'])); ?></span>
            <?php if ($d['revoked']) : ?><span class="cd-pl mute">باطل‌شده</span><?php elseif ($online) : ?><span class="cd-pl go">آنلاین</span><?php else : ?><span class="cd-pl wait">آفلاین</span><?php endif; ?></div>
        <?php endforeach; ?>
        <?php if (!$r['devices']) : ?><p class="cd-mu">هنوز گوشی‌ای وارد نشده است.</p><?php endif; ?>
      </div>
    </div>
    <?php if ($csv_url) : ?>
      <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap"><a class="cd-btn" href="<?php echo esc_url($csv_url); ?>"><span class="dashicons dashicons-download"></span>خروجی CSV</a><span class="cd-mu">گزارش کامل‌تر (اکسل و PDF) را از اپ مدیریت بگیرید.</span></div>
    <?php endif;
    return ob_get_clean();
}
