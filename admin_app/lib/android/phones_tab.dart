// تب «گوشی‌ها و کارکنان» (طرح ۹ تا ۱۱): وضعیت گوشی‌های نیروها، جزئیات و لغو دسترسی،
// و کارکنان با دسترسی‌ها و PIN که فقط یک بار نشان داده می‌شود.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import 'nv_admin.dart';
import 'nv_theme.dart';
import 'nv_widgets.dart';
import 'person_page.dart' show confirmDanger;

class PhonesTab extends StatefulWidget {
  const PhonesTab({super.key});

  @override
  State<PhonesTab> createState() => _PhonesTabState();
}

class _PhonesTabState extends State<PhonesTab> {
  bool _staff = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final s = StateScope.read(context);
    await s.loadReport();
    if (s.messageIsError) s.message = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final devices = s.deviceList;
    final active = devices.where((d) => d['revoked'] != true).length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        NvTabHeader(line: '${faDigits(active)} گوشی · ${faDigits(s.staff.length)} نفر کارکنان', title: 'گوشی‌ها و کارکنان', bottom: 60),
        Transform.translate(
          offset: const Offset(0, -30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r16), boxShadow: Nv.raised(c)),
                child: Row(children: [
                  for (final (on, label) in [(false, 'گوشی‌ها'), (true, 'کارکنان')])
                    Expanded(
                      child: Material(
                        color: _staff == on ? c.brand : Colors.transparent,
                        borderRadius: BorderRadius.circular(Nv.r12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Nv.r12),
                          onTap: () => setState(() => _staff = on),
                          child: SizedBox(
                            height: 44,
                            child: Center(child: Text(label, style: nvText(context, 14, w: FontWeight.w800, color: _staff == on ? c.onBrand : c.ink))),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              if (_staff) const _StaffList() else _DeviceList(devices: devices),
            ]),
          ),
        ),
      ]),
    );
  }
}

int? _silentMinutes(Map<String, dynamic> d) {
  final last = DateTime.tryParse('${d['last_sync_at'] ?? ''}')?.toLocal();
  return last == null ? null : DateTime.now().difference(last).inMinutes;
}

String _ago(int? mins) {
  if (mins == null) return 'هنوز وصل نشده';
  if (mins < 1) return 'الان';
  if (mins < 60) return '${faDigits(mins)} دقیقه پیش';
  if (mins < 60 * 24) return '${faDigits(mins ~/ 60)} ساعت پیش';
  return '${faDigits(mins ~/ (60 * 24))} روز پیش';
}

class _DeviceList extends StatelessWidget {
  final List<Map<String, dynamic>> devices;
  const _DeviceList({required this.devices});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    if (s.report == null) return const LinearProgressIndicator();
    final silent = devices.where((d) => d['revoked'] != true && (_silentMinutes(d) ?? 0) > 10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in silent)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NvBanner(
            tone: NvTone.wait,
            icon: Icons.wifi_off_rounded,
            title: '«${d['label']}» ${faDigits(_silentMinutes(d)!)} دقیقه است به سرور نرسیده',
            text: (d['pending'] ?? 0) > 0
                ? 'آخرین گزارشش: ${faDigits(d['pending'])} مورد در صف ارسال. کارها روی خود گوشی امن است.'
                : 'کارهای ثبت‌شده روی خود گوشی امن است و با اینترنت می‌رسد.',
          ),
        ),
      if (devices.isEmpty)
        NvCard(child: Text('هنوز گوشی‌ای وارد نشده.', style: nvText(context, 14, color: c.muted)))
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Column(children: [
            for (var i = 0; i < devices.length; i++) _DeviceRow(d: devices[i], last: i == devices.length - 1),
          ]),
        ),
      const SizedBox(height: 14),
      NvBanner(
        tone: NvTone.info,
        icon: Icons.qr_code_2_rounded,
        text: 'برای وصل کردن گوشی تازه، در اپ نیروها کد رویداد «${s.event?.code ?? ''}» و PIN همان نیرو را وارد کنید. نیرو و PIN را در «کارکنان» بسازید.',
      ),
    ]);
  }
}

