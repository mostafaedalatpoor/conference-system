import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../normalize.dart';
import 'scanner.dart';
import 'walkin.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _scanToFind() async {
    final store = StoreScope.read(context);
    final token = await ScannerPage.scan(context);
    if (token == null || !mounted) return;
    final a = store.attendeeForToken(token);
    if (a == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(store.cards.containsKey(token) ? 'این کارت رزرو هنوز به کسی وصل نشده.' : 'این کارت در لیست نیست.'),
      ));
      return;
    }
    showAttendeeSheet(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final results = store.search(_q.text);
    final checked = store.checkins.length;
    final total = store.attendees.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'نام، نام خانوادگی یا موبایل',
                    border: const OutlineInputBorder(),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_q.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'اسکن کارت',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scanToFind,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'پذیرش‌شده: ${faDigits(checked)} از ${faDigits(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: _q.text.trim().isEmpty
              ? const _EmptyHint()
              : ListView(
                  children: [
                    for (final a in results) _AttendeeTile(a: a),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: Text(results.isEmpty ? 'پیدا نشد؛ ثبت‌نام در محل' : 'کسی که دنبالش هستید نیست؟ ثبت‌نام در محل'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => WalkinScreen(initialName: _q.text.trim()),
                        )),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'چند حرف از نام یا شماره‌ی موبایل را بنویسید.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
}

class _AttendeeTile extends StatelessWidget {
  final Attendee a;
  const _AttendeeTile({required this.a});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final state = store.checkins[a.id];
    final parts = [
      store.typeName(a.registrationTypeId),
      store.roleName(a.roleId),
      a.organization,
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      title: Text(a.displayName),
      subtitle: Text(parts),
      trailing: state == null
          ? null
          : Chip(
              avatar: const Icon(Icons.check, size: 16, color: Colors.white),
              label: Text(hm(state.at), style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
              side: BorderSide.none,
            ),
      onTap: () => showAttendeeSheet(context, a),
    );
  }
}

String presentationLabel(String k) => switch (k) {
      'poster' => 'ارائه‌ی پوستری',
      'oral' => 'ارائه‌ی شفاهی',
      _ => '',
    };

Future<void> showAttendeeSheet(BuildContext context, Attendee a) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AttendeeSheet(attendeeId: a.id),
    );

class _AttendeeSheet extends StatelessWidget {
  final String attendeeId;
  const _AttendeeSheet({required this.attendeeId});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final a = store.attendees[attendeeId];
    if (a == null) return const SizedBox.shrink();
    final state = store.checkins[a.id];
    final card = store.cardOf(a.id);
    final theme = Theme.of(context);

    final details = <(String, String)>[
      ('نوع ثبت‌نام', store.typeName(a.registrationTypeId)),
      ('نقش', store.roleName(a.roleId)),
      ('ارائه', presentationLabel(a.presentationKind)),
      ('سازمان', a.organization),
      ('موبایل', faDigits(a.mobile)),
      ('شماره‌ی کارت', card == null ? '' : faDigits(card.serial)),
      ('منبع', a.source == 'walkin' ? 'ثبت‌نام در محل' : ''),
    ].where((d) => d.$2.isNotEmpty);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            for (final d in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(d.$1, style: const TextStyle(color: Colors.grey))),
                  Expanded(child: Text(d.$2)),
                ]),
              ),
            const SizedBox(height: 20),
            if (state != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'قبلاً پذیرش شده: ساعت ${hm(state.at)}'
                  '${state.staffId != null && store.staffNames[state.staffId] != null ? ' توسط ${store.staffNames[state.staffId]}' : ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (store.isAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    final ok = await _confirm(context, 'پذیرش ${a.fullName} لغو شود؟');
                    if (ok == true) store.undoCheckin(a);
                  },
                  child: const Text('لغو پذیرش'),
                ),
              ],
            ] else
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: Colors.green),
                icon: const Icon(Icons.check),
                label: const Text('تیک پذیرش', style: TextStyle(fontSize: 18)),
                onPressed: () {
                  store.checkin(a);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${a.fullName} پذیرش شد${card != null ? ' — کارت شماره‌ی ${faDigits(card.serial)}' : ''}'),
                  ));
                },
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _confirm(BuildContext context, String text) => showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('نه')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله')),
        ],
      ),
    );
