// وضعیت در ویندوز (طرح ۱۱): همگام‌سازی، این دستگاه، کارهای ردشده، پذیرایی امروز،
// دریافت دوباره‌ی لیست، تعویض نیرو و خروج امن.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/nv_theme.dart';
import '../android/nv_widgets.dart';
import '../brand.dart';
import '../errors.dart';
import '../main.dart';
import '../normalize.dart';
import '../store.dart';
import 'scan_field.dart';

class DeskStatusTab extends StatefulWidget {
  final bool wide;
  const DeskStatusTab({super.key, required this.wide});

  @override
  State<DeskStatusTab> createState() => _DeskStatusTabState();
}

class _DeskStatusTabState extends State<DeskStatusTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final s = StoreScope.read(context);
    final m = ScaffoldMessenger.of(context);
    setState(() => _refreshing = true);
    try {
      await s.sync();
      await s.refreshSnapshot();
      m.showSnackBar(const SnackBar(content: Text('لیست به‌روز شد.')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _report(AppStore s, Map<String, dynamic> item) async {
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('خبر به مدیر'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('«${item['reason'] ?? ''}» — چه شد؟ متن در گزارش مدیر دیده می‌شود.'),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(hintText: 'مثلاً: کارت را اشتباه به نفر دیگری دادیم'),
                onChanged: (_) => set(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
            FilledButton(onPressed: text.text.trim().isEmpty ? null : () => Navigator.pop(d, true), child: const Text('بفرست')),
          ],
        ),
      ),
    );
    if (ok == true && text.text.trim().isNotEmpty) {
      s.reportToAdmin(item, text.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای مدیر فرستاده شد.')));
    }
  }

  Future<void> _switch(AppStore s) async {
    await showDialog<void>(context: context, builder: (_) => _SwitchStaffDialog(store: s));
  }

  Future<void> _logout(AppStore s) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _LogoutDialog(store: s));
    if (ok == true) await s.logout();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final c = NvColors.of(context);
    final n = s.pending.length;

    Widget card(Widget child, {Color? color}) => Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(color: color ?? c.surface, borderRadius: BorderRadius.circular(Nv.r18)),
          child: child,
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: nvText(context, 14, color: c.muted)),
            const SizedBox(width: 12),
            Expanded(child: Text(v, textAlign: TextAlign.end, style: nvText(context, 14, w: FontWeight.w700))),
          ]),
        );
    Widget mini(String label, String value, {String? of, bool warn = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: warn ? c.waitSoft : c.field, borderRadius: BorderRadius.circular(Nv.r14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: nvText(context, 12, color: warn ? c.waitInk : c.muted)),
              Text.rich(TextSpan(children: [
                TextSpan(text: value, style: nvText(context, 28, w: FontWeight.w800, color: warn ? c.waitInk : c.ink, height: 1.3)),
                if (of != null) TextSpan(text: ' از $of', style: nvText(context, 14, color: c.muted)),
              ])),
            ]),
          ),
        );

    final (IconData icon, Color iconBg, Color iconFg, String title, String sub) = s.needsLogin
        ? (Icons.lock_rounded, c.stopSoft, c.stop, 'دسترسی این دستگاه باطل شد', 'با PIN دوباره وارد شوید؛ کارهای ارسال‌نشده می‌مانند.')
        : s.syncing
            ? (Icons.sync_rounded, c.chip, c.brandText, 'در حال ارسال…', 'کارها به سرور فرستاده می‌شوند.')
            : !s.online
                ? (Icons.cloud_off_rounded, c.tag, c.muted, 'آفلاین', 'اپ بدون اینترنت هم کار می‌کند؛ با اتصال، خودکار ارسال می‌شود.')
                : n > 0
                    ? (Icons.cloud_upload_rounded, c.waitSoft, c.wait, '${faDigits(n)} کار در صف', s.pendingSummary())
                    : (Icons.cloud_done_rounded, c.goSoft, c.go, 'همه‌چیز ارسال شد', 'کارهای این دستگاه روی سرور است.');

    final sync = card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, size: 28, color: iconFg),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nvText(context, 20, w: FontWeight.w800)),
            Text(sub, style: nvText(context, 14, color: c.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            onPressed: s.syncing || s.needsLogin ? null : s.sync,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sync_rounded, size: 22),
              const SizedBox(width: 8),
              Text('همگام‌سازی الان', style: nvText(context, 16, w: FontWeight.w800, color: Colors.white)),
              if (widget.wide) ...[const SizedBox(width: 8), const NvKbd('Ctrl+R', onBrand: true)],
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        mini('در صف ارسال', faDigits(n), warn: n > 0),
        const SizedBox(width: 10),
        mini('آخرین ارسال', s.lastSyncOk == null ? '—' : faDigits(hm(s.lastSyncOk!))),
        const SizedBox(width: 10),
        mini('پذیرش‌شده', faDigits(s.checkins.length), of: faDigits(s.attendees.length)),
      ]),
      if (s.lastError != null && !s.online && !s.needsLogin) ...[
        const SizedBox(height: 10),
        Text(s.lastError!, style: nvText(context, 12, color: c.muted)),
      ],
    ]));

    final device = card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('این دستگاه', style: nvText(context, 16, w: FontWeight.w800)),
      const SizedBox(height: 6),
      kv('نیرو', s.staffName.isEmpty ? '—' : s.staffName),
      kv('نام دستگاه', s.deviceLabel.isEmpty ? '—' : s.deviceLabel),
      kv('رویداد', s.eventName.isEmpty ? (s.eventCode ?? '—') : s.eventName),
      ValueListenableBuilder<DateTime?>(
        valueListenable: scannerLastAt,
        builder: (context, last, _) => kv(
          'بارکدخوان',
          !s.scanEnabled
              ? 'در این رویداد اسکن نیست'
              : last == null
                  ? 'هنوز اسکنی نیامده'
                  : 'کار می‌کند · آخرین اسکن ${faDigits(hm(last))}',
        ),
      ),
    ]));

    final now = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final todays = s.meals.where((m) => m.day == null || m.day!.isEmpty || m.day!.startsWith(today)).toList();
    final meals = card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('پذیرایی امروز', style: nvText(context, 16, w: FontWeight.w800)),
      const SizedBox(height: 6),
      if (todays.isEmpty) Text('امروز وعده‌ای نیست.', style: nvText(context, 14, color: c.muted)),
      for (final m in todays) kv(m.name, '${faDigits(s.servedCount(m.id))} از ${faDigits(s.entitledCount(m))}'),
      if (s.usesCards) kv('کارت رزرو آزاد', faDigits(s.freeReserveCards.length)),
    ]));

    final rejected = s.rejected.isEmpty
        ? null
        : card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.report_rounded, size: 22, color: c.wait),
              const SizedBox(width: 8),
              Text('${faDigits(s.rejected.length)} کار را سرور نپذیرفت', style: nvText(context, 16, w: FontWeight.w800)),
            ]),
            for (final r in s.rejected.reversed.take(8).toList())
              Builder(builder: (context) {
                final who = s.attendees[r['attendee_id']?.toString()];
                final at = DateTime.tryParse('${r['at'] ?? ''}');
                return Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(Nv.r14)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['reason'] ?? 'دلیل نامشخص'}', style: nvText(context, 14, w: FontWeight.w700)),
                        Text([if (who != null) who.fullName, if (at != null) 'ساعت ${faDigits(hm(at))}'].join(' · '),
                            style: nvText(context, 12, color: c.muted)),
                      ]),
                    ),
                    TextButton(onPressed: () => s.dismissRejected(r), child: const Text('دیدم، پاک کن')),
                    const SizedBox(width: 6),
                    OutlinedButton(onPressed: () => _report(s, r), child: const Text('خبر به مدیر')),
                  ]),
                );
              }),
          ]));

    Widget outline(String label, VoidCallback? onTap, {Color? color}) => SizedBox(
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: color ?? c.ink,
              backgroundColor: c.surface,
              side: BorderSide(color: color ?? c.line, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: onTap,
            child: Text(label, style: nvText(context, 14, w: FontWeight.w700, color: color ?? c.ink)),
          ),
        );

    final actions = Wrap(spacing: 12, runSpacing: 12, children: [
      outline(_refreshing ? 'در حال دریافت…' : 'دریافت دوباره‌ی لیست', _refreshing || s.needsLogin ? null : _refresh),
      outline('تعویض نیرو', s.needsLogin ? null : () => _switch(s)),
      outline('خروج از رویداد', () => _logout(s), color: c.stop),
    ]);
    final about = Text.rich(
      TextSpan(children: [
        TextSpan(text: '$appName · نسخه‌ی ${faDigits(appVersionLabel)} · ساخته‌ی '),
        TextSpan(text: makerTeam, style: nvText(context, 12, w: FontWeight.w700)),
        const TextSpan(text: '\n'),
        const TextSpan(text: '$makerEmail · $makerWebsite'),
      ]),
      textAlign: widget.wide ? TextAlign.left : TextAlign.center,
      style: nvText(context, 12, color: c.muted, height: 1.7),
    );

    if (!widget.wide) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        sync,
        const SizedBox(height: 14),
        if (rejected != null) ...[rejected, const SizedBox(height: 14)],
        device,
        const SizedBox(height: 14),
        meals,
        const SizedBox(height: 18),
        actions,
        const SizedBox(height: 18),
        about,
      ]);
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => s.sync()},
      child: ListView(padding: const EdgeInsets.all(24), children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 2, child: sync),
            const SizedBox(width: 18),
            Expanded(child: device),
          ]),
        ),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: rejected ?? const SizedBox.shrink()),
          SizedBox(width: rejected == null ? 0 : 18),
          Expanded(child: meals),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: actions),
          const SizedBox(width: 18),
          about,
        ]),
      ]),
    );
  }
}

