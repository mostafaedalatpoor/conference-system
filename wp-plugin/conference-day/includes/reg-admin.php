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
    // تنظیم خالی درگاه شیء JSON بماند، نه آرایه.
    $cfg['payment']['gateway_settings'] = (object) $cfg['payment']['gateway_settings'];
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
        'paid_at' => !empty($reg['paid_at']) ? cd_iso($reg['paid_at']) : null,
        'archived' => !empty($reg['archived_at']),
        'archived_at' => !empty($reg['archived_at']) ? cd_iso($reg['archived_at']) : null,
        'can_delete' => !cd_reg_has_history($reg),
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
    // بایگانی‌شده‌ها در شمارش وضعیت‌ها نیستند و فقط با archived=1 می‌آیند.
    $with_archived = !empty($r->get_param('archived'));
    $by_status = array_fill_keys(array_keys(cd_reg_statuses()), 0);
    $archived = 0;
    $out = [];
    foreach ($rows as $x) {
        if (!empty($x['archived_at'])) {
            $archived++;
            if (!$with_archived) {
                continue;
            }
        } else {
            $by_status[$x['status']] = ($by_status[$x['status']] ?? 0) + 1;
        }
        $out[] = cd_reg_out($x);
    }
    return ['registrations' => $out, 'by_status' => $by_status, 'archived' => $archived, 'statuses' => cd_reg_statuses()];
}

