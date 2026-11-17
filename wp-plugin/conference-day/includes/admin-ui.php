<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * پیشخوان وردپرس: «رویدادیار» با دو صفحه
 * - داشبورد زنده: پذیرش، وعده‌ها، موارد مشکوک، گوشی‌ها، خروجی CSV
 * - تنظیمات: کلید API اپ مدیریت، کلیدهای گوشی مدیر، و «درباره»
 */

add_action('admin_menu', function () {
    add_menu_page('رویدادیار', 'رویدادیار', 'manage_options', 'cd-dashboard', 'cd_render_dashboard', 'dashicons-groups', 30);
    add_submenu_page('cd-dashboard', 'داشبورد رویدادیار', 'داشبورد', 'manage_options', 'cd-dashboard', 'cd_render_dashboard');
    add_submenu_page('cd-dashboard', 'تنظیمات رویدادیار', 'تنظیمات', 'manage_options', 'cd-settings', 'cd_render_settings');
});

/** پانویس پیشخوان فقط در صفحه‌های خود افزونه (MakerCredit). */
add_filter('admin_footer_text', function ($text) {
    $page = isset($_GET['page']) ? sanitize_key(wp_unslash($_GET['page'])) : '';
    if (strpos($page, 'cd-') !== 0) {
        return $text;
    }
    return 'رویدادیار ' . esc_html(CD_VERSION) . ' · ساخته‌ی <a href="https://newvisionteam.ir" target="_blank" rel="noopener">تیم راهکارهای نرم‌افزاری نگاه جدید</a>';
});

/** لینک «پشتیبانی» در فهرست افزونه‌ها. */
add_filter('plugin_row_meta', function ($links, $file) {
    if ($file === plugin_basename(CD_DIR . 'conference-day.php')) {
        $links[] = '<a href="https://newvisionteam.ir" target="_blank" rel="noopener">پشتیبانی</a>';
    }
    return $links;
}, 10, 2);

add_action('admin_post_cd_export_csv', function () {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_export_csv');
    $event = cd_get_event((int) ($_GET['event'] ?? 0));
    if (!$event) {
        wp_die('رویداد پیدا نشد.', 404);
    }
    nocache_headers();
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . sanitize_file_name($event['code'] . '-' . gmdate('Ymd-His') . '.csv') . '"');
    echo cd_export_csv($event); // phpcs:ignore WordPress.Security.EscapeOutput
    exit;
});

add_action('admin_post_cd_revoke_device', function () {
    global $wpdb;
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_revoke_device');
    $wpdb->update(cd_table('devices'), ['revoked' => 1], ['id' => (int) ($_POST['device'] ?? 0)]);
    wp_safe_redirect(admin_url('admin.php?page=cd-dashboard&event=' . (int) ($_POST['event'] ?? 0)));
    exit;
});

function cd_admin_time($iso) {
    if (!$iso) {
        return '—';
    }
    return get_date_from_gmt(gmdate('Y-m-d H:i:s', strtotime($iso)), 'Y-m-d H:i');
}