class _SwitchStaffDialog extends StatefulWidget {
  final AppStore store;
  const _SwitchStaffDialog({required this.store});

  @override
  State<_SwitchStaffDialog> createState() => _SwitchStaffDialogState();
}

class _SwitchStaffDialogState extends State<_SwitchStaffDialog> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_pin.text.trim().isEmpty) {
      setState(() => _error = 'PIN را بنویسید.');
      return;
    }
    final before = widget.store.staffName;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.switchStaff(_pin.text);
      if (!mounted) return;
      final m = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      m.showSnackBar(SnackBar(content: Text('نیرو عوض شد: ${widget.store.staffName}${before.isEmpty ? '' : ' (به‌جای $before)'}.')));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, login: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final n = s.pending.length;
    return AlertDialog(
      title: const Text('تعویض نیرو'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('نیروی بعدی با PIN خودش روی همین دستگاه وارد می‌شود. لیست روی دستگاه می‌ماند و از این به بعد کارها به نام نیروی جدید ثبت می‌شود.',
              style: nvText(context, 14, height: 1.6)),
          if (n > 0) ...[
            const SizedBox(height: 12),
            NvBanner(tone: NvTone.info, text: '${faDigits(n)} کار ارسال‌نشده‌ی ${s.staffName} از بین نمی‌رود و به نام خود او فرستاده می‌شود.'),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: 'PIN نیروی جدید', errorText: _error),
            onSubmitted: (_) => _busy ? null : _go(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'در حال ورود…' : 'ورود نیروی جدید')),
      ],
    );
  }
}

