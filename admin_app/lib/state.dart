import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'excel_import.dart';
import 'normalize.dart';

const _uuid = Uuid();
// فضای نام ثابت برای ساخت شناسه‌ی پایدار شرکت‌کننده (ورود دوباره‌ی اکسل همان شناسه را می‌دهد).
const _attendeeNamespace = '6f1d3c2a-8b47-4e59-9a0c-2d5e7b8f1a34';
const reserveSerialStart = 5001;

class EventInfo {
  final String code;
  final String name;
  final String? startDate;
  final String? endDate;
  final String baseUrl;
  final bool locked;
  EventInfo(this.code, this.name, this.startDate, this.endDate, this.baseUrl, this.locked);

  factory EventInfo.fromJson(Map<String, dynamic> j) => EventInfo(
        j['code'].toString(),
        (j['name'] ?? '').toString(),
        j['start_date']?.toString(),
        j['end_date']?.toString(),
        (j['base_url'] ?? '').toString(),
        j['base_url_locked'] == true,
      );
}

class CodeName {
  String code;
  String name;
  CodeName(this.code, this.name);
  Map<String, dynamic> toJson() => {'code': code, 'name': name};
  factory CodeName.fromJson(Map<String, dynamic> j) => CodeName(j['code'].toString(), (j['name'] ?? '').toString());
}

class MealDef {
  String code;
  String name;
  String day;
  Set<String> types;
  Set<String> roles;
  MealDef(this.code, this.name, this.day, this.types, this.roles);

  Map<String, dynamic> toJson() =>
      {'code': code, 'name': name, 'day': day, 'registration_types': types.toList(), 'roles': roles.toList()};

  factory MealDef.fromJson(Map<String, dynamic> j) => MealDef(
        j['code'].toString(),
        (j['name'] ?? '').toString(),
        (j['day'] ?? '').toString(),
        ((j['registration_types'] as List?) ?? []).map((e) => e.toString()).toSet(),
        ((j['roles'] as List?) ?? []).map((e) => e.toString()).toSet(),
      );
}

class SessionDef {
  String day;
  String start;
  String end;
  String title;
  String hall;
  String kind;
  SessionDef(this.day, this.start, this.end, this.title, this.hall, this.kind);

  Map<String, dynamic> toJson() =>
      {'day': day, 'start_time': start, 'end_time': end, 'title': title, 'hall': hall, 'kind': kind};

  factory SessionDef.fromJson(Map<String, dynamic> j) => SessionDef(
        (j['day'] ?? '').toString(),
        (j['start_time'] ?? '').toString(),
        (j['end_time'] ?? '').toString(),
        (j['title'] ?? '').toString(),
        (j['hall'] ?? '').toString(),
        (j['kind'] ?? '').toString(),
      );
}

class StaffDef {
  String name;
  String newPin; // فقط تا ارسال بعدی در حافظه می‌ماند و ذخیره نمی‌شود
  bool canCheckin;
  bool canServe;
  bool isAdmin;
  bool hasPin;
  StaffDef(this.name, {this.newPin = '', this.canCheckin = true, this.canServe = true, this.isAdmin = false, this.hasPin = false});

  Map<String, dynamic> toJson() =>
      {'name': name, 'can_checkin': canCheckin, 'can_serve': canServe, 'is_admin': isAdmin, 'has_pin': hasPin};

  factory StaffDef.fromJson(Map<String, dynamic> j) => StaffDef(
        j['name'].toString(),
        canCheckin: j['can_checkin'] != false,
        canServe: j['can_serve'] != false,
        isAdmin: j['is_admin'] == true,
        hasPin: j['has_pin'] == true,
      );
}

/// یک شرکت‌کننده، همان شکلی که سرور می‌شناسد، همراه کارت.
class Person {
  final String id;
  String title;
  String firstName;
  String lastName;
  String email;
  String mobile;
  String organization;
  String country;
  String typeCode;
  String presentationKind;
  String? roleCode;
  String source;
  String? token;
  int? serial;

  /// ستون «اشتراک اطلاعات تماس» اکسل: null = طبق تنظیم رویداد، false = فقط نام و سازمان.
  bool? shareContact;

  /// لینک شخصی (صفحه‌ی شخصی) برای دکمه‌ی صفحه‌ی عمومی.
  String website;