function cd_render_dashboard() {
    if (!current_user_can('manage_options')) {
        return;
    }
    $events = cd_all_events();
    $current = isset($_GET['event']) ? cd_get_event((int) $_GET['event']) : ($events[0] ?? null);

    echo '<div class="wrap" dir="rtl" style="text-align:right">';
    echo '<h1>داشبورد رویدادیار</h1>';

    if (!$events) {
        echo '<p>هنوز رویدادی ثبت نشده است. رویداد را از اپ مدیریت بسازید.</p>';
        echo '</div>';
        return;
    }

    echo '<form method="get" style="margin:12px 0"><input type="hidden" name="page" value="cd-dashboard"><select name="event" onchange="this.form.submit()">';
    foreach ($events as $ev) {
        printf(
            '<option value="%d" %s>%s</option>',
            (int) $ev['id'],
            selected($current && (int) $current['id'] === (int) $ev['id'], true, false),
            esc_html($ev['name'] . ' (' . $ev['code'] . ')')
        );
    }
    echo '</select> <label><input type="checkbox" id="cd-auto" checked> به‌روزرسانی خودکار هر ۳۰ ثانیه</label></form>';
    echo '<script>setTimeout(function(){ if (document.getElementById("cd-auto").checked) location.reload(); }, 30000);</script>';

    if (!$current) {
        echo '</div>';
        return;
    }

    $r = cd_build_report($current);
    $t = $r['totals'];
    $pct = $t['attendees'] ? round(100 * $t['checked_in'] / $t['attendees']) : 0;

    echo '<div style="display:flex;gap:12px;flex-wrap:wrap;margin:16px 0">';
    $tiles = [
        ['پذیرش‌شده', $t['checked_in'] . ' از ' . $t['attendees'] . ' (' . $pct . '٪)'],
        ['ثبت‌نام در محل', $t['walkins']],
        ['کارت رزرو باقی‌مانده', $t['reserve_cards_free']],
        ['موارد مشکوک', count($r['flagged'])],
    ];
    foreach ($tiles as $tile) {
        printf(
            '<div style="background:#fff;border:1px solid #dcdcde;border-radius:8px;padding:12px 16px;min-width:170px"><div style="color:#646970">%s</div><div style="font-size:22px;font-weight:600">%s</div></div>',
            esc_html($tile[0]),
            esc_html((string) $tile[1])
        );
    }
    echo '</div>';

    echo '<h2>پذیرش بر اساس نوع ثبت‌نام</h2><table class="widefat striped" style="max-width:700px"><thead><tr><th>نوع</th><th>کل</th><th>پذیرش‌شده</th></tr></thead><tbody>';
    foreach ($r['by_registration_type'] as $bt) {
        printf('<tr><td>%s</td><td>%d</td><td>%d</td></tr>', esc_html($bt['name']), $bt['total'], $bt['checked_in']);
    }
    echo '</tbody></table>';

    echo '<h2>پذیرایی</h2><table class="widefat striped" style="max-width:900px"><thead><tr><th>وعده</th><th>روز</th><th>حق دارند</th><th>تحویل‌شده</th><th>تکراری</th><th>بدون حق</th></tr></thead><tbody>';
    foreach ($r['meals'] as $m) {
        printf(
            '<tr><td>%s</td><td>%s</td><td>%d</td><td>%d</td><td>%d</td><td>%d</td></tr>',
            esc_html($m['name']),
            esc_html((string) $m['day']),
            $m['entitled'],
            $m['served'],
            $m['duplicates'],
            $m['not_entitled']
        );
    }
    if (!$r['meals']) {
        echo '<tr><td colspan="6">وعده‌ای تعریف نشده است.</td></tr>';
    }
    echo '</tbody></table>';

    echo '<h2>موارد مشکوک</h2><table class="widefat striped" style="max-width:1100px"><thead><tr><th>زمان</th><th>کار</th><th>فرد</th><th>مشکل</th><th>نیرو</th></tr></thead><tbody>';
    foreach ($r['flagged'] as $f) {
        printf(
            '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
            esc_html(cd_admin_time($f['device_time'])),
            esc_html(CD_KIND_LABELS[$f['kind']] ?? $f['kind']),
            esc_html($f['name'] !== '' ? $f['name'] : '—'),
            esc_html($f['flag_label']),
            esc_html((string) $f['staff'])
        );
    }
    if (!$r['flagged']) {
        echo '<tr><td colspan="5">موردی نیست.</td></tr>';
    }
    echo '</tbody></table>';

    echo '<h2>گوشی‌ها</h2><table class="widefat striped" style="max-width:900px"><thead><tr><th>نیرو</th><th>گوشی</th><th>آخرین همگام‌سازی</th><th></th></tr></thead><tbody>';
    foreach ($r['devices'] as $d) {
        $btn = $d['revoked'] ? 'باطل‌شده' : sprintf(
            '<form method="post" action="%s" onsubmit="return confirm(\'این گوشی باطل شود؟\')"><input type="hidden" name="action" value="cd_revoke_device"><input type="hidden" name="device" value="%d"><input type="hidden" name="event" value="%d">%s<button class="button button-small">باطل کردن</button></form>',
            esc_url(admin_url('admin-post.php')),
            $d['id'],
            (int) $current['id'],
            wp_nonce_field('cd_revoke_device', '_wpnonce', true, false)
        );
        printf(
            '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
            esc_html((string) $d['staff']),
            esc_html($d['label']),
            esc_html(cd_admin_time($d['last_sync_at'])),
            $btn // phpcs:ignore WordPress.Security.EscapeOutput
        );
    }
    if (!$r['devices']) {
        echo '<tr><td colspan="4">هنوز گوشی‌ای وارد نشده است.</td></tr>';
    }
    echo '</tbody></table>';

    $csv = wp_nonce_url(admin_url('admin-post.php?action=cd_export_csv&event=' . (int) $current['id']), 'cd_export_csv');
    printf('<p style="margin-top:20px"><a class="button button-primary" href="%s">دانلود CSV شرکت‌کننده‌ها و وضعیتشان</a></p>', esc_url($csv));
    echo '</div>';
}