/** کار مدیر روی یک ثبت‌نام: approve (تأیید مدیر)، mark_paid (پرداخت شد)، reject (با دلیل). */
function cd_reg_admin_action($id, $action, $reason = '', $confirm_code = '') {
    $reg = cd_reg_get((int) $id);
    if (!$reg) {
        return cd_error('cd_reg_not_found', 'ثبت‌نام پیدا نشد.', 404);
    }
    if (in_array($action, ['archive', 'unarchive', 'delete'], true)) {
        $res = cd_reg_archive_action($reg, $action, (string) $confirm_code);
        if (is_wp_error($res)) {
            return $res;
        }
        $row = $res['registration'] ?: ['deleted' => true, 'id' => (int) $id];
        return $row + ['_result' => $res['result']];
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
    $res = cd_reg_admin_action((int) $r['id'], (string) $r->get_param('action'), (string) $r->get_param('reason'), (string) $r->get_param('confirm_code'));
    if (is_wp_error($res)) {
        return $res;
    }
    $result = $res['_result'] ?? 'ok';
    if (!empty($res['deleted'])) {
        return ['registration' => null, 'result' => 'deleted'];
    }
    unset($res['_result']);
    return [
        'registration' => cd_reg_out($res),
        'result' => $result,
        'message' => $result === 'archived_instead' ? 'این ثبت‌نام پرداخت یا ورود به لیست دارد؛ به‌جای حذف بایگانی شد.' : null,
    ];
}

/** تصویر لوگو، سربرگ یا کارت‌به‌کارت؛ عمومی، در uploads/roydadyar-reg. */
function cd_rest_reg_asset(WP_REST_Request $r) {
    $bytes = base64_decode((string) $r->get_param('data'), true);
    if ($bytes === false || strlen($bytes) < 100) {
        return cd_error('cd_asset', 'تصویر خراب رسید.');
    }
    // طرح کارت چاپی (۳۰۰ DPI) بزرگ‌تر است: تا ۱۲ مگابایت.
    $card = $r->get_param('kind') === 'card';
    $limit = $card ? 12 : 3;
    if (strlen($bytes) > $limit * 1024 * 1024) {
        return cd_error('cd_asset', 'تصویر بزرگ‌تر از ' . cd_fa_digits((string) $limit) . ' مگابایت است.');
    }
    $ext = strncmp($bytes, "\x89PNG", 4) === 0 ? 'png' : (strncmp($bytes, "\xFF\xD8\xFF", 3) === 0 ? 'jpg' : (substr($bytes, 8, 4) === 'WEBP' ? 'webp' : ''));
    if ($ext === '') {
        return cd_error('cd_asset', 'فقط PNG، JPG یا WebP.');
    }
    $up = wp_upload_dir();
    $folder = $card ? 'roydadyar-card' : 'roydadyar-reg';
    $dir = rtrim($up['basedir'], '/') . '/' . $folder;
    wp_mkdir_p($dir);
    $name = bin2hex(random_bytes(12)) . '.' . $ext;
    if (@file_put_contents("$dir/$name", $bytes) === false) {
        return cd_error('cd_asset', 'ذخیره‌ی تصویر روی سرور ناموفق بود.', 500);
    }
    return ['url' => rtrim($up['baseurl'], '/') . '/' . $folder . '/' . $name];
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

// منوی وردپرس: «صفحه‌ی ثبت‌نام» و «ثبت‌نام‌ها» در CD_ADMIN_PAGES (admin-ui.php) هستند، با همین تابع‌ها.

/** رویداد انتخاب‌شده در صفحه‌های ثبت‌نام، و سربرگ با انتخاب رویداد. */
function cd_reg_admin_open($slug, $title, $sub_fn) {
    $events = cd_all_events();
    $event = cd_ui_current_event($events);
    $sub = $event ? $sub_fn($event) : 'رویدادی نیست';
    cd_ui_open($slug, $title, $sub, $event ? cd_ui_event_picker($slug, $events, $event) : '');
    if (!$event) {
        echo '<div class="cd-card pop"><p class="cd-mu">هنوز رویدادی نیست. رویداد را در اپ مدیریت بسازید.</p></div>';
        cd_ui_close();
        return null;
    }
    return $event;
}

/** استایل‌های کوچک ویرایشگر ثبت‌نام، روی پایه‌ی cd_ui_styles. */
function cd_reg_admin_css() {
    return '<style>.cd-ui .ry-fl{display:flex;flex-direction:column;gap:6px}.cd-ui .ry-fl>span:first-child{font-size:12px;font-weight:700;color:var(--mu)}'
        . '.cd-ui .ry-area{width:100%;border:0;border-radius:14px;background:var(--sf2);padding:10px 14px;font:inherit;font-size:14px;color:var(--ink)}'
        . '.cd-ui .ry-seg{display:flex;padding:4px;background:var(--sf2);border-radius:14px;gap:2px}.cd-ui .ry-seg button{flex:1;height:40px;border:0;border-radius:10px;background:transparent;color:var(--mu);font:inherit;font-size:13px;font-weight:700;cursor:pointer}'
        . '.cd-ui .ry-seg button.on{background:var(--b);color:#fff;font-weight:800}'
        . '.cd-ui .ry-tg{display:flex;align-items:center;gap:12px;font-size:14px;cursor:pointer}.cd-ui .ry-tg input{width:20px;height:20px;accent-color:var(--b)}'
        . '.cd-ui .ry-st{display:flex;align-items:center;gap:10px;min-height:48px;padding:0 10px;border-radius:14px;font:inherit;font-size:13px;border:0;background:transparent;color:var(--ink);text-align:right;cursor:pointer}'
        . '.cd-ui .ry-st .n{width:26px;height:26px;border-radius:13px;display:grid;place-items:center;font-size:12px;font-weight:800;background:var(--sf2);color:var(--mu);flex-shrink:0}'
        . '.cd-ui .ry-st.on{background:color-mix(in srgb,var(--b) 12%,var(--sf));box-shadow:inset 0 0 0 2px var(--b)}.cd-ui .ry-st.on .n{background:var(--b);color:#fff}'
        . '.cd-ui .ry-sub{border-radius:16px;box-shadow:inset 0 0 0 1px var(--ln);padding:14px;display:flex;flex-direction:column;gap:10px}'
        . '.cd-ui .ry-sw{width:36px;height:36px;border-radius:18px;border:0;cursor:pointer}.cd-ui .ry-sw.on{box-shadow:0 0 0 3px var(--sf),0 0 0 5px var(--ink)}'
        . '.cd-ui .ry-tbl{display:flex;flex-direction:column}.cd-ui .ry-tbl>div{display:grid;grid-template-columns:1fr 1.6fr .9fr .8fr 1.2fr;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid var(--ln)}'
        . '.cd-ui .ry-tbl>div.h{font-size:12px;font-weight:700;color:var(--mu)}'
        . '.cd-ui .ry-tr{display:grid;grid-template-columns:1.5fr 1fr 1fr 1fr 1.2fr;gap:12px;align-items:center;padding:0 18px;min-height:56px;border-bottom:1px solid var(--ln);font-size:14px;text-decoration:none;color:var(--ink)}'
        . '.cd-ui .ry-tr.hd{min-height:42px;background:var(--sf2);font-size:12px;font-weight:700;color:var(--mu)}.cd-ui .ry-tr.on{background:color-mix(in srgb,var(--b) 10%,var(--sf));box-shadow:inset -4px 0 0 var(--b)}'
        . '.cd-ui .ry-kv{display:flex;justify-content:space-between;gap:10px;font-size:13px}.cd-ui .ry-kv span:first-child{color:var(--mu)}'
        . '.cd-ui .ry-chips{display:flex;gap:8px;flex-wrap:wrap}.cd-ui .ry-chips a{height:34px;padding:0 14px;border-radius:17px;background:var(--sf);box-shadow:inset 0 0 0 1px var(--ln);display:inline-flex;align-items:center;font-size:12px;font-weight:700;color:var(--ink);text-decoration:none}'
        . '.cd-ui .ry-chips a.on{background:#fff;color:var(--b);font-weight:800;box-shadow:0 2px 8px rgba(0,0,0,.08)}'
        . '.cd-ui .ry-mono{direction:ltr;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}'
        . '@media (max-width:960px){.cd-ui .ry-tr{grid-template-columns:1.4fr 1fr 1fr}.cd-ui .ry-tr>:nth-child(4),.cd-ui .ry-tr>:nth-child(2){display:none}}</style>';
}

function cd_render_reg_page_admin() {
    if (!current_user_can('manage_options')) {
        return;
    }
    if (isset($_GET['view']) && $_GET['view'] === 'connect') {
        cd_render_reg_connect_admin();
        return;
    }
    $notice = '';
    $step = isset($_GET['step']) ? max(1, min(7, (int) $_GET['step'])) : 1;
    $events = cd_all_events();
    $event = cd_ui_current_event($events);
    if ($event && isset($_POST['cd_reg_config']) && check_admin_referer('cd_reg_page')) {
        $cfg = cd_sanitize_reg_config(json_decode(wp_unslash($_POST['cd_reg_config']), true));
        $saved = $cfg['path'] === '' ? new WP_Error('x', 'آدرس صفحه را بنویسید (گام ۱).') : cd_reg_save_page((int) $event['id'], $cfg);
        if (is_wp_error($saved)) {
            $notice = '<div class="cd-callout stop" style="margin-bottom:14px">' . esc_html($saved->get_error_message()) . '</div>';
        } else {
            $notice = '<div class="cd-callout go" style="margin-bottom:14px">ذخیره شد.</div>';
            $step = max(1, min(7, (int) ($_POST['next'] ?? $step)));
        }
    }
    $page = $event ? cd_reg_get_page_by_event((int) $event['id']) : null;
    $status = $page ? ['draft' => 'پیش‌نویس', 'open' => 'باز', 'closed' => 'بسته'][$page['config']['status']] : 'ساخته نشده';
    $event = cd_reg_admin_open('cd-reg-page', 'صفحه‌ی ثبت‌نام', function ($e) use ($step, $status) {
        return $e['name'] . ' · گام ' . cd_fa_digits((string) $step) . ' از ۷ · وضعیت: ' . $status;
    });
    if (!$event) {
        return;
    }
    echo cd_reg_admin_css(); // phpcs:ignore WordPress.Security.EscapeOutput
    echo $notice; // phpcs:ignore WordPress.Security.EscapeOutput
    $data = cd_reg_editor_data($event);
    $data['step'] = $step;
    $data['defaults'] = cd_reg_default_config();
    $data['triggers'] = CD_REG_TRIGGERS;
    $data['variables'] = ['{name}', '{code}', '{event}', '{amount}', '{status}', '{link}', '{personal_link}', '{reason}'];
    $data['connect_url'] = admin_url('admin.php?page=cd-reg-page&view=connect&event=' . (int) $event['id']);
    $data['sms_ready'] = cd_conn_get()['sms']['url'] !== '';
    $data['home'] = trailingslashit(home_url('/'));
    echo '<form method="post" id="cd-reg-form" action="' . esc_url(admin_url('admin.php?page=cd-reg-page&event=' . (int) $event['id'])) . '">';
    wp_nonce_field('cd_reg_page');
    echo '<input type="hidden" name="cd_reg_config" id="cd-reg-config"><input type="hidden" name="next" id="cd-reg-next" value="' . (int) $step . '">';
    echo '<div id="cd-reg-editor"><div class="cd-card pop"><p class="cd-mu">در حال بارگذاری…</p></div></div></form>';
    echo '<script>window.CD_REG_EDITOR=' . wp_json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP) . ';</script>';
    echo '<script>' . file_get_contents(CD_DIR . 'assets/reg-admin.js') . '</script>'; // phpcs:ignore
    cd_ui_close();
}

/** «اتصال درگاه و سرویس پیامک» (بوم ۱۱-RegConnect). */
function cd_render_reg_connect_admin() {
    global $wpdb;
    $events = cd_all_events();
    $event = cd_ui_current_event($events);
    $notice = '';
    if (isset($_POST['cd_conn']) && check_admin_referer('cd_conn')) {
        $in = wp_unslash($_POST['cd_conn']);
        cd_conn_save(is_array($in) ? $in : []);
        $notice = '<div class="cd-callout go" style="margin-bottom:14px">ذخیره شد.</div>';
        if (!empty($_POST['test_sms'])) {
            $m = cd_msg_send(0, null, 'sms', cd_normalize_mobile(sanitize_text_field(wp_unslash($_POST['test_mobile'] ?? ''))), 'پیام آزمایشی رویدادیار. اگر این را می‌خوانید، اتصال پیامک درست است.', 'test');
            $notice = '<div class="cd-callout ' . ($m['ok'] ? 'go' : 'stop') . '" style="margin-bottom:14px">' . esc_html(($m['ok'] ? 'پیام آزمایشی فرستاده شد. ' : 'پیام آزمایشی فرستاده نشد. ') . $m['response']) . '</div>';
        }
    }
    if ($event && isset($_POST['test_pay']) && check_admin_referer('cd_conn')) {
        $req = new WP_REST_Request('POST');
        $req['code'] = $event['code'];
        $res = cd_rest_reg_test_payment($req);
        if (is_wp_error($res)) {
            $notice = '<div class="cd-callout stop" style="margin-bottom:14px">' . esc_html($res->get_error_message()) . '</div>';
        } else {
            wp_redirect($res['url']); // درگاه بیرونی
            exit;
        }
    }
    if (isset($_POST['retry']) && check_admin_referer('cd_conn')) {
        $m = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . cd_table('reg_messages') . ' WHERE id = %d', (int) $_POST['retry']), ARRAY_A);
        if ($m) {
            $r = cd_msg_send((int) $m['event_id'], $m['registration_id'], $m['channel'], $m['recipient'], $m['body'], $m['trigger_key'], (int) $m['id']);
            $notice = '<div class="cd-callout ' . ($r['ok'] ? 'go' : 'stop') . '" style="margin-bottom:14px">' . esc_html($r['ok'] ? 'دوباره فرستاده شد.' : 'باز هم فرستاده نشد: ' . $r['response']) . '</div>';
        }
    }
    $event = cd_reg_admin_open('cd-reg-page', 'اتصال درگاه و سرویس پیامک', function () {
        return 'صفحه‌ی ثبت‌نام · گام ۵ و ۶';
    });
    if (!$event) {
        return;
    }
    echo cd_reg_admin_css(); // phpcs:ignore
    echo $notice; // phpcs:ignore
    $c = cd_conn_get();
    $g = $c['gateway'];
    $s = $c['sms'];
    $page = cd_reg_get_page_by_event((int) $event['id']);
    $gid = $page ? $page['config']['payment']['gateway'] : 'zarinpal';
    $last = get_option('cd_reg_last_test', null);
    $f = function ($name, $value, $ltr = true, $ph = '') {
        return '<div class="cd-field"><input name="cd_conn' . $name . '" value="' . esc_attr($value) . '"' . ($ltr ? ' dir="ltr"' : '') . ' placeholder="' . esc_attr($ph) . '"></div>';
    };
    $t = function ($name, $value, $rows = 3, $ph = '') {
        return '<textarea class="ry-area ry-mono" rows="' . (int) $rows . '" name="cd_conn' . $name . '" placeholder="' . esc_attr($ph) . '">' . esc_textarea($value) . '</textarea>';
    };
    $m = function ($name, $value) {
        return '<div class="cd-field" style="max-width:120px"><select name="cd_conn' . $name . '"><option' . ($value === 'POST' ? ' selected' : '') . '>POST</option><option' . ($value === 'GET' ? ' selected' : '') . '>GET</option></select></div>';
    };
    $lab = function ($label, $html, $hint = '') {
        return '<div class="ry-fl"><span>' . esc_html($label) . '</span>' . $html . ($hint ? '<span class="cd-mu" style="font-size:12px">' . esc_html($hint) . '</span>' : '') . '</div>';
    };
    $gw_ok = $gid !== 'custom' || ($g['start_url'] !== '' && $g['redirect_field'] !== '');
    echo '<form method="post">';
    wp_nonce_field('cd_conn');
    echo '<div class="cd-grid cd-g2" style="align-items:start">';
    // درگاه
    echo '<div class="cd-card pop" style="display:flex;flex-direction:column;gap:12px">';
    echo '<div style="display:flex;align-items:center;gap:10px"><span class="dashicons dashicons-money-alt cd-ic b"></span><h2 style="flex-grow:1;margin:0">درگاه پرداخت</h2><span class="cd-pl ' . ($gw_ok ? 'go">وصل است' : 'wait">کامل نیست') . '</span></div>';
    $names = array_map(function ($x) {
        return $x['name'];
    }, array_column(cd_payment_gateways_out(), null, 'id'));
    echo $lab('درگاه این رویداد', '<div class="cd-field"><b>' . esc_html($names[$gid] ?? $gid) . '</b></div>', 'انتخاب درگاه و کد مرچنت زرین‌پال در «صفحه‌ی ثبت‌نام ← گام ۵ پرداخت» است. ماژول‌های نصب‌شده: ' . implode('، ', $names) . '.'); // phpcs:ignore
    echo $lab('آدرس برگشت (به درگاه بدهید)', '<div class="cd-field ry-mono" style="justify-content:space-between"><span>' . esc_html(rest_url(CD_NS . '/reg/callback')) . '</span></div>'); // phpcs:ignore
    echo '<div class="cd-callout go"><span><b>درگاه دلخواه:</b> آدرس شروع، آدرس تأیید، هدر و بدنه با متغیرهای {amount} {callback} {code} {mobile} {authority} را خودتان بنویسید. هدرها و بدنه رمزشده ذخیره می‌شوند.</span></div>';
    echo $lab('نام درگاه', $f('[gateway][name]', $g['name'], false, 'مثلاً پرداخت سازمان'));
    echo $lab('واحد مبلغ', '<div class="ry-seg"><label style="flex:1"><input type="radio" name="cd_conn[gateway][unit]" value="toman"' . checked($g['unit'], 'toman', false) . '> تومان</label><label style="flex:1"><input type="radio" name="cd_conn[gateway][unit]" value="rial"' . checked($g['unit'], 'rial', false) . '> ریال</label></div>'); // phpcs:ignore
    echo '<b style="font-size:14px">شروع پرداخت</b>';
    echo '<div style="display:flex;gap:8px">' . $m('[gateway][start_method]', $g['start_method']) . '<div style="flex-grow:1">' . $f('[gateway][start_url]', $g['start_url'], true, 'https://api.gateway.example/start') . '</div></div>'; // phpcs:ignore
    echo $lab('هدرها (هر خط Name: value)', $t('[gateway][start_headers]', $g['start_headers'], 2, 'Authorization: Bearer …')); // phpcs:ignore
    echo $lab('بدنه', $t('[gateway][start_body]', $g['start_body'], 3, '{"amount": {amount}, "callback": "{callback}", "order": "{code}"}')); // phpcs:ignore
    echo '<div class="cd-grid cd-g2">' . $lab('فیلد آدرس رفتن به درگاه در پاسخ', $f('[gateway][redirect_field]', $g['redirect_field'], true, 'data.url')) . $lab('فیلد شناسه‌ی تراکنش (اختیاری)', $f('[gateway][authority_field]', $g['authority_field'], true, 'data.id')) . '</div>'; // phpcs:ignore
    echo '<b style="font-size:14px">تأیید پرداخت</b>';
    echo '<div style="display:flex;gap:8px">' . $m('[gateway][verify_method]', $g['verify_method']) . '<div style="flex-grow:1">' . $f('[gateway][verify_url]', $g['verify_url'], true, 'https://api.gateway.example/verify') . '</div></div>'; // phpcs:ignore
    echo $lab('هدرها', $t('[gateway][verify_headers]', $g['verify_headers'], 2)); // phpcs:ignore
    echo $lab('بدنه', $t('[gateway][verify_body]', $g['verify_body'], 2, '{"id": "{authority}", "amount": {amount}}')); // phpcs:ignore
    echo '<div class="cd-grid cd-g2">' . $lab('فیلد نتیجه در پاسخ', $f('[gateway][verify_field]', $g['verify_field'], true, 'status')) . $lab('پارامتر برگشت', $f('[gateway][callback_param]', $g['callback_param'], true, 'Status')) . '</div>'; // phpcs:ignore
    echo $lab('مقدار موفق', $f('[gateway][success_value]', $g['success_value'], true, 'OK')); // phpcs:ignore
    echo '<label class="ry-tg"><span style="flex-grow:1">حالت آزمایشی</span><input type="checkbox" name="cd_conn[gateway][test_mode]" value="1"' . checked($g['test_mode'], true, false) . '></label>'; // phpcs:ignore
    if ($last) {
        echo '<div class="cd-callout ' . ($last['ok'] ? 'go' : 'stop') . '">آخرین آزمون ۱۰۰ تومانی: ' . esc_html($last['ok'] ? 'موفق · ' . $last['ref'] : 'ناموفق') . '</div>';
    }
    echo '<div style="display:flex;gap:8px;flex-wrap:wrap"><button class="cd-btn pri">ذخیره</button><button class="cd-btn" name="test_pay" value="1"><span class="dashicons dashicons-admin-tools"></span>آزمون با ۱۰۰ تومان</button></div>';
    echo '</div>';
    // پیامک و آخرین ارسال‌ها
    echo '<div style="display:flex;flex-direction:column;gap:14px">';
    echo '<div class="cd-card" style="display:flex;flex-direction:column;gap:12px">';
    echo '<div style="display:flex;align-items:center;gap:10px"><span class="dashicons dashicons-email-alt cd-ic b"></span><h2 style="flex-grow:1;margin:0">سرویس پیامک</h2><span class="cd-pl ' . ($s['url'] !== '' ? 'go">وصل است' : 'wait">انتخاب نشده') . '</span></div>';
    $providers = cd_sms_providers();
    if (count($providers) > 1) {
        $opts = '';
        foreach ($providers as $id => $pv) {
            $opts .= '<option value="' . esc_attr($id) . '"' . selected($s['provider'], $id, false) . '>' . esc_html($pv['name'] ?? $id) . '</option>';
        }
        echo $lab('سرویس', '<div class="cd-field"><select name="cd_conn[sms][provider]">' . $opts . '</select></div>', 'ماژول‌های نصب‌شده خودکار اینجا می‌آیند.'); // phpcs:ignore
    }
    echo '<b style="font-size:14px">اتصال دلخواه (HTTP)</b>';
    echo '<div style="display:flex;gap:8px">' . $m('[sms][method]', $s['method']) . '<div style="flex-grow:1">' . $f('[sms][url]', $s['url'], true, 'https://api.sms.example/send') . '</div></div>'; // phpcs:ignore
    echo $lab('هدرها', $t('[sms][headers]', $s['headers'], 2, 'X-API-KEY: …')); // phpcs:ignore
    echo $lab('بدنه', $t('[sms][body]', $s['body'], 3, '{"to": "{mobile}", "from": "{sender}", "text": "{text}"}')); // phpcs:ignore
    echo '<div class="cd-grid cd-g2">' . $lab('شماره‌ی فرستنده', $f('[sms][sender]', $s['sender'])) . $lab('قاعده‌ی موفقیت', '<div class="cd-field"><select name="cd_conn[sms][success]"><option value="http200"' . selected($s['success'], 'http200', false) . '>HTTP ۲۰۰</option><option value="text"' . selected($s['success'], 'text', false) . '>متن در پاسخ</option></select></div>') . '</div>'; // phpcs:ignore
    echo $lab('متن موفقیت (برای «متن در پاسخ»)', $f('[sms][success_text]', $s['success_text'])); // phpcs:ignore
    echo '<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center"><button class="cd-btn pri">ذخیره</button><div class="cd-field" style="width:170px"><input name="test_mobile" dir="ltr" placeholder="0912…"></div><button class="cd-btn" name="test_sms" value="1"><span class="dashicons dashicons-format-chat"></span>پیام آزمایشی</button></div>';
    echo '</div>';
    $msgs = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('reg_messages') . ' WHERE event_id IN (%d, 0) ORDER BY id DESC LIMIT 12', $event['id']), ARRAY_A);
    echo '<div class="cd-card" style="display:flex;flex-direction:column;gap:2px"><h2>آخرین ارسال‌ها</h2>';
    if (!$msgs) {
        echo '<p class="cd-mu">هنوز پیامی فرستاده نشده.</p>';
    }
    $names = [];
    foreach ($msgs as $x) {
        if ($x['registration_id'] && !isset($names[$x['registration_id']])) {
            $r = cd_reg_get((int) $x['registration_id']);
            $names[$x['registration_id']] = $r ? trim($r['first_name'] . ' ' . $r['last_name']) : '';
        }
        $who = $x['registration_id'] ? ($names[$x['registration_id']] ?: $x['recipient']) : $x['recipient'];
        $label = $x['trigger_key'] === 'test' ? 'آزمایشی' : (CD_REG_TRIGGERS[$x['trigger_key']] ?? $x['trigger_key']);
        echo '<div style="display:flex;align-items:center;gap:10px;font-size:13px;min-height:38px;border-bottom:1px solid var(--ln)">';
        echo '<span class="dashicons ' . ($x['ok'] ? 'dashicons-yes-alt" style="color:var(--go)' : 'dashicons-warning" style="color:var(--st)') . '"></span>';
        echo '<span style="flex-grow:1">' . esc_html($who . ' · ' . $label . ($x['channel'] === 'email' ? ' · ایمیل' : '')) . ($x['ok'] ? '' : ' · <span class="cd-mu">' . esc_html(mb_substr($x['response'], 0, 60)) . '</span> <button class="cd-btn sm" name="retry" value="' . (int) $x['id'] . '">تلاش دوباره</button>') . '</span>';
        echo '<span class="cd-mu" style="font-size:12px">' . esc_html(cd_ui_hm($x['created_at'])) . '</span></div>';
    }
    echo '</div></div></div></form>';
    cd_ui_close();
}

