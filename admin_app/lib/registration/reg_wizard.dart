// راه‌اندازی ثبت‌نام آنلاین در ۷ گام (بوم‌های ۲۰ تا ۲۶ اندروید؛ ۱۱ تا ۱۷ ویندوز با چیدمان سه‌ستونه).
// همان تنظیم‌های پیشخوان وردپرس؛ هر گام با «ذخیره و بعدی» روی سرور می‌رود.
import 'dart:math';

import 'package:flutter/material.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../main.dart';
import '../normalize.dart';
import 'reg_api.dart';
import 'reg_widgets.dart';

const regStepTitles = [
  'آدرس و ورود به لیست',
  'محتوا و ظاهر',
  'نوع‌ها و ظرفیت',
  'اطلاعات بیشتر و گزینه‌ها',
  'پرداخت',
  'پیام به ثبت‌نام‌کننده',
  'پیش‌نمایش و انتشار',
];

class RegWizardPage extends StatefulWidget {
  final RegEditor editor;
  final int step;
  const RegWizardPage({super.key, required this.editor, this.step = 1});

  @override
  State<RegWizardPage> createState() => _RegWizardPageState();
}

class _RegWizardPageState extends State<RegWizardPage> {
  late RegEditor ed = widget.editor;
  late int step = widget.step;
  int _rev = 0; // با هر بارگذاری دوباره، فیلدها از نو ساخته می‌شوند
  String? _error;

  Map<String, dynamic> get cfg => ed.config;
  Map<String, dynamic> m(String k) => (cfg[k] as Map).cast<String, dynamic>();

  void _set(VoidCallback f) => setState(f);

  String? _validate() {
    final path = '${cfg['path'] ?? ''}';
    if (step == 1 && !RegExp(r'^[a-z0-9][a-z0-9-]{1,60}$').hasMatch(path)) {
      return 'آدرس صفحه را بنویسید: فقط حروف کوچک انگلیسی، رقم و خط تیره، دست‌کم ۲ حرف.';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,60}$').hasMatch(path)) return 'اول آدرس صفحه را در گام ۱ بنویسید.';
    return null;
  }

  Future<void> _save({int? next, String? status}) async {
    final err = _validate();
    if (err != null) return setState(() => _error = err);
    if (status != null) cfg['status'] = status;
    final s = StateScope.read(context);
    final r = await s.saveRegPage(cfg, ok: status == 'open' ? 'ثبت‌نام باز شد.' : 'ذخیره شد.');
    if (!mounted || r == null) return setState(() => _error = s.message);
    setState(() {
      ed = r;
      _rev++;
      _error = null;
      if (next != null) step = next;
    });
    if (next == null && status != null && mounted) Navigator.of(context).maybePop(r);
  }

