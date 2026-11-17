import 'package:flutter/material.dart';

import '../main.dart';
import '../normalize.dart';
import '../theme/daftar.dart';
import '../theme/widgets.dart';

/// «افراد» در حالت دسترسی محدود (کلید فقط گزارش): فهرست فقط‌خواندنی از خروجی فهرست حضور، با تاریخچه‌ی هر نفر.
class LimitedPeopleScreen extends StatefulWidget {
  const LimitedPeopleScreen({super.key});

  @override
  State<LimitedPeopleScreen> createState() => _LimitedPeopleScreenState();
}

class _LimitedPeopleScreenState extends State<LimitedPeopleScreen> {
  final _q = TextEditingController();
  late Future<Map<String, dynamic>> _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data = StateScope.read(context).exportRows();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _timeline(Map<String, dynamic> p) async {
    final s = StateScope.read(context);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${p['first_name']} ${p['last_name']}'),
        content: SizedBox(
          width: 420,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: s.loadTimeline('${p['id']}'),
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              if (snap.hasError) return Text('${snap.error}');
              final ev = snap.data!;
              if (ev.isEmpty) return const Hint('هنوز کاری برای این نفر ثبت نشده.');
              return ListView(shrinkWrap: true, children: [
                for (final e in ev)
                  ListTile(
                    dense: true,
                    title: Text([
                      switch ('${e['kind']}') {
                        'checkin' => 'پذیرش',
                        'checkin_undo' => 'لغو پذیرش',
                        'meal_served' => 'تحویل ${e['meal_name'] ?? 'وعده'}',
                        'meal_undo' => 'برگرداندن ${e['meal_name'] ?? 'وعده'}',
                        'walkin_register' => 'ثبت‌نام در محل',
                        _ => '${e['kind']}',
                      },
                      if (e['flag_label'] != null) '${e['flag_label']}',
                    ].join(' · ')),
                    subtitle: Text('${e['staff'] ?? ''}'),
                    trailing: DateTime.tryParse('${e['device_time']}') == null
                        ? null
                        : Text(hm(DateTime.parse('${e['device_time']}'))),
                  ),
              ]);
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = DaftarColors.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(DaftarSize.space4),
            child: Notice(tone: NoticeTone.stop, text: 'فهرست افراد نیامد: ${snap.error}'),
          );
        }
        final q = normalizeText(_q.text);
        final rows = ((snap.data!['rows'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .where((r) => q.isEmpty || q.split(' ').every(normalizeText('${r['first_name']} ${r['last_name']} ${r['mobile']} ${r['organization']} ${r['card'] ?? ''}').contains))
            .toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(DaftarSize.space4),
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'نام، موبایل یا شماره‌ی کارت'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final r in rows.take(200))
                ListTile(
                  title: Text('${r['title'] ?? ''} ${r['first_name']} ${r['last_name']}'.trim()),
                  subtitle: Text([r['type'], r['role'], r['organization']].where((e) => '${e ?? ''}'.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                  trailing: r['checked_in'] == true
                      ? Text(DateTime.tryParse('${r['last_checkin']}') == null ? 'آمده' : hm(DateTime.parse('${r['last_checkin']}')),
                          style: theme.textTheme.bodySmall?.copyWith(color: x.go, fontWeight: FontWeight.w700))
                      : Text('هنوز نیامده', style: theme.textTheme.bodySmall?.copyWith(color: x.inkMuted)),
                  onTap: () => _timeline(r),
                ),
              if (rows.length > 200)
                Padding(
                  padding: const EdgeInsets.all(DaftarSize.space4),
                  child: Hint('${faDigits(rows.length - 200)} نفر دیگر؛ جستجو را دقیق‌تر کنید.'),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

/// بنر حالت دسترسی محدود (طراحی ۱۸-States حالت ۱۵).
class LimitedBanner extends StatelessWidget {
  const LimitedBanner({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(DaftarSize.space4, DaftarSize.space3, DaftarSize.space4, 0),
        child: Notice(
          tone: NoticeTone.neutral,
          icon: Icons.lock_rounded,
          text: 'این کلید فقط گزارش را می‌بیند. تنظیمات رویداد برای شما بسته است.',
        ),
      );
}