  Person({
    required this.id,
    this.title = '',
    required this.firstName,
    required this.lastName,
    this.email = '',
    this.mobile = '',
    this.organization = '',
    this.country = '',
    required this.typeCode,
    this.presentationKind = '',
    this.roleCode,
    this.source = 'import',
    this.token,
    this.serial,
    this.shareContact,
    this.website = '',
  });

  String get fullName => '$firstName $lastName'.trim();
  String get displayName => '$title $firstName $lastName'.trim();

  Map<String, dynamic> toUpload() => {
        'id': id,
        'title': title,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'mobile': mobile,
        'organization': organization,
        'country': country,
        'registration_type': typeCode,
        'presentation_kind': presentationKind,
        'role': roleCode,
        'card_token': token,
        'card_serial': serial,
        'share_contact': shareContact,
        'website': website,
      };
}

class ReserveCard {
  final String token;
  final int serial;
  final bool used;
  ReserveCard(this.token, this.serial, this.used);
}

/// تنظیمات قالب کارت. مختصات به درصد از عرض/ارتفاع کارت.
class CardTemplate {
  String frontImage = '';
  String backImage = '';
  double widthMm = 85;
  double heightMm = 55;
  double nameX = 50;
  double nameY = 70;
  double nameSize = 16;
  String nameColor = '10141A';
  bool showRole = true;
  double qrX = 50;
  double qrY = 45;
  double qrSizeMm = 30;
  bool showSerial = true;

  Map<String, dynamic> toJson() => {
        'front_image': frontImage,
        'back_image': backImage,
        'width_mm': widthMm,
        'height_mm': heightMm,
        'name_x': nameX,
        'name_y': nameY,
        'name_size': nameSize,
        'name_color': nameColor,
        'show_role': showRole,
        'qr_x': qrX,
        'qr_y': qrY,
        'qr_size_mm': qrSizeMm,
        'show_serial': showSerial,
      };

  void load(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    frontImage = (j['front_image'] ?? '').toString();
    backImage = (j['back_image'] ?? '').toString();
    widthMm = d('width_mm', widthMm);
    heightMm = d('height_mm', heightMm);
    nameX = d('name_x', nameX);
    nameY = d('name_y', nameY);
    nameSize = d('name_size', nameSize);
    nameColor = (j['name_color'] ?? nameColor).toString();
    showRole = j['show_role'] != false;
    qrX = d('qr_x', qrX);
    qrY = d('qr_y', qrY);
    qrSizeMm = d('qr_size_mm', qrSizeMm);
    showSerial = j['show_serial'] != false;
  }
}

class ImportResult {
  final List<Person> people;
  final List<String> problems;
  final int updated;
  final int created;
  ImportResult(this.people, this.problems, this.updated, this.created);
}

/// تنظیم‌های رویداد که هم اپ نیروها و هم صفحه‌ی عمومی به آن نیاز دارند.
/// به سرور با پیکربندی فرستاده می‌شود (کلید `settings`) و یک نسخه هم روی همین رایانه می‌ماند.
class EventSettings {
  /// IdentifyMode: scan = کارت QR با اسکن، card = کارت بدون اسکن، none = بدون کارت.
  String identifyMode = 'scan';

  /// QrBehavior: person = صفحه‌ی فرد، redirect = انتقال به یک آدرس، vcard = کارت ویزیت.
  String qrBehavior = 'person';
  String redirectUrl = '';

  /// فیلدهای تماس مجاز در vCard و دکمه‌ی «ذخیره در مخاطبین». موبایل پیش‌فرض خاموش.
  bool shareName = true;
  bool shareOrg = true;
  bool shareEmail = false;
  bool shareMobile = false;
  bool shareCountry = false;

  /// خط «ساخته‌شده با رویدادیار» در صفحه‌ی عمومی.
  bool showMakerCredit = true;

  Map<String, dynamic> toJson() => {
        'identify_mode': identifyMode,
        'qr_behavior': qrBehavior,
        'qr_redirect_url': redirectUrl,
        'contact_fields': {
          'name': shareName,
          'organization': shareOrg,
          'email': shareEmail,
          'mobile': shareMobile,
          'country': shareCountry,
        },
        'show_maker_credit': showMakerCredit,
      };

