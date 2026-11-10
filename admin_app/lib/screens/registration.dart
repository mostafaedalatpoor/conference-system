// «صفحه‌ی ثبت‌نام» (ساخت و ویرایش صفحه‌ی عمومی ثبت‌نام روی سایت) و «ثبت‌نام‌ها» (تأیید، پرداخت، رد، اکسل).
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'cards.dart' show isMobilePlatform;
import 'report.dart' show relativeTime;

Map<String, dynamic> _defaultRegConfig() => {
      'path': '',
      'use_prefix': false,
      'status': 'draft',
      'list_mode': 'direct',
      'content': {
        'title': '', 'subtitle': '', 'description': '', 'logo_url': '', 'cover_url': '',
        'days': <String>[], 'venue': <String>[], 'site_url': '', 'contact': '', 'links': <Map<String, dynamic>>[], 'closed_text': '',
      },
      'theme': {'accent': '#2A42D4', 'highlight': '#B7791F', 'mode': 'light', 'maker_credit': true},
      'capacity_total': 0,
      'deadline': '',
      'types': <Map<String, dynamic>>[],
      'fields': {'email': 'optional', 'organization': 'required'},
      'custom_fields': <Map<String, dynamic>>[],
      'addons': <Map<String, dynamic>>[],
      'payment': {
        'method': 'gateway', 'gateway': 'zarinpal', 'gateway_settings': <String, dynamic>{}, 'link_url': '', 'link_text': '',
        'card': {'number': '', 'sheba': '', 'holder': '', 'bank': '', 'text': '', 'image_url': '', 'require': 'code'},
        'hold_hours': 48,
      },
      'success': {'show_personal_link': true, 'text': ''},
    };

dynamic _deepCopy(dynamic v) => v is Map
    ? {for (final e in v.entries) e.key.toString(): _deepCopy(e.value)}
    : (v is List ? [for (final x in v) _deepCopy(x)] : v);

String _rid(String p) => '$p${Random().nextInt(1 << 30).toRadixString(36)}';

String money(int n) => n <= 0 ? 'رایگان' : '${faDigits(n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '٬'))} تومان';

/// «2026-11-05 23:59» → «۱۴۰۵-۰۸-۱۴ ۲۳:۵۹» برای نمایش؛ سرور هر دو را می‌پذیرد.
String jalaliDeadline(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2})$').firstMatch(v);
  if (m == null) return v;
  final (jy, jm, jd) = gregorianToJalali(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  String two(int n) => n.toString().padLeft(2, '0');
  return faDigits('$jy-${two(jm)}-${two(jd)} ${m[4]}');
}

(int, int, int) gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) + ((gy2 + 399) ~/ 400) + gd + gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return (jy, jm, jd);
}

Color? _hex(String s) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s.trim());
  return m == null ? null : Color(int.parse('FF${m[1]}', radix: 16));
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

const regStatusLabels = {
  'pending_payment': 'در انتظار پرداخت',
  'pending_review': 'در انتظار تأیید پرداخت',
  'pending_approval': 'در انتظار تأیید مدیر',
  'confirmed': 'تأییدشده',
  'rejected': 'ردشده',
  'expired': 'منقضی',
};

Future<void> saveBytesAs(AdminState s, String name, String ext, Uint8List bytes) async {
  String? path;
  if (isMobilePlatform) {
    path = await FilePicker.platform.saveFile(fileName: name, type: FileType.custom, allowedExtensions: [ext], bytes: bytes);
    if (path == null) return;
  } else {
    path = await FilePicker.platform.saveFile(fileName: name, type: FileType.custom, allowedExtensions: [ext]);
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
    await File(path).writeAsBytes(bytes);
  }
  s.message = 'ذخیره شد: $path';
  s.messageIsError = false;
  s.notify();
}

// ================================================================ صفحه‌ی ثبت‌نام

class RegPageScreen extends StatefulWidget {
  /// گوشی: فقط یک بخش (۱ تا ۹) با دکمه‌ی ذخیره؛ null = همه.
  final int? section;
  const RegPageScreen({super.key, this.section});

  @override
  State<RegPageScreen> createState() => _RegPageScreenState();
}