  @override
  Widget build(BuildContext context) {
    final wide = regWide(context);
    final body = KeyedSubtree(key: ValueKey('$step-$_rev'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap([
      if (_error != null) NvBanner(tone: NvTone.stop, text: _error!),
      ..._step(context),
    ])));
    final foot = Row(children: [
      Expanded(
        flex: 10,
        child: NvSoftButton(label: 'قبلی', onPressed: step > 1 ? () => setState(() => step--) : null),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 18,
        child: NvButton(
          label: step < 7 ? 'ذخیره و بعدی' : (cfg['status'] == 'open' ? 'ذخیره' : 'ذخیره به‌صورت پیش‌نویس'),
          busy: StateScope.of(context).busy,
          onPressed: () => _save(next: step < 7 ? step + 1 : null, status: step == 7 && cfg['status'] != 'open' ? 'draft' : null),
        ),
      ),
    ]);
    if (!wide) {
      return RegScaffold(
        title: regStepTitles[step - 1],
        subtitle: 'راه‌اندازی ثبت‌نام آنلاین · گام ${faDigits(step)} از ۷',
        step: step,
        overlap: 26,
        bottom: foot,
        children: [body],
      );
    }
    // ویندوز: گام‌ها | فرم | پیش‌نمایش زنده
    return RegScaffold(
      title: 'صفحه‌ی ثبت‌نام',
      subtitle: '${StateScope.of(context).event?.name ?? ''} · گام ${faDigits(step)} از ۷ · ${regStepTitles[step - 1]}',
      maxWidth: 1240,
      overlap: 36,
      bottom: Align(alignment: AlignmentDirectional.centerStart, heightFactor: 1, child: SizedBox(width: 460, child: foot)),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 250, child: _StepList(step: step, onTap: (i) => setState(() => step = i))),
          const SizedBox(width: 16),
          Expanded(child: body),
          const SizedBox(width: 16),
          SizedBox(width: 300, child: RegPreview(ed: ed)),
        ]),
      ],
    );
  }

  static List<Widget> _gap(List<Widget> w) => [for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 12), w[i]]];

  List<Widget> _step(BuildContext context) => switch (step) {
        1 => _s1(context),
        2 => _s2(context),
        3 => _s3(context),
        4 => _s4(context),
        5 => _s5(context),
        6 => _s6(context),
        _ => _s7(context),
      };

  // ---------------------------------------------------------------- ۱ آدرس و ورود به لیست
  List<Widget> _s1(BuildContext context) {
    final c = NvColors.of(context);
    final base = ed.home.replaceFirst(RegExp(r'^https?://'), '');
    final path = '${cfg['path'] ?? ''}';
    final okPath = RegExp(r'^[a-z0-9][a-z0-9-]{1,60}$').hasMatch(path);
    return [
      RegCard(title: 'آدرس صفحه‌ی ثبت‌نام', hint: 'شرکت‌کنندگان با این آدرس وارد می‌شوند. آدرس را شما تعیین می‌کنید.', raised: true, children: [
        Text('$base${cfg['use_prefix'] == true ? 'register/' : ''}', textDirection: TextDirection.ltr, style: nvText(context, 12, color: c.muted)),
        RegText('', cfg, 'path', ltr: true, hint: 'vision-1405', onChanged: (_) => _set(() {})),
        if (path.isNotEmpty)
          Row(children: [
            Icon(okPath ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: okPath ? c.go : c.stop),
            const SizedBox(width: 6),
            Expanded(
              child: Text(okPath ? 'قالب آدرس درست است؛ تکراری‌بودن هنگام ذخیره بررسی می‌شود.' : 'فقط حروف کوچک انگلیسی، رقم و خط تیره؛ دست‌کم ۲ حرف.',
                  style: nvText(context, 12, color: okPath ? c.go : c.stop)),
            ),
          ]),
        RegToggle(
          title: 'با پیشوند register/',
          hint: 'تا آدرس با برگه‌های سایت قاطی نشود.',
          value: cfg['use_prefix'] == true,
          onChanged: (v) => _set(() => cfg['use_prefix'] = v),
        ),
      ]),
      RegCard(title: 'ثبت‌نام‌کننده کی وارد لیست شرکت‌کننده‌ها شود؟', children: [
        for (final o in const [
          ('direct', 'مستقیم', 'هر ثبت‌نام قطعی فوراً شرکت‌کننده می‌شود، با کارت و شماره.'),
          ('approval', 'با تأیید مدیر', 'ثبت‌نام‌ها در «ثبت‌نام‌ها» منتظر تأیید شما می‌مانند.'),
          ('separate', 'جدا', 'فقط فهرست و خروجی اکسل؛ ورود به لیست با اکسل.'),
        ])
          RegOption(title: o.$2, hint: o.$3, selected: cfg['list_mode'] == o.$1, onTap: () => _set(() => cfg['list_mode'] = o.$1)),
      ]),
      RegCard(title: 'وضعیت صفحه', hint: 'پیش‌نویس فقط برای مدیر واردشده پیش‌نمایش دارد. صفحه را در گام آخر باز می‌کنید.', children: [
        RegSeg<String>(
          value: '${cfg['status']}',
          options: const [('draft', 'پیش‌نویس'), ('open', 'باز'), ('closed', 'بسته')],
          onChanged: (v) => _set(() => cfg['status'] = v),
        ),
      ]),
    ];
  }

  // ---------------------------------------------------------------- ۲ محتوا و ظاهر
  List<Widget> _s2(BuildContext context) {
    final content = m('content');
    final theme = m('theme');
    return [
      RegCard(title: 'محتوای صفحه', raised: true, children: [
        RegText('تیتر', content, 'title', optional: true, helper: 'خالی = نام رویداد', onChanged: (_) => _set(() {})),
        RegText('زیرتیتر', content, 'subtitle', optional: true),
        RegText('توضیح', content, 'description', lines: 3, optional: true),
        RegText('روزها (هر خط یک روز)', content, 'days', lines: 2, hint: '۱۴ و ۱۵ آذر ۱۴۰۵', onChanged: (_) => _set(() {})),
        RegText('مکان (هر خط یک بخش)', content, 'venue', lines: 2, hint: 'دانشگاه کاشان، تالار آزادی', onChanged: (_) => _set(() {})),
        RegText('نشانی لوگو', content, 'logo_url', ltr: true, optional: true),
        RegText('نشانی تصویر سربرگ', content, 'cover_url', ltr: true, optional: true),
        RegText('سایت رویداد', content, 'site_url', ltr: true, optional: true),
        RegText('تماس دبیرخانه', content, 'contact', ltr: true, optional: true),
        RegText('متن صفحه‌ی بسته', content, 'closed_text', lines: 2, optional: true),
      ]),
      RegCard(title: 'ظاهر', hint: 'رنگ برند صفحه؛ رنگ‌های معنایی (تأیید، هشدار، خطا) عوض نمی‌شوند.', children: [
        Wrap(spacing: 12, children: [
          for (final hex in const ['#0B7A7B', '#1D5FD1', '#6B3FA0', '#B34A00'])
            Semantics(
              button: true,
              selected: '${theme['accent']}'.toUpperCase() == hex,
              label: hex,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _set(() => theme['accent'] = hex),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                    shape: BoxShape.circle,
                    border: '${theme['accent']}'.toUpperCase() == hex ? Border.all(color: NvColors.of(context).ink, width: 3) : null,
                  ),
                ),
              ),
            ),
        ]),
        RegSeg<String>(
          value: '${theme['mode']}',
          options: const [('light', 'زمینه‌ی روشن'), ('dark', 'زمینه‌ی تیره')],
          onChanged: (v) => _set(() => theme['mode'] = v),
        ),
        RegToggle(
          title: 'خط سازنده',
          hint: '«ساخته‌شده با رویدادیار» پایین صفحه',
          value: theme['maker_credit'] != false,
          onChanged: (v) => _set(() => theme['maker_credit'] = v),
        ),
      ]),
    ];
  }

  // ---------------------------------------------------------------- ۳ نوع‌ها و ظرفیت
  List<Widget> _s3(BuildContext context) {
    final c = NvColors.of(context);
    final types = (cfg['types'] as List).cast<Map>();
    return [
      if (types.isEmpty)
        const NvBanner(tone: NvTone.wait, text: 'هنوز نوع ثبت‌نامی نیست. اول در «تنظیم رویداد» نوع‌ها را بسازید (مثل شرکت‌کننده و دانشجو).'),
      for (final t in types)
        RegCard(
          title: ed.typeName('${t['code']}'),
          raised: t == types.first,
          trailing: Switch(value: t['visible'] != false, onChanged: (v) => _set(() => t['visible'] = v)),
          children: [
            if (t['visible'] == false) Text('در فرم دیده نمی‌شود.', style: nvText(context, 12, color: c.muted)),
            RegText('توضیح زیر نام', t, 'description', optional: true),
            Row(children: [
              Expanded(child: RegText('قیمت (تومان)', t, 'price', number: true, helper: 'صفر = رایگان')),
              const SizedBox(width: 10),
              Expanded(child: RegText('ظرفیت', t, 'capacity', number: true, helper: 'صفر = نامحدود')),
            ]),
            RegText('مهلت این نوع', t, 'deadline', ltr: true, optional: true, hint: '1405-09-10 18:00', helper: 'به وقت تهران؛ شمسی یا میلادی'),
          ],
        ),
      RegCard(title: 'ظرفیت و مهلت کل', children: [
        Row(children: [
          Expanded(child: RegText('ظرفیت کل', cfg, 'capacity_total', number: true, helper: 'صفر = نامحدود')),
          const SizedBox(width: 10),
          Expanded(child: RegText('مهلت کل', cfg, 'deadline', ltr: true, optional: true, hint: '1405-09-10 18:00')),
        ]),
        Text('با تمام شدن ظرفیت یا مهلت (کل یا هر نوع)، صفحه یا آن نوع بسته می‌شود.', style: nvText(context, 12, color: c.muted)),
      ]),
    ];
  }

  // ---------------------------------------------------------------- ۴ اطلاعات بیشتر و گزینه‌ها
  String _rid(String p) => '$p${Random().nextInt(1 << 30).toRadixString(36)}';

  Widget _typeChips(Map item) {
    final list = ((item['types'] as List?) ?? []).map((e) => '$e').toList();
    item['types'] = list;
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('برای نوع‌ها (هیچ = همه):', style: nvText(context, 12, color: NvColors.of(context).muted)),
      for (final t in ed.types)
        FilterChip(
          label: Text('${t['name']}'),
          selected: list.contains(t['code']),
          onSelected: (v) => _set(() => v ? list.add('${t['code']}') : list.remove(t['code'])),
        ),
    ]);
  }

  List<Widget> _s4(BuildContext context) {
    final fields = m('fields');
    final custom = (cfg['custom_fields'] as List).cast<Map>();
    final addons = (cfg['addons'] as List).cast<Map>();
    final meals = <(String, String)>[('', 'وصل نیست'), for (final x in ed.meals) ('${x['code']}', '${x['name']}${'${x['day'] ?? ''}'.isEmpty ? '' : ' (${x['day']})'}')];
    return [
      RegCard(title: 'فیلدهای فرم', hint: 'نام، نام خانوادگی و موبایل همیشه الزامی است.', raised: true, children: [
        Text('ایمیل', style: nvText(context, 13, w: FontWeight.w700)),
        RegSeg<String>(value: '${fields['email']}', options: const [('required', 'الزامی'), ('optional', 'اختیاری'), ('hidden', 'پنهان')], onChanged: (v) => _set(() => fields['email'] = v)),
        Text('دانشگاه یا سازمان', style: nvText(context, 13, w: FontWeight.w700)),
        RegSeg<String>(value: '${fields['organization']}', options: const [('required', 'الزامی'), ('optional', 'اختیاری'), ('hidden', 'پنهان')], onChanged: (v) => _set(() => fields['organization'] = v)),
      ]),
      RegCard(title: 'اطلاعات بیشتر', hint: 'پرسش‌های دلخواه، مثل رشته یا کارگاه‌ها.', children: [
        for (final f in custom)
          _Sub(onDelete: () => _set(() => custom.remove(f)), children: [
            RegText('عنوان پرسش', f, 'label'),
            RegSeg<String>(
              value: '${f['kind'] ?? 'text'}',
              options: const [('text', 'متن کوتاه'), ('select', 'تک‌انتخابی'), ('multi', 'چندانتخابی')],
              onChanged: (v) => _set(() => f['kind'] = v),
            ),
            RegText('راهنما', f, 'help', optional: true),
            RegToggle(title: 'الزامی', value: f['required'] == true, onChanged: (v) => _set(() => f['required'] = v)),
            if (f['kind'] != 'text') _OptionsField(field: f),
            _typeChips(f),
          ]),
        NvSoftButton(
          label: 'افزودن پرسش',
          icon: Icons.add_rounded,
          onPressed: () => _set(() => custom.add({'id': _rid('f'), 'label': '', 'kind': 'text', 'required': false, 'help': '', 'options': [], 'types': []})),
        ),
      ]),
      RegCard(title: 'گزینه‌های اضافه', hint: 'مثل ناهار یا شام؛ با پرداخت آنلاین، در محل، یا فقط اطلاع.', children: [
        for (final a in addons)
          _Sub(onDelete: () => _set(() => addons.remove(a)), children: [
            RegText('عنوان', a, 'title'),
            RegText('توضیح زیرش', a, 'description', optional: true),
            Row(children: [
              Expanded(child: RegText('قیمت (تومان)', a, 'price', number: true)),
              const SizedBox(width: 10),
              Expanded(child: RegText('ظرفیت', a, 'capacity', number: true, helper: 'صفر = نامحدود')),
            ]),
            RegSeg<String>(
              value: '${a['price_mode'] ?? 'online'}',
              options: const [('online', 'روی مبلغ آنلاین'), ('onsite', 'در محل'), ('info', 'فقط اطلاع')],
              onChanged: (v) => _set(() => a['price_mode'] = v),
            ),
            Text('وعده‌ی پذیرایی', style: nvText(context, 13, w: FontWeight.w700)),
            DropdownButtonFormField<String>(
              initialValue: meals.any((x) => x.$1 == '${a['meal_code'] ?? ''}') ? '${a['meal_code'] ?? ''}' : '',
              items: [for (final x in meals) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
              onChanged: (v) => _set(() => a['meal_code'] = v ?? ''),
            ),
            Text('کسی که این گزینه را بزند، در اپ نیروها برای این وعده مجاز می‌شود.', style: nvText(context, 12, color: NvColors.of(context).muted)),
            _typeChips(a),
          ]),
        NvSoftButton(
          label: 'افزودن گزینه',
          icon: Icons.add_rounded,
          onPressed: () => _set(() => addons.add({'id': _rid('a'), 'title': '', 'description': '', 'price': 0, 'price_mode': 'online', 'capacity': 0, 'meal_code': '', 'types': []})),
        ),
      ]),
    ];
  }

  // ---------------------------------------------------------------- ۵ پرداخت
  List<Widget> _s5(BuildContext context) {
    final c = NvColors.of(context);
    final p = m('payment');
    final card = (p['card'] as Map).cast<String, dynamic>();
    // PHP تنظیم خالی را [] می‌فرستد، نه {}.
    final raw = p['gateway_settings'];
    final gs = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    p['gateway_settings'] = gs;
    final gw = ed.gateways.where((g) => g['id'] == p['gateway']).firstOrNull;
    return [
      RegCard(title: 'روش پرداخت', hint: 'فقط وقتی نوع یا گزینه‌ای مبلغ آنلاین دارد.', raised: true, children: [
        for (final o in const [
          ('gateway', 'درگاه بانکی', 'پرداخت آنلاین؛ جا ۳۰ دقیقه نگه داشته می‌شود.'),
          ('card', 'کارت‌به‌کارت', 'شماره کارت نشان داده می‌شود و فرد رسید را ثبت می‌کند.'),
          ('link', 'لینک بیرونی', 'پرداخت در سایت دیگر و ثبت شماره‌ی پیگیری.'),
        ])
          RegOption(title: o.$2, hint: o.$3, selected: p['method'] == o.$1, onTap: () => _set(() => p['method'] = o.$1)),
      ]),
      if (p['method'] == 'gateway')
        RegCard(title: 'درگاه', children: [
          DropdownButtonFormField<String>(
            initialValue: ed.gateways.any((g) => g['id'] == p['gateway']) ? '${p['gateway']}' : null,
            items: [for (final g in ed.gateways) DropdownMenuItem(value: '${g['id']}', child: Text('${g['name']}'))],
            onChanged: (v) => _set(() => p['gateway'] = v),
          ),
          for (final f in ((gw?['fields'] as List?) ?? []).cast<Map>()) RegText('${f['label']}', gs, '${f['key']}', ltr: true),
          if (p['gateway'] == 'custom')
            const NvBanner(tone: NvTone.info, text: 'آدرس شروع، آدرس تأیید، هدر و بدنه‌ی «درگاه دلخواه» در «اتصال درگاه و پیامک» تنظیم می‌شود.'),
          Text('برای آزمون یک پرداخت واقعی ۱۰۰ تومانی، صفحه را ذخیره کنید و در «اتصال درگاه و پیامک» «آزمون با ۱۰۰ تومان» را بزنید.',
              style: nvText(context, 12, color: c.muted, height: 1.6)),
        ]),
      if (p['method'] == 'card')
        RegCard(title: 'مشخصات حساب', children: [
          RegText('شماره کارت', card, 'number', ltr: true, hint: '6037 …'),
          RegText('شبا', card, 'sheba', ltr: true, optional: true, hint: 'IR…'),
          RegText('صاحب حساب', card, 'holder'),
          RegText('بانک', card, 'bank', optional: true),
          RegText('توضیح', card, 'text', lines: 2, optional: true),
          Text('از فرد بخواهد', style: nvText(context, 13, w: FontWeight.w700)),
          RegSeg<String>(
            value: '${card['require'] ?? 'code'}',
            options: const [('code', 'شماره‌ی پیگیری'), ('receipt', 'تصویر رسید'), ('both', 'هر دو')],
            onChanged: (v) => _set(() => card['require'] = v),
          ),
        ]),
      if (p['method'] == 'link')
        RegCard(title: 'لینک پرداخت', children: [
          RegText('نشانی لینک', p, 'link_url', ltr: true),
          RegText('توضیح', p, 'link_text', lines: 2, optional: true),
        ]),
      if (p['method'] != 'gateway')
        RegCard(children: [RegText('نگه‌داشتن جا (ساعت)', p, 'hold_hours', number: true, helper: 'اگر تا این مدت رسید یا تأیید پرداخت نیاید، جا آزاد می‌شود (۱ تا ۷۲۰).')]),
    ];
  }

  // ---------------------------------------------------------------- ۶ پیام‌ها
  List<Widget> _s6(BuildContext context) {
    final msg = m('messages');
    final tpl = ((msg['templates'] as Map?) ?? {}).cast<String, dynamic>();
    msg['templates'] = tpl;
    return [
      RegCard(title: 'کانال ارسال', raised: true, children: [
        RegToggle(title: 'پیامک', hint: 'با سرویسی که در «اتصال درگاه و پیامک» وصل شده.', value: msg['sms'] == true, onChanged: (v) => _set(() => msg['sms'] = v)),
        RegToggle(title: 'ایمیل', hint: 'اگر وارد کرده باشد؛ با ایمیل خود سایت.', value: msg['email'] == true, onChanged: (v) => _set(() => msg['email'] = v)),
      ]),
      RegCard(title: 'متن پیام‌ها', hint: 'متن خالی = برای آن وضعیت پیامی نمی‌رود.', children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in regMessageVars)
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: NvColors.of(context).lineSoft)),
              child: Text(v, textDirection: TextDirection.ltr, style: nvText(context, 12, w: FontWeight.w700, color: NvColors.of(context).brandText)),
            ),
        ]),
        for (final e in regTriggers.entries) RegText(e.value, tpl, e.key, lines: 2, optional: true),
      ]),
    ];
  }

  // ---------------------------------------------------------------- ۷ پیش‌نمایش و انتشار
  List<Widget> _s7(BuildContext context) {
    final c = NvColors.of(context);
    final success = m('success');
    final content = m('content');
    final types = (cfg['types'] as List).cast<Map>().where((t) => t['visible'] != false).toList();
    final p = m('payment');
    final paid = types.any((t) => (t['price'] as num? ?? 0) > 0) || (cfg['addons'] as List).cast<Map>().any((a) => a['price_mode'] == 'online' && (a['price'] as num? ?? 0) > 0);
    final payOk = !paid ||
        switch ('${p['method']}') {
          'card' => '${(p['card'] as Map)['number'] ?? ''}'.isNotEmpty,
          'link' => '${p['link_url'] ?? ''}'.isNotEmpty,
          _ => true,
        };
    final checks = <(bool?, String, int)>[
      (RegExp(r'^[a-z0-9][a-z0-9-]{1,60}$').hasMatch('${cfg['path']}'), 'آدرس: ${cfg['path']}', 1),
      ('${(content['days'] as List?)?.join() ?? ''}${(content['venue'] as List?)?.join() ?? ''}'.isNotEmpty, 'زمان و مکان پر است', 2),
      (types.isNotEmpty, '${faDigits(types.length)} نوع قابل دیدن', 3),
      (payOk, paid ? 'پرداخت ${regPayMethods[p['method']] ?? ''} کامل است' : 'همه‌ی نوع‌ها رایگان‌اند', 5),
      ((m('messages')['sms'] == true || m('messages')['email'] == true) ? true : null, 'پیام به ثبت‌نام‌کننده (اختیاری)', 6),
    ];
    final url = ed.url;
    return [
      RegCard(title: 'آمادگی برای انتشار', raised: true, children: [
        for (final x in checks)
          InkWell(
            onTap: x.$1 == true ? null : () => setState(() => step = x.$3),
            child: Row(children: [
              Icon(x.$1 == true ? Icons.check_circle_rounded : Icons.warning_rounded, color: x.$1 == true ? c.go : c.wait),
              const SizedBox(width: 10),
              Expanded(child: Text(x.$2, style: nvText(context, 14))),
              if (x.$1 != true) Text('گام ${faDigits(x.$3)}', style: nvText(context, 12, w: FontWeight.w800, color: c.brandText)),
            ]),
          ),
      ]),
      if (!regWide(context)) RegCard(title: 'پیش‌نمایش صفحه', children: [Center(child: SizedBox(width: 240, child: RegPreview(ed: ed, compact: true)))]),
      RegCard(title: 'صفحه‌ی تأیید (بعد از ثبت‌نام قطعی)', children: [
        RegToggle(
          title: 'لینک صفحه‌ی شخصی (QR) نشان داده شود',
          hint: 'فقط وقتی ثبت‌نام قطعی و فرد وارد لیست شده.',
          value: success['show_personal_link'] != false,
          onChanged: (v) => _set(() => success['show_personal_link'] = v),
        ),
        RegText('متن اضافه', success, 'text', lines: 2, optional: true),
      ]),
      if (url != null)
        RegCard(title: 'لینک ثبت‌نام', children: [
          Row(children: [
            Expanded(child: Text(url, textDirection: TextDirection.ltr, style: nvText(context, 13, w: FontWeight.w700))),
            RegCopy(url),
          ]),
        ]),
      NvButton(
        label: cfg['status'] == 'open' ? 'ثبت‌نام باز است · ذخیره' : 'باز کردن ثبت‌نام',
        icon: Icons.rocket_launch_rounded,
        color: c.go,
        onPressed: checks.take(4).every((x) => x.$1 == true) ? () => _save(status: 'open') : null,
      ),
      Text('هر وقت خواستید از صفحه‌ی ثبت‌نام «بسته» کنید؛ ثبت‌شده‌ها می‌مانند.', textAlign: TextAlign.center, style: nvText(context, 12, color: c.muted)),
    ];
  }
}