  void load(Map<String, dynamic> j) {
    String pick(String k, List<String> allowed, String def) {
      final v = j[k]?.toString();
      return allowed.contains(v) ? v! : def;
    }

    identifyMode = pick('identify_mode', ['scan', 'card', 'none'], identifyMode);
    qrBehavior = pick('qr_behavior', ['person', 'redirect', 'vcard'], qrBehavior);
    redirectUrl = (j['qr_redirect_url'] ?? redirectUrl).toString();
    final c = ((j['contact_fields'] as Map?) ?? {}).cast<String, dynamic>();
    shareName = c['name'] as bool? ?? shareName;
    shareOrg = c['organization'] as bool? ?? shareOrg;
    shareEmail = c['email'] as bool? ?? shareEmail;
    shareMobile = c['mobile'] as bool? ?? shareMobile;
    shareCountry = c['country'] as bool? ?? shareCountry;
    showMakerCredit = j['show_maker_credit'] as bool? ?? showMakerCredit;
  }

  bool get usesCards => identifyMode != 'none';
}

class AdminState extends ChangeNotifier {
  String server = 'https://newvisionteam.ir';
  String apiKey = '';
  String? eventCode;

  List<EventInfo> events = [];
  EventInfo? event;

  List<CodeName> types = [];
  List<CodeName> roles = [];
  List<MealDef> meals = [];
  List<SessionDef> sessions = [];
  List<StaffDef> staff = [];

  Map<String, Person> people = {};
  List<ReserveCard> reserveCards = [];
  Map<String, dynamic>? report;

  final CardTemplate template = CardTemplate();
  EventSettings settings = EventSettings();
  Map<String, dynamic> _settingsByEvent = {};

  bool busy = false;
  String? message;
  bool messageIsError = false;

  AdminApi get api => AdminApi(server, apiKey);
  bool get connected => apiKey.isNotEmpty && events.isNotEmpty || event != null;

