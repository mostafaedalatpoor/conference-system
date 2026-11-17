<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * پیشخوان وردپرس «رویدادیار» (طراحی «افزونه‌ی وردپرس رویدادیار» در سیستم فیروزه):
 * داشبورد (و «شروع» بار اول)، رویدادها، اتصال اپ‌ها، صفحه‌های عمومی، راهنما.
 * ساخت و ویرایش رویداد در اپ مدیریت است؛ اینجا فقط دیدن، لینک‌ها، کلیدها و چند کار ساده (خروجی، بایگانی).
 */

const CD_DOWNLOADS_URL = 'https://github.com/mostafaedalatpoor/conference-system/releases/latest';
const CD_SUPPORT_EMAIL = 'info@newvisionteam.ir';
const CD_SUPPORT_URL = 'https://newvisionteam.ir/contact-us';

const CD_ADMIN_PAGES = [
    'cd-dashboard' => 'داشبورد',
    'cd-events' => 'رویدادها',
    'cd-connect' => 'اتصال اپ‌ها',
    'cd-public' => 'صفحه‌های عمومی',
    'cd-help' => 'راهنما',
];

add_action('admin_menu', function () {
    add_menu_page('رویدادیار', 'رویدادیار', 'manage_options', 'cd-dashboard', 'cd_render_dashboard', 'dashicons-calendar-alt', 30);
    $render = [
        'cd-dashboard' => 'cd_render_dashboard',
        'cd-events' => 'cd_render_events',
        'cd-connect' => 'cd_render_connect',
        'cd-public' => 'cd_render_public',
        'cd-help' => 'cd_render_help',
    ];
    foreach (CD_ADMIN_PAGES as $slug => $title) {
        add_submenu_page('cd-dashboard', $title . ' · رویدادیار', $title, 'manage_options', $slug, $render[$slug]);
    }
    // نشانی قدیمی «تنظیمات» (نسخه‌ی پیش) به «اتصال اپ‌ها» می‌رسد.
    add_submenu_page('', 'اتصال اپ‌ها · رویدادیار', '', 'manage_options', 'cd-settings', 'cd_render_connect');
});