class _DeviceRow extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool last;
  const _DeviceRow({required this.d, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final revoked = d['revoked'] == true;
    final mins = _silentMinutes(d);
    final online = !revoked && mins != null && mins <= 10;
    final roles = ((d['roles'] as List?) ?? const []).join('، ');
    return Opacity(
      opacity: revoked ? .55 : 1,
      child: InkWell(
        onTap: () => showNvSheet<void>(context, (_) => _DeviceSheet(d: d)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.lineSoft))),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
              child: Icon(revoked ? Icons.phonelink_erase_rounded : Icons.smartphone_rounded, color: c.brandText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['label'] ?? 'گوشی بی‌نام'}', style: nvText(context, 15, w: FontWeight.w800)),
                Text(
                  revoked
                      ? 'لغو شده · ${_ago(mins)}'
                      : [if ('${d['staff'] ?? ''}'.isNotEmpty) '${d['staff']}', if (roles.isNotEmpty) roles, 'آخرین ارتباط: ${_ago(mins)}'].join(' · '),
                  style: nvText(context, 12, color: c.muted),
                ),
              ]),
            ),
            if (!revoked)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                online
                    ? NvStatusChip(text: 'آنلاین', icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go)
                    : NvStatusChip(text: 'آفلاین', icon: Icons.wifi_off_rounded, bg: c.waitSoft, fg: c.wait),
                const SizedBox(height: 4),
                Text(
                  (d['pending'] ?? 0) > 0 && !online ? '${faDigits(d['pending'])} در صف' : '${faDigits(d['today_count'] ?? 0)} ثبت امروز',
                  style: nvText(context, 11, color: c.muted),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _DeviceSheet extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DeviceSheet({required this.d});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final revoked = d['revoked'] == true;
    final mins = _silentMinutes(d);
    final online = !revoked && mins != null && mins <= 10;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(k, style: nvText(context, 14, color: c.muted))),
            Text(v, style: nvText(context, 14, w: FontWeight.w700)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
            child: Icon(Icons.smartphone_rounded, color: c.brandText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['label']}', style: nvText(context, 18, w: FontWeight.w800)),
              Text(['${d['staff'] ?? ''}', if (((d['roles'] as List?) ?? const []).isNotEmpty) 'نقش: ${(d['roles'] as List).join('، ')}'].where((e) => e.isNotEmpty).join(' · '),
                  style: nvText(context, 13, color: c.muted)),
            ]),
          ),
          if (revoked)
            NvStatusChip(text: 'لغو شده', icon: Icons.block_rounded, bg: c.field, fg: c.muted)
          else
            online
                ? NvStatusChip(text: 'آنلاین', icon: Icons.check_circle_rounded, bg: c.goSoft, fg: c.go)
                : NvStatusChip(text: 'آفلاین', icon: Icons.wifi_off_rounded, bg: c.waitSoft, fg: c.wait),
        ]),
        const SizedBox(height: 10),
        kv('آخرین ارتباط', _ago(mins)),
        kv('در صف ارسال (آخرین گزارش)', '${faDigits(d['pending'] ?? 0)} مورد'),
        kv('ثبت‌شده امروز', faDigits(d['today_count'] ?? 0)),
        kv('نسخه‌ی اپ', '${d['app_version'] ?? ''}'.isEmpty ? 'گزارش نشده' : faDigits(d['app_version'])),
        if (!revoked) ...[
          const SizedBox(height: 10),
          const NvBanner(
            tone: NvTone.info,
            text: 'اگر گوشی گم شد یا دست فرد نامطمئنی افتاد، دسترسی را لغو کنید. کارهای ثبت‌شده‌ی قبلی می‌ماند و کارهای ارسال‌نشده تا ورود دوباره با PIN روی همان گوشی می‌ماند.',
          ),
          const SizedBox(height: 14),
          NvSoftButton(
            label: 'لغو دسترسی این گوشی…',
            icon: Icons.block_rounded,
            iconColor: c.stop,
            fg: c.stop,
            border: c.stop.withValues(alpha: .4),
            onPressed: s.busy
                ? null
                : () async {
                    final ok = await confirmDanger(context,
                        title: 'لغو دسترسی «${d['label']}»؟', text: 'این گوشی تا ورود دوباره با PIN نمی‌تواند چیزی ثبت کند.', confirm: 'لغو دسترسی');
                    if (ok == true) {
                      await s.revokeDevice((d['id'] as num).toInt());
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
          ),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ]),
    );
  }
}

