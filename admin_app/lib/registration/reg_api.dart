// ثبت‌نام آنلاین در اپ مدیریت: خواندن و نوشتن روی همان API افزونه که پیشخوان وردپرس هم دارد.
// هر کدام را عوض کنید (اپ یا پیشخوان)، دیگری همان را می‌بیند.
import 'dart:convert';
import 'dart:typed_data';

import '../normalize.dart';
import '../state.dart';

const regStatusLabels = {
  'pending_payment': 'در انتظار پرداخت',
  'pending_review': 'بررسی پرداخت',
  'pending_approval': 'منتظر تأیید',
  'confirmed': 'تأییدشده',
  'rejected': 'ردشده',
  'expired': 'منقضی',
};

const regPayMethods = {'gateway': 'درگاه', 'card': 'کارت‌به‌کارت', 'link': 'لینک بیرونی', '': '—'};

const regTriggers = {
  'created': 'ثبت شد (بدون پرداخت)',
  'pending_payment': 'منتظر پرداخت',
  'pending_review': 'رسید رسید؛ منتظر بررسی',
  'pending_approval': 'منتظر تأیید مدیر',
  'confirmed': 'تأیید شد',
  'rejected': 'رد شد',
  'expired': 'منقضی شد',
};

const regMessageVars = ['{name}', '{code}', '{event}', '{amount}', '{status}', '{link}', '{personal_link}', '{reason}'];

/// «۸۰۰٬۰۰۰ تومان»؛ صفر = «رایگان» اگر [free] باشد.
String regMoney(num n, {bool unit = true, bool free = false}) {
  if (n == 0 && free) return 'رایگان';
  final s = n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '٬');
  return '${faDigits(s)}${unit ? ' تومان' : ''}';
}

Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map(_map).toList() : <Map<String, dynamic>>[];

/// پیش‌فرض صفحه‌ی ثبت‌نام (همان cd_reg_default_config افزونه).
Map<String, dynamic> regDefaultConfig() => {
      'path': '',
      'use_prefix': true,
      'status': 'draft',
      'list_mode': 'direct',
      'content': {
        'title': '', 'subtitle': '', 'description': '', 'logo_url': '', 'cover_url': '',
        'days': <String>[], 'venue': <String>[], 'site_url': '', 'contact': '', 'links': <Map>[], 'closed_text': '',
      },
      'theme': {'accent': '#0B7A7B', 'highlight': '#B34A00', 'mode': 'light', 'maker_credit': true},
      'capacity_total': 0,
      'deadline': '',
      'types': <Map>[],
      'fields': {'email': 'optional', 'organization': 'required'},
      'custom_fields': <Map>[],
      'addons': <Map>[],
      'payment': {
        'method': 'gateway',
        'gateway': 'zarinpal',
        'gateway_settings': <String, dynamic>{},
        'link_url': '',
        'link_text': '',
        'card': {'number': '', 'sheba': '', 'holder': '', 'bank': '', 'text': '', 'image_url': '', 'require': 'code'},
        'hold_hours': 48,
      },
      'success': {'show_personal_link': true, 'text': ''},
      'messages': {'sms': false, 'email': false, 'templates': <String, dynamic>{}},
    };

/// داده‌ی ویرایشگر: تنظیم صفحه، نوع‌ها، وعده‌ها، درگاه‌ها و شمارش‌ها.
class RegEditor {
  Map<String, dynamic> config;
  final bool exists;
  final String? url;
  final String home;
  final List<Map<String, dynamic>> types, meals, gateways;
  final Map<String, dynamic> counts;
  RegEditor(this.config, this.exists, this.url, this.home, this.types, this.meals, this.gateways, this.counts);

  factory RegEditor.fromJson(Map<String, dynamic> j) {
    final cfg = j['page'] is Map ? jsonDecode(jsonEncode(j['page'])) as Map<String, dynamic> : regDefaultConfig();
    final ed = RegEditor(cfg, j['page'] is Map, j['url']?.toString(), (j['home'] ?? '').toString(), _list(j['types']), _list(j['meals']),
        _list(j['gateways']), _map(j['counts']));
    ed._fillTypes();
    return ed;
  }

