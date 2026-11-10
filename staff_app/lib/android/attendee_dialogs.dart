// کارهای مشترک روی یک نفر: حرف دسته‌ی کارت، تکمیل اطلاعات ناقص، وصل‌کردن کارت رزرو.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';
import 'walkin.dart' show NvScanPage;

/// حرف دسته‌ی کارت چاپی (همان قاعده‌ی چیدن کارت‌ها در اپ مدیریت).
String batchLetter(Attendee a) {
  // همان قاعده‌ی چیدن کارت‌ها در اپ مدیریت: نام خانوادگی، اگر نبود نام، اگر هیچ نبود «؟» (آخر دسته‌ها).
  final last = a.printedLast ?? a.lastName;
  var first = a.printedFirst ?? a.firstName;
  if (first.startsWith('بی‌نام (ردیف ')) first = ''; // نام جایگزین ردیف بی‌نام اپ مدیریت
  final s = (last.trim().isNotEmpty ? last : first).trim();
  if (s.isEmpty) return '؟';
  final ch = String.fromCharCode(s.runes.first);
  return ch == 'آ' ? 'ا' : ch;
}


bool _noFirst(Attendee a) => a.firstName.trim().isEmpty || a.firstName.startsWith('بی‌نام (ردیف ');

/// تکمیل اطلاعات فردی که ناقص ثبت‌نام کرده؛ فقط خانه‌های خالی.
Future<void> showCompleteInfo(BuildContext context, Attendee a) async {
  final store = StoreScope.of(context);
  final fields = <(String, String, TextEditingController, TextInputType)>[
    if (_noFirst(a)) ('first_name', 'نام', TextEditingController(), TextInputType.name),
    if (a.lastName.trim().isEmpty) ('last_name', 'نام خانوادگی', TextEditingController(), TextInputType.name),
    if (a.mobile.isEmpty) ('mobile', 'موبایل', TextEditingController(), TextInputType.phone),
    if (a.email.isEmpty) ('email', 'ایمیل', TextEditingController(), TextInputType.emailAddress),
  ];
  if (fields.isEmpty) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('تکمیل اطلاعات'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(a.displayName, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: DaftarSize.space3),
            for (final (i, f) in fields.indexed) ...[
              DaftarField(
                label: f.$2,
                optional: true,
                child: TextField(
                  controller: f.$3,
                  autofocus: i == 0,
                  keyboardType: f.$4,
                  textDirection: f.$4 == TextInputType.name ? TextDirection.rtl : TextDirection.ltr,
                  textInputAction: i == fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: i == fields.length - 1 ? (_) => Navigator.pop(c, true) : null,
                ),
              ),
              const SizedBox(height: DaftarSize.space3),
            ],
            Text('بدون اینترنت هم ثبت می‌شود و با همگام‌سازی به سرور و گوشی‌های دیگر می‌رسد. در گزارش ثبت می‌شود چه کسی تکمیل کرد.',
                style: Theme.of(c).textTheme.bodySmall?.copyWith(color: DaftarColors.of(c).inkMuted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ذخیره')),
      ],
    ),
  );
  if (ok != true) return;
  String v(String k) => fields.where((f) => f.$1 == k).map((f) => f.$3.text).firstOrNull ?? '';
  store.completeInfo(a, firstName: v('first_name'), lastName: v('last_name'), mobile: v('mobile'), email: v('email'));
}

/// وصل‌کردن کارت رزرو تازه به کسی که بدون کارت ثبت شده بود؛ با شماره یا اسکن. آفلاین هم ثبت می‌شود.
Future<void> showLinkCard(BuildContext context, Attendee a) async {
  final store = StoreScope.read(context);
  final serial = TextEditingController();
  String? error;
  final card = await showDialog<PassCard>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      void submit(String input) {
        final (found, err) = store.reserveCardFrom(input);
        if (found != null) return Navigator.pop(c, found);
        setState(() => error = err);
      }

      return AlertDialog(
        title: const Text('وصل‌کردن کارت رزرو'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(a.displayName, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: DaftarSize.space3),
            DaftarField(
              label: 'شماره‌ی روی کارت',
              error: error,
              helper: store.cameraScan
                  ? 'کارت را اسکن کنید یا شماره را بنویسید (R5001 یا 5001).'
                  : 'شماره‌ی روی کارت را بنویسید (R5001 یا 5001).',
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: serial,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    onSubmitted: submit,
                  ),
                ),
                if (store.cameraScan) ...[
                  const SizedBox(width: DaftarSize.space2),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final token = await Navigator.of(c).push<String>(MaterialPageRoute(builder: (_) => const NvScanPage(title: 'اسکن کارت رزرو')));
                      if (token != null) submit(token);
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('اسکن'),
                  ),
                ],
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('انصراف')),
          FilledButton(onPressed: () => submit(serial.text), child: const Text('وصل شود')),
        ],
      );
    }),
  );
  if (card == null || !context.mounted) return;
  store.linkCard(a, card);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('کارت رزرو R${faDigits(card.serial)} به ${a.fullName} وصل شد.')),
  );
}
