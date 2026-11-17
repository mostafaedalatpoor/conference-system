import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../main.dart';
import '../normalize.dart';
import '../state.dart';
import '../theme/firouzeh.dart';
import '../theme/widgets.dart';

/// «ویرایش اطلاعات» و «افزودن فرد» (طراحی ۱۹-EditPerson). [person] = null یعنی افزودن.
/// خروجی: true اگر ذخیره شد.
Future<bool> showPersonEditor(BuildContext context, {Person? person}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: _PersonEditor(person: person),
    ),
  );
  return r == true;
}

class _PersonEditor extends StatefulWidget {
  final Person? person;
  const _PersonEditor({this.person});

  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final _first = TextEditingController(text: widget.person?.firstName ?? '');
  late final _last = TextEditingController(text: widget.person?.lastName ?? '');
  late final _mobile = TextEditingController(text: widget.person?.mobile ?? '');
  late final _email = TextEditingController(text: widget.person?.email ?? '');
  late final _org = TextEditingController(text: widget.person?.organization ?? '');
  String? _type;
  String? _role;
  String? _error;

  bool get _adding => widget.person == null;

  @override
  void initState() {
    super.initState();
    _type = widget.person?.typeCode;
    _role = widget.person?.roleCode;
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _mobile, _email, _org]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(AdminState s) async {
    final first = _first.text.trim(), last = _last.text.trim();
    final mobile = normalizeMobile(_mobile.text), email = _email.text.trim().toLowerCase();
    String? err;
    if (first.isEmpty || last.isEmpty) {
      err = 'نام و نام خانوادگی را بنویسید.';
    } else if (_adding && mobile.isEmpty && email.isEmpty) {
      err = 'یکی از موبایل یا ایمیل لازم است.';
    } else if (_type == null) {
      err = 'نوع ثبت‌نام را انتخاب کنید.';
    }
    setState(() => _error = err);
    if (err != null) return;
    final bool ok;
    if (_adding) {
      ok = await s.addPerson(Person(
        id: const Uuid().v4(),
        firstName: first,
        lastName: last,
        mobile: mobile,
        email: email,
        organization: _org.text.trim(),
        typeCode: _type!,
        roleCode: _role,
        source: 'manual',
      ));
    } else {
      final p = widget.person!;
      ok = await s.patchPerson(p.id, {
        if (first != p.firstName) 'first_name': first,
        if (last != p.lastName) 'last_name': last,
        if (mobile != p.mobile) 'mobile': mobile,
        if (email != p.email) 'email': email,
        if (_org.text.trim() != p.organization) 'organization': _org.text.trim(),
        if (_type != p.typeCode) 'registration_type': _type,
        if (_role != p.roleCode) 'role': _role,
      });
    }
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = StateScope.of(context);
    final theme = Theme.of(context);
    const gap = SizedBox(height: FirouzehSize.space3);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(FirouzehSize.space4, FirouzehSize.space4, FirouzehSize.space4, FirouzehSize.space5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(_adding ? 'افزودن فرد' : 'ویرایش اطلاعات', style: theme.textTheme.titleLarge)),
          if (_adding) Text('ثبت‌نام دستی', style: theme.textTheme.bodySmall?.copyWith(color: FirouzehColors.of(context).inkMuted)),
        ]),
        gap,
        Row(children: [
          Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'نام'))),
          const SizedBox(width: FirouzehSize.space3),
          Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'نام خانوادگی'))),
        ]),
        gap,
        TextField(
          controller: _mobile,
          decoration: const InputDecoration(labelText: 'موبایل', prefixIcon: Icon(Icons.call_rounded)),
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
        ),
        gap,
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'ایمیل', prefixIcon: Icon(Icons.mail_rounded)),
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
        ),
        gap,
        TextField(controller: _org, decoration: const InputDecoration(labelText: 'سازمان (اختیاری)')),
        gap,
        DropdownButtonFormField<String>(
          initialValue: s.types.any((t) => t.code == _type) ? _type : null,
          decoration: const InputDecoration(labelText: 'نوع ثبت‌نام'),
          items: [for (final t in s.types) DropdownMenuItem(value: t.code, child: Text(t.name))],
          onChanged: (v) => setState(() => _type = v),
        ),
        gap,
        DropdownButtonFormField<String?>(
          initialValue: s.roles.any((r) => r.code == _role) ? _role : null,
          decoration: const InputDecoration(labelText: 'نقش (اختیاری)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('بدون نقش')),
            for (final r in s.roles) DropdownMenuItem<String?>(value: r.code, child: Text(r.name)),
          ],
          onChanged: (v) => setState(() => _role = v),
        ),
        gap,
        if (_adding)
          const Notice(
            tone: NoticeTone.neutral,
            text: 'نام و یکی از موبایل یا ایمیل کافی است. بقیه را بعداً هم می‌شود کامل کرد.',
          ),
        if (_error != null) ...[
          gap,
          Notice(tone: NoticeTone.stop, text: _error!),
        ],
        const SizedBox(height: FirouzehSize.space4),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(FirouzehSize.tapLg)),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
          ),
          const SizedBox(width: FirouzehSize.space3),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(FirouzehSize.tapLg)),
              onPressed: s.busy ? null : () => _save(s),
              child: const Text('ذخیره'),
            ),
          ),
        ]),
      ]),
    );
  }
}