class _StaffList extends StatelessWidget {
  const _StaffList();

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    String desk(StaffDef st) {
      final d = s.deviceList.where((d) => d['staff'] == st.name && d['revoked'] != true).firstOrNull;
      return d == null ? '' : '${d['label']}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.staff.isEmpty) NvCard(child: Text('هنوز نیرویی نساخته‌اید.', style: nvText(context, 14, color: c.muted))),
      if (s.staff.isNotEmpty)
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Nv.r22)),
          child: Column(children: [
            for (var i = 0; i < s.staff.length; i++)
              InkWell(
                onTap: () => showNvSheet<void>(context, (_) => _StaffEditor(existing: s.staff[i])),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: i == s.staff.length - 1 ? null : Border(bottom: BorderSide(color: c.lineSoft))),
                  child: Row(children: [
                    NvLetter(s.staff[i].name.isEmpty ? '؟' : String.fromCharCode(s.staff[i].name.runes.first), size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.staff[i].name, style: nvText(context, 15, w: FontWeight.w800)),
                        Text(
                          [
                            _roles(s.staff[i]),
                            if (desk(s.staff[i]).isNotEmpty) desk(s.staff[i]),
                            if (!s.staff[i].hasPin) 'بدون PIN',
                          ].join(' · '),
                          style: nvText(context, 12, color: s.staff[i].hasPin ? c.muted : c.wait),
                        ),
                      ]),
                    ),
                    Icon(Icons.edit_rounded, color: c.muted),
                  ]),
                ),
              ),
          ]),
        ),
      const SizedBox(height: 12),
      NvButton(label: 'نیروی تازه', icon: Icons.person_add_rounded, onPressed: () => showNvSheet<void>(context, (_) => const _StaffEditor())),
    ]);
  }
}

String _roles(StaffDef st) => [if (st.canCheckin) 'پذیرش', if (st.canServe) 'پذیرایی', if (st.isAdmin) 'مدیر'].join('، ').ifEmpty('بدون دسترسی');

extension on String {
  String ifEmpty(String v) => isEmpty ? v : this;
}

String _randomPin(Iterable<String> taken) {
  final r = Random.secure();
  String pin;
  do {
    pin = (100000 + r.nextInt(900000)).toString();
  } while (taken.contains(pin));
  return pin;
}

/// ساخت یا ویرایش نیرو؛ بعد از ذخیره، PIN یک بار نشان داده می‌شود.
class _StaffEditor extends StatefulWidget {
  final StaffDef? existing;
  const _StaffEditor({this.existing});

  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _pin = TextEditingController();
  late bool _checkin = widget.existing?.canCheckin ?? true;
  late bool _serve = widget.existing?.canServe ?? false;
  late bool _admin = widget.existing?.isAdmin ?? false;
  String? _error;
  String? _shownPin;
  String _shownName = '';

  @override
  void initState() {
    super.initState();
    if (widget.existing == null) _pin.text = _randomPin(StateScope.read(context).staff.map((x) => x.newPin));
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = StateScope.read(context);
    final name = _name.text.trim();
    final pin = latinDigits(_pin.text.trim());
    if (name.isEmpty) return setState(() => _error = 'نام نیرو را بنویسید.');
    if (widget.existing == null && s.staff.any((x) => x.name == name)) return setState(() => _error = 'نیرویی با این نام هست.');
    if (pin.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(pin)) return setState(() => _error = 'PIN باید ۴ تا ۸ رقم باشد.');
    if (widget.existing == null && pin.isEmpty) return setState(() => _error = 'PIN لازم است.');
    if (!_checkin && !_serve) return setState(() => _error = 'دست‌کم «پذیرش» یا «پذیرایی» را بزنید.');
    final st = widget.existing ?? StaffDef(name);
    st
      ..canCheckin = _checkin
      ..canServe = _serve
      ..isAdmin = _admin
      ..newPin = pin;
    if (widget.existing == null) s.staff.add(st);
    await s.pushStaff();
    if (!mounted) return;
    if (s.messageIsError) {
      if (widget.existing == null) s.staff.remove(st);
      return setState(() => _error = s.message);
    }
    s.message = null;
    if (pin.isEmpty) return Navigator.pop(context);
    setState(() {
      _shownPin = pin;
      _shownName = name;
    });
  }

