<?php
if (!defined('ABSPATH')) {
    exit;
}

/*
 * سمت مدیر ماژول ثبت‌نام: API اپ مدیریت، خروجی اکسل، و دو صفحه در پیشخوان وردپرس
 * («صفحه‌ی ثبت‌نام» برای تنظیم و «ثبت‌نام‌ها» برای تأیید و پرداخت).
 */

// ---------------------------------------------------------------- API اپ مدیریت

add_action('rest_api_init', function () {
    $code = '(?P<code>[A-Za-z0-9_-]{1,64})';
    $admin = 'cd_admin_permission';
    register_rest_route(CD_NS, "/admin/events/$code/reg-page", [
        ['methods' => 'GET', 'permission_callback' => $admin, 'callback' => 'cd_rest_reg_page_get'],
        ['methods' => 'POST', 'permission_callback' => $admin, 'callback' => 'cd_rest_reg_page_save'],
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/registrations", [
        'methods' => 'GET', 'permission_callback' => $admin, 'callback' => 'cd_rest_regs_list',
    ]);
    register_rest_route(CD_NS, "/admin/events/$code/registrations/export", [
        'methods' => 'GET', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            $event = cd_event_from_request($r);
            if (is_wp_error($event)) {
                return $event;
            }
            [$name, $bytes, $mime] = cd_reg_export($event);
            return ['filename' => $name, 'mime' => $mime, 'data' => base64_encode($bytes)];
        },
    ]);
    register_rest_route(CD_NS, '/admin/registrations/(?P<id>\d+)/action', [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => 'cd_rest_reg_action',
    ]);
    register_rest_route(CD_NS, '/admin/registrations/(?P<id>\d+)/receipt', [
        'methods' => 'GET', 'permission_callback' => $admin, 'callback' => function (WP_REST_Request $r) {
            $reg = cd_reg_get((int) $r['id']);
            if (!$reg || $reg['receipt_file'] === '' || !preg_match('/^[a-f0-9]{32}\.(png|jpg|pdf)$/', $reg['receipt_file'])) {
                return cd_error('cd_no_receipt', 'رسیدی نیست.', 404);
            }
            $bytes = @file_get_contents(cd_reg_receipts_dir() . '/' . $reg['receipt_file']);
            if ($bytes === false) {
                return cd_error('cd_no_receipt', 'فایل رسید روی سرور نیست.', 404);
            }
            $ext = pathinfo($reg['receipt_file'], PATHINFO_EXTENSION);
            return ['mime' => ['png' => 'image/png', 'jpg' => 'image/jpeg', 'pdf' => 'application/pdf'][$ext], 'data' => base64_encode($bytes)];
        },
    ]);
    register_rest_route(CD_NS, '/admin/reg-assets', [
        'methods' => 'POST', 'permission_callback' => $admin, 'callback' => 'cd_rest_reg_asset',
    ]);
});

/** تنظیم صفحه + چیزهایی که ویرایشگر لازم دارد (نوع‌ها، وعده‌ها، درگاه‌ها). */
function cd_reg_editor_data(array $event) {
    $eid = (int) $event['id'];
    $page = cd_reg_get_page_by_event($eid);
    $cfg = $page ? $page['config'] : cd_reg_default_config();
    $config = cd_event_config($eid);
    $counts = $page ? cd_reg_counts($eid) : ['total' => 0, 'types' => [], 'addons' => [], 'options' => []];
    return [
        'page' => $page ? $cfg : null,
        'url' => $page && $cfg['path'] !== '' ? cd_reg_page_url($cfg) : null,
        'types' => array_map(function ($t) {
            return ['code' => $t['code'], 'name' => $t['name']];
        }, $config['registration_types']),
        'meals' => array_map(function ($m) {
            return ['code' => $m['code'], 'name' => $m['name'], 'day' => $m['day']];
        }, $config['meals']),
        'gateways' => cd_payment_gateways_out(),
        'counts' => $counts,
        'home' => home_url('/'),
    ];
}