class _RegPageScreenState extends State<RegPageScreen> {
  Map<String, dynamic>? _cfg;
  String? _loadError;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = StateScope.read(context);
    try {
      await s.loadRegPage();
      _loadError = null;
    } catch (e) {
      _loadError = 'صفحه‌ی ثبت‌نام از سرور خوانده نشد. افزونه‌ی سایت باید نسخه‌ی ۰٫۳ یا تازه‌تر باشد. ($e)';
    }
    if (!mounted) return;
    setState(() {
      _cfg = _fromEditor(s.regEditor);
      _rev++;
    });
  }

  Map<String, dynamic> _fromEditor(Map<String, dynamic>? ed) {
    final base = _defaultRegConfig();
    final page = ed?['page'];
    final cfg = page is Map ? _merge(base, _deepCopy(page) as Map<String, dynamic>) : base;
    // هر نوع پیکربندی یک ردیف دارد، با همان ترتیب.
    final existing = {for (final t in (cfg['types'] as List)) (t as Map)['code']: t};
    cfg['types'] = [
      for (final t in (ed?['types'] as List? ?? const []))
        existing[(t as Map)['code']] ?? {'code': t['code'], 'description': '', 'price': 0, 'capacity': 0, 'deadline': '', 'visible': true},
    ];
    if (cfg['path'] == '' && page == null) cfg['path'] = (StateScope.read(context).eventCode ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
    return cfg;
  }

  Map<String, dynamic> _merge(Map<String, dynamic> a, Map<String, dynamic> b) {
    final out = Map<String, dynamic>.from(a);
    b.forEach((k, v) => out[k] = (v is Map && a[k] is Map) ? _merge((a[k] as Map).cast<String, dynamic>(), v.cast<String, dynamic>()) : v);
    return out;
  }

  Map<String, dynamic> get _c => (_cfg!['content'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _t => (_cfg!['theme'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _p => (_cfg!['payment'] as Map).cast<String, dynamic>();

  Widget _text(Map m, String key, String label,
      {bool ltr = false, int lines = 1, String? helper, bool optional = false, double? width, TextInputType? keyboard}) {
    final f = DaftarField(
      label: label,
      optional: optional,
      helper: helper,
      child: TextFormField(
        key: ValueKey('$label-$key-$_rev'),
        initialValue: (m[key] ?? '').toString(),
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : null),
        textDirection: ltr ? TextDirection.ltr : null,
        onChanged: (v) => m[key] = v,
      ),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  Widget _num(Map m, String key, String label, {String? helper, double width = 180}) => SizedBox(
        width: width,
        child: DaftarField(
          label: label,
          helper: helper,
          child: TextFormField(
            key: ValueKey('$label-$key-$_rev'),
            initialValue: '${m[key] ?? 0}' == '0' ? '' : faDigits('${m[key]}'),
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            onChanged: (v) => m[key] = int.tryParse(latinDigits(v).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          ),
        ),
      );

  Widget _deadline(Map m, String label, double width) => SizedBox(
        width: width,
        child: DaftarField(
          label: label,
          optional: true,
          helper: 'مثل ۱۴۰۵-۰۸-۱۵ ۱۸:۰۰',
          child: TextFormField(
            key: ValueKey('$label-deadline-$_rev'),
            initialValue: jalaliDeadline((m['deadline'] ?? '').toString()),
            textDirection: TextDirection.ltr,
            onChanged: (v) => m['deadline'] = latinDigits(v.trim()),
          ),
        ),
      );

  Widget _lines(Map m, String key, String label, {String? helper}) => DaftarField(
        label: label,
        helper: helper,
        child: TextFormField(
          key: ValueKey('$label-$key-$_rev'),
          initialValue: ((m[key] as List?) ?? const []).join('\n'),
          minLines: 2,
          maxLines: 6,
          onChanged: (v) => m[key] = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        ),
      );

  Widget _seg<T>(Map m, String key, List<(T, String)> items) => SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [for (final (v, l) in items) ButtonSegment(value: v, label: Text(l))],
        selected: {m[key] as T},
        onSelectionChanged: (v) => setState(() => m[key] = v.first),
      );

  Widget _image(Map m, String key, String label) {
    final s = StateScope.read(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: _text(m, key, label, ltr: true, optional: true)),
      const SizedBox(width: DaftarSize.space2),
      OutlinedButton.icon(
        icon: const Icon(Icons.upload_rounded),
        label: const Text('بارگذاری'),
        onPressed: () async {
          final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'], withData: true);
          final f = r?.files.single;
          final bytes = f?.bytes ?? (f?.path == null ? null : await File(f!.path!).readAsBytes());
          if (bytes == null) return;
          final url = await s.uploadRegAsset(bytes);
          if (url != null && mounted) setState(() {
            m[key] = url;
            _rev++;
          });
        },
      ),
    ]);
  }

  Widget _color(Map m, String key, String label, List<String> presets) {
    final c = _hex((m[key] ?? '').toString());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c ?? Colors.transparent, borderRadius: BorderRadius.circular(DaftarSize.radiusSm), border: Border.all(color: DaftarColors.of(context).line)),
        ),
        const SizedBox(width: DaftarSize.space2),
        Expanded(
          child: DaftarField(
            label: label,
            error: c == null ? 'به شکل #RRGGBB' : null,
            child: TextFormField(
              key: ValueKey('$key-$_rev'),
              initialValue: m[key].toString(),
              textDirection: TextDirection.ltr,
              onChanged: (v) => setState(() => m[key] = v.trim().toUpperCase()),
            ),
          ),
        ),
      ]),
      const SizedBox(height: DaftarSize.space2),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in presets)
          InkWell(
            onTap: () => setState(() {
              m[key] = p;
              _rev++;
            }),
            child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _hex(p), borderRadius: BorderRadius.circular(6))),
          ),
      ]),
    ]);
  }

  Future<void> _save(AdminState s) async {
    final cfg = _deepCopy(_cfg) as Map<String, dynamic>;
    cfg['path'] = (cfg['path'] as String).trim().toLowerCase();
    await s.saveRegPage(cfg);
    if (!s.messageIsError && mounted) setState(() => _rev++);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final x = DaftarColors.of(context);
    final ed = s.regEditor;
    if (_cfg == null) {
      return PageBody(title: 'صفحه‌ی ثبت‌نام', children: [
        if (_loadError != null) Notice(tone: NoticeTone.stop, text: _loadError!) else const LinearProgressIndicator(),
      ]);
    }
    final cfg = _cfg!;
    final c = _c, t = _t, p = _p;
    final types = (ed?['types'] as List? ?? const []).cast<Map>();
    final meals = (ed?['meals'] as List? ?? const []).cast<Map>();
    final gateways = (ed?['gateways'] as List? ?? const []).cast<Map>();
    final url = ed?['url'] as String?;
    final home = (ed?['home'] ?? '${s.server}/').toString();
    String typeName(String code) => (types.where((e) => e['code'] == code).firstOrNull?['name'] ?? code).toString();
    final anyPrice = (cfg['types'] as List).any((e) => ((e as Map)['price'] ?? 0) > 0) ||
        (cfg['addons'] as List).any((e) => (e as Map)['price_mode'] == 'online' && (e['price'] ?? 0) > 0);

    final accent = _hex(t['accent'].toString());
    final surface = t['mode'] == 'dark' ? const Color(0xFF161A21) : Colors.white;
    final lowContrast = accent != null && _contrast(accent, surface) < 3;

    final all = <Widget>[
      if (_loadError != null) Notice(tone: NoticeTone.stop, text: _loadError!),
      if (url != null)
        Container(
          padding: const EdgeInsets.all(DaftarSize.space3),
          decoration: BoxDecoration(color: x.sunken, borderRadius: BorderRadius.circular(DaftarSize.radiusSm)),
          child: Row(children: [
            Icon(Icons.public_rounded, color: x.stamp),
            const SizedBox(width: DaftarSize.space2),
            Expanded(child: SelectableText(url, textDirection: TextDirection.ltr, style: TextStyle(color: x.stamp, fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
              child: const Text('کپی'),
            ),
            DaftarTag(cfg['status'] == 'open' ? 'باز' : (cfg['status'] == 'closed' ? 'بسته' : 'پیش‌نویس'), kind: TagKind.stamp),
          ]),
        )
      else
        const Hint('صفحه‌ی ثبت‌نام این رویداد هنوز ساخته نشده. گام‌ها را پر کنید و «ذخیره» را بزنید؛ اول در حالت پیش‌نویس است.'),
      if (s.regByStatus.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space2),
          child: Text(
            '${faDigits(s.regByStatus['confirmed'] ?? 0)} تأییدشده، '
            '${faDigits((s.regByStatus['pending_payment'] ?? 0) + (s.regByStatus['pending_review'] ?? 0) + (s.regByStatus['pending_approval'] ?? 0))} در انتظار',
            style: TextStyle(color: x.inkMuted),
          ),
        ),

      const SectionTitle('۱. آدرس و ورود به لیست'),
      // آدرس از چپ به راست خوانده می‌شود: پیشوند سایت، بعد نام صفحه.
      Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(spacing: DaftarSize.space2, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('$home${cfg['use_prefix'] == true ? 'register/' : ''}', style: TextStyle(color: x.inkMuted)),
          SizedBox(
            width: 240,
            child: TextFormField(
              key: ValueKey('path-$_rev'),
              initialValue: cfg['path'].toString(),
              decoration: const InputDecoration(hintText: 'conf-2026', isDense: true),
              onChanged: (v) => cfg['path'] = v,
            ),
          ),
        ]),
      ),
      const Hint('نام صفحه: حروف کوچک انگلیسی، رقم و خط تیره، دست‌کم ۲ حرف.'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: cfg['use_prefix'] == true,
        onChanged: (v) => setState(() => cfg['use_prefix'] = v),
        title: const Text('با پیشوند register/'),
        subtitle: const Text('تا آدرس با برگه‌های سایت قاطی نشود.'),
      ),
      Text('وضعیت صفحه', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: DaftarSize.space1),
      _seg<String>(cfg, 'status', const [('draft', 'پیش‌نویس'), ('open', 'باز'), ('closed', 'بسته')]),
      const Hint('پیش‌نویس فقط برای مدیر وردپرس (وارد شده در همان مرورگر) پیش‌نمایش دارد.'),
      const SizedBox(height: DaftarSize.space3),
      Text('ثبت‌نام‌کننده کی وارد لیست شرکت‌کننده‌ها شود؟', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: DaftarSize.space1),
      _seg<String>(cfg, 'list_mode', const [('direct', 'مستقیم'), ('approval', 'با تأیید مدیر'), ('separate', 'جدا')]),
      Hint(const {
        'direct': 'هر ثبت‌نامِ قطعی فوراً شرکت‌کننده می‌شود، با کارت و شماره؛ گوشی نیروها با همگام‌سازی بعدی می‌بینند.',
        'approval': 'ثبت‌نام‌ها در «ثبت‌نام‌ها» منتظر تأیید شما می‌مانند و بعد از تأیید وارد لیست می‌شوند.',
        'separate': 'فقط فهرست و خروجی اکسل؛ ورود به لیست با اکسل، مثل الان.',
      }[cfg['list_mode']]!),

      const SectionTitle('۲. محتوا'),
      _text(c, 'title', 'تیتر'),
      const SizedBox(height: DaftarSize.space3),
      _text(c, 'subtitle', 'زیرتیتر', optional: true),
      const SizedBox(height: DaftarSize.space3),
      _text(c, 'description', 'توضیح', lines: 3, optional: true),
      const SizedBox(height: DaftarSize.space3),
      _image(c, 'logo_url', 'لوگو'),
      const SizedBox(height: DaftarSize.space3),
      _image(c, 'cover_url', 'تصویر سربرگ'),
      const SizedBox(height: DaftarSize.space3),
      _lines(c, 'days', 'روزها', helper: 'هر روز یک خط، مثلاً «چهارشنبه ۲۰ آبان ۱۴۰۵».'),
      const SizedBox(height: DaftarSize.space3),
      _lines(c, 'venue', 'مکان', helper: 'هر خط یک بخش، مثلاً «دانشگاه کاشان، تالار آزادی».'),
      const SizedBox(height: DaftarSize.space3),
      _text(c, 'site_url', 'سایت رویداد', ltr: true, optional: true),
      const SizedBox(height: DaftarSize.space3),
      _text(c, 'contact', 'تماس دبیرخانه', ltr: true, optional: true),
      const SizedBox(height: DaftarSize.space3),
      DaftarField(
        label: 'لینک‌های پایین صفحه',
        optional: true,
        helper: 'هر خط: «نام | نشانی»، مثلاً «تلگرام | https://t.me/conf»',
        child: TextFormField(
          key: ValueKey('links-$_rev'),
          initialValue: ((c['links'] as List?) ?? const []).map((l) => '${(l as Map)['label']} | ${l['url']}').join('\n'),
          minLines: 2,
          maxLines: 6,
          textDirection: TextDirection.ltr,
          onChanged: (v) => c['links'] = [
            for (final line in v.split('\n'))
              if (line.trim().isNotEmpty)
                line.contains('|')
                    ? {'label': line.split('|').first.trim(), 'url': line.split('|').sublist(1).join('|').trim()}
                    : {'label': '', 'url': line.trim()},
          ],
        ),
      ),
      const SizedBox(height: DaftarSize.space3),
      _text(c, 'closed_text', 'متن صفحه‌ی «ثبت‌نام بسته»', lines: 2, optional: true,
          helper: 'پیش‌فرض: «ظرفیت یا مهلت تمام شده؛ اگر جا باشد روز رویداد در میز پذیرش ثبت‌نام می‌شوید.»'),

      const SectionTitle('۳. تم'),
      Wrap(spacing: DaftarSize.space5, runSpacing: DaftarSize.space4, children: [
        SizedBox(width: 300, child: _color(t, 'accent', 'رنگ اصلی (دکمه‌ها و انتخاب‌ها)', const ['#2A42D4', '#2BC4F3', '#127A3B', '#B42318', '#6D28D9', '#0F766E', '#10141A'])),
        SizedBox(width: 300, child: _color(t, 'highlight', 'رنگ دوم (تیتر و قیمت)', const ['#B7791F', '#F2C14E', '#2A42D4', '#B42318', '#0F766E', '#10141A'])),
      ]),
      const SizedBox(height: DaftarSize.space3),
      Text('زمینه', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: DaftarSize.space1),
      _seg<String>(t, 'mode', const [('light', 'روشن'), ('dark', 'تیره')]),
      if (lowContrast)
        const Padding(
          padding: EdgeInsets.only(top: DaftarSize.space2),
          child: Notice(tone: NoticeTone.wait, text: 'رنگ اصلی روی این زمینه کم‌رنگ است. صفحه متن‌ها را خودکار خواناتر می‌کند، ولی دکمه‌ها با همین رنگ‌اند؛ رنگ پررنگ‌تری انتخاب کنید.'),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: t['maker_credit'] != false,
        onChanged: (v) => setState(() => t['maker_credit'] = v),
        title: const Text('خط «ساخته‌شده با رویدادیار» پایین صفحه'),
      ),

      const SectionTitle('۴. نوع‌های ثبت‌نام'),
      const Hint('همان نوع‌های «پیکربندی». قیمت به تومان (خالی = رایگان)، ظرفیت خالی = نامحدود، مهلت به وقت تهران مثل «۱۴۰۵-۰۸-۱۵ ۱۸:۰۰».'),
      if (types.isEmpty) const Notice(tone: NoticeTone.wait, text: 'نوع ثبت‌نامی تعریف نشده؛ اول در «پیکربندی» نوع‌ها را بسازید و روی سرور ذخیره کنید.'),
      for (final tp in (cfg['types'] as List).cast<Map>())
        Card(
          child: Padding(
            padding: const EdgeInsets.all(DaftarSize.space3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: tp['visible'] != false,
                onChanged: (v) => setState(() => tp['visible'] = v),
                title: Text(typeName(tp['code'].toString()), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(tp['visible'] != false ? 'روی صفحه دیده می‌شود' : 'پنهان'),
              ),
              if (tp['visible'] != false) ...[
                _text(tp, 'description', 'توضیح کوتاه', optional: true),
                const SizedBox(height: DaftarSize.space2),
                Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
                  _num(tp, 'price', 'قیمت (تومان)'),
                  _num(tp, 'capacity', 'ظرفیت'),
                  _deadline(tp, 'مهلت', 200),
                ]),
              ],
            ]),
          ),
        ),

      const SectionTitle('۵. ظرفیت کل و فیلدها'),
      Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
        _num(cfg, 'capacity_total', 'ظرفیت کل', helper: 'خالی = نامحدود'),
        _deadline(cfg, 'مهلت کل', 220),
      ]),
      const SizedBox(height: DaftarSize.space3),
      const Hint('نام، نام خانوادگی و موبایل همیشه الزامی‌اند.'),
      for (final (key, label) in const [('email', 'ایمیل'), ('organization', 'دانشگاه یا سازمان')])
        Padding(
          padding: const EdgeInsets.only(top: DaftarSize.space2),
          child: Row(children: [
            SizedBox(width: 140, child: Text(label)),
            _seg<String>((cfg['fields'] as Map), key, const [('required', 'الزامی'), ('optional', 'اختیاری'), ('hidden', 'پنهان')]),
          ]),
        ),

      const SectionTitle('۶. فیلدهای دلخواه'),
      const Hint('مثل «وضعیت» (تک‌انتخابی) یا «کارگاه‌ها» (چندانتخابی، با ظرفیت برای هر گزینه). پاسخ‌ها ستون‌های اضافه‌ی شرکت‌کننده می‌شوند و روی کارت قابل چاپ‌اند.'),
      for (final (i, f) in (cfg['custom_fields'] as List).cast<Map>().indexed)
        _ItemTile(
          title: (f['label'] ?? '').toString().isEmpty ? 'بدون عنوان' : f['label'].toString(),
          subtitle: [
            const {'text': 'متن کوتاه', 'select': 'تک‌انتخابی', 'multi': 'چندانتخابی'}[f['kind']] ?? '',
            if (f['required'] == true) 'الزامی',
            if ((f['options'] as List?)?.isNotEmpty ?? false) '${faDigits((f['options'] as List).length)} گزینه',
          ].join('، '),
          onEdit: () => _editField(f, types),
          onDelete: () => setState(() => (cfg['custom_fields'] as List).removeAt(i)),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('افزودن فیلد'),
          onPressed: () async {
            final f = <String, dynamic>{'id': _rid('f'), 'label': '', 'kind': 'select', 'required': false, 'help': '', 'options': <Map<String, dynamic>>[], 'types': <String>[]};
            if (await _editField(f, types)) setState(() => (cfg['custom_fields'] as List).add(f));
          },
        ),
      ),

      const SectionTitle('۷. گزینه‌های اضافه'),
      const Hint('مثل «ناهار روز اول». قیمت می‌تواند روی مبلغ آنلاین برود، «تسویه در روز اجرا» باشد (نیرو هنگام پذیرش یادآوری می‌بیند)، یا فقط اطلاع باشد. اگر به یک وعده وصل شود، در اپ نیروها برای آن وعده «مجاز» است.'),
      for (final (i, a) in (cfg['addons'] as List).cast<Map>().indexed)
        _ItemTile(
          title: (a['title'] ?? '').toString().isEmpty ? 'بدون عنوان' : a['title'].toString(),
          subtitle: [
            a['price_mode'] == 'info' || (a['price'] ?? 0) == 0
                ? 'فقط اطلاع'
                : '${money((a['price'] as num).toInt())}${a['price_mode'] == 'onsite' ? '، در روز اجرا' : ''}',
            if ((a['capacity'] ?? 0) > 0) 'ظرفیت ${faDigits(a['capacity'])}',
            if ((a['meal_code'] ?? '') != '') 'وعده: ${meals.where((m) => m['code'] == a['meal_code']).firstOrNull?['name'] ?? a['meal_code']}',
          ].join('، '),
          onEdit: () => _editAddon(a, types, meals),
          onDelete: () => setState(() => (cfg['addons'] as List).removeAt(i)),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('افزودن گزینه'),
          onPressed: () async {
            final a = <String, dynamic>{'id': _rid('a'), 'title': '', 'description': '', 'price': 0, 'price_mode': 'online', 'capacity': 0, 'meal_code': '', 'types': <String>[]};
            if (await _editAddon(a, types, meals)) setState(() => (cfg['addons'] as List).add(a));
          },
        ),
      ),

      const SectionTitle('۸. پرداخت'),
      if (!anyPrice) const Hint('همه‌چیز رایگان است؛ پرداخت فقط وقتی لازم است که نوع یا گزینه‌ای مبلغ آنلاین داشته باشد.'),
      _seg<String>(p, 'method', const [('gateway', 'درگاه'), ('link', 'لینک بیرونی'), ('card', 'کارت‌به‌کارت')]),
      const SizedBox(height: DaftarSize.space3),
      if (p['method'] == 'gateway') ...[
        DropdownButtonFormField<String>(
          key: ValueKey('gw-$_rev'),
          initialValue: gateways.any((g) => g['id'] == p['gateway']) ? p['gateway'] as String : null,
          decoration: const InputDecoration(labelText: 'درگاه'),
          items: [for (final g in gateways) DropdownMenuItem(value: g['id'].toString(), child: Text(g['name'].toString()))],
          onChanged: (v) => setState(() => p['gateway'] = v),
        ),
        const SizedBox(height: DaftarSize.space3),
        for (final f in ((gateways.where((g) => g['id'] == p['gateway']).firstOrNull?['fields'] as List?) ?? const []).cast<Map>())
          Padding(
            padding: const EdgeInsets.only(bottom: DaftarSize.space3),
            child: _text((p['gateway_settings'] as Map), f['key'].toString(), f['label'].toString(), ltr: true),
          ),
        const Hint('درگاه ندارید؟ بعداً فقط مشخصات را اینجا وارد کنید. درگاه دیگری (غیر از زرین‌پال) را برنامه‌نویس با قلاب roydadyar_payment_gateways اضافه می‌کند؛ راهنما در README افزونه است. هر پرداخت ۳۰ دقیقه جا نگه می‌دارد.'),
      ] else if (p['method'] == 'link') ...[
        _text(p, 'link_url', 'نشانی صفحه‌ی پرداخت', ltr: true),
        const SizedBox(height: DaftarSize.space3),
        _text(p, 'link_text', 'توضیح', lines: 2, optional: true),
        const Hint('بعد از پرداخت، فرد شماره‌ی پیگیری یا رسید را در همان صفحه ثبت می‌کند و شما در «ثبت‌نام‌ها» «پرداخت شد» را می‌زنید.'),
      ] else ...[
        Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
          _text((p['card'] as Map), 'number', 'شماره کارت', ltr: true, width: 260, keyboard: TextInputType.number),
          _text((p['card'] as Map), 'sheba', 'شبا', ltr: true, width: 320, optional: true),
          _text((p['card'] as Map), 'holder', 'صاحب حساب', width: 240),
          _text((p['card'] as Map), 'bank', 'بانک', width: 160, optional: true),
        ]),
        const SizedBox(height: DaftarSize.space3),
        _text((p['card'] as Map), 'text', 'توضیح', lines: 2, optional: true),
        const SizedBox(height: DaftarSize.space3),
        _image((p['card'] as Map), 'image_url', 'تصویر (مثلاً توضیح واریز)'),
        const SizedBox(height: DaftarSize.space3),
        Text('از ثبت‌نام‌کننده چه بخواهد؟', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: DaftarSize.space1),
        _seg<String>((p['card'] as Map), 'require', const [('code', 'شماره‌ی پیگیری'), ('receipt', 'تصویر رسید'), ('both', 'هر دو')]),
      ],
      if (p['method'] != 'gateway') ...[
        const SizedBox(height: DaftarSize.space3),
        _num(p, 'hold_hours', 'نگه‌داشتن جا (ساعت)', helper: 'اگر تا این مدت رسیدی نیاید، جا آزاد می‌شود. بعد از رسید، تا تصمیم شما.'),
      ],

      const SectionTitle('۹. صفحه‌ی تأیید'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: (cfg['success'] as Map)['show_personal_link'] != false,
        onChanged: (v) => setState(() => (cfg['success'] as Map)['show_personal_link'] = v),
        title: const Text('لینک صفحه‌ی شخصی (QR) نشان داده شود'),
        subtitle: const Text('فقط وقتی ثبت‌نام قطعی شده و فرد وارد لیست شده.'),
      ),
      _text((cfg['success'] as Map), 'text', 'متن اضافه', lines: 2, optional: true),
    ];
    return PageBody(title: 'صفحه‌ی ثبت‌نام', children: [
      ..._sectionOf(all, widget.section),
      const SizedBox(height: DaftarSize.space5),
      Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
        FilledButton.icon(
          icon: const Icon(Icons.cloud_upload_rounded),
          onPressed: s.busy ? null : () => _save(s),
          label: const Text('ذخیره روی سرور'),
        ),
        TextButton(onPressed: s.busy ? null : _load, child: const Text('خواندن دوباره از سرور')),
      ]),
    ]);
  }

  /// در حالت یک‌بخشی، ویجت‌های بین سرفصل n و سرفصل بعدی (بدون خود سرفصل).
  List<Widget> _sectionOf(List<Widget> all, int? n) {
    if (n == null) return all;
    final starts = [for (var i = 0; i < all.length; i++) if (all[i] is SectionTitle) i];
    if (n < 1 || n > starts.length) return all;
    final from = starts[n - 1] + 1;
    final to = n < starts.length ? starts[n] : all.length;
    return [if (_loadError != null) Notice(tone: NoticeTone.stop, text: _loadError!), ...all.sublist(from, to)];
  }

  Widget _typeChips(Map item, List<Map> types, StateSetter set) {
    final sel = ((item['types'] as List?) ?? []).cast<String>().toList();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final t in types)
        FilterChip(
          label: Text(t['name'].toString()),
          selected: sel.contains(t['code']),
          onSelected: (v) => set(() {
            v ? sel.add(t['code'].toString()) : sel.remove(t['code']);
            item['types'] = sel;
          }),
        ),
    ]);
  }

  Future<bool> _editField(Map f, List<Map> types) async {
    final draft = _deepCopy(f) as Map<String, dynamic>;
    final options = TextEditingController(
      text: ((draft['options'] as List?) ?? const []).map((o) => '${(o as Map)['label']}${(o['capacity'] ?? 0) > 0 ? ' | ${o['capacity']}' : ''}').join('\n'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return AlertDialog(
          title: const Text('فیلد دلخواه'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DaftarField(label: 'عنوان', child: TextFormField(initialValue: draft['label'], onChanged: (v) => draft['label'] = v)),
                const SizedBox(height: DaftarSize.space3),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'text', label: Text('متن')), ButtonSegment(value: 'select', label: Text('تک‌انتخابی')), ButtonSegment(value: 'multi', label: Text('چندانتخابی'))],
                  selected: {draft['kind'] as String},
                  onSelectionChanged: (v) => set(() => draft['kind'] = v.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: draft['required'] == true,
                  onChanged: (v) => set(() => draft['required'] = v),
                  title: const Text('الزامی'),
                ),
                DaftarField(label: 'راهنما', optional: true, child: TextFormField(initialValue: draft['help'], onChanged: (v) => draft['help'] = v)),
                if (draft['kind'] != 'text') ...[
                  const SizedBox(height: DaftarSize.space3),
                  DaftarField(
                    label: 'گزینه‌ها',
                    helper: 'هر خط یک گزینه؛ ظرفیت اختیاری: «کارگاه پزشکی | 30»',
                    child: TextField(controller: options, minLines: 3, maxLines: 10),
                  ),
                ],
                const SizedBox(height: DaftarSize.space3),
                Text('برای کدام نوع‌ها؟ (هیچ = همه)', style: Theme.of(c).textTheme.labelLarge),
                const SizedBox(height: DaftarSize.space1),
                _typeChips(draft, types, set),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأیید')),
          ],
        );
      }),
    );
    if (ok != true) return false;
    final old = ((f['options'] as List?) ?? const []).cast<Map>();
    draft['options'] = [
      for (final line in options.text.split('\n'))
        if (line.split('|').first.trim().isNotEmpty)
          {
            'id': old.where((o) => o['label'] == line.split('|').first.trim()).firstOrNull?['id'] ?? _rid('o'),
            'label': line.split('|').first.trim(),
            'capacity': line.contains('|') ? int.tryParse(latinDigits(line.split('|')[1].trim())) ?? 0 : 0,
          },
    ];
    setState(() {
      f
        ..clear()
        ..addAll(draft);
      _rev++;
    });
    return true;
  }

  Future<bool> _editAddon(Map a, List<Map> types, List<Map> meals) async {
    final draft = _deepCopy(a) as Map<String, dynamic>;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return AlertDialog(
          title: const Text('گزینه‌ی اضافه'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DaftarField(label: 'عنوان', child: TextFormField(initialValue: draft['title'], onChanged: (v) => draft['title'] = v)),
                const SizedBox(height: DaftarSize.space3),
                DaftarField(
                  label: 'توضیح زیرش',
                  optional: true,
                  helper: 'مثلاً «تسویه در روز اجرا، کنار میز پذیرش»',
                  child: TextFormField(initialValue: draft['description'], onChanged: (v) => draft['description'] = v),
                ),
                const SizedBox(height: DaftarSize.space3),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'online', label: Text('روی مبلغ آنلاین')), ButtonSegment(value: 'onsite', label: Text('روز اجرا')), ButtonSegment(value: 'info', label: Text('فقط اطلاع'))],
                  selected: {draft['price_mode'] as String},
                  onSelectionChanged: (v) => set(() => draft['price_mode'] = v.first),
                ),
                const SizedBox(height: DaftarSize.space3),
                Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space3, children: [
                  if (draft['price_mode'] != 'info')
                    SizedBox(
                      width: 180,
                      child: DaftarField(
                        label: 'قیمت (تومان)',
                        child: TextFormField(
                          initialValue: (draft['price'] ?? 0) == 0 ? '' : faDigits('${draft['price']}'),
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          onChanged: (v) => draft['price'] = int.tryParse(latinDigits(v).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 140,
                    child: DaftarField(
                      label: 'ظرفیت',
                      optional: true,
                      child: TextFormField(
                        initialValue: (draft['capacity'] ?? 0) == 0 ? '' : faDigits('${draft['capacity']}'),
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        onChanged: (v) => draft['capacity'] = int.tryParse(latinDigits(v)) ?? 0,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: DaftarSize.space3),
                DropdownButtonFormField<String>(
                  initialValue: meals.any((m) => m['code'] == draft['meal_code']) ? draft['meal_code'] as String : '',
                  decoration: const InputDecoration(labelText: 'وصل به وعده‌ی پذیرایی'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('وصل نیست')),
                    for (final m in meals) DropdownMenuItem(value: m['code'].toString(), child: Text(m['name'].toString())),
                  ],
                  onChanged: (v) => draft['meal_code'] = v ?? '',
                ),
                const SizedBox(height: DaftarSize.space3),
                Text('برای کدام نوع‌ها؟ (هیچ = همه)', style: Theme.of(c).textTheme.labelLarge),
                const SizedBox(height: DaftarSize.space1),
                _typeChips(draft, types, set),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأیید')),
          ],
        );
      }),
    );
    if (ok != true) return false;
    setState(() {
      a
        ..clear()
        ..addAll(draft);
      _rev++;
    });
    return true;
  }
}