/// زیرکارت پرسش یا گزینه با دکمه‌ی حذف.
class _Sub extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onDelete;
  const _Sub({required this.children, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nv.r16), border: Border.all(color: c.lineSoft)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final w in children) ...[w, const SizedBox(height: 10)],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.stop),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('حذف'),
          ),
        ),
      ]),
    );
  }
}

/// گزینه‌های پرسش انتخابی: هر خط یک گزینه، ظرفیت اختیاری «کارگاه | 30».
class _OptionsField extends StatelessWidget {
  final Map field;
  const _OptionsField({required this.field});

  @override
  Widget build(BuildContext context) {
    final opts = ((field['options'] as List?) ?? []).cast<Map>();
    final holder = {'v': opts.map((o) => '${o['label']}${(o['capacity'] ?? 0) > 0 ? ' | ${o['capacity']}' : ''}').join('\n')};
    return RegText('گزینه‌ها', holder, 'v', lines: 3, helper: 'هر خط یک گزینه؛ ظرفیت اختیاری: «کارگاه پزشکی | 30»', onChanged: (v) {
      final old = opts;
      final lines = v.split('\n');
      field['options'] = [
        for (var j = 0; j < lines.length; j++)
          if (lines[j].split('|').first.trim().isNotEmpty)
            {
              'id': j < old.length && old[j]['label'] == lines[j].split('|').first.trim() ? old[j]['id'] : 'o${Random().nextInt(1 << 30).toRadixString(36)}',
              'label': lines[j].split('|').first.trim(),
              'capacity': int.tryParse(latinDigits(lines[j].contains('|') ? lines[j].split('|')[1].trim() : '0')) ?? 0,
            },
      ];
    });
  }
}