function cd_rest_reg_page_get(WP_REST_Request $r) {
    $event = cd_event_from_request($r);
    return is_wp_error($event) ? $event : cd_reg_editor_data($event);
}

function cd_rest_reg_page_save(WP_REST_Request $r) {
    $event = cd_event_from_request($r);
    if (is_wp_error($event)) {
        return $event;
    }
    $cfg = cd_sanitize_reg_config($r->get_param('config'));
    if ($cfg['path'] === '') {
        return cd_error('cd_reg_path', 'آدرس صفحه را بنویسید: فقط حروف کوچک انگلیسی، رقم و خط تیره، دست‌کم ۲ حرف.');
    }
    $saved = cd_reg_save_page((int) $event['id'], $cfg);
    if (is_wp_error($saved)) {
        return $saved;
    }
    return cd_reg_editor_data($event);
}

function cd_reg_out(array $reg) {
    return [
        'id' => (int) $reg['id'],
        'code' => $reg['code'],
        'status' => $reg['status'],
        'status_label' => cd_reg_statuses()[$reg['status']] ?? $reg['status'],
        'type' => $reg['type_code'],
        'first_name' => $reg['first_name'],
        'last_name' => $reg['last_name'],
        'mobile' => $reg['mobile'],
        'email' => $reg['email'],
        'organization' => $reg['organization'],
        'answers' => (object) ((array) json_decode((string) $reg['answers'], true)),
        'addons' => (array) json_decode((string) $reg['addons'], true),
        'amount_online' => (int) $reg['amount_online'],
        'amount_onsite' => (int) $reg['amount_onsite'],
        'pay_method' => $reg['pay_method'],
        'pay_ref' => $reg['pay_ref'],
        'pay_tracking' => $reg['pay_tracking'],
        'has_receipt' => $reg['receipt_file'] !== '',
        'reject_reason' => $reg['reject_reason'],
        'attendee_id' => $reg['attendee_id'],
        'hold_until' => $reg['hold_until'] ? cd_iso($reg['hold_until']) : null,
        'created_at' => cd_iso($reg['created_at']),
        'updated_at' => cd_iso($reg['updated_at']),
    ];
}

function cd_rest_regs_list(WP_REST_Request $r) {
    global $wpdb;
    $event = cd_event_from_request($r);
    if (is_wp_error($event)) {
        return $event;
    }
    cd_reg_expire_holds((int) $event['id']);
    $rows = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE event_id = %d ORDER BY id DESC', $event['id']), ARRAY_A);
    $by_status = array_fill_keys(array_keys(cd_reg_statuses()), 0);
    foreach ($rows as $x) {
        $by_status[$x['status']] = ($by_status[$x['status']] ?? 0) + 1;
    }
    return ['registrations' => array_map('cd_reg_out', $rows), 'by_status' => $by_status, 'statuses' => cd_reg_statuses()];
}

/** کار مدیر روی یک ثبت‌نام: approve (تأیید مدیر)، mark_paid (پرداخت شد)، reject (با دلیل). */
function cd_reg_admin_action($id, $action, $reason = '') {
    $reg = cd_reg_get((int) $id);
    if (!$reg) {
        return cd_error('cd_reg_not_found', 'ثبت‌نام پیدا نشد.', 404);
    }
    $page = cd_reg_get_page_by_event((int) $reg['event_id']);
    if (!$page) {
        return cd_error('cd_reg_not_found', 'صفحه‌ی ثبت‌نام این رویداد پیدا نشد.', 404);
    }
    $s = $reg['status'];
    if ($action === 'approve') {
        if ($s !== 'pending_approval') {
            return cd_error('cd_reg_state', 'فقط ثبت‌نامِ «در انتظار تأیید مدیر» تأیید می‌شود.', 409);
        }
        return cd_reg_set_status($page, $reg, 'confirmed');
    }
    if ($action === 'mark_paid') {
        if (!in_array($s, ['pending_payment', 'pending_review', 'expired'], true)) {
            return cd_error('cd_reg_state', 'این ثبت‌نام منتظر پرداخت نیست.', 409);
        }
        return cd_reg_after_payment($page, $reg);
    }
    if ($action === 'reject') {
        if (in_array($s, ['rejected'], true)) {
            return $reg;
        }
        if ($s === 'confirmed' && !empty($reg['attendee_id'])) {
            return cd_error('cd_reg_state', 'این فرد در لیست شرکت‌کننده‌هاست؛ رد کردن او را از لیست برنمی‌دارد. اول از لیست حذفش کنید.', 409);
        }
        return cd_reg_set_status($page, $reg, 'rejected', ['reject_reason' => cd_str($reason, 500), 'hold_until' => null]);
    }
    return cd_error('cd_reg_action', 'کار نامعتبر.', 400);
}