class _ItemTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ItemTile({required this.title, required this.subtitle, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: onEdit,
          trailing: IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline_rounded), onPressed: onDelete),
        ),
      );
}

// ================================================================ ثبت‌نام‌ها

class RegistrationsScreen extends StatefulWidget {
  const RegistrationsScreen({super.key});

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  String? _filter;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = StateScope.read(context);
    try {
      await s.loadRegistrations();
      if (s.regEditor == null) await s.loadRegPage();
      _error = null;
    } catch (e) {
      _error = 'ثبت‌نام‌ها از سرور خوانده نشد. ($e)';
    }
    if (mounted) setState(() {});
  }

  NoticeTone _tone(String st) => switch (st) {
        'confirmed' => NoticeTone.go,
        'rejected' || 'expired' => NoticeTone.stop,
        _ => NoticeTone.wait,
      };

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final x = DaftarColors.of(context);
    final q = normalizeText(_q);
    final list = s.registrations.where((r) {
      if (_filter != null && r['status'] != _filter) return false;
      if (q.isEmpty) return true;
      return normalizeText('${r['first_name']} ${r['last_name']} ${r['mobile']} ${r['code']} ${r['email']}').contains(q) ||
          normalizeMobile(_q).length >= 4 && (r['mobile'] ?? '').toString().contains(normalizeMobile(_q));
    }).toList();
    final waiting = (s.regByStatus['pending_review'] ?? 0) + (s.regByStatus['pending_approval'] ?? 0);

    return PageBody(title: 'ثبت‌نام‌ها', children: [
      if (_error != null) Notice(tone: NoticeTone.stop, text: _error!),
      if (waiting > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: DaftarSize.space2),
          child: Notice(tone: NoticeTone.wait, text: '${faDigits(waiting)} ثبت‌نام منتظر تصمیم شماست (تأیید پرداخت یا تأیید مدیر).'),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text('همه (${faDigits(s.registrations.length)})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
        for (final e in regStatusLabels.entries)
          if ((s.regByStatus[e.key] ?? 0) > 0)
            ChoiceChip(
              label: Text('${e.value} (${faDigits(s.regByStatus[e.key]!)})'),
              selected: _filter == e.key,
              onSelected: (_) => setState(() => _filter = e.key),
            ),
      ]),
      const SizedBox(height: DaftarSize.space3),
      Wrap(spacing: DaftarSize.space3, runSpacing: DaftarSize.space2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 320,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'نام، موبایل یا کد ثبت‌نام', isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        OutlinedButton.icon(onPressed: s.busy ? null : _load, icon: const Icon(Icons.refresh_rounded), label: const Text('به‌روز کردن')),
        OutlinedButton.icon(
          onPressed: s.busy || s.registrations.isEmpty
              ? null
              : () async {
                  final r = await s.run('', s.exportRegistrations);
                  s.message = null;
                  if (r != null && mounted) await saveBytesAs(s, r.$1, r.$1.endsWith('.csv') ? 'csv' : 'xlsx', r.$2);
                },
          icon: const Icon(Icons.table_chart_rounded),
          label: const Text('خروجی اکسل'),
        ),
      ]),
      const SizedBox(height: DaftarSize.space3),
      if (list.isEmpty)
        EmptyState(
          icon: Icons.how_to_reg_rounded,
          title: s.registrations.isEmpty ? 'هنوز ثبت‌نامی نیست' : 'چیزی پیدا نشد',
          hint: s.registrations.isEmpty ? 'وقتی کسی در صفحه‌ی ثبت‌نام فرم را بفرستد، اینجا می‌آید.' : null,
        ),
      for (final r in list)
        Card(
          child: InkWell(
            onTap: () => _detail(r),
            child: Padding(
              padding: const EdgeInsets.all(DaftarSize.space3),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['first_name']} ${r['last_name']}', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      [_typeName(s, r['type'].toString()), faDigits(r['mobile']), if ((r['amount_online'] ?? 0) > 0) money(r['amount_online'])].join('، '),
                      style: TextStyle(color: x.inkMuted),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _StatusTag(text: regStatusLabels[r['status']] ?? r['status'].toString(), tone: _tone(r['status'].toString())),
                  const SizedBox(height: 4),
                  Text(r['code'].toString(), textDirection: TextDirection.ltr, style: TextStyle(color: x.inkMuted, fontSize: 12)),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }

  String _typeName(AdminState s, String code) =>
      s.types.where((t) => t.code == code).firstOrNull?.name ?? code;

  String _answer(AdminState s, String fid, dynamic v) {
    final fields = ((s.regEditor?['page'] as Map?)?['custom_fields'] as List? ?? const []).cast<Map>();
    final f = fields.where((e) => e['id'] == fid).firstOrNull;
    final opts = ((f?['options'] as List?) ?? const []).cast<Map>();
    String label(dynamic id) => opts.where((o) => o['id'] == id).firstOrNull?['label']?.toString() ?? '$id';
    return v is List ? v.map(label).join('، ') : (opts.isEmpty ? '$v' : label(v));
  }

  Future<void> _detail(Map<String, dynamic> r) async {
    final s = StateScope.read(context);
    final page = (s.regEditor?['page'] as Map?) ?? const {};
    final fields = ((page['custom_fields'] as List?) ?? const []).cast<Map>();
    final addons = ((page['addons'] as List?) ?? const []).cast<Map>();
    final reason = TextEditingController();
    final st = r['status'].toString();
    final rows = <(String, String)>[
      ('کد ثبت‌نام', r['code'].toString()),
      ('وضعیت', regStatusLabels[st] ?? st),
      ('نوع حضور', _typeName(s, r['type'].toString())),
      ('موبایل', faDigits(r['mobile'])),
      if ((r['email'] ?? '') != '') ('ایمیل', r['email'].toString()),
      if ((r['organization'] ?? '') != '') ('سازمان', r['organization'].toString()),
      for (final e in ((r['answers'] as Map?) ?? const {}).entries)
        (fields.where((f) => f['id'] == e.key).firstOrNull?['label']?.toString() ?? e.key.toString(), _answer(s, e.key.toString(), e.value)),
      if ((r['addons'] as List?)?.isNotEmpty ?? false)
        ('گزینه‌ها', (r['addons'] as List).map((id) => addons.where((a) => a['id'] == id).firstOrNull?['title'] ?? id).join('، ')),
      if ((r['amount_online'] ?? 0) > 0) ('مبلغ آنلاین', money(r['amount_online'])),
      if ((r['amount_onsite'] ?? 0) > 0) ('تسویه در روز اجرا', money(r['amount_onsite'])),
      if ((r['pay_ref'] ?? '') != '') ('پیگیری بانک', r['pay_ref'].toString()),
      if ((r['pay_tracking'] ?? '') != '') ('پیگیری واریز', faDigits(r['pay_tracking'])),
      if ((r['reject_reason'] ?? '') != '') ('دلیل رد', r['reject_reason'].toString()),
      ('زمان ثبت', DateTime.tryParse('${r['created_at']}') == null ? '' : relativeTime(DateTime.parse('${r['created_at']}'))),
    ];
    final canPaid = const ['pending_payment', 'pending_review', 'expired'].contains(st);
    final canApprove = st == 'pending_approval';
    final canReject = st != 'rejected' && !(st == 'confirmed' && r['attendee_id'] != null);
    final act = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${r['first_name']} ${r['last_name']}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 130, child: Text(k, style: TextStyle(color: DaftarColors.of(c).inkMuted))),
                    Expanded(child: SelectableText(v)),
                  ]),
                ),
              if (r['has_receipt'] == true) ...[
                const SizedBox(height: DaftarSize.space2),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(icon: const Icon(Icons.receipt_long_rounded), label: const Text('دیدن رسید'), onPressed: () => _receipt(r)),
                ),
              ],
              if (canReject) ...[
                const SizedBox(height: DaftarSize.space3),
                DaftarField(
                  label: 'دلیل رد',
                  optional: true,
                  helper: 'به خود فرد در «پیگیری ثبت‌نام» نشان داده می‌شود. پول پرداخت‌شده خودکار برنمی‌گردد.',
                  child: TextField(controller: reason),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن')),
          if (canReject) TextButton(style: TextButton.styleFrom(foregroundColor: DaftarColors.of(c).stop), onPressed: () => Navigator.pop(c, 'reject'), child: const Text('رد')),
          if (canPaid) FilledButton(onPressed: () => Navigator.pop(c, 'mark_paid'), child: const Text('پرداخت شد')),
          if (canApprove) FilledButton(onPressed: () => Navigator.pop(c, 'approve'), child: const Text('تأیید')),
        ],
      ),
    );
    if (act == null || !mounted) return;
    await s.regAction(r['id'] as int, act, reason: reason.text.trim());
  }

  Future<void> _receipt(Map<String, dynamic> r) async {
    final s = StateScope.read(context);
    final res = await s.run('', () => s.loadReceipt(r['id'] as int));
    s.message = null;
    if (res == null || !mounted) return;
    final (mime, bytes) = res;
    if (mime == 'application/pdf') {
      await saveBytesAs(s, 'receipt-${r['code']}.pdf', 'pdf', bytes);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('رسید ${r['code']}'),
        content: InteractiveViewer(child: Image.memory(bytes)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن'))],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final String text;
  final NoticeTone tone;
  const _StatusTag({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final (bg, fg) = switch (tone) {
      NoticeTone.go => (x.goSoft, x.go),
      NoticeTone.stop => (x.stopSoft, x.stop),
      NoticeTone.wait => (x.waitSoft, x.wait),
      _ => (x.sunken, x.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