class _LogoutDialog extends StatelessWidget {
  final AppStore store;
  const _LogoutDialog({required this.store});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    final s = store;
    final n = s.pending.length;
    return AlertDialog(
      title: const Text('خروج از رویداد'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (n == 0)
            Text('همه‌ی کارها ارسال شده. داده‌ی رویداد از این دستگاه پاک می‌شود.', style: nvText(context, 14, height: 1.6))
          else ...[
            NvBanner(
              tone: NvTone.stop,
              title: '${faDigits(n)} کار هنوز به سرور نرسیده',
              text: '${s.pendingSummary()}. با خروج این کارها برای همیشه از بین می‌روند.',
            ),
            if (!s.online) ...[
              const SizedBox(height: 10),
              const NvBanner(tone: NvTone.neutral, icon: Icons.cloud_off_rounded, text: 'دستگاه آفلاین است. اول اینترنت را وصل کنید تا کارها ارسال شوند.'),
            ],
            const SizedBox(height: 10),
            Text('اگر فقط نیرو عوض می‌شود، «تعویض نیرو» را بزنید؛ چیزی پاک نمی‌شود.', style: nvText(context, 13, color: c.muted)),
          ],
        ]),
      ),
      actions: n > 0
          ? [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: c.stop),
                onPressed: () => Navigator.pop(context, true),
                child: Text('با این حال خارج شو و ${faDigits(n)} کار را از دست بده'),
              ),
              FilledButton(
                onPressed: () {
                  s.sync();
                  Navigator.pop(context, false);
                },
                child: const Text('برگرد و همگام‌سازی کن'),
              ),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: c.stop), onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
            ],
    );
  }
}