add_action('admin_post_cd_reg_action', function () {
    if (!current_user_can('manage_options')) {
        wp_die('دسترسی ندارید.', 403);
    }
    check_admin_referer('cd_reg_action');
    $res = cd_reg_admin_action((int) ($_POST['id'] ?? 0), sanitize_key(wp_unslash($_POST['act'] ?? '')), sanitize_text_field(wp_unslash($_POST['reason'] ?? '')), sanitize_text_field(wp_unslash($_POST['confirm_code'] ?? '')));
    $msg = is_wp_error($res) ? $res->get_error_message() : (($res['_result'] ?? '') === 'archived_instead' ? 'این ثبت‌نام پرداخت یا ورود به لیست دارد؛ به‌جای حذف بایگانی شد.' : (($res['_result'] ?? '') === 'deleted' ? 'حذف شد.' : 'انجام شد.'));
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
    $events = cd_all_events();
    $current = cd_ui_current_event($events);
    $count = $current ? (int) $wpdb->get_var($wpdb->prepare('SELECT COUNT(*) FROM ' . cd_table('registrations') . ' WHERE event_id = %d AND archived_at IS NULL', $current['id'])) : 0;
    $export = $current ? wp_nonce_url(admin_url('admin-post.php?action=cd_reg_export&event=' . (int) $current['id']), 'cd_reg_export') : '';
    $event = cd_reg_admin_open('cd-registrations', 'ثبت‌نام‌ها', function ($e) use ($count) {
        return $e['name'] . ' · ' . cd_fa_digits((string) $count) . ' نفر';
    });
    if (!$event) {
        return;
    }
    echo cd_reg_admin_css(); // phpcs:ignore
    if (isset($_GET['msg'])) {
        printf('<div class="cd-callout go" style="margin-bottom:14px">%s</div>', esc_html(rawurldecode(sanitize_text_field(wp_unslash($_GET['msg'])))));
    }
    $eid = (int) $event['id'];
    cd_reg_expire_holds($eid);
    $filter = isset($_GET['status']) ? sanitize_key(wp_unslash($_GET['status'])) : '';
    $statuses = cd_reg_statuses();
    $all = $wpdb->get_results($wpdb->prepare('SELECT * FROM ' . cd_table('registrations') . ' WHERE event_id = %d ORDER BY id DESC LIMIT 1000', $eid), ARRAY_A);
    $counts = ['all' => 0, 'archived' => 0];
    foreach ($all as $x) {
        if ($x['archived_at']) {
            $counts['archived']++;
            continue;
        }
        $counts['all']++;
        $counts[$x['status']] = ($counts[$x['status']] ?? 0) + 1;
    }
    $rows = array_values(array_filter($all, function ($x) use ($filter) {
        if ($filter === 'archived') {
            return (bool) $x['archived_at'];
        }
        if ($x['archived_at']) {
            return false;
        }
        if ($filter === 'ended') {
            return in_array($x['status'], ['rejected', 'expired'], true);
        }
        return $filter === '' || $x['status'] === $filter;
    }));
    $base = admin_url('admin.php?page=cd-registrations&event=' . $eid);
    $chips = [
        '' => 'همه ' . cd_fa_digits((string) $counts['all']),
        'pending_approval' => 'منتظر تأیید ' . cd_fa_digits((string) ($counts['pending_approval'] ?? 0)),
        'pending_review' => 'بررسی پرداخت ' . cd_fa_digits((string) ($counts['pending_review'] ?? 0)),
        'pending_payment' => 'در انتظار پرداخت ' . cd_fa_digits((string) ($counts['pending_payment'] ?? 0)),
        'confirmed' => 'تأییدشده ' . cd_fa_digits((string) ($counts['confirmed'] ?? 0)),
        'ended' => 'ردشده / منقضی',
        'archived' => 'بایگانی‌شده ' . cd_fa_digits((string) $counts['archived']),
    ];
    $sel = isset($_GET['id']) ? (int) $_GET['id'] : ($rows[0]['id'] ?? 0);
    $types = cd_code_names('registration_types', $eid);
    $pill = function ($x) use ($statuses) {
        $cls = ['confirmed' => 'go', 'pending_approval' => 'wait', 'pending_review' => 'wait', 'rejected' => 'stop'][$x['status']] ?? 'mute';
        return '<span class="cd-pl ' . $cls . '">' . esc_html($statuses[$x['status']] ?? $x['status']) . '</span>';
    };
    $method = ['gateway' => 'درگاه', 'card' => 'کارت‌به‌کارت', 'link' => 'لینک بیرونی', '' => '—'];
    echo '<div class="cd-grid" style="grid-template-columns:1fr 340px;align-items:start">';
    echo '<div style="display:flex;flex-direction:column;gap:12px"><div class="ry-chips">';
    foreach ($chips as $k => $label) {
        printf('<a class="%s" href="%s">%s</a>', $filter === $k ? 'on' : '', esc_url($base . ($k !== '' ? '&status=' . $k : '')), esc_html($label));
    }
    printf('<a href="%s"><span class="dashicons dashicons-download" style="font-size:16px;width:16px;height:16px;margin-left:4px"></span>خروجی اکسل</a>', esc_url($export));
    echo '</div><div class="cd-card pop" style="padding:0;overflow:hidden">';
    echo '<div class="ry-tr hd"><span>نام</span><span>نوع</span><span>مبلغ</span><span>روش</span><span>وضعیت</span></div>';
    if (!$rows) {
        echo '<p class="cd-mu" style="padding:18px">ثبت‌نامی نیست.</p>';
    }
    foreach ($rows as $x) {
        printf(
            '<a class="ry-tr%s" href="%s"><b>%s</b><span>%s</span><span>%s</span><span>%s</span>%s</a>',
            (int) $x['id'] === $sel ? ' on' : '',
            esc_url($base . ($filter !== '' ? '&status=' . $filter : '') . '&id=' . (int) $x['id']),
            esc_html(trim($x['first_name'] . ' ' . $x['last_name'])),
            esc_html($types[$x['type_code']] ?? $x['type_code']),
            esc_html(cd_fa_digits(number_format((int) $x['amount_online']))),
            esc_html($method[$x['pay_method']] ?? $x['pay_method']),
            $pill($x) // phpcs:ignore
        );
    }
    echo '</div></div>';
    // پنل جزئیات
    $x = $sel ? cd_reg_get($sel) : null;
    echo '<div class="cd-card pop" style="display:flex;flex-direction:column;gap:10px">';
    if (!$x || (int) $x['event_id'] !== $eid) {
        echo '<p class="cd-mu">یک ثبت‌نام را از فهرست انتخاب کنید.</p></div></div>';
        cd_ui_close();
        return;
    }
    $page = cd_reg_get_page_by_event($eid);
    $cfg = $page ? $page['config'] : cd_reg_default_config();
    echo '<div style="display:flex;flex-direction:column"><b style="font-size:18px">' . esc_html(trim($x['first_name'] . ' ' . $x['last_name'])) . '</b><span class="cd-mu" style="font-size:12px">کد <span dir="ltr">' . esc_html($x['code']) . '</span> · ' . esc_html(cd_ui_ago($x['created_at'])) . '</span></div>';
    echo $pill($x); // phpcs:ignore
    $kv = function ($k, $v, $ltr = false) {
        if ($v === '' || $v === null) {
            return;
        }
        echo '<div class="ry-kv"><span>' . esc_html($k) . '</span><b' . ($ltr ? ' dir="ltr"' : '') . '>' . esc_html($v) . '</b></div>';
    };
    $kv('موبایل', cd_fa_digits($x['mobile']), true);
    $kv('ایمیل', $x['email'], true);
    $kv('سازمان', $x['organization']);
    $kv('نوع', $types[$x['type_code']] ?? $x['type_code']);
    $addons = (array) json_decode((string) $x['addons'], true);
    foreach ($cfg['addons'] as $a) {
        if (in_array($a['id'], $addons, true)) {
            $kv($a['title'] . ($a['price_mode'] === 'onsite' ? ' · در محل' : ''), $a['price'] ? cd_fa_digits(number_format((int) $a['price'])) : '✓');
        }
    }
    $kv('مبلغ آنلاین', cd_fa_digits(number_format((int) $x['amount_online'])) . ' تومان');
    $kv('روش پرداخت', $method[$x['pay_method']] ?? '');
    $kv('شماره‌ی بانک', $x['pay_ref'], true);
    $kv('شماره‌ی پیگیری', $x['pay_tracking'], true);
    if ($x['receipt_file']) {
        echo '<a class="cd-btn" target="_blank" href="' . esc_url(wp_nonce_url(admin_url('admin-post.php?action=cd_reg_receipt&id=' . (int) $x['id']), 'cd_reg_receipt')) . '"><span class="dashicons dashicons-media-document"></span>رسید (فقط برای مدیر)</a>';
    }
    if ($x['reject_reason']) {
        echo '<div class="cd-callout stop">دلیل رد: ' . esc_html($x['reject_reason']) . '</div>';
    }
    $act = function ($a, $label, $cls = '', $extra = '') use ($x, $eid) {
        return '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '" style="display:contents">' . wp_nonce_field('cd_reg_action', '_wpnonce', true, false)
            . '<input type="hidden" name="action" value="cd_reg_action"><input type="hidden" name="act" value="' . esc_attr($a) . '"><input type="hidden" name="id" value="' . (int) $x['id'] . '"><input type="hidden" name="event" value="' . $eid . '">'
            . $extra . '<button class="cd-btn ' . esc_attr($cls) . '" style="justify-content:center">' . esc_html($label) . '</button></form>';
    };
    $s = $x['status'];
    echo '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">';
    if (!in_array($s, ['rejected', 'confirmed'], true)) {
        echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '" style="grid-column:1/-1;display:flex;gap:8px">' . wp_nonce_field('cd_reg_action', '_wpnonce', true, false) // phpcs:ignore
            . '<input type="hidden" name="action" value="cd_reg_action"><input type="hidden" name="act" value="reject"><input type="hidden" name="id" value="' . (int) $x['id'] . '"><input type="hidden" name="event" value="' . $eid . '">'
            . '<div class="cd-field" style="flex-grow:1;height:44px"><input name="reason" placeholder="دلیل رد (به فرد نشان داده می‌شود)"></div><button class="cd-btn danger">رد…</button></form>';
    }
    if (in_array($s, ['pending_payment', 'pending_review', 'expired'], true)) {
        echo $act('mark_paid', 'پرداخت شد'); // phpcs:ignore
    }
    if ($s === 'pending_approval') {
        echo $act('approve', 'تأیید ثبت‌نام', 'pri'); // phpcs:ignore
    }
    echo $x['archived_at'] ? $act('unarchive', 'برگرداندن از بایگانی') : $act('archive', 'بایگانی'); // phpcs:ignore
    echo $act('delete', 'حذف…', 'danger', '<input type="hidden" name="confirm_code" value="" class="ry-confirm">'); // phpcs:ignore
    echo '</div>';
    echo '<span class="cd-mu" style="font-size:12px">حذف دو مرحله‌ای است و کد پیگیری را می‌خواهد؛ ثبت‌نامی که پرداخت یا ورود به لیست دارد فقط بایگانی می‌شود.</span>';
    echo '<script>document.querySelectorAll(".ry-confirm").forEach(function(i){i.form.addEventListener("submit",function(e){var v=prompt("برای حذف، کد پیگیری را بنویسید: ' . esc_js($x['code']) . '");if(!v){e.preventDefault();return;}i.value=v;});});</script>';
    echo '</div></div>';
    cd_ui_close();
}