/** بعد از فعال‌سازی، صفحه‌ی «شروع» یک بار باز می‌شود. */
add_action('admin_init', function () {
    if (get_transient('cd_activation_redirect') && current_user_can('manage_options') && !wp_doing_ajax() && !isset($_GET['activate-multi'])) {
        delete_transient('cd_activation_redirect');
        wp_safe_redirect(admin_url('admin.php?page=cd-dashboard'));
        exit;
    }
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

// ---------------------------------------------------------------- کارها (admin-post)

function cd_admin_guard($nonce) {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer($nonce);
}

add_action('admin_post_cd_export_csv', function () {
    cd_admin_guard('cd_export_csv');
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
    cd_admin_guard('cd_revoke_device');
    $wpdb->update(cd_table('devices'), ['revoked' => 1], ['id' => (int) ($_POST['device'] ?? 0)]);
    wp_safe_redirect(admin_url('admin.php?page=cd-dashboard&event=' . (int) ($_POST['event'] ?? 0)));
    exit;
});

/** بایگانی یا برگرداندن رویداد از صفحه‌ی «رویدادها». حذف فقط در اپ و با نوشتن کد رویداد. */
add_action('admin_post_cd_archive_event', function () {
    global $wpdb;
    cd_admin_guard('cd_archive_event');
    $event = cd_get_event((int) ($_POST['event'] ?? 0));
    if ($event) {
        $archive = !empty($_POST['archive']);
        $wpdb->query($wpdb->prepare(
            'UPDATE ' . cd_table('events') . ' SET archived_at = ' . ($archive ? '%s' : 'NULL') . ', updated_at = %s WHERE id = %d',
            array_values(array_filter([$archive ? cd_now() : null, cd_now(), (int) $event['id']], function ($v) {
                return $v !== null;
            }))
        ));
        cd_bump_config((int) $event['id']);
    }
    wp_safe_redirect(admin_url('admin.php?page=cd-events'));
    exit;
});

/** «بازنشانی پیوندها» (راهنما): قانون‌های /c/ و وب‌پیج از نو ساخته می‌شوند. */
add_action('admin_post_cd_flush_links', function () {
    cd_admin_guard('cd_flush_links');
    cd_add_rewrite();
    cd_web_add_rewrite();
    flush_rewrite_rules(false);
    wp_safe_redirect(admin_url('admin.php?page=cd-help&flushed=1'));
    exit;
});

add_action('admin_post_cd_web_dashboard', function () {
    cd_admin_guard('cd_web_dashboard');
    $err = cd_web_save([
        'enabled' => !empty($_POST['enabled']),
        'slug' => sanitize_text_field(wp_unslash($_POST['slug'] ?? '')),
        'access' => sanitize_key(wp_unslash($_POST['access'] ?? 'admins')),
        'new_key' => !empty($_POST['new_key']),
    ]);
    $args = ['page' => 'cd-public', 'event' => (int) ($_POST['event'] ?? 0)];
    if ($err !== null) {
        set_transient('cd_web_error_' . get_current_user_id(), [$err, sanitize_text_field(wp_unslash($_POST['slug'] ?? ''))], 60);
        $args['web'] = 'error';
    } else {
        $args['web'] = 'saved';
    }
    wp_safe_redirect(add_query_arg($args, admin_url('admin.php')));
    exit;
});

function cd_admin_time($iso) {
    if (!$iso) {
        return '—';
    }
    return get_date_from_gmt(gmdate('Y-m-d H:i:s', strtotime($iso)), 'Y-m-d H:i');
}

// ---------------------------------------------------------------- قاب مشترک

/** سربرگ فیروزه‌ای با زبانه‌ها. $extra کنار عنوان (مثلاً انتخاب رویداد). */
function cd_ui_open($active, $title, $sub = '', $extra = '') {
    echo cd_ui_styles(); // phpcs:ignore WordPress.Security.EscapeOutput
    echo '<div class="cd-ui"><div class="cd-hero"><div class="t"><div style="flex-grow:1;display:flex;flex-direction:column">';
    if ($sub !== '') {
        printf('<span class="sub">%s</span>', esc_html($sub));
    }
    printf('<h1>%s</h1></div>%s</div><div class="cd-tabs">', esc_html($title), $extra); // phpcs:ignore WordPress.Security.EscapeOutput
    foreach (CD_ADMIN_PAGES as $slug => $label) {
        printf(
            '<a class="cd-tab%s" href="%s">%s</a>',
            $slug === $active ? ' on' : '',
            esc_url(admin_url('admin.php?page=' . $slug)),
            esc_html($label)
        );
    }
    echo '</div></div><div class="cd-body">';
}

function cd_ui_close() {
    echo '</div></div>';
}

/** انتخاب رویداد در سربرگ (رویدادهای فعال). */
function cd_ui_event_picker($page, array $events, array $current) {
    $out = sprintf('<form method="get" class="cd-chip"><input type="hidden" name="page" value="%s">رویداد: <select name="event" onchange="this.form.submit()">', esc_attr($page));
    foreach ($events as $ev) {
        $out .= sprintf('<option value="%d"%s>%s</option>', (int) $ev['id'], selected((int) $ev['id'], (int) $current['id'], false), esc_html($ev['code']));
    }
    return $out . '</select></form>';
}

/** رویداد انتخاب‌شده از ?event، وگرنه اولین رویداد فعال. */
function cd_ui_current_event(array $events) {
    $current = isset($_GET['event']) ? cd_get_event((int) $_GET['event']) : null;
    return $current ?: ($events[0] ?? null);
}

// ---------------------------------------------------------------- ۰۳ داشبورد (و ۰۲ شروع)

function cd_render_dashboard() {
    if (!current_user_can('manage_options')) {
        return;
    }
    $events = cd_all_events();
    if (!cd_all_events(true)) {
        cd_render_welcome();
        return;
    }
    $current = cd_ui_current_event($events);
    if (!$current) {
        cd_ui_open('cd-dashboard', 'داشبورد', 'رویدادیار');
        echo '<div class="cd-card pop"><p class="cd-mu">رویداد فعالی نیست؛ همه بایگانی شده‌اند. از «رویدادها» برگردانید یا در اپ رویداد تازه بسازید.</p></div>';
        cd_ui_close();
        return;
    }
    $sub = 'رویدادیار' . ($current['start_date'] ? ' · ' . cd_jalali_label($current['start_date']) : '') . ' · ' . cd_event_phase($current)[0];
    $extra = '<label class="cd-chip"><input type="checkbox" id="cd-auto" checked> به‌روزرسانی خودکار · ' . esc_html(cd_fa_digits(current_time('H:i'))) . '</label>'
        . cd_ui_event_picker('cd-dashboard', $events, $current);
    cd_ui_open('cd-dashboard', $current['name'], $sub, $extra);
    $csv = wp_nonce_url(admin_url('admin-post.php?action=cd_export_csv&event=' . (int) $current['id']), 'cd_export_csv');
    echo cd_dashboard_body($current, $csv); // phpcs:ignore WordPress.Security.EscapeOutput
    echo '<script>setTimeout(function(){var a=document.getElementById("cd-auto");if(a&&a.checked)location.reload();},30000);</script>';
    cd_ui_close();
}

/** «شروع» (۰۲-Welcome): بار اول، تا وقتی رویدادی ساخته نشده. */
function cd_render_welcome() {
    $keys = array_filter(cd_admin_keys(), function ($k) {
        return empty($k['revoked']);
    });
    $permalinks = (string) get_option('permalink_structure') !== '';
    $has_key = (bool) $keys;
    $steps = 4 - ($has_key ? 1 : 0);
    cd_ui_open('cd-dashboard', 'برای شروع، ' . ['', 'یک', 'دو', 'سه', 'چهار'][$steps] . ' قدم مانده', 'رویدادیار · نسخه‌ی ' . cd_fa_digits(CD_VERSION));
    ?>
    <div class="cd-grid cd-g31" style="align-items:start">
      <div class="cd-card pop" style="display:flex;flex-direction:column;gap:20px;padding:24px">
        <div class="cd-step"><span class="cd-dot ok">✓</span><div><b>افزونه فعال شد</b><div class="cd-mu"><?php echo $permalinks ? 'پیوندهای زیبا (permalink) هم درست است.' : 'پیوندهای زیبا خاموش است؛ صفحه‌ی QR با ?c= کار می‌کند. در «راهنما» ببینید.'; ?></div></div></div>
        <div class="cd-step" style="<?php echo $has_key ? '' : 'padding:16px;margin:0 -8px;border-radius:18px;background:color-mix(in srgb,var(--b) 8%,var(--sf));box-shadow:inset 0 0 0 2px var(--b)'; ?>">
          <span class="cd-dot <?php echo $has_key ? 'ok' : 'on'; ?>"><?php echo $has_key ? '✓' : '۲'; ?></span>
          <div style="flex-grow:1;display:flex;flex-direction:column;gap:12px"><div><b>کلید اتصال اپ مدیریت را بسازید</b><div class="cd-mu">اپ با آدرس سایت و این کلید به سایت وصل می‌شود. کلید را هر وقت لازم شد از «اتصال اپ‌ها» دوباره ببینید و کپی کنید.</div></div>
            <?php if (!$has_key) : ?>
              <form method="post" action="<?php echo esc_url(admin_url('admin.php?page=cd-connect')); ?>" style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
                <?php wp_nonce_field('cd_admin_keys'); ?><input type="hidden" name="cd_key_action" value="create"><input type="hidden" name="cd_key_role" value="owner"><input type="hidden" name="cd_key_label" value="اپ مدیریت">
                <button class="cd-btn pri"><span class="dashicons dashicons-admin-network"></span>ساخت کلید</button>
                <a href="<?php echo esc_url(admin_url('admin.php?page=cd-connect')); ?>" style="font-size:13px;font-weight:800;text-decoration:none">کلید گوشی جدا هم می‌خواهم</a>
              </form>
            <?php endif; ?>
          </div></div>
        <div class="cd-step"><span class="cd-dot">۳</span><div><b>اپ مدیریت را وصل کنید</b><div class="cd-mu">اپ را باز کنید، آدرس و کلید را وارد کنید.</div></div></div>
        <div class="cd-step"><span class="cd-dot">۴</span><div><b>رویداد را در اپ بسازید</b><div class="cd-mu">با ساخت اولین رویداد، این صفحه به داشبورد تبدیل می‌شود.</div></div></div>
        <div class="cd-step"><span class="cd-dot">۵</span><div><b>یک کارت آزمایشی را اسکن کنید</b><div class="cd-mu">پیش از روز اجرا، یک بار مسیر پذیرش را امتحان کنید.</div></div></div>
      </div>
      <div style="display:flex;flex-direction:column;gap:14px">
        <div class="cd-card"><h2>آدرس سایت برای اپ‌ها</h2><div class="cd-field"><span class="cd-ltr" style="flex-grow:1;font-weight:600"><?php echo esc_html(untrailingslashit(home_url())); ?></span><?php echo cd_ui_copy(untrailingslashit(home_url())); // phpcs:ignore ?></div></div>
        <div class="cd-card"><h2>دانلود اپ‌ها</h2>
          <?php foreach ([['dashicons-smartphone', 'مدیریت · اندروید'], ['dashicons-desktop', 'مدیریت · ویندوز'], ['dashicons-smartphone', 'نیروها · اندروید'], ['dashicons-desktop', 'نیروها · ویندوز']] as $i => $d) : ?>
            <a href="<?php echo esc_url(CD_DOWNLOADS_URL); ?>" target="_blank" rel="noopener" class="cd-row" style="grid-template-columns:28px 1fr auto;text-decoration:none;color:inherit"><span class="dashicons <?php echo esc_attr($d[0]); ?> cd-ic b"></span><span><?php echo esc_html($d[1]); ?></span><span class="dashicons dashicons-download" style="color:var(--mu)"></span></a>
          <?php endforeach; ?>
        </div>
      </div>
    </div>
    <?php
    cd_ui_close();
}

// ---------------------------------------------------------------- ۰۴ رویدادها

function cd_render_events() {
    global $wpdb;
    if (!current_user_can('manage_options')) {
        return;
    }
    $events = cd_all_events(true);
    cd_ui_open('cd-events', 'رویدادها', cd_fa_digits(count($events)) . ' رویداد');
    echo '<div class="cd-card pop" style="padding:0;overflow:hidden">';
    echo '<div class="cd-row hd" style="grid-template-columns:2fr 1fr 1fr 1fr 1.4fr;padding:0 20px;background:var(--sf2)"><span>رویداد</span><span>تاریخ</span><span>افراد</span><span>وضعیت</span><span></span></div>';
    foreach ($events as $e) {
        $eid = (int) $e['id'];
        $people = (int) $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('attendees') . " WHERE event_id = %d AND status = 'active'", $eid));
        $checked = (int) cd_build_report($e)['totals']['checked_in'];
        [$phase, $tone] = cd_event_phase($e);
        $archived = !empty($e['archived_at']);
        $actions = '';
        if (!$archived) {
            $actions .= sprintf('<a class="cd-btn sm" href="%s">داشبورد</a>', esc_url(admin_url('admin.php?page=cd-dashboard&event=' . $eid)));
            $actions .= sprintf('<a class="cd-btn sm" href="%s"><span class="dashicons dashicons-download"></span>خروجی</a>', esc_url(wp_nonce_url(admin_url('admin-post.php?action=cd_export_csv&event=' . $eid), 'cd_export_csv')));
        }
        $actions .= sprintf(
            '<form method="post" action="%s" style="display:inline"%s>%s<input type="hidden" name="action" value="cd_archive_event"><input type="hidden" name="event" value="%d"><input type="hidden" name="archive" value="%d"><button class="cd-btn sm">%s</button></form>',
            esc_url(admin_url('admin-post.php')),
            $archived ? '' : ' onsubmit="return confirm(\'بایگانی شود؟ رویداد از فهرست اپ‌ها کنار می‌رود و فقط خواندنی می‌شود؛ هر وقت خواستید برش می‌گردانید.\')"',
            wp_nonce_field('cd_archive_event', '_wpnonce', true, false),
            $eid,
            $archived ? 0 : 1,
            $archived ? 'برگرداندن' : '<span class="dashicons dashicons-archive"></span>بایگانی…'
        );
        printf(
            '<div class="cd-row" style="grid-template-columns:2fr 1fr 1fr 1fr 1.4fr;padding:0 20px;min-height:68px;%s"><span style="display:flex;flex-direction:column"><b style="font-size:15px">%s</b><span class="cd-mu cd-ltr">%s</span></span><span>%s</span><span>%s · %s پذیرش</span><span class="cd-pl %s">%s</span><span style="display:flex;gap:6px;justify-content:flex-end;flex-wrap:wrap">%s</span></div>',
            $archived ? 'opacity:.7' : '',
            esc_html($e['name']),
            esc_html($e['code']),
            esc_html(cd_jalali_label($e['start_date'] ?? '') ?: '—'),
            esc_html(cd_fa_digits($people)),
            esc_html(cd_fa_digits($checked)),
            esc_attr($tone),
            esc_html($phase),
            $actions // phpcs:ignore WordPress.Security.EscapeOutput
        );
    }
    if (!$events) {
        echo '<p class="cd-mu" style="padding:20px">هنوز رویدادی نیست.</p>';
    }
    echo '</div>';
    ?>
    <div class="cd-card" style="display:flex;align-items:center;gap:16px;flex-wrap:wrap"><span class="dashicons dashicons-plus-alt cd-ic b" style="font-size:32px;width:32px;height:32px"></span><div style="flex-grow:1"><b>رویداد تازه را در اپ مدیریت بسازید</b><div class="cd-mu">ساخت رویداد، افراد و کارت‌ها همه در اپ انجام می‌شود. این صفحه فقط فهرست و لینک‌هاست.</div></div><a class="cd-btn pri" href="<?php echo esc_url(admin_url('admin.php?page=cd-connect')); ?>">اتصال اپ‌ها</a></div>
    <div class="cd-note"><span class="dashicons dashicons-info"></span><span>حذف رویداد از اینجا ممکن نیست. بایگانی‌کردن رویداد را از دید می‌اندازد و اطلاعات را نگه می‌دارد؛ حذف کامل فقط در اپ و با نوشتن کد رویداد انجام می‌شود.</span></div>
    <?php
    cd_ui_close();
}