function cd_rest_reg_action(WP_REST_Request $r) {
    $res = cd_reg_admin_action((int) $r['id'], (string) $r->get_param('action'), (string) $r->get_param('reason'));
    return is_wp_error($res) ? $res : ['registration' => cd_reg_out($res)];
}

/** تصویر لوگو، سربرگ یا کارت‌به‌کارت؛ عمومی، در uploads/roydadyar-reg. */
function cd_rest_reg_asset(WP_REST_Request $r) {
    $bytes = base64_decode((string) $r->get_param('data'), true);
    if ($bytes === false || strlen($bytes) < 100) {
        return cd_error('cd_asset', 'تصویر خراب رسید.');
    }
    if (strlen($bytes) > 3 * 1024 * 1024) {
        return cd_error('cd_asset', 'تصویر بزرگ‌تر از ۳ مگابایت است.');
    }
    $ext = strncmp($bytes, "\x89PNG", 4) === 0 ? 'png' : (strncmp($bytes, "\xFF\xD8\xFF", 3) === 0 ? 'jpg' : (substr($bytes, 8, 4) === 'WEBP' ? 'webp' : ''));
    if ($ext === '') {
        return cd_error('cd_asset', 'فقط PNG، JPG یا WebP.');
    }
    $up = wp_upload_dir();
    $dir = rtrim($up['basedir'], '/') . '/roydadyar-reg';
    wp_mkdir_p($dir);
    $name = bin2hex(random_bytes(12)) . '.' . $ext;
    if (@file_put_contents("$dir/$name", $bytes) === false) {
        return cd_error('cd_asset', 'ذخیره‌ی تصویر روی سرور ناموفق بود.', 500);
    }
    return ['url' => rtrim($up['baseurl'], '/') . '/roydadyar-reg/' . $name];
}

// ---------------------------------------------------------------- خروجی اکسل