  /// نوع‌های پیکربندی که هنوز در صفحه نیستند اضافه می‌شوند؛ نوع حذف‌شده می‌رود.
  void _fillTypes() {
    final list = (config['types'] as List? ?? []).map(_map).toList();
    for (final t in types) {
      if (!list.any((x) => x['code'] == t['code'])) {
        list.add({'code': t['code'], 'description': '', 'price': 0, 'capacity': 0, 'deadline': '', 'visible': true});
      }
    }
    config['types'] = list.where((x) => types.any((t) => t['code'] == x['code'])).toList();
    if (config['messages'] is! Map) config['messages'] = {'sms': false, 'email': false, 'templates': <String, dynamic>{}};
    final msg = config['messages'] as Map;
    if (msg['templates'] is! Map) msg['templates'] = <String, dynamic>{};
    final pay = config['payment'];
    if (pay is Map && pay['gateway_settings'] is! Map) pay['gateway_settings'] = <String, dynamic>{};
  }

  String typeName(String code) => types.firstWhere((t) => t['code'] == code, orElse: () => {'name': code})['name'].toString();

  String get fullPath => '${config['use_prefix'] == true ? 'register/' : ''}${config['path'] ?? ''}';
}

/// یک ثبت‌نام (cd_reg_out افزونه).
class Registration {
  final Map<String, dynamic> j;
  Registration(this.j);
  int get id => (j['id'] as num).toInt();
  String get code => '${j['code'] ?? ''}';
  String get status => '${j['status'] ?? ''}';
  String get statusLabel => regStatusLabels[status] ?? '${j['status_label'] ?? status}';
  String get name => '${j['first_name'] ?? ''} ${j['last_name'] ?? ''}'.trim();
  String get mobile => '${j['mobile'] ?? ''}';
  String get email => '${j['email'] ?? ''}';
  String get organization => '${j['organization'] ?? ''}';
  String get type => '${j['type'] ?? ''}';
  int get amountOnline => (j['amount_online'] as num?)?.toInt() ?? 0;
  int get amountOnsite => (j['amount_onsite'] as num?)?.toInt() ?? 0;
  String get payMethod => '${j['pay_method'] ?? ''}';
  String get payRef => '${j['pay_ref'] ?? ''}';
  String get payTracking => '${j['pay_tracking'] ?? ''}';
  bool get hasReceipt => j['has_receipt'] == true;
  String get rejectReason => '${j['reject_reason'] ?? ''}';
  bool get archived => j['archived'] == true;
  bool get canDelete => j['can_delete'] == true;
  List<String> get addons => [for (final a in (j['addons'] as List? ?? [])) '$a'];
  Map<String, dynamic> get answers => _map(j['answers']);
  DateTime? get createdAt => DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal();
  DateTime? get holdUntil => DateTime.tryParse('${j['hold_until'] ?? ''}')?.toLocal();
  bool get needsAction => !archived && (status == 'pending_approval' || status == 'pending_review');
}

class RegList {
  final List<Registration> items;
  final Map<String, int> byStatus;
  final int archived;
  RegList(this.items, this.byStatus, this.archived);
  int get active => byStatus.values.fold(0, (a, b) => a + b);
}

extension RegApi on AdminState {
  String get _ev => '/admin/events/${Uri.encodeComponent(eventCode ?? '')}';

  Future<RegEditor?> loadRegEditor() =>
      run('', () async => RegEditor.fromJson(_map(await api.get('$_ev/reg-page'))));

  /// ذخیره‌ی صفحه؛ داده‌ی تازه‌ی ویرایشگر (با آدرس) برمی‌گردد.
  Future<RegEditor?> saveRegPage(Map<String, dynamic> config, {String ok = 'صفحه‌ی ثبت‌نام ذخیره شد.'}) =>
      run(ok, () async => RegEditor.fromJson(_map(await api.post('$_ev/reg-page', {'config': config}))));