function cd_render_settings() {
    if (!current_user_can('manage_options')) {
        return;
    }
    $notice = null;
    $shown = null; // [id, متن کلید] برای نمایش در همین صفحه
    if (isset($_POST['cd_key_action']) && check_admin_referer('cd_admin_keys')) {
        $action = sanitize_key(wp_unslash($_POST['cd_key_action']));
        $id = sanitize_text_field(wp_unslash($_POST['cd_key_id'] ?? ''));
        if ($action === 'create') {
            $label = cd_str(wp_unslash($_POST['cd_key_label'] ?? ''), 64);
            $role = sanitize_key(wp_unslash($_POST['cd_key_role'] ?? 'manager'));
            $shown = cd_admin_key_create($label, $role);
            $notice = 'کلید تازه ساخته شد. کلیدهای دیگر همچنان کار می‌کنند.';
        } elseif ($action === 'reveal') {
            $plain = cd_admin_key_reveal($id);
            if ($plain !== null) {
                $shown = [$id, $plain];
            } else {
                $notice = 'متن این کلید ذخیره نشده (کلید قدیمی). یک‌بار بازتولیدش کنید.';
            }
        } elseif ($action === 'revoke') {
            cd_admin_key_revoke($id);
            $notice = 'کلید باطل شد؛ اپی که با آن وصل بود دیگر دسترسی ندارد.';
        } elseif ($action === 'regenerate') {
            // کلید قدیمی بی‌متن: کلید تازه با همان نقش ساخته و قدیمی باطل می‌شود (به درخواست صریح مدیر).
            $keys = cd_admin_keys();
            if (isset($keys[$id])) {
                $label = strpos((string) $keys[$id]['label'], 'قدیمی') === 0 ? '' : (string) $keys[$id]['label'];
                $shown = cd_admin_key_create($label, (string) $keys[$id]['role']);
                cd_admin_key_revoke($id);
                $notice = 'کلید تازه جای کلید قدیمی را گرفت. آن را در اپ‌هایی که با کلید قدیمی وصل بودند وارد کنید.';
            }
        }
    }
    $keys = cd_admin_keys();

    echo '<div class="wrap" dir="rtl" style="text-align:right">';
    echo '<h1>تنظیمات رویدادیار</h1>';

    echo '<h2>آدرس سرور برای اپ‌ها</h2>';
    printf('<p><code dir="ltr">%s</code></p>', esc_html(untrailingslashit(home_url())));

    echo '<h2>کلیدهای اپ مدیریت</h2>';
    echo '<p>برای هر رایانه و گوشی کلید جدا بسازید. کلید را هر وقت لازم شد از همین صفحه دوباره ببینید و کپی کنید. '
        . 'اگر دستگاهی گم شد، فقط کلید همان را باطل کنید؛ ساختن کلید تازه کلیدهای دیگر را باطل نمی‌کند.</p>';
    if ($notice) {
        printf('<div class="notice notice-info"><p>%s</p></div>', esc_html($notice));
    }
    if ($shown) {
        printf(
            '<p><input id="cd-shown-key" type="text" readonly value="%s" style="width:100%%;max-width:560px;direction:ltr;font-family:monospace" onclick="this.select()"> '
            . '<button type="button" class="button" onclick="var i=document.getElementById(\'cd-shown-key\');i.select();(navigator.clipboard?navigator.clipboard.writeText(i.value):Promise.reject()).then(function(){},function(){document.execCommand(\'copy\')});this.textContent=\'کپی شد\'">کپی</button></p>',
            esc_attr($shown[1])
        );
    }
    $form = function ($action, $id, $label, $confirm = '', $class = 'button button-small') {
        return sprintf(
            '<form method="post" style="display:inline">%s<input type="hidden" name="cd_key_action" value="%s"><input type="hidden" name="cd_key_id" value="%s"><button class="%s"%s>%s</button></form> ',
            wp_nonce_field('cd_admin_keys', '_wpnonce', true, false),
            esc_attr($action),
            esc_attr($id),
            esc_attr($class),
            $confirm !== '' ? ' onclick="return confirm(\'' . esc_js($confirm) . '\')"' : '',
            esc_html($label)
        );
    };
    echo '<table class="widefat striped" style="max-width:900px"><thead><tr><th>کلید</th><th>دسترسی</th><th>ساخته‌شده</th><th>آخرین استفاده</th><th></th></tr></thead><tbody>';
    foreach ($keys as $id => $k) {
        $actions = '';
        if (!empty($k['revoked'])) {
            $actions = 'باطل‌شده';
        } else {
            $actions .= $k['enc'] !== ''
                ? $form('reveal', $id, 'نمایش و کپی')
                : $form('regenerate', $id, 'بازتولید', 'کلید تازه ساخته و این کلید باطل می‌شود. اپ‌هایی که با آن وصل‌اند باید کلید تازه را بگیرند. ادامه؟');
            $actions .= $form('revoke', $id, 'باطل کردن', 'این کلید باطل شود؟ اپی که با آن وصل است دیگر دسترسی ندارد.');
        }
        printf(
            '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
            esc_html($k['label']),
            esc_html(CD_KEY_ROLES[$k['role']] ?? $k['role']),
            esc_html(cd_admin_time(cd_iso($k['created_at']))),
            esc_html(cd_admin_time(!empty($k['last_used']) ? cd_iso($k['last_used']) : null)),
            $actions // phpcs:ignore WordPress.Security.EscapeOutput
        );
    }
    if (!$keys) {
        echo '<tr><td colspan="5">هنوز کلیدی ساخته نشده است.</td></tr>';
    }
    echo '</tbody></table>';
    echo '<form method="post" style="margin-top:12px">';
    wp_nonce_field('cd_admin_keys');
    echo '<input type="hidden" name="cd_key_action" value="create">';
    echo '<input type="text" name="cd_key_label" placeholder="نام دستگاه، مثلاً لپ‌تاپ دفتر یا گوشی محمد" style="width:280px"> ';
    echo '<select name="cd_key_role">';
    foreach (CD_KEY_ROLES as $r => $label) {
        printf('<option value="%s"%s>%s</option>', esc_attr($r), selected($r, 'manager', false), esc_html($label));
    }
    echo '</select> ';
    echo '<button class="button button-primary">ساخت کلید</button>';
    echo '</form>';
    echo '<p style="color:#646970">مالک: همه‌ی کارها. مدیر اجرایی: همه‌چیز جز حذف و بایگانی رویداد. فقط گزارش: فقط «امروز» و «افراد»، بدون تغییر.</p>';

    echo '<h2>درباره</h2>';
    echo '<div style="background:#fff;border:1px solid #dcdcde;border-radius:8px;padding:16px;max-width:640px">';
    printf('<p style="margin:0;font-size:15px;font-weight:600">رویدادیار (RoydadYar) %s</p>', esc_html(CD_VERSION));
    echo '<p style="margin:4px 0 0;color:#646970">ساخته‌ی تیم راهکارهای نرم‌افزاری نگاه جدید (NewVisionteam)</p>';
    echo '<p style="margin:4px 0 0"><a href="https://newvisionteam.ir" target="_blank" rel="noopener" dir="ltr">newvisionteam.ir</a></p>';
    echo '</div>';
    echo '</div>';
}