/** ردیف‌های خروجی: ستون‌ها و مقدارها. */
function cd_reg_export_rows(array $event) {
    global $wpdb;
    $page = cd_reg_get_page_by_event((int) $event['id']);
    $cfg = $page ? $page['config'] : cd_reg_default_config();
    $types = [];
    foreach (cd_event_config((int) $event['id'])['registration_types'] as $t) {
        $types[$t['code']] = $t['name'];
    }
    $head = ['ردیف', 'کد ثبت‌نام', 'وضعیت ثبت‌نام', 'نوع حضور', 'نام', 'نام خانوادگی', 'موبایل', 'ایمیل', 'سازمان'];
    foreach ($cfg['custom_fields'] as $f) {
        $head[] = $f['label'];
    }
    foreach ($cfg['addons'] as $a) {
        $head[] = $a['title'];
    }
    array_push($head, 'مبلغ آنلاین (تومان)', 'تسویه در روز اجرا (تومان)', 'روش پرداخت', 'پیگیری بانک', 'پیگیری واریز', 'دلیل رد', 'تاریخ ثبت');
    $rows = [];
    $regs = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE event_id = %d ORDER BY id', $event['id']), ARRAY_A);
    $methods = ['gateway' => 'درگاه', 'link' => 'لینک', 'card' => 'کارت‌به‌کارت', '' => ''];
    foreach ($regs as $i => $x) {
        $answers = (array) json_decode((string) $x['answers'], true);
        $addons = (array) json_decode((string) $x['addons'], true);
        $row = [$i + 1, $x['code'], cd_reg_statuses()[$x['status']] ?? $x['status'], $types[$x['type_code']] ?? $x['type_code'],
            $x['first_name'], $x['last_name'], $x['mobile'], $x['email'], $x['organization']];
        foreach ($cfg['custom_fields'] as $f) {
            $v = $answers[$f['id']] ?? '';
            $labels = [];
            foreach ((array) $v as $one) {
                $match = array_values(array_filter($f['options'], function ($o) use ($one) {
                    return $o['id'] === $one;
                }));
                $labels[] = $match ? $match[0]['label'] : (string) $one;
            }
            $row[] = implode('، ', array_filter($labels, 'strlen'));
        }
        foreach ($cfg['addons'] as $a) {
            $row[] = in_array($a['id'], $addons, true) ? '✓' : '';
        }
        $tehran = new DateTime($x['created_at'] . ' UTC');
        $tehran->setTimezone(new DateTimeZone('Asia/Tehran'));
        array_push($row, (int) $x['amount_online'], (int) $x['amount_onsite'], $methods[$x['pay_method']] ?? $x['pay_method'],
            $x['pay_ref'], $x['pay_tracking'], $x['reject_reason'], $tehran->format('Y-m-d H:i'));
        $rows[] = $row;
    }
    // برگه‌ی خلاصه: هر وضعیت، هر نوع، هر گزینه.
    $summary = [['مورد', 'تعداد']];
    $summary[] = ['کل ثبت‌نام‌ها', count($regs)];
    foreach (cd_reg_statuses() as $k => $label) {
        $summary[] = [$label, count(array_filter($regs, function ($x) use ($k) {
            return $x['status'] === $k;
        }))];
    }
    $active = array_filter($regs, function ($x) {
        return !in_array($x['status'], ['rejected', 'expired'], true);
    });
    foreach ($types as $code => $name) {
        $summary[] = ['نوع: ' . $name, count(array_filter($active, function ($x) use ($code) {
            return $x['type_code'] === $code;
        }))];
    }
    foreach ($cfg['addons'] as $a) {
        $summary[] = ['گزینه: ' . $a['title'], count(array_filter($active, function ($x) use ($a) {
            return in_array($a['id'], (array) json_decode((string) $x['addons'], true), true);
        }))];
    }
    return [$head, $rows, $summary];
}