  Future<RegList?> loadRegistrations({bool archived = true}) => run('', () async {
        final r = _map(await api.get('$_ev/registrations${archived ? '?archived=1' : ''}'));
        return RegList(
          [for (final x in _list(r['registrations'])) Registration(x)],
          {for (final e in _map(r['by_status']).entries) e.key: (e.value as num).toInt()},
          (r['archived'] as num?)?.toInt() ?? 0,
        );
      });

  /// approve، mark_paid، reject (با دلیل)، archive، unarchive، delete (با کد پیگیری).
  Future<Map<String, dynamic>?> regAction(int id, String action, {String reason = '', String confirmCode = ''}) => run(
        switch (action) {
          'approve' => 'ثبت‌نام تأیید شد.',
          'mark_paid' => 'پرداخت ثبت شد.',
          'reject' => 'ثبت‌نام رد شد.',
          'archive' => 'بایگانی شد.',
          'unarchive' => 'از بایگانی برگشت.',
          _ => '',
        },
        () async {
          final r = _map(await api.post('/admin/registrations/$id/action', {'action': action, 'reason': reason, 'confirm_code': confirmCode}));
          if (action == 'delete') {
            message = r['result'] == 'archived_instead' ? '${r['message'] ?? 'به‌جای حذف بایگانی شد.'}' : 'ثبت‌نام حذف شد.';
          }
          return r;
        },
      );

  Future<Map<String, dynamic>?> regBulk(List<int> ids, String action) => run('', () async {
        final r = _map(await api.post('$_ev/registrations/bulk', {'action': action, 'ids': ids}));
        final d = _map(r['done']);
        message = [
          if ((d['archived'] ?? 0) > 0) '${faDigits(d['archived'])} بایگانی شد',
          if ((d['unarchived'] ?? 0) > 0) '${faDigits(d['unarchived'])} از بایگانی برگشت',
          if ((d['deleted'] ?? 0) > 0) '${faDigits(d['deleted'])} حذف شد',
          if ((d['archived_instead'] ?? 0) > 0) '${faDigits(d['archived_instead'])} پرداخت یا ورود به لیست داشت و بایگانی شد',
        ].join('، ');
        if (message!.isEmpty) message = null;
        return d;
      });

  Future<Uint8List?> regReceipt(int id) => run('', () async {
        final r = _map(await api.get('/admin/registrations/$id/receipt'));
        return base64Decode('${r['data']}');
      });

  Future<(String, Uint8List)?> regExport() => run('', () async {
        final r = _map(await api.get('$_ev/registrations/export'));
        return ('${r['filename'] ?? 'registrations.xlsx'}', base64Decode('${r['data']}'));
      });

  Future<Map<String, dynamic>?> loadFinance() => run('', () async => _map(await api.get('$_ev/finance')));

  Future<Map<String, dynamic>?> loadConnections() => run('', () async => _map(await api.get('/admin/connections')));

  Future<Map<String, dynamic>?> saveConnections(Map<String, dynamic> c) =>
      run('اتصال‌ها ذخیره شد.', () async => _map(await api.post('/admin/connections', {'connections': c})));

  Future<Map<String, dynamic>?> testSms(String mobile) => run('', () async {
        final m = _map(_map(await api.post('/admin/connections/test-sms', {'mobile': mobile}))['message']);
        if (m['ok'] != true) throw 'پیام آزمایشی فرستاده نشد: ${m['response']}';
        message = 'پیام آزمایشی فرستاده شد.';
        return m;
      });

  /// «آزمون با ۱۰۰ تومان»: آدرس درگاه برای باز کردن در مرورگر.
  Future<String?> testPayment() => run('', () async => '${_map(await api.post('$_ev/reg-page/test-payment', {}))['url']}');

  Future<List<Map<String, dynamic>>?> loadMessages() => run('', () async => _list(_map(await api.get('$_ev/messages'))['messages']));

  Future<Map<String, dynamic>?> retryMessage(int id) => run('', () async {
        final m = _map(_map(await api.post('/admin/messages/$id/retry', {}))['message']);
        if (m['ok'] != true) throw 'باز هم فرستاده نشد: ${m['response']}';
        message = 'دوباره فرستاده شد.';
        return m;
      });
}
