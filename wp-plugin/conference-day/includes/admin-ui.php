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
    $new_key = null;
    if (isset($_POST['cd_new_key']) && check_admin_referer('cd_new_key')) {
        $new_key = 'cdk_' . cd_random_token(32);
        update_option('cd_admin_key_hash', hash('sha256', $new_key), false);
    }
    $has_key = (string) get_option('cd_admin_key_hash', '') !== '';

    // کلیدهای جدای گوشی مدیر (M1): هر گوشی کلید خودش را دارد و جدا باطل می‌شود.
    $mobile_keys = get_option('cd_mobile_keys', []);
    if (!is_array($mobile_keys)) {
        $mobile_keys = [];
    }
    $new_mobile_key = null;
    if (isset($_POST['cd_new_mobile_key']) && check_admin_referer('cd_mobile_keys')) {
        $label = cd_str(wp_unslash($_POST['cd_mobile_label'] ?? ''), 64);
        $new_mobile_key = 'cdm_' . cd_random_token(32);
        $mobile_keys[wp_generate_uuid4()] = [
            'label' => $label !== '' ? $label : 'گوشی مدیر',
            'hash' => hash('sha256', $new_mobile_key),
            'created_at' => cd_now(),
            'last_used' => null,
            'revoked' => false,
        ];
        update_option('cd_mobile_keys', $mobile_keys, false);
    }
    if (isset($_POST['cd_revoke_mobile_key']) && check_admin_referer('cd_mobile_keys')) {
        $id = sanitize_text_field(wp_unslash($_POST['cd_revoke_mobile_key']));
        if (isset($mobile_keys[$id])) {
            $mobile_keys[$id]['revoked'] = true;
            update_option('cd_mobile_keys', $mobile_keys, false);
        }
    }

    echo '<div class="wrap" dir="rtl" style="text-align:right">';
    echo '<h1>تنظیمات رویدادیار</h1>';

    echo '<h2>آدرس سرور برای اپ‌ها</h2>';
    printf('<p><code dir="ltr">%s</code></p>', esc_html(untrailingslashit(home_url())));

    echo '<h2>کلید API اپ مدیریت</h2>';
    if ($new_key) {
        echo '<div class="notice notice-success"><p>کلید جدید ساخته شد. همین حالا کپی‌اش کنید و در اپ مدیریت وارد کنید؛ دوباره نمایش داده نمی‌شود.</p></div>';
        printf('<p><input type="text" readonly value="%s" style="width:100%%;max-width:640px;direction:ltr;font-family:monospace" onclick="this.select()"></p>', esc_attr($new_key));
    } elseif ($has_key) {
        echo '<p>یک کلید فعال وجود دارد. ساختن کلید جدید، کلید قبلی را باطل می‌کند.</p>';
    } else {
        echo '<p>هنوز کلیدی ساخته نشده است.</p>';
    }
    echo '<form method="post">';
    wp_nonce_field('cd_new_key');
    submit_button($has_key ? 'ساخت کلید جدید (کلید قبلی باطل می‌شود)' : 'ساخت کلید', 'primary', 'cd_new_key');
    echo '</form>';

    echo '<h2>کلیدهای گوشی مدیر</h2>';
    echo '<p>برای اپ مدیریت روی گوشی یک کلید جدا بسازید. اگر گوشی گم شد، فقط همان کلید را باطل کنید؛ اپ ویندوز و گوشی‌های دیگر کار می‌کنند.</p>';
    if ($new_mobile_key) {
        echo '<div class="notice notice-success"><p>کلید گوشی ساخته شد. همین حالا در اپ مدیریت گوشی وارد کنید؛ دوباره نمایش داده نمی‌شود.</p></div>';
        printf('<p><input type="text" readonly value="%s" style="width:100%%;max-width:640px;direction:ltr;font-family:monospace" onclick="this.select()"></p>', esc_attr($new_mobile_key));
    }
    echo '<form method="post">';
    wp_nonce_field('cd_mobile_keys');
    echo '<table class="widefat striped" style="max-width:760px"><thead><tr><th>گوشی</th><th>ساخته‌شده</th><th>آخرین استفاده</th><th></th></tr></thead><tbody>';
    foreach ($mobile_keys as $id => $k) {
        printf(
            '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
            esc_html($k['label']),
            esc_html(cd_admin_time(cd_iso($k['created_at']))),
            esc_html(cd_admin_time($k['last_used'] ? cd_iso($k['last_used']) : null)),
            $k['revoked']
                ? 'باطل‌شده'
                : sprintf('<button class="button button-small" name="cd_revoke_mobile_key" value="%s" onclick="return confirm(\'این کلید باطل شود؟ آن گوشی دیگر به مدیریت دسترسی ندارد.\')">باطل کردن</button>', esc_attr($id)) // phpcs:ignore WordPress.Security.EscapeOutput
        );
    }
    if (!$mobile_keys) {
        echo '<tr><td colspan="4">هنوز کلید گوشی ساخته نشده است.</td></tr>';
    }
    echo '</tbody></table>';
    echo '<p><input type="text" name="cd_mobile_label" placeholder="نام گوشی، مثلاً گوشی محمد" style="width:260px"> ';
    echo '<button class="button button-primary" name="cd_new_mobile_key" value="1">ساخت کلید گوشی</button></p>';
    echo '</form>';

    echo '<h2>درباره</h2>';
    echo '<div style="background:#fff;border:1px solid #dcdcde;border-radius:8px;padding:16px;max-width:640px">';
    printf('<p style="margin:0;font-size:15px;font-weight:600">رویدادیار (RoydadYar) %s</p>', esc_html(CD_VERSION));
    echo '<p style="margin:4px 0 0;color:#646970">ساخته‌ی تیم راهکارهای نرم‌افزاری نگاه جدید (NewVisionteam)</p>';
    echo '<p style="margin:4px 0 0"><a href="https://newvisionteam.ir" target="_blank" rel="noopener" dir="ltr">newvisionteam.ir</a></p>';
    echo '</div>';
    echo '</div>';
}