  Future<void> _delete() async {
    final s = StateScope.read(context);
    final st = widget.existing!;
    final ok = await confirmDanger(context,
        title: 'حذف «${st.name}»؟', text: 'گوشی‌هایی که با این نیرو وارد شده‌اند هم لغو می‌شوند. کارهای ثبت‌شده‌اش می‌ماند.', confirm: 'حذف نیرو');
    if (ok != true) return;
    s.staff.remove(st);
    await s.pushStaff();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = StateScope.of(context);
    final pad = EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom);

    if (_shownPin != null) {
      return Padding(
        padding: pad,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'نیروی تازه ساخته شد' : 'PIN تازه ذخیره شد', style: nvText(context, 20, w: FontWeight.w800)),
          Text('$_shownName · ${_roles(StaffDef(_shownName, canCheckin: _checkin, canServe: _serve, isAdmin: _admin))}', style: nvText(context, 13, color: c.muted)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r18)),
            child: Column(children: [
              Text('PIN ورود (فقط همین یک بار نشان داده می‌شود)', textAlign: TextAlign.center, style: nvText(context, 13, color: c.muted)),
              const SizedBox(height: 6),
              Text(_shownPin!, textDirection: TextDirection.ltr, style: nvText(context, 40, w: FontWeight.w800).copyWith(letterSpacing: 8)),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _shownPin!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN کپی شد.')));
                },
                icon: const Icon(Icons.content_copy_rounded),
                label: const Text('کپی PIN'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const NvBanner(tone: NvTone.wait, icon: Icons.warning_rounded, text: 'PIN بعد از بستن این صفحه دیگر دیده نمی‌شود. اگر گم شد، PIN تازه بسازید.'),
          const SizedBox(height: 14),
          NvButton(label: 'PIN را به او دادم', onPressed: () => Navigator.pop(context)),
        ]),
      );
    }

    Widget role(String label, bool on, ValueChanged<bool> set) => FilterChip(label: Text(label), selected: on, onSelected: set);
    return Padding(
      padding: pad,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'نیروی تازه' : 'ویرایش نیرو', style: nvText(context, 20, w: FontWeight.w800)),
          const SizedBox(height: 14),
          NvField(
            label: 'نام',
            helper: widget.existing == null ? null : 'نام عوض نمی‌شود؛ برای نام تازه، نیروی تازه بسازید.',
            child: TextField(controller: _name, readOnly: widget.existing != null, autofocus: widget.existing == null),
          ),
          const SizedBox(height: 12),
          Text('دسترسی‌ها', style: nvText(context, 14, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            role('پذیرش', _checkin, (v) => setState(() => _checkin = v)),
            role('پذیرایی', _serve, (v) => setState(() => _serve = v)),
            role('مدیر', _admin, (v) => setState(() => _admin = v)),
          ]),
          Text('«مدیر» یعنی در اپ نیروها می‌تواند پذیرش اشتباه را لغو کند.', style: nvText(context, 12, color: c.muted)),
          const SizedBox(height: 12),
          NvField(
            label: widget.existing == null ? 'PIN' : 'PIN تازه',
            optional: widget.existing != null,
            helper: widget.existing == null ? 'خودکار ساخته شد؛ می‌توانید عوضش کنید (۴ تا ۸ رقم).' : 'خالی = PIN فعلی می‌ماند.',
            child: TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: 'PIN تصادفی',
                  icon: const Icon(Icons.casino_rounded),
                  onPressed: () => setState(() => _pin.text = _randomPin(const [])),
                ),
              ),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 10), NvBanner(tone: NvTone.stop, text: _error!)],
          const SizedBox(height: 16),
          NvButton(label: 'ذخیره روی سرور', busy: s.busy, onPressed: s.busy ? null : _save),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.stop),
              onPressed: s.busy ? null : _delete,
              child: const Text('حذف این نیرو…'),
            ),
          ],
        ]),
      ),
    );
  }
}