/// گام‌های ویزارد در ستون کنار (ویندوز).
class _StepList extends StatelessWidget {
  final int step;
  final ValueChanged<int> onTap;
  const _StepList({required this.step, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvCard(
      raised: true,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 1; i <= 7; i++)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: i == step
                  ? BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.brand, width: 2))
                  : null,
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i == step ? c.brand : (i < step ? c.go : c.field), shape: BoxShape.circle),
                  child: i < step
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : Text(faDigits(i), style: nvText(context, 12, w: FontWeight.w800, color: i == step ? c.onBrand : c.muted)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(regStepTitles[i - 1], style: nvText(context, 13, w: i == step ? FontWeight.w800 : FontWeight.w500))),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text('همین تنظیم‌ها در پیشخوان وردپرس هم هست؛ هر کدام را عوض کنید، دیگری همان را می‌بیند.',
              style: nvText(context, 12, color: c.muted, height: 1.6)),
        ),
      ]),
    );
  }
}

/// پیش‌نمایش کوچک صفحه‌ی عمومی با داده‌ی همین تنظیم (بدون ساختن ثبت‌نام).
class RegPreview extends StatelessWidget {
  final RegEditor ed;
  final bool compact;
  const RegPreview({super.key, required this.ed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final cfg = ed.config;
    final content = (cfg['content'] as Map).cast<String, dynamic>();
    final accentHex = '${(cfg['theme'] as Map)['accent'] ?? '#0B7A7B'}';
    final accent = Color(int.tryParse('FF${accentHex.replaceFirst('#', '')}', radix: 16) ?? 0xFF0B7A7B);
    final title = '${content['title'] ?? ''}'.isNotEmpty ? '${content['title']}' : (StateScope.of(context).event?.name ?? 'ثبت‌نام');
    final types = (cfg['types'] as List).cast<Map>().where((t) => t['visible'] != false).toList();
    final meta = [(content['days'] as List?)?.join('، ') ?? '', (content['venue'] as List?)?.join('، ') ?? ''].where((e) => e.isNotEmpty).join(' · ');
    return NvCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Expanded(child: Text('پیش‌نمایش زنده', style: nvText(context, 14, w: FontWeight.w800))),
              Icon(Icons.smartphone_rounded, size: 18, color: c.muted),
            ]),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.lineSoft)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 34),
              decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ثبت‌نام آنلاین', style: nvText(context, 10, color: Colors.white.withValues(alpha: .85))),
                Text(title, style: nvText(context, 14, w: FontWeight.w800, color: Colors.white, height: 1.5)),
                if (meta.isNotEmpty) Text(meta, style: nvText(context, 10, color: Colors.white.withValues(alpha: .9))),
              ]),
            ),
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('نوع حضور', style: nvText(context, 11, w: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (types.isEmpty) Text('نوعی دیده نمی‌شود', style: nvText(context, 10, color: c.muted)),
                  for (var i = 0; i < types.length && i < 4; i++) ...[
                    Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(
                        color: i == 0 ? accent.withValues(alpha: .09) : null,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: i == 0 ? accent : c.lineSoft, width: i == 0 ? 2 : 1),
                      ),
                      child: Text('${ed.typeName('${types[i]['code']}')} · ${regMoney((types[i]['price'] as num?) ?? 0, unit: false, free: true)}',
                          style: nvText(context, 10, w: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                    ),
                    const SizedBox(height: 6),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text('پیش‌نمایش با داده‌ی نمونه است؛ هیچ ثبت‌نامی ساخته نمی‌شود.', style: nvText(context, 11, color: c.muted)),
          ),
      ]),
    );
  }
}