/** فایل xlsx (دو برگه، راست‌به‌چپ، ردیف عنوان ثابت). بدون ZipArchive: CSV. */
function cd_reg_export(array $event) {
    [$head, $rows, $summary] = cd_reg_export_rows($event);
    $base = sanitize_file_name($event['code'] . '-registrations-' . gmdate('Ymd-His'));
    if (!class_exists('ZipArchive')) {
        $out = "\xEF\xBB\xBF";
        foreach (array_merge([$head], $rows) as $r) {
            $out .= implode(',', array_map(function ($v) {
                return '"' . str_replace('"', '""', (string) $v) . '"';
            }, $r)) . "\r\n";
        }
        return [$base . '.csv', $out, 'text/csv'];
    }
    $tmp = wp_tempnam('cd-xlsx');
    $zip = new ZipArchive();
    $zip->open($tmp, ZipArchive::OVERWRITE);
    $zip->addFromString('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>');
    $zip->addFromString('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    $zip->addFromString('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="ثبت‌نام‌ها" sheetId="1" r:id="rId1"/><sheet name="خلاصه" sheetId="2" r:id="rId2"/></sheets></workbook>');
    $zip->addFromString('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
    $zip->addFromString('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Tahoma"/></font><font><b/><sz val="11"/><name val="Tahoma"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE9ECF0"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf/><xf fontId="1" fillId="2" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>');
    $zip->addFromString('xl/worksheets/sheet1.xml', cd_xlsx_sheet(array_merge([$head], $rows), true));
    $zip->addFromString('xl/worksheets/sheet2.xml', cd_xlsx_sheet($summary, false));
    $zip->close();
    $bytes = file_get_contents($tmp);
    @unlink($tmp);
    return [$base . '.xlsx', $bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'];
}

function cd_xlsx_col($i) {
    $s = '';
    for ($i++; $i > 0; $i = intdiv($i - 1, 26)) {
        $s = chr(65 + ($i - 1) % 26) . $s;
    }
    return $s;
}

function cd_xlsx_sheet(array $rows, $filter) {
    $last = cd_xlsx_col(max(0, count($rows[0] ?? []) - 1)) . max(1, count($rows));
    $x = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        . '<sheetViews><sheetView rightToLeft="1" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>';
    foreach ($rows as $ri => $r) {
        $x .= '<row r="' . ($ri + 1) . '">';
        foreach (array_values($r) as $ci => $v) {
            $ref = cd_xlsx_col($ci) . ($ri + 1);
            $style = $ri === 0 ? ' s="1"' : '';
            if (is_int($v)) {
                $x .= '<c r="' . $ref . '"' . $style . '><v>' . $v . '</v></c>';
            } else {
                $x .= '<c r="' . $ref . '" t="inlineStr"' . $style . '><is><t xml:space="preserve">' . htmlspecialchars((string) $v, ENT_XML1 | ENT_QUOTES, 'UTF-8') . '</t></is></c>';
            }
        }
        $x .= '</row>';
    }
    $x .= '</sheetData>';
    if ($filter && count($rows) > 1) {
        $x .= '<autoFilter ref="A1:' . $last . '"/>';
    }
    return $x . '</worksheet>';
}

// ---------------------------------------------------------------- پیشخوان وردپرس

add_action('admin_menu', function () {
    add_submenu_page('cd-dashboard', 'صفحه‌ی ثبت‌نام', 'صفحه‌ی ثبت‌نام', 'manage_options', 'cd-reg-page', 'cd_render_reg_page_admin');
    add_submenu_page('cd-dashboard', 'ثبت‌نام‌ها', 'ثبت‌نام‌ها', 'manage_options', 'cd-registrations', 'cd_render_registrations_admin');
}, 20);

function cd_admin_event_picker($slug) {
    $events = cd_all_events();
    $current = isset($_GET['event']) ? cd_get_event((int) $_GET['event']) : ($events[0] ?? null);
    echo '<form method="get" style="margin:12px 0"><input type="hidden" name="page" value="' . esc_attr($slug) . '"><label>رویداد: <select name="event" onchange="this.form.submit()">';
    foreach ($events as $e) {
        printf('<option value="%d"%s>%s</option>', (int) $e['id'], $current && (int) $current['id'] === (int) $e['id'] ? ' selected' : '', esc_html($e['name'] . ' (' . $e['code'] . ')'));
    }
    echo '</select></label></form>';
    return $current;
}

function cd_render_reg_page_admin() {
    if (!current_user_can('manage_options')) {
        return;
    }
    echo '<div class="wrap" dir="rtl"><h1>صفحه‌ی ثبت‌نام</h1>';
    $event = cd_admin_event_picker('cd-reg-page');
    if (!$event) {
        echo '<p>هنوز رویدادی نیست. رویداد را در اپ مدیریت بسازید.</p></div>';
        return;
    }
    $notice = '';
    if (isset($_POST['cd_reg_config']) && check_admin_referer('cd_reg_page')) {
        $cfg = cd_sanitize_reg_config(json_decode(wp_unslash($_POST['cd_reg_config']), true));
        $saved = $cfg['path'] === '' ? new WP_Error('x', 'آدرس صفحه را بنویسید.') : cd_reg_save_page((int) $event['id'], $cfg);
        $notice = is_wp_error($saved)
            ? '<div class="notice notice-error"><p>' . esc_html($saved->get_error_message()) . '</p></div>'
            : '<div class="notice notice-success"><p>ذخیره شد.</p></div>';
    }
    echo $notice; // phpcs:ignore
    $data = cd_reg_editor_data($event);
    if ($data['url']) {
        printf('<p>آدرس صفحه: <a href="%1$s" target="_blank" rel="noopener" dir="ltr">%1$s</a></p>', esc_url($data['url']));
    }
    echo '<form method="post" id="cd-reg-form">';
    wp_nonce_field('cd_reg_page');
    echo '<input type="hidden" name="cd_reg_config" id="cd-reg-config">';
    echo '<div id="cd-reg-editor"></div>';
    submit_button('ذخیره‌ی صفحه‌ی ثبت‌نام');
    echo '</form>';
    echo '<script>window.CD_REG_EDITOR=' . wp_json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) . ';</script>';
    echo '<script>' . file_get_contents(CD_DIR . 'assets/reg-admin.js') . '</script></div>'; // phpcs:ignore
}

add_action('admin_post_cd_reg_action', function () {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_reg_action');
    $res = cd_reg_admin_action((int) ($_POST['id'] ?? 0), sanitize_key(wp_unslash($_POST['act'] ?? '')), sanitize_text_field(wp_unslash($_POST['reason'] ?? '')));
    $msg = is_wp_error($res) ? $res->get_error_message() : 'انجام شد.';
    wp_safe_redirect(add_query_arg(['page' => 'cd-registrations', 'event' => (int) ($_POST['event'] ?? 0), 'msg' => rawurlencode($msg)], admin_url('admin.php')));
    exit;
});

add_action('admin_post_cd_reg_export', function () {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_reg_export');
    $event = cd_get_event((int) ($_GET['event'] ?? 0));
    if (!$event) {
        wp_die('رویداد پیدا نشد.', 404);
    }
    [$name, $bytes, $mime] = cd_reg_export($event);
    nocache_headers();
    header('Content-Type: ' . $mime);
    header('Content-Disposition: attachment; filename="' . $name . '"');
    echo $bytes; // phpcs:ignore
    exit;
});

add_action('admin_post_cd_reg_receipt', function () {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_reg_receipt');
    $reg = cd_reg_get((int) ($_GET['id'] ?? 0));
    if (!$reg || !preg_match('/^[a-f0-9]{32}\.(png|jpg|pdf)$/', $reg['receipt_file'], $m)) {
        wp_die('رسیدی نیست.', 404);
    }
    nocache_headers();
    header('Content-Type: ' . ['png' => 'image/png', 'jpg' => 'image/jpeg', 'pdf' => 'application/pdf'][$m[1]]);
    readfile(cd_reg_receipts_dir() . '/' . $reg['receipt_file']);
    exit;
});

function cd_render_registrations_admin() {
    global $wpdb;
    if (!current_user_can('manage_options')) {
        return;
    }
    echo '<div class="wrap" dir="rtl"><h1>ثبت‌نام‌ها</h1>';
    $event = cd_admin_event_picker('cd-registrations');
    if (!$event) {
        echo '</div>';
        return;
    }
    if (isset($_GET['msg'])) {
        printf('<div class="notice notice-info"><p>%s</p></div>', esc_html(rawurldecode(sanitize_text_field(wp_unslash($_GET['msg'])))));
    }
    cd_reg_expire_holds((int) $event['id']);
    $filter = isset($_GET['status']) ? sanitize_key(wp_unslash($_GET['status'])) : '';
    $statuses = cd_reg_statuses();
    $sql = 'SELECT * FROM ' . cd_table('registrations') . ' WHERE event_id = %d';
    $args = [(int) $event['id']];
    if (isset($statuses[$filter])) {
        $sql .= ' AND status = %s';
        $args[] = $filter;
    }
    $rows = $wpdb->get_results($wpdb->prepare($sql . ' ORDER BY id DESC LIMIT 500', $args), ARRAY_A);
    $base = admin_url('admin.php?page=cd-registrations&event=' . (int) $event['id']);
    echo '<p>';
    printf('<a href="%s">%s</a>', esc_url($base), $filter === '' ? '<b>همه</b>' : 'همه');
    foreach ($statuses as $k => $label) {
        printf(' | <a href="%s">%s</a>', esc_url($base . '&status=' . $k), $filter === $k ? '<b>' . esc_html($label) . '</b>' : esc_html($label));
    }
    printf(' | <a class="button" href="%s">دریافت فایل اکسل</a></p>', esc_url(wp_nonce_url(admin_url('admin-post.php?action=cd_reg_export&event=' . (int) $event['id']), 'cd_reg_export')));
    echo '<table class="widefat striped"><thead><tr><th>کد</th><th>نام</th><th>موبایل</th><th>نوع</th><th>مبلغ</th><th>پرداخت</th><th>وضعیت</th><th>کار</th></tr></thead><tbody>';
    if (!$rows) {
        echo '<tr><td colspan="8">ثبت‌نامی نیست.</td></tr>';
    }
    foreach ($rows as $x) {
        $pay = [];
        if ($x['pay_ref']) {
            $pay[] = 'بانک: ' . esc_html($x['pay_ref']);
        }
        if ($x['pay_tracking']) {
            $pay[] = 'پیگیری: ' . esc_html($x['pay_tracking']);
        }
        if ($x['receipt_file']) {
            $pay[] = '<a target="_blank" href="' . esc_url(wp_nonce_url(admin_url('admin-post.php?action=cd_reg_receipt&id=' . (int) $x['id']), 'cd_reg_receipt')) . '">رسید</a>';
        }
        echo '<tr><td dir="ltr">' . esc_html($x['code']) . '</td><td>' . esc_html($x['first_name'] . ' ' . $x['last_name']) . '</td><td dir="ltr">' . esc_html($x['mobile'])
            . '</td><td>' . esc_html($x['type_code']) . '</td><td>' . esc_html(number_format((int) $x['amount_online'])) . ($x['amount_onsite'] ? ' + ' . esc_html(number_format((int) $x['amount_onsite'])) . ' روز اجرا' : '')
            . '</td><td>' . implode('<br>', $pay) . '</td><td>' . esc_html($statuses[$x['status']] ?? $x['status']) . ($x['reject_reason'] ? '<br><small>' . esc_html($x['reject_reason']) . '</small>' : '') . '</td><td>';
        $form = function ($act, $label, $reason = false) use ($x, $event) {
            echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '" style="display:inline-block;margin:2px">';
            wp_nonce_field('cd_reg_action');
            echo '<input type="hidden" name="action" value="cd_reg_action"><input type="hidden" name="act" value="' . esc_attr($act) . '"><input type="hidden" name="id" value="' . (int) $x['id'] . '"><input type="hidden" name="event" value="' . (int) $event['id'] . '">';
            if ($reason) {
                echo '<input name="reason" placeholder="دلیل (به فرد نشان داده می‌شود)" style="width:180px"> ';
            }
            echo '<button class="button">' . esc_html($label) . '</button></form>';
        };
        if ($x['status'] === 'pending_approval') {
            $form('approve', 'تأیید');
        }
        if (in_array($x['status'], ['pending_payment', 'pending_review', 'expired'], true)) {
            $form('mark_paid', 'پرداخت شد');
        }
        if (!in_array($x['status'], ['rejected', 'confirmed'], true)) {
            $form('reject', 'رد', true);
        }
        echo '</td></tr>';
    }
    echo '</tbody></table></div>';
}