  // ---------------------------------------------------------------- ذخیره‌ی محلی

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/conference_admin.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        server = (j['server'] ?? server).toString();
        apiKey = (j['api_key'] ?? '').toString();
        eventCode = j['event_code']?.toString();
        template.load(((j['template'] as Map?) ?? {}).cast<String, dynamic>());
        final staffByEvent = ((j['staff'] as Map?) ?? {}).cast<String, dynamic>();
        if (eventCode != null && staffByEvent[eventCode] is List) {
          staff = (staffByEvent[eventCode] as List).map((e) => StaffDef.fromJson((e as Map).cast<String, dynamic>())).toList();
        }
        _staffByEvent = staffByEvent;
        _settingsByEvent = ((j['settings'] as Map?) ?? {}).cast<String, dynamic>();
        if (eventCode != null && _settingsByEvent[eventCode] is Map) {
          settings.load((_settingsByEvent[eventCode] as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Map<String, dynamic> _staffByEvent = {};

  Future<void> save() async {
    if (eventCode != null) _staffByEvent[eventCode!] = staff.map((s) => s.toJson()).toList();
    if (eventCode != null) _settingsByEvent[eventCode!] = settings.toJson();
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({
      'server': server,
      'api_key': apiKey,
      'event_code': eventCode,
      'template': template.toJson(),
      'staff': _staffByEvent,
      'settings': _settingsByEvent,
    }));
  }

  // ---------------------------------------------------------------- کمکی

  Future<T?> run<T>(String okMessage, Future<T> Function() fn) async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      final r = await fn();
      message = okMessage.isEmpty ? null : okMessage;
      messageIsError = false;
      return r;
    } catch (e) {
      message = e.toString();
      messageIsError = true;
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void notify() => notifyListeners();

  // ---------------------------------------------------------------- اتصال و رویداد

  Future<void> connect(String server, String key) => run('اتصال برقرار شد.', () async {
        this.server = server.trim();
        apiKey = key.trim();
        await api.get('/admin/ping');
        await _loadEvents();
        await save();
        if (eventCode != null && events.any((e) => e.code == eventCode)) await _loadEvent(eventCode!);
      });

  Future<void> _loadEvents() async {
    final list = await api.get('/admin/events') as List;
    events = list.map((e) => EventInfo.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> selectEvent(String code) => run('', () async {
        await _loadEvent(code);
        await save();
      });

  Future<void> saveEvent({
    required String code,
    required String name,
    required String startDate,
    required String endDate,
    required String baseUrl,
  }) =>
      run('رویداد ذخیره شد.', () async {
        await api.post('/admin/events', {
          'code': code.trim(),
          'name': name.trim(),
          'start_date': startDate.trim(),
          'end_date': endDate.trim(),
          'base_url': baseUrl.trim(),
        });
        await _loadEvents();
        await _loadEvent(code.trim());
        await save();
      });

  Future<void> reload() => run('', () async {
        if (eventCode != null) await _loadEvent(eventCode!);
      });

  /// همه‌چیز رویداد از سرور: پیکربندی، شرکت‌کننده‌ها و کارت‌ها.
  Future<void> _loadEvent(String code) async {
    final prevStaff = eventCode == code ? staff : null;
    eventCode = code;
    final s = (await api.get('/admin/events/$code/snapshot') as Map).cast<String, dynamic>();
    event = EventInfo.fromJson((s['event'] as Map).cast<String, dynamic>());

    List<Map<String, dynamic>> list(String k) =>
        ((s[k] as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();

    final typeById = <int, String>{};
    types = [
      for (final t in list('registration_types')) CodeName(t['code'].toString(), t['name'].toString()),
    ];
    for (final t in list('registration_types')) {
      typeById[t['id'] as int] = t['code'].toString();
    }
    final roleById = <int, String>{};
    roles = [for (final r in list('roles')) CodeName(r['code'].toString(), r['name'].toString())];
    for (final r in list('roles')) {
      roleById[r['id'] as int] = r['code'].toString();
    }
    meals = [
      for (final m in list('meals'))
        MealDef(
          m['code'].toString(),
          m['name'].toString(),
          (m['day'] ?? '').toString(),
          (((m['rules'] as Map?)?['registration_type_ids'] as List?) ?? [])
              .map((id) => typeById[id as int])
              .whereType<String>()
              .toSet(),
          (((m['rules'] as Map?)?['role_ids'] as List?) ?? []).map((id) => roleById[id as int]).whereType<String>().toSet(),
        ),
    ];
    sessions = list('sessions').map(SessionDef.fromJson).toList();

    final cardByAttendee = <String, Map<String, dynamic>>{};
    reserveCards = [];
    for (final c in list('cards')) {
      final aid = c['attendee_id']?.toString();
      if (c['is_reserve'] == true) {
        reserveCards.add(ReserveCard(c['token'].toString(), c['serial'] as int, aid != null));
      }
      if (aid != null) cardByAttendee[aid] = c;
    }
    reserveCards.sort((a, b) => a.serial.compareTo(b.serial));

    people = {};
    for (final a in list('attendees')) {
      final id = a['id'].toString();
      final card = cardByAttendee[id];
      people[id] = Person(
        id: id,
        title: (a['title'] ?? '').toString(),
        firstName: (a['first_name'] ?? '').toString(),
        lastName: (a['last_name'] ?? '').toString(),
        email: (a['email'] ?? '').toString(),
        mobile: (a['mobile'] ?? '').toString(),
        organization: (a['organization'] ?? '').toString(),
        country: (a['country'] ?? '').toString(),
        typeCode: typeById[a['registration_type_id'] as int] ?? '',
        presentationKind: (a['presentation_kind'] ?? '').toString(),
        roleCode: a['role_id'] == null ? null : roleById[a['role_id'] as int],
        source: (a['source'] ?? 'import').toString(),
        token: card?['token']?.toString(),
        serial: card?['serial'] as int?,
        shareContact: a['share_contact'] as bool?,
        website: (a['website'] ?? '').toString(),
      );
    }

    // نیروها: نام‌ها از سرور، تنظیمات از ذخیره‌ی محلی همین رویداد.
    final saved = prevStaff ??
        ((_staffByEvent[code] as List?) ?? [])
            .map((e) => StaffDef.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
    final byName = {for (final s in saved) s.name: s};
    staff = [
      for (final st in list('staff')) byName[st['name'].toString()] ?? StaffDef(st['name'].toString(), hasPin: true),
    ];
    for (final s in saved) {
      if (!staff.any((x) => x.name == s.name)) staff.add(s);
    }
    // قالب کارت از سرور، اگر آنجا ذخیره شده؛ مسیر تصویرهای طرح همان محلی می‌ماند.
    final serverTemplate = s['card_template'];
    if (serverTemplate is Map) {
      final local = template.toJson();
      template.load({...local, ...serverTemplate.cast<String, dynamic>()});
    }
    // تنظیم‌های رویداد: اگر سرور دارد از سرور، وگرنه نسخه‌ی محلی همین رویداد.
    settings = EventSettings();
    final local = _settingsByEvent[code];
    if (local is Map) settings.load(local.cast<String, dynamic>());
    final remote = (s['settings'] as Map?) ?? ((s['event'] as Map?)?['settings'] as Map?);
    if (remote != null) settings.load(remote.cast<String, dynamic>());
    report = null;
  }

  // ---------------------------------------------------------------- پیکربندی

  Future<void> pushConfig() => run('پیکربندی روی سرور ذخیره شد.', () async {
        final r = (await api.post('/admin/events/$eventCode/config', {
          'registration_types': types.map((t) => t.toJson()).toList(),
          'roles': roles.map((t) => t.toJson()).toList(),
          'meals': [
            for (var i = 0; i < meals.length; i++) {...meals[i].toJson(), 'sort': i},
          ],
          'sessions': sessions.map((s) => s.toJson()).toList(),
          'settings': settings.toJson(),
        }) as Map)
            .cast<String, dynamic>();
        final errors = (r['errors'] as List?) ?? [];
        await save();
        await _loadEvent(eventCode!);
        if (errors.isNotEmpty) throw ApiException('partial', 'بعضی ردیف‌ها ذخیره نشدند: ${jsonEncode(errors)}', 200);
      });

  Future<void> pushStaff() => run('نیروها روی سرور ذخیره شدند.', () async {
        final r = await api.post('/admin/events/$eventCode/staff', {
          'staff': [
            for (final s in staff)
              {
                'name': s.name,
                if (s.newPin.isNotEmpty) 'pin': latinDigits(s.newPin),
                'can_checkin': s.canCheckin,
                'can_serve': s.canServe,
                'is_admin': s.isAdmin,
              },
          ],
        }) as List;
        for (final s in staff) {
          s.newPin = '';
          final row = r.cast<Map>().firstWhere((x) => x['name'] == s.name, orElse: () => {});
          s.hasPin = row['has_pin'] == true;
        }
        await save();
      });

  // ---------------------------------------------------------------- ورود اکسل

  String _stableId(String key) => _uuid.v5(_attendeeNamespace, '$eventCode|$key');

  static String _randomToken() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  int get _nextSerial {
    var m = 0;
    for (final p in people.values) {
      if (p.serial != null && p.serial! < reserveSerialStart && p.serial! > m) m = p.serial!;
    }
    return m + 1;
  }

  /// تبدیل ردیف‌های اکسل به شرکت‌کننده؛ فقط پیش‌نمایش، چیزی ارسال نمی‌شود.
  ImportResult buildImport(SheetTable table, Map<String, int> mapping, String typeCode) {
    final out = <String, Person>{};
    final problems = <String>[];
    var serial = _nextSerial;
    var created = 0;
    var updated = 0;
    String cell(List<String> row, String field) {
      final i = mapping[field];
      return (i == null || i >= row.length) ? '' : row[i].trim();
    }

    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      var first = cell(row, 'first_name');
      var last = cell(row, 'last_name');
      if ((first.isEmpty || last.isEmpty) && cell(row, 'full_name').isNotEmpty) {
        final parts = cell(row, 'full_name').split(RegExp(r'\s+'));
        first = parts.first;
        last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      if (first.isEmpty || last.isEmpty) {
        problems.add('ردیف ${r + 2}: نام یا نام خانوادگی خالی است؛ رد شد.');
        continue;
      }
      final email = cell(row, 'email').toLowerCase();
      final mobile = normalizeMobile(cell(row, 'mobile'));
      final key = email.isNotEmpty ? 'e:$email' : (mobile.isNotEmpty ? 'm:$mobile' : 'n:${normalizeText('$first $last')}');
      final id = _stableId(key);
      if (out.containsKey(id)) {
        problems.add('ردیف ${r + 2}: تکراری ($first $last)؛ فقط یک بار وارد می‌شود.');
        continue;
      }
      final existing = people[id];
      var roleCode = existing?.roleCode;
      final roleRaw = cell(row, 'role');
      if (roleRaw.isNotEmpty) {
        final n = normalizeText(roleRaw);
        final match = roles.where((ro) => normalizeText(ro.name) == n || ro.code == roleRaw);
        if (match.isNotEmpty) {
          roleCode = match.first.code;
        } else {
          problems.add('ردیف ${r + 2}: نقش «$roleRaw» تعریف نشده؛ بدون نقش وارد شد.');
        }
      }
      final pk = presentationKindFrom(cell(row, 'presentation_kind'));
      out[id] = Person(
        id: id,
        title: cell(row, 'title'),
        firstName: first,
        lastName: last,
        email: email,
        mobile: mobile,
        organization: cell(row, 'organization'),
        country: cell(row, 'country'),
        typeCode: typeCode,
        presentationKind: pk.isNotEmpty ? pk : (existing?.presentationKind ?? ''),
        roleCode: roleCode,
        token: existing?.token ?? _randomToken(),
        serial: existing?.serial ?? serial++,
        shareContact: shareFrom(cell(row, 'share_contact')) ?? existing?.shareContact,
        website: cell(row, 'website').isNotEmpty ? cell(row, 'website') : (existing?.website ?? ''),
      );
      if (existing == null) {
        created++;
      } else {
        updated++;
      }
    }
    return ImportResult(out.values.toList(), problems, updated, created);
  }

  Future<void> uploadPeople(List<Person> list) => run('${faDigits(list.length)} نفر روی سرور ذخیره شدند.', () async {
        final errors = <dynamic>[];
        for (var i = 0; i < list.length; i += 200) {
          final batch = list.sublist(i, min(i + 200, list.length));
          final r = (await api.post('/admin/events/$eventCode/attendees', {
            'attendees': batch.map((p) => p.toUpload()).toList(),
          }) as Map)
              .cast<String, dynamic>();
          errors.addAll((r['errors'] as List?) ?? []);
        }
        await _loadEvent(eventCode!);
        if (errors.isNotEmpty) throw ApiException('partial', 'بعضی ردیف‌ها ذخیره نشدند: ${jsonEncode(errors)}', 200);
      });

  // ---------------------------------------------------------------- کارت رزرو و قفل

  Future<void> addReserveCards(int count) => run('${faDigits(count)} کارت رزرو ساخته شد.', () async {
        var serial = reserveSerialStart;
        for (final c in reserveCards) {
          if (c.serial >= serial) serial = c.serial + 1;
        }
        final cards = [for (var i = 0; i < count; i++) {'token': _randomToken(), 'serial': serial + i}];
        await api.post('/admin/events/$eventCode/reserve-cards', {'cards': cards});
        await _loadEvent(eventCode!);
      });

  /// قالب کارت روی سرور تا اپ ویندوز و موبایل یک قالب ببینند (مسیر تصویرهای طرح محلی می‌ماند).
  Future<void> saveTemplate() => run('قالب کارت ذخیره شد.', () async {
        await save();
        final j = template.toJson()
          ..remove('front_image')
          ..remove('back_image');
        await api.post('/admin/events/$eventCode/card-template', {'template': j});
      });

  /// باطل‌کردن دسترسی یک دستگاه نیرو.
  Future<void> revokeDevice(int id) => run('دستگاه باطل شد.', () async {
        await api.post('/admin/devices/$id/revoke', {});
        report = (await api.get('/admin/events/$eventCode/report') as Map).cast<String, dynamic>();
      });

  /// لغو پذیرش یک نفر از اپ مدیریت (در دفتر رخدادها ثبت می‌شود).
  Future<void> undoCheckin(String attendeeId) => run('پذیرش لغو شد.', () async {
        await api.post('/admin/events/$eventCode/attendees/$attendeeId/checkin-undo', {});
      });

  Future<void> setLocked(bool locked) => run(locked ? 'آدرس پایه قفل شد.' : 'قفل آدرس پایه برداشته شد.', () async {
        await api.post('/admin/events/$eventCode/lock', {'locked': locked});
        await _loadEvent(eventCode!);
      });

  String qrUrl(String token) {
    final base = (event?.baseUrl ?? server).replaceAll(RegExp(r'/+$'), '');
    return '$base/c/$token';
  }

  /// محتوای QR یک نفر بسته به QrBehavior. کارت‌های رزرو همیشه لینک‌اند چون موقع چاپ صاحب ندارند.
  String qrDataFor(Person p) => settings.qrBehavior == 'vcard' ? vcardFor(p) : qrUrl(p.token!);

  /// vCard 3.0 با UTF-8. نام در N، سازمان در ORG، نقش کنفرانس در NOTE، TITLE خالی.
  /// URL اجباری است چون اپ نیروها توکن را از همین فیلد می‌خواند.
  String vcardFor(Person p) {
    String esc(String v) => v.replaceAll(r'\', r'\\').replaceAll(',', r'\,').replaceAll(';', r'\;').replaceAll('\n', r'\n');
    final st = settings;
    final no = p.shareContact == false; // «خیر» خود فرد: فقط نام و سازمان
    final role = roleName(p.roleCode);
    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      if (st.shareName) 'N:${esc(p.lastName)};${esc(p.firstName)};;${esc(p.title)};',
      'FN:${esc(st.shareName ? p.displayName : (p.organization.isNotEmpty ? p.organization : 'شرکت‌کننده'))}',
      if (st.shareOrg && p.organization.isNotEmpty) 'ORG:${esc(p.organization)}',
      if (!no && st.shareEmail && p.email.isNotEmpty) 'EMAIL;TYPE=INTERNET:${esc(p.email)}',
      if (!no && st.shareMobile && p.mobile.isNotEmpty) 'TEL;TYPE=CELL:${esc(p.mobile)}',
      if (!no && st.shareCountry && p.country.isNotEmpty) 'ADR:;;;;;;${esc(p.country)}',
      'NOTE:${esc([if (role.isNotEmpty) role, event?.name ?? ''].where((x) => x.isNotEmpty).join(' · '))}',
      'URL:${qrUrl(p.token!)}',
      'END:VCARD',
    ];
    return lines.join('\r\n');
  }

  /// خط ۷pt زیر QR که می‌گوید اسکن با دوربین معمولی چه می‌کند.
  String qrHint({required bool reserve}) {
    if (reserve) return 'اسکن کنید: صفحه‌ی من';
    return switch (settings.qrBehavior) {
      'vcard' => 'اسکن کنید: ذخیره در مخاطبین',
      'redirect' => settings.redirectUrl.trim().isEmpty ? 'اسکن کنید: صفحه‌ی من' : 'اسکن کنید: سایت رویداد',
      _ => 'اسکن کنید: صفحه‌ی من',
    };
  }

  /// کمینه‌ی اندازه‌ی چاپ QR: لینک ۲۲mm، کارت ویزیت (پرتراکم‌تر) ۳۰mm.
  double get minQrMm => settings.qrBehavior == 'vcard' ? 30 : 22;

  /// کارت‌ها به ترتیب الفبایی نام خانوادگی، همان ترتیبی که روز پذیرش دنبالشان می‌گردند.
  List<Person> get sortedPeople {
    final l = people.values.where((p) => p.token != null && p.source != 'walkin').toList();
    l.sort((a, b) {
      final c = normalizeText(a.lastName).compareTo(normalizeText(b.lastName));
      return c != 0 ? c : normalizeText(a.firstName).compareTo(normalizeText(b.firstName));
    });
    return l;
  }

  String typeName(String code) => types.firstWhere((t) => t.code == code, orElse: () => CodeName(code, code)).name;
  String roleName(String? code) =>
      code == null ? '' : roles.firstWhere((t) => t.code == code, orElse: () => CodeName(code, code)).name;

  // ---------------------------------------------------------------- گزارش

  Future<void> loadReport() => run('', () async {
        report = (await api.get('/admin/events/$eventCode/report') as Map).cast<String, dynamic>();
      });

  /// تاریخچه‌ی یک نفر (PersonTimeline): پذیرش، وعده‌ها و موارد مشکوک به ترتیب زمان.
  /// نیازمند مسیر `GET /admin/events/{code}/attendees/{id}/timeline` در افزونه.
  Future<List<Map<String, dynamic>>> loadTimeline(String attendeeId) async {
    final r = await api.get('/admin/events/$eventCode/attendees/$attendeeId/timeline');
    final list = r is Map ? (r['events'] as List? ?? const []) : (r as List);
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}