// ---------------------------------------------------------------- ۰۵ اتصال اپ‌ها (کلیدها، آ-۲)

/** کارهای فرم کلیدها؛ خروجی [پیام، [id، متن کلید] یا null]. */
function cd_handle_key_actions() {
    $notice = null;
    $shown = null;
    if (!isset($_POST['cd_key_action']) || !check_admin_referer('cd_admin_keys')) {
        return [null, null];
    }
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
        $keys = cd_admin_keys();
        if (isset($keys[$id])) {
            $label = strpos((string) $keys[$id]['label'], 'قدیمی') === 0 ? '' : (string) $keys[$id]['label'];
            $shown = cd_admin_key_create($label, (string) $keys[$id]['role']);
            cd_admin_key_revoke($id);
            $notice = 'کلید تازه جای کلید قدیمی را گرفت. آن را در اپ‌هایی که با کلید قدیمی وصل بودند وارد کنید.';
        }
    }
    return [$notice, $shown];
}

function cd_render_connect() {
    if (!current_user_can('manage_options')) {
        return;
    }
    [$notice, $shown] = cd_handle_key_actions();
    $keys = cd_admin_keys();
    $active = array_filter($keys, function ($k) {
        return empty($k['revoked']);
    });
    cd_ui_open('cd-connect', 'اتصال اپ‌ها', 'قدم ۲ و ۳ شروع');
    $site = untrailingslashit(home_url());
    $form = function ($action, $id, $label, $confirm = '', $class = 'cd-btn sm') {
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
    ?>
    <div class="cd-card pop"><h2><span class="dashicons dashicons-admin-site-alt3 cd-ic b"></span> آدرس سایت</h2>
      <div class="cd-field" style="max-width:640px"><span class="cd-ltr" style="flex-grow:1;font-weight:600"><?php echo esc_html($site); ?></span><?php echo cd_ui_copy($site); // phpcs:ignore ?></div>
      <p class="cd-mu" style="margin:8px 0 0">این را در اپ، بخش «آدرس سایت» بنویسید.</p></div>

    <div class="cd-card">
      <div style="display:flex;align-items:center;gap:10px"><h2 style="flex-grow:1"><span class="dashicons dashicons-admin-network cd-ic b"></span> کلیدهای اپ مدیریت</h2><?php if ($active) : ?><span class="cd-pl go"><?php echo esc_html(cd_fa_digits(count($active))); ?> کلید فعال</span><?php endif; ?></div>
      <p class="cd-mu">برای هر رایانه و گوشی کلید جدا بسازید. کلید را هر وقت لازم شد از همین صفحه دوباره ببینید و کپی کنید؛ ساختن کلید تازه کلیدهای دیگر را باطل نمی‌کند. اگر دستگاهی گم شد، فقط کلید همان را باطل کنید.</p>
      <?php if ($notice) : ?><div class="cd-callout go" style="margin-bottom:10px"><?php echo esc_html($notice); ?></div><?php endif; ?>
      <?php if ($shown) : ?>
        <div class="cd-field" style="max-width:640px;margin-bottom:10px;box-shadow:inset 0 0 0 2px var(--b)"><span class="cd-ltr" style="flex-grow:1;font-family:monospace"><?php echo esc_html($shown[1]); ?></span><?php echo cd_ui_copy($shown[1], 'کپی'); // phpcs:ignore ?></div>
      <?php endif; ?>
      <div class="cd-row hd" style="grid-template-columns:1.4fr 1fr 1fr 1fr 1.6fr"><span>کلید</span><span>دسترسی</span><span>ساخته‌شده</span><span>آخرین استفاده</span><span></span></div>
      <?php foreach ($keys as $id => $k) :
          $actions = '';
          if (!empty($k['revoked'])) {
              $actions = '<span class="cd-pl mute">باطل‌شده</span>';
          } else {
              $actions .= $k['enc'] !== ''
                  ? $form('reveal', $id, 'نمایش و کپی')
                  : $form('regenerate', $id, 'بازتولید', 'کلید تازه ساخته و این کلید باطل می‌شود. اپ‌هایی که با آن وصل‌اند باید کلید تازه را بگیرند. ادامه؟');
              $actions .= $form('revoke', $id, 'باطل کن…', 'این کلید باطل شود؟ اپی که با آن وصل است دیگر دسترسی ندارد.', 'cd-btn sm danger');
          }
          ?>
        <div class="cd-row" style="grid-template-columns:1.4fr 1fr 1fr 1fr 1.6fr;<?php echo !empty($k['revoked']) ? 'color:var(--mu)' : ''; ?>"><b><?php echo esc_html($k['label']); ?></b><span><?php echo esc_html(CD_KEY_ROLES[$k['role']] ?? $k['role']); ?></span><span><?php echo esc_html(cd_ui_ago(cd_iso($k['created_at']))); ?></span><span><?php echo esc_html(!empty($k['last_used']) ? cd_ui_ago(cd_iso($k['last_used'])) : '—'); ?></span><span style="display:flex;gap:6px;justify-content:flex-end;flex-wrap:wrap"><?php echo $actions; // phpcs:ignore ?></span></div>
      <?php endforeach; ?>
      <?php if (!$keys) : ?><p class="cd-mu">هنوز کلیدی ساخته نشده است.</p><?php endif; ?>
      <form method="post" style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-top:12px">
        <?php wp_nonce_field('cd_admin_keys'); ?><input type="hidden" name="cd_key_action" value="create">
        <div class="cd-field" style="width:300px"><input type="text" name="cd_key_label" placeholder="نام دستگاه، مثلاً «گوشی محمد»"></div>
        <div class="cd-field" style="width:180px"><select name="cd_key_role"><?php foreach (CD_KEY_ROLES as $r => $label) : ?><option value="<?php echo esc_attr($r); ?>" <?php selected($r, 'manager'); ?>><?php echo esc_html($label); ?></option><?php endforeach; ?></select></div>
        <button class="cd-btn pri"><span class="dashicons dashicons-plus"></span>ساخت کلید</button>
      </form>
      <p class="cd-mu" style="margin:10px 0 0">مالک: همه‌ی کارها. مدیر اجرایی: همه‌چیز جز حذف و بایگانی رویداد. فقط گزارش: فقط «امروز» و «افراد»، بدون تغییر.</p>
    </div>
    <div class="cd-note"><span class="dashicons dashicons-info"></span><span>گوشی نیروها با کلید جدا و با پین، از داخل اپ مدیریت ساخته می‌شود، نه از اینجا.</span></div>
    <?php
    cd_ui_close();
}

// ---------------------------------------------------------------- ۰۶ صفحه‌های عمومی

function cd_render_public() {
    global $wpdb;
    if (!current_user_can('manage_options')) {
        return;
    }
    $events = cd_all_events();
    $current = cd_ui_current_event($events);
    $title = $current ? $current['name'] : 'صفحه‌های عمومی';
    cd_ui_open('cd-public', $title, 'صفحه‌های عمومی', $current ? cd_ui_event_picker('cd-public', $events, $current) : '');

    if ($current) {
        $st = cd_event_settings($current);
        $base = untrailingslashit($current['base_url'] ?: home_url());
        $qr = ['person' => 'صفحه‌ی شخصی', 'redirect' => 'رفتن به یک آدرس', 'vcard' => 'افزودن به مخاطبان (vCard)'][$st['qr_behavior']] ?? $st['qr_behavior'];
        $contact = array_keys(array_filter($st['contact_fields']));
        $labels = ['name' => 'نام', 'organization' => 'سازمان', 'email' => 'ایمیل', 'mobile' => 'موبایل', 'country' => 'کشور'];
        $sample = $wpdb->get_var($wpdb->prepare(
            'SELECT c.token FROM ' . cd_table('cards') . ' c JOIN ' . cd_table('attendees') . " a ON a.id = c.attendee_id
             WHERE c.event_id = %d AND c.revoked_at IS NULL AND a.status = 'active' ORDER BY c.serial LIMIT 1",
            (int) $current['id']
        ));
        ?>
        <div class="cd-card pop"><h2><span class="dashicons dashicons-id-alt cd-ic b"></span> صفحه‌ی شخصی هر فرد (QR کارت)</h2>
          <div class="cd-field" style="max-width:640px"><span class="cd-ltr" style="flex-grow:1;font-weight:600"><?php echo esc_html($base); ?>/c/<b style="color:var(--b)">{token}</b></span><?php echo cd_ui_copy($base . '/c/'); // phpcs:ignore ?></div>
          <div class="cd-row" style="grid-template-columns:1fr 1.4fr;max-width:640px"><span class="cd-mu">وقتی QR باز شود</span><b><?php echo esc_html($qr); ?></b></div>
          <div class="cd-row" style="grid-template-columns:1fr 1.4fr;max-width:640px"><span class="cd-mu">اطلاعات تماس روی صفحه</span><b><?php echo esc_html(implode('، ', array_map(function ($k) use ($labels) { return $labels[$k] ?? $k; }, $contact)) ?: '—'); ?></b></div>
          <div class="cd-row" style="grid-template-columns:1fr 1.4fr;max-width:640px"><span class="cd-mu">صفحه‌ها ساخته می‌شوند</span><b>هنگام باز شدن</b></div>
          <p class="cd-mu">صفحه‌ی هر فرد از قبل ساخته نمی‌شود؛ فقط وقتی کسی QR را باز کند ساخته می‌شود، پس بار اضافه‌ای روی سایت نیست. رفتار QR را از «تنظیم رویداد» در اپ عوض کنید.</p>
          <?php if ($sample) : ?><a class="cd-btn" target="_blank" rel="noopener" href="<?php echo esc_url($base . '/c/' . $sample); ?>"><span class="dashicons dashicons-external"></span>پیش‌نمایش صفحه‌ی یک نفر</a><?php endif; ?>
        </div>
        <?php if ((int) $current['base_url_locked']) : ?>
          <div class="cd-callout stop"><span class="dashicons dashicons-lock"></span><span><b>آدرس پایه‌ی QR کارت‌ها قفل است.</b> کارت‌ها با <?php echo esc_html(wp_parse_url($base, PHP_URL_HOST)); ?> چاپ شده‌اند. اگر دامنه‌ی سایت را عوض کنید، QR کارت‌های چاپ‌شده کار نمی‌کند و باید دوباره چاپ شوند.</span></div>
        <?php endif;
    }

    // داشبورد روی صفحه‌ی وب
    $web = cd_web_settings();
    $error = null;
    $typed = $web['slug'];
    if (isset($_GET['web']) && $_GET['web'] === 'error') {
        $e = get_transient('cd_web_error_' . get_current_user_id());
        if (is_array($e)) {
            [$error, $typed] = $e;
        }
    }
    $url = cd_web_url();
    ?>
    <div class="cd-card">
      <h2><span class="dashicons dashicons-dashboard cd-ic b"></span> داشبورد روی صفحه‌ی وب</h2>
      <p class="cd-mu">اگر بخواهید، همین داشبورد روی یک صفحه‌ی وب هم در دسترس باشد (مثلاً روی تلویزیون سالن یا گوشی مدیر بدون ورود به پیشخوان). پیشخوان وردپرس مثل قبل کار می‌کند.</p>
      <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" style="display:flex;flex-direction:column;gap:12px;max-width:640px">
        <?php wp_nonce_field('cd_web_dashboard'); ?><input type="hidden" name="action" value="cd_web_dashboard"><input type="hidden" name="event" value="<?php echo (int) ($current['id'] ?? 0); ?>">
        <label style="display:flex;gap:8px;align-items:center;font-weight:700"><input type="checkbox" name="enabled" value="1" <?php checked($web['enabled']); ?>> روشن باشد</label>
        <span class="cd-mu">آدرس صفحه</span>
        <div class="cd-field" style="<?php echo $error ? 'box-shadow:inset 0 0 0 2px var(--st)' : ''; ?>"><span class="cd-ltr" style="color:var(--mu)"><?php echo esc_html(trailingslashit(home_url())); ?></span><input class="cd-ltr" type="text" name="slug" value="<?php echo esc_attr($typed); ?>" placeholder="ops-dashboard" style="direction:ltr;text-align:left"></div>
        <?php if ($error) : ?><span style="color:var(--st);font-size:13px;font-weight:600"><?php echo esc_html($error); ?></span>
        <?php elseif ($web['enabled'] && $web['slug'] !== '') : ?><span style="color:var(--go);font-size:13px;font-weight:600">این آدرس آزاد است و صفحه روشن است.</span><?php endif; ?>
        <span class="cd-mu">چه کسی می‌تواند ببیند؟</span>
        <label style="display:flex;gap:8px;align-items:center"><input type="radio" name="access" value="admins" <?php checked($web['access'], 'admins'); ?>> فقط مدیران واردشده به وردپرس</label>
        <label style="display:flex;gap:8px;align-items:center"><input type="radio" name="access" value="key" <?php checked($web['access'], 'key'); ?>> هر کس لینک کامل (با کلید داخل لینک) را داشته باشد</label>
        <?php if ($web['access'] === 'key' && $web['key_hash'] !== '') : ?><label style="display:flex;gap:8px;align-items:center" class="cd-mu"><input type="checkbox" name="new_key" value="1"> کلید لینک عوض شود (لینک قبلی دیگر کار نمی‌کند)</label><?php endif; ?>
        <div class="cd-callout go" style="background:var(--sf2);color:var(--ink)"><span class="dashicons dashicons-shield"></span><span>صفحه فقط می‌خواند، در موتورهای جستجو نمی‌آید، ذخیره‌ی میانی نمی‌شود و بدون ورود یا کلید معتبر چیزی نشان نمی‌دهد.</span></div>
        <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="cd-btn pri">ذخیره</button>
          <?php if ($url) : ?><?php echo cd_ui_copy($url, 'کپی لینک'); // phpcs:ignore ?><a class="cd-btn" href="<?php echo esc_url($url); ?>" target="_blank" rel="noopener"><span class="dashicons dashicons-external"></span>باز کردن</a><?php endif; ?></div>
      </form>
    </div>
    <?php
    cd_ui_close();
}

// ---------------------------------------------------------------- ۰۷ راهنما و وضعیت سیستم

/** بررسی‌های «وضعیت سیستم»: [متن، درست؟، توضیح در صورت مشکل]. */
function cd_system_checks() {
    $rules = get_option('rewrite_rules');
    $checks = [];
    $checks[] = [(string) get_option('permalink_structure') !== '', 'پیوندهای زیبا (permalink)', 'خاموش است؛ صفحه‌ی QR با ?c= کار می‌کند ولی بهتر است در «تنظیمات ← پیوندهای یکتا» روشن شود.'];
    $checks[] = [function_exists('rest_url') && strpos((string) rest_url(CD_NS), 'conf/v1') !== false, 'دسترسی API از اپ‌ها', 'مسیر API افزونه ساخته نشده؛ افزونه را غیرفعال و دوباره فعال کنید.'];
    $c_ok = (string) get_option('permalink_structure') === '' || (is_array($rules) && isset($rules['^c/([A-Za-z0-9_-]{16,64})/?$']));
    $checks[] = [$c_ok, 'آدرس صفحه‌ی شخصی (/c/…)', 'قانون آدرس /c/ در وردپرس ثبت نیست؛ «بازنشانی پیوندها» را بزنید.'];
    $web = cd_web_settings();
    if ($web['enabled']) {
        $checks[] = [is_array($rules) && isset($rules['^' . preg_quote($web['slug'], '/') . '/?$']), 'آدرس داشبورد روی صفحه‌ی وب', 'قانون آدرس وب‌پیج ثبت نیست؛ «بازنشانی پیوندها» را بزنید.'];
    }
    $checks[] = [strpos(home_url(), 'https://') === 0, 'HTTPS', 'سایت بدون HTTPS است؛ اپ‌ها کلید را بی‌رمز می‌فرستند. گواهی SSL را روشن کنید.'];
    $checks[] = [get_option('cd_db_version') === CD_DB_VERSION, 'پایگاه داده به‌روز', 'جدول‌ها به‌روز نیستند؛ افزونه را غیرفعال و دوباره فعال کنید.'];
    $checks[] = [function_exists('sodium_crypto_secretbox'), 'رمزنگاری کلیدها و پین (sodium)', 'افزونه‌ی sodium در PHP این سرور نیست؛ کلیدها و پین‌ها قابل نمایش دوباره نیستند.'];
    return $checks;
}

function cd_render_help() {
    if (!current_user_can('manage_options')) {
        return;
    }
    cd_ui_open('cd-help', 'راهنما و وضعیت سیستم', 'رویدادیار (RoydadYar) · نسخه‌ی ' . cd_fa_digits(CD_VERSION));
    $checks = cd_system_checks();
    $bad = array_filter($checks, function ($c) {
        return !$c[0];
    });
    ?>
    <div class="cd-grid cd-g31" style="align-items:start">
      <div class="cd-card pop"><h2>وضعیت سیستم</h2>
        <?php if (isset($_GET['flushed'])) : ?><div class="cd-callout go" style="margin-bottom:8px">پیوندها بازنشانی شد.</div><?php endif; ?>
        <?php foreach ($checks as $c) : ?>
          <div class="cd-row" style="grid-template-columns:28px 1fr auto"><span class="dashicons <?php echo $c[0] ? 'dashicons-yes-alt cd-ic go' : 'dashicons-warning cd-ic wait'; ?>"></span><span><?php echo esc_html($c[1]); ?><?php if (!$c[0]) : ?><br><span class="cd-mu"><?php echo esc_html($c[2]); ?></span><?php endif; ?></span><span class="cd-pl <?php echo $c[0] ? 'go' : 'wait'; ?>"><?php echo $c[0] ? 'درست' : 'نیاز به توجه'; ?></span></div>
        <?php endforeach; ?>
        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" style="margin-top:12px"><?php wp_nonce_field('cd_flush_links'); ?><input type="hidden" name="action" value="cd_flush_links"><button class="cd-btn <?php echo $bad ? 'pri' : ''; ?>"><span class="dashicons dashicons-update"></span>بازنشانی پیوندها</button></form>
        <div class="cd-note" style="margin-top:12px"><span class="dashicons dashicons-info"></span><span>بیشتر وقت‌ها با «بازنشانی پیوندها» مشکل صفحه‌ی QR حل می‌شود. اگر نشد، تنظیم پیوندهای یکتا را در وردپرس یک‌بار دیگر ذخیره کنید.</span></div>
      </div>
      <div style="display:flex;flex-direction:column;gap:14px">
        <div class="cd-card"><h2>پشتیبانی</h2><p class="cd-mu">اگر گیر کردید، با تیم نگاه جدید در تماس باشید.</p>
          <div class="cd-field"><span class="dashicons dashicons-email cd-ic b"></span><span class="cd-ltr" style="flex-grow:1"><?php echo esc_html(CD_SUPPORT_EMAIL); ?></span><?php echo cd_ui_copy(CD_SUPPORT_EMAIL); // phpcs:ignore ?></div>
          <a class="cd-field" style="margin-top:8px;text-decoration:none;color:inherit" href="<?php echo esc_url(CD_SUPPORT_URL); ?>" target="_blank" rel="noopener"><span class="dashicons dashicons-sos cd-ic b"></span><span class="cd-ltr" style="flex-grow:1">newvisionteam.ir/contact-us</span><span class="dashicons dashicons-external"></span></a></div>
        <div class="cd-card" style="text-align:center"><span class="dashicons dashicons-calendar-alt cd-ic b" style="font-size:32px;width:32px;height:32px"></span><p style="margin:6px 0 0"><b>رویدادیار (RoydadYar)</b></p><p class="cd-mu" style="margin:0">ساخته‌ی تیم راهکارهای نرم‌افزاری نگاه جدید (NewVisionteam)</p></div>
      </div>
    </div>
    <?php
    cd_ui_close();
}
