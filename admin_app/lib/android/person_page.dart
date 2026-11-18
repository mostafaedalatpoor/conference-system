// سربرگ صفحه‌های داخلی، تأیید کار حساس، و موردهای مشکوک (طرح ۶ و ۱۸).
// صفحه‌ی فرد همان صفحه‌ی کامل ۲٫۰ است (ویرایش، ادغام، حذف، برگردان وعده و پذیرش).
import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../screens/people.dart' show PersonPage;
import 'nv_theme.dart';
import 'nv_widgets.dart';

export '../screens/people.dart' show PersonPage;

/// سربرگ صفحه‌های داخلی: برگشت، عنوان، و یک دکمه‌ی اختیاری.
class NvPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final double bottom;
  const NvPageHeader({super.key, required this.title, this.subtitle, this.action, this.bottom = 20});

  @override
  Widget build(BuildContext context) {
    final c = NvColors.of(context);
    return NvHeader(
      radius: 28,
      bottom: bottom,
      child: Row(children: [
        NvRoundIcon(icon: Icons.arrow_forward_rounded, label: 'بازگشت', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle != null) Text(subtitle!, style: nvText(context, 12, color: c.onBrand.withValues(alpha: .85))),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: nvText(context, 19, w: FontWeight.w800, color: c.onBrand, height: 1.4)),
          ]),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

/// کارت یک مورد مشکوک با «بررسی شد، علامت را بردار» (یا برگرداندن علامت).
class FlagCard extends StatelessWidget {
  final Map<String, dynamic> flag;
  const FlagCard({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final resolved = flag['resolved_at'] != null;
    final at = DateTime.tryParse('${flag['device_time']}')?.toLocal();
    final text = [
      if ('${flag['detail'] ?? ''}'.isNotEmpty) '${flag['detail']}',
      if (at != null) 'ساعت ${faDigits(hm(at))}',
      if ('${flag['device'] ?? ''}'.isNotEmpty) '${flag['device']}',
      if ('${flag['staff'] ?? ''}'.isNotEmpty) '${flag['staff']}',
      if (resolved) 'بررسی شد${'${flag['resolved_by'] ?? ''}'.isEmpty ? '' : ' (${flag['resolved_by']})'}',
    ].join(' · ');
    return NvBanner(
      tone: resolved ? NvTone.neutral : NvTone.wait,
      icon: resolved ? Icons.flag_outlined : Icons.flag_rounded,
      title: '${flag['flag_label']}${'${flag['name'] ?? ''}'.isEmpty ? '' : ' — ${flag['name']}'}',
      text: text,
    );
  }
}

/// همه‌ی موردهای مشکوک، اول بررسی‌نشده‌ها.
class FlagsPage extends StatelessWidget {
  const FlagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final flags = s.flaggedList;
    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        NvPageHeader(title: 'موارد مشکوک', subtitle: '${faDigits(flags.where((f) => f['resolved_at'] == null).length)} بررسی‌نشده'),
        for (final f in flags)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: InkWell(
              onTap: () {
                final p = s.people[f['attendee_id']?.toString()];
                if (p != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonPage(person: p)));
              },
              child: FlagCard(flag: f),
            ),
          ),
      ]),
    );
  }
}

/// موردی که به یک نفر وصل نیست (مثلاً خبر نیرو بدون نام).
class FlagPage extends StatelessWidget {
  final Map<String, dynamic> flag;
  const FlagPage({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final c = NvColors.of(context);
    final live = s.flaggedList.where((f) => f['seq'] == flag['seq']).firstOrNull ?? flag;
    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(children: [
        NvPageHeader(title: '${live['flag_label']}'),
        Padding(padding: const EdgeInsets.all(16), child: FlagCard(flag: live)),
      ]),
    );
  }
}

/// پرسش تأیید برای کار حساس؛ دکمه‌ی خطر قرمز.
Future<bool?> confirmDanger(BuildContext context, {required String title, required String text, required String confirm}) {
  final c = NvColors.of(context);
  return showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('نه، برگرد')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: c.stop), onPressed: () => Navigator.pop(d, true), child: Text(confirm)),
      ],
    ),
  );
}

