import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'card_logic.dart';
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

  /// بایگانی‌شده: از فهرست کنار رفته و فقط خواندنی است.
  final bool archived;
  EventInfo(this.code, this.name, this.startDate, this.endDate, this.baseUrl, this.locked, [this.archived = false]);

  factory EventInfo.fromJson(Map<String, dynamic> j) => EventInfo(
        j['code'].toString(),
        (j['name'] ?? '').toString(),
        j['start_date']?.toString(),
        j['end_date']?.toString(),
        (j['base_url'] ?? '').toString(),
        j['base_url_locked'] == true,
        j['archived'] == true,
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

  /// وعده‌ی غیرفعال در گوشی نیروها دیده نمی‌شود ولی تحویل‌های قبلی‌اش در گزارش می‌ماند.
  bool active;

  /// شناسه‌ی سرور (برای خواندن تاریخچه)؛ وعده‌ی ذخیره‌نشده ندارد.
  int? id;
  MealDef(this.code, this.name, this.day, this.types, this.roles, {this.active = true});

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'day': day,
        'registration_types': types.toList(),
        'roles': roles.toList(),
        'active': active,
      };

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

/// یک نیرو، همان‌طور که روی سرور است. اجازه‌ها و فعال‌بودن فقط از سرور خوانده می‌شود، نه فایل محلی.
class StaffDef {
  /// شناسه‌ی سرور؛ null یعنی نیروی تازه‌ای که هنوز ذخیره نشده.
  int? id;
  String name;
  String newPin; // فقط تا ارسال بعدی در حافظه می‌ماند و ذخیره نمی‌شود
  bool canCheckin;
  bool canServe;
  bool isAdmin;
  bool hasPin;
  bool active;

  /// پین فعلی از سرور (آ-۱)؛ null برای نیروی بی‌پین یا قدیمی که هنوز وارد نشده (pinLegacy).
  String? pin;
  bool pinLegacy;

  /// زمان و فاعل آخرین ذخیره روی سرور؛ updatedAt برای تشخیص تعارض فرستاده می‌شود.
  String? updatedAt;
  String updatedBy;
  StaffDef(
    this.name, {
    this.id,
    this.newPin = '',
    this.canCheckin = true,
    this.canServe = true,
    this.isAdmin = false,
    this.hasPin = false,
    this.active = true,
    this.updatedAt,
    this.updatedBy = '',
    this.pin,
    this.pinLegacy = false,
  });

  /// ردیف ارسال به سرور (ذخیره‌ی جزئی).
  Map<String, dynamic> toUpload() => {
        if (id != null) 'id': id,
        'name': name,
        if (newPin.isNotEmpty) 'pin': latinDigits(newPin),
        'can_checkin': canCheckin,
        'can_serve': canServe,
        'is_admin': isAdmin,
        'active': active,
        if (id != null) 'updated_at': updatedAt,
      };

  factory StaffDef.fromJson(Map<String, dynamic> j) => StaffDef(
        j['name'].toString(),
        id: j['id'] as int?,
        canCheckin: j['can_checkin'] != false,
        canServe: j['can_serve'] != false,
        isAdmin: j['is_admin'] == true,
        hasPin: j['has_pin'] == true,
        active: j['active'] != false,
        updatedAt: j['updated_at']?.toString(),
        updatedBy: (j['updated_by'] ?? '').toString(),
        pin: j['pin']?.toString(),
        pinLegacy: j['pin_legacy'] == true,
      );
}

/// آیا فرد با این تاریخچه (خروجی timeline سرور) الان پذیرش‌شده است؟ آخرین پذیرش یا لغو، به ترتیب seq.
/// با [day] (حضور روزانه) فقط رخدادهای همان روز.
bool isCheckedInFromTimeline(List<Map<String, dynamic>> events, {String? day}) {
  final l = [...events]..sort((a, b) => ((a['seq'] as int?) ?? 0).compareTo((b['seq'] as int?) ?? 0));
  var inNow = false;
  for (final e in l) {
    if (day != null && e['day'] != null && e['day'] != day) continue;
    if (e['kind'] == 'checkin') inNow = true;
    if (e['kind'] == 'checkin_undo') inNow = false;
  }
  return inNow;
}

/// شمار فعلی تحویل هر وعده (meal_id) از تاریخچه: تحویل منهای برگردان.
Map<int, int> mealCountsFromTimeline(List<Map<String, dynamic>> events) {
  final out = <int, int>{};
  for (final e in events) {
    final id = e['meal_id'] as int?;
    if (id == null) continue;
    if (e['kind'] == 'meal_served') out[id] = (out[id] ?? 0) + 1;
    if (e['kind'] == 'meal_undo') out[id] = ((out[id] ?? 0) - 1).clamp(0, 1 << 30);
  }
  return out;
}

/// امروز (وقت این دستگاه) به شکل YYYY-MM-DD.
String todayIso([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// افراد فعال دیگری با موبایل یا ایمیل یکسان با [p].
List<Person> findPossibleDuplicates(Person p, Iterable<Person> all) {
  final m = normalizeMobile(p.mobile);
  final e = p.email.trim().toLowerCase();
  return all
      .where((o) =>
          o.id != p.id &&
          o.isActive &&
          ((m.isNotEmpty && normalizeMobile(o.mobile) == m) || (e.isNotEmpty && o.email.trim().toLowerCase() == e)))
      .toList();
}

/// یک فایل اکسلِ واردشده («ورودی‌های قبلی»).
class ImportBatch {
  final String id;
  final String fileName;
  final String? createdAt;
  final int people;
  final int withActivity;
  ImportBatch(this.id, this.fileName, this.createdAt, this.people, this.withActivity);

  factory ImportBatch.fromJson(Map<String, dynamic> j) => ImportBatch(
        j['id'].toString(),
        (j['file_name'] ?? '').toString(),
        j['created_at']?.toString(),
        (j['people'] as int?) ?? 0,
        (j['with_activity'] as int?) ?? 0,
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

  /// active یا inactive (حذف‌شده‌ها از سرور نمی‌آیند).
  String status;
  String importBatch;

  /// آخرین بار که کارتش برای چاپخانه ساخته شد؛ null یعنی «چاپ‌نشده».
  String? printedAt;
  int printCount;

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
    this.status = 'active',
    this.importBatch = '',
    this.printedAt,
    this.printCount = 0,
  });

  bool get printed => printedAt != null;

  bool get isActive => status == 'active';

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

/// ردیفی از اکسل که موبایل یا ایمیلش با فرد فعلی دیگری یکی است. [row] شماره‌ی ردیف داده (از ۰).
class ImportConflict {
  final int row;
  final Person existing;
  final Person incoming;
  ImportConflict(this.row, this.existing, this.incoming);
}

class ImportResult {
  final List<Person> people;
  final List<String> problems;
  final int updated;
  final int created;

  /// ردیف‌هایی که موبایل یا ایمیلشان با ردیف دیگری یکی است ولی نامشان نه: جدا وارد می‌شوند.
  final int possibleDuplicates;

  /// ردیف‌هایی که موبایل یا ایمیلشان با فرد فعلی دیگری یکی است (ادغام / فرد جدید / رد).
  final List<ImportConflict> conflicts;

  /// ردیف‌های واردشونده بدون موبایل («ناقص · وارد می‌شوند»).
  final int incomplete;
  ImportResult(this.people, this.problems, this.updated, this.created,
      [this.possibleDuplicates = 0, this.conflicts = const [], this.incomplete = 0]);
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

  /// حضور روزانه: پذیرش هر روز جدا ثبت می‌شود و تکراری فقط در همان روز.
  bool dailyAttendance = false;

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
        'daily_attendance': dailyAttendance,
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
    dailyAttendance = j['daily_attendance'] as bool? ?? dailyAttendance;
  }

  bool get usesCards => identifyMode != 'none';
}

class AdminState extends ChangeNotifier {
  String server = 'https://newvisionteam.ir';
  String apiKey = '';

  /// نقش کلید از /admin/ping: owner، manager یا report. افزونه‌ی قدیمی نقش نمی‌فرستد = owner.
  String keyRole = 'owner';
  String keyRoleLabel = '';

  /// «دسترسی محدود»: کلید فقط گزارش؛ ناوبری فقط «امروز» و «افراد»، بدون تغییر.
  bool get limited => keyRole == 'report';

  /// حذف و بایگانی رویداد فقط برای مالک.
  bool get isOwner => keyRole == 'owner';
  String? eventCode;

  List<EventInfo> events = [];
  List<EventInfo> archivedEvents = [];
  EventInfo? event;

  /// کدهایی که روی سرور هستند؛ حذف این‌ها از راه API است، بقیه فقط از فرم.
  Set<String> serverTypeCodes = {};
  Set<String> serverRoleCodes = {};
  Set<String> serverMealCodes = {};
  List<ImportBatch> imports = [];

  List<CodeName> types = [];
  List<CodeName> roles = [];
  List<MealDef> meals = [];
  List<SessionDef> sessions = [];
  List<StaffDef> staff = [];

  Map<String, Person> people = {};
  List<ReserveCard> reserveCards = [];
  Map<String, dynamic>? report;

  /// روز انتخاب‌شده در «امروز» (حضور روزانه)؛ null = همه‌ی روزها.
  String? reportDay;

  /// قالب‌های کارت رویداد (نسخه‌ی ۲)؛ مسیر تصویرهای طرح فقط روی همین رایانه.
  final CardTemplateSet cards = CardTemplateSet();

  /// با هر بار خواندن قالب‌ها از سرور یا فایل بالا می‌رود تا فیلدهای صفحه‌ی کارت تازه شوند.
  int cardsRev = 0;
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
        keyRole = (j['key_role'] ?? 'owner').toString();
        keyRoleLabel = (j['key_role_label'] ?? '').toString();
        eventCode = j['event_code']?.toString();
        cards.load(((j['template'] as Map?) ?? {}).cast<String, dynamic>());
        cardsRev++;
        // نیروها فقط از سرور خوانده می‌شوند (فایل محلی قدیمی نادیده گرفته می‌شود).
        _settingsByEvent = ((j['settings'] as Map?) ?? {}).cast<String, dynamic>();
        if (eventCode != null && _settingsByEvent[eventCode] is Map) {
          settings.load((_settingsByEvent[eventCode] as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    if (eventCode != null) _settingsByEvent[eventCode!] = settings.toJson();
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({
      'server': server,
      'api_key': apiKey,
      'key_role': keyRole,
      'key_role_label': keyRoleLabel,
      'event_code': eventCode,
      'template': cards.toJson(images: true),
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
      // پیام خالی یعنی پیامی که خود کار گذاشته (مثلاً شمار حذف‌شده‌ها) بماند.
      if (okMessage.isNotEmpty) message = okMessage;
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
        final ping = ((await api.get('/admin/ping')) as Map).cast<String, dynamic>();
        keyRole = const ['owner', 'manager', 'report'].contains(ping['role']) ? ping['role'] as String : 'owner';
        keyRoleLabel = (ping['role_label'] ?? '').toString();
        await _loadEvents();
        await save();
        if (eventCode != null && events.any((e) => e.code == eventCode)) await _loadEvent(eventCode!);
      });

  Future<void> _loadEvents() async {
    final list = await api.get('/admin/events?include_archived=1') as List;
    final all = list.map((e) => EventInfo.fromJson((e as Map).cast<String, dynamic>())).toList();
    // افزونه‌ی قدیمی include_archived را نمی‌شناسد و archived نمی‌فرستد؛ همه فعال حساب می‌شوند.
    events = all.where((e) => !e.archived).toList();
    archivedEvents = all.where((e) => e.archived).toList();
  }

  Future<void> selectEvent(String code) => run('', () async {
        await _loadEvent(code);
        await save();
      });

  /// ساخت ([create] = true) یا ویرایش رویداد. کد رویداد بعد از ساخت عوض نمی‌شود؛
  /// ویرایش هیچ‌وقت رویداد تازه نمی‌سازد (mode در افزونه).
  Future<void> saveEvent({
    required String code,
    required String name,
    required String startDate,
    required String endDate,
    required String baseUrl,
    bool create = false,
  }) =>
      run(create ? 'رویداد ساخته شد.' : 'رویداد ذخیره شد.', () async {
        await api.post('/admin/events', {
          'mode': create ? 'create' : 'update',
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

  /// پیامد حذف رویداد: شمار افراد، پذیرش، تحویل و نیروها.
  Future<Map<String, dynamic>> eventImpact() async =>
      ((await api.get('/admin/events/$eventCode/impact')) as Map).cast<String, dynamic>();

  /// بایگانی یا برگرداندن رویداد فعلی.
  Future<void> archiveEvent(bool archived) =>
      run(archived ? 'رویداد بایگانی شد.' : 'رویداد از بایگانی برگشت.', () async {
        await api.post('/admin/events/$eventCode/archive', {'archived': archived});
        await _loadEvents();
        await _loadEvent(eventCode!);
      });

  /// حذف واقعی رویداد؛ سرور فقط وقتی کاری ثبت نشده قبول می‌کند. خطای 409 (کار ثبت‌شده) به بالا می‌رود.
  Future<void> deleteEvent(String confirmCode) async {
    await api.delete('/admin/events/$eventCode', {'confirm': confirmCode});
    event = null;
    eventCode = null;
    staff = [];
    people = {};
    await _loadEvents();
    await save();
    message = 'رویداد حذف شد.';
    messageIsError = false;
    notifyListeners();
  }

  Future<void> reload() => run('', () async {
        if (eventCode != null) await _loadEvent(eventCode!);
      });

  /// همه‌چیز رویداد از سرور: پیکربندی، شرکت‌کننده‌ها و کارت‌ها.
  Future<void> _loadEvent(String code) async {
    eventCode = code;
    if (limited) {
      // کلید «فقط گزارش» snapshot را نمی‌بیند؛ رویداد از فهرست رویدادها، بقیه از گزارش و خروجی.
      event = [...events, ...archivedEvents].where((e) => e.code == code).firstOrNull;
      types = [];
      roles = [];
      meals = [];
      staff = [];
      people = {};
      report = null;
      return;
    }
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
    for (var i = 0; i < meals.length; i++) {
      meals[i].active = list('meals')[i]['active'] != false;
      meals[i].id = list('meals')[i]['id'] as int?;
    }
    serverTypeCodes = types.map((t) => t.code).toSet();
    serverRoleCodes = roles.map((t) => t.code).toSet();
    serverMealCodes = meals.map((t) => t.code).toSet();
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
        status: (a['status'] ?? 'active').toString(),
        importBatch: (a['import_batch'] ?? '').toString(),
        printedAt: a['printed_at']?.toString(),
        printCount: (a['print_count'] as int?) ?? 0,
      );
    }

    // نیروها فقط از سرور: فعال/غیرفعال، اجازه‌ها و داشتن PIN. نیروی غیرفعال دوباره اضافه یا فعال نمی‌شود.
    staff = list('staff').map(StaffDef.fromJson).toList();
    await _loadStaffPins();
    // قالب‌های کارت از سرور، اگر آنجا ذخیره شده؛ مسیر تصویرهای طرح همان محلی می‌ماند.
    // قالب تکی قدیمی (بدون templates) قالب «پیش‌فرض» می‌شود.
    final serverTemplate = s['card_template'];
    if (serverTemplate is Map) {
      final images = cards.images();
      cards.load(serverTemplate.cast<String, dynamic>());
      cards.restoreImages(images);
      cardsRev++;
    }
    // تنظیم‌های رویداد: اگر سرور دارد از سرور، وگرنه نسخه‌ی محلی همین رویداد.
    settings = EventSettings();
    final local = _settingsByEvent[code];
    if (local is Map) settings.load(local.cast<String, dynamic>());
    final remote = (s['settings'] as Map?) ?? ((s['event'] as Map?)?['settings'] as Map?);
    if (remote != null) settings.load(remote.cast<String, dynamic>());
    report = null;
    await _loadImportsQuiet();
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

  /// ذخیره‌ی نیروها (فقط ردیف‌های همین فهرست؛ partial). اگر کسی دیگر بعد از آخرین خواندن ذخیره کرده باشد،
  /// چیزی ذخیره نمی‌شود و ردیف‌های فعلی سرور برمی‌گردد (تعارض). [force] یعنی «تغییر من را بگذار».
  Future<List<StaffDef>?> pushStaff({bool force = false}) async {
    List<StaffDef>? conflicts;
    await run('نیروها روی سرور ذخیره شدند.', () async {
      try {
        final r = await api.post('/admin/events/$eventCode/staff', {
          'partial': true,
          if (force) 'force': true,
          'staff': [for (final s in staff) s.toUpload()],
        }) as List;
        staff = r.map((e) => StaffDef.fromJson((e as Map).cast<String, dynamic>())).toList();
        await _loadStaffPins();
      } on ApiException catch (e) {
        if (e.code != 'cd_staff_conflict') rethrow;
        final list = ((e.data as Map?)?['conflicts'] as List?) ?? const [];
        conflicts = list.map((x) => StaffDef.fromJson((x as Map).cast<String, dynamic>())).toList();
      }
    });
    if (conflicts != null) {
      message = null;
      notifyListeners();
    }
    return conflicts;
  }

  /// پین نیروها از GET staff (افزونه‌ی ۰٫۶ به بعد، کلید مالک یا مدیر). خطا یعنی پین نمایش داده نمی‌شود.
  Future<void> _loadStaffPins() async {
    try {
      final r = await api.get('/admin/events/$eventCode/staff') as List;
      final byId = {for (final x in r.cast<Map>()) x['id']: x};
      for (final st in staff) {
        final x = byId[st.id];
        if (x == null) continue;
        st.pin = x['pin']?.toString();
        st.pinLegacy = x['pin_legacy'] == true;
      }
    } catch (_) {}
  }

  /// «تغییر او را ببین»: فهرست نیروها از سرور، تغییرهای ذخیره‌نشده‌ی این دستگاه دور ریخته می‌شود.
  Future<void> reloadStaff() => run('', () async {
        final r = await api.get('/admin/events/$eventCode/staff') as List;
        staff = r.map((e) => StaffDef.fromJson((e as Map).cast<String, dynamic>())).toList();
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
  /// تبدیل ردیف‌های اکسل به شرکت‌کننده.
  /// نوع: [typeCode] برای همه، یا از ستون `type` با [typeByValue] (normalizeText مقدار → کد نوع).
  /// نقش: اگر [roleByValue] داده شود از آن (مقدار null = بدون نقش)، وگرنه تطبیق نام یا کد.
  /// [resolutions]: برای ردیفی که با فرد فعلی دیگری تماس مشترک دارد: merge، new (پیش‌فرض) یا skip.
  ImportResult buildImport(
    SheetTable table,
    Map<String, int> mapping,
    String? typeCode, {
    Map<String, String>? typeByValue,
    Map<String, String?>? roleByValue,
    Map<int, String> resolutions = const {},
  }) {
    final out = <String, Person>{};
    final problems = <String>[];
    final conflicts = <ImportConflict>[];
    var incomplete = 0;
    var serial = _nextSerial;
    var created = 0;
    var updated = 0;
    var possibleDuplicates = 0;
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
      final nameKey = normalizeText('$first $last');
      final key = email.isNotEmpty ? 'e:$email' : (mobile.isNotEmpty ? 'm:$mobile' : 'n:$nameKey');
      var id = _stableId(key);
      if (out.containsKey(id)) {
        final other = out[id]!;
        if (normalizeText('${other.firstName} ${other.lastName}') == nameKey) {
          problems.add('ردیف ${r + 2}: تکرار همان ردیف ($first $last)؛ فقط یک بار وارد می‌شود.');
          continue;
        }
        // تماس مشترک با نام دیگر (مثلاً موبایل یک اداره): بی‌صدا حذف نمی‌شود؛ جدا وارد و «احتمال تکراری» گزارش می‌شود.
        id = _stableId('$key|n:$nameKey');
        if (out.containsKey(id)) {
          problems.add('ردیف ${r + 2}: تکرار همان ردیف ($first $last)؛ فقط یک بار وارد می‌شود.');
          continue;
        }
        possibleDuplicates++;
        problems.add('ردیف ${r + 2}: ${email.isNotEmpty ? 'ایمیل' : 'موبایل'} با «${other.fullName}» یکی است؛ '
            'جدا وارد شد (احتمال تکراری). بعداً از صفحه‌ی فرد می‌توانید ادغام کنید.');
      }
      // نوع: یک نوع برای همه یا از ستون با جدول تطبیق.
      var rowType = typeCode;
      if (rowType == null) {
        final raw = cell(row, 'type');
        rowType = typeByValue?[normalizeText(raw)];
        if (rowType == null) {
          problems.add('ردیف ${r + 2}: نوع «$raw» به نوعی تطبیق داده نشده؛ رد شد.');
          continue;
        }
      }
      // تماس مشترک با فرد فعلی دیگری: تصمیم با مدیر (ادغام، فرد جدید، رد).
      if (people[id] == null) {
        final probe = Person(id: id, firstName: first, lastName: last, typeCode: rowType, mobile: mobile, email: email);
        final same = findPossibleDuplicates(probe, people.values);
        if (same.isNotEmpty) {
          final choice = resolutions[r] ?? 'new';
          // کارت تصمیم همیشه می‌ماند تا انتخاب «رد» هم برگشت‌پذیر باشد.
          conflicts.add(ImportConflict(r, same.first, probe));
          if (choice == 'skip') {
            problems.add('ردیف ${r + 2}: تکراری با «${same.first.fullName}»؛ به انتخاب شما رد شد.');
            continue;
          }
          if (choice == 'merge') id = same.first.id;
        }
      }
      final existing = people[id];
      var roleCode = existing?.roleCode;
      final roleRaw = cell(row, 'role');
      if (roleByValue != null && roleRaw.isNotEmpty) {
        final k = normalizeText(roleRaw);
        if (roleByValue.containsKey(k)) {
          roleCode = roleByValue[k];
        } else {
          problems.add('ردیف ${r + 2}: نقش «$roleRaw» تطبیق داده نشده؛ بدون نقش وارد شد.');
        }
      } else if (roleRaw.isNotEmpty) {
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
        typeCode: rowType,
        presentationKind: pk.isNotEmpty ? pk : (existing?.presentationKind ?? ''),
        roleCode: roleCode,
        token: existing?.token ?? _randomToken(),
        serial: existing?.serial ?? serial++,
        shareContact: shareFrom(cell(row, 'share_contact')) ?? existing?.shareContact,
        website: cell(row, 'website').isNotEmpty ? cell(row, 'website') : (existing?.website ?? ''),
      );
      if (mobile.isEmpty) incomplete++;
      if (existing == null) {
        created++;
      } else {
        updated++;
      }
    }
    return ImportResult(out.values.toList(), problems, updated, created, possibleDuplicates, conflicts, incomplete);
  }

  /// «ساخت نوع تازه» یا نقش تازه از مقدار ستون اکسل؛ روی سرور ذخیره و کدش برگردانده می‌شود.
  Future<String?> createTypeOrRole({required bool role, required String name}) async {
    final list = role ? roles : types;
    var n = list.length + 1;
    String code() => '${role ? 'role' : 'type'}$n';
    while (list.any((x) => x.code == code())) {
      n++;
    }
    final c = code();
    String? out;
    await run('«$name» ساخته شد.', () async {
      await api.post('/admin/events/$eventCode/config', {
        role ? 'roles' : 'registration_types': [
          {'code': c, 'name': name},
        ],
      });
      await _loadEvent(eventCode!);
      out = c;
    });
    return out;
  }

  /// ارسال افراد. [fileName] اگر باشد، همه‌ی این ارسال یک «ورودی» است تا بعداً یکجا حذف شود.
  Future<void> uploadPeople(List<Person> list, {String? fileName}) =>
      run('${faDigits(list.length)} نفر روی سرور ذخیره شدند.', () async {
        final errors = <Map>[];
        final batchId = fileName == null ? null : _uuid.v4();
        for (var i = 0; i < list.length; i += 200) {
          final batch = list.sublist(i, min(i + 200, list.length));
          final r = (await api.post('/admin/events/$eventCode/attendees', {
            'attendees': batch.map((p) => p.toUpload()).toList(),
            if (batchId != null) 'batch': {'id': batchId, 'file_name': fileName},
          }) as Map)
              .cast<String, dynamic>();
          errors.addAll(((r['errors'] as List?) ?? []).cast<Map>());
        }
        await _loadEvent(eventCode!);
        await _loadImportsQuiet();
        if (errors.isNotEmpty) {
          final deleted = errors.where((e) => e['reason'] == 'deleted_person').length;
          final other = errors.where((e) => e['reason'] != 'deleted_person').toList();
          throw ApiException(
            'partial',
            [
              if (deleted > 0) '${faDigits(deleted)} نفر قبلاً از رویداد حذف شده‌اند و دوباره وارد نشدند.',
              if (other.isNotEmpty) 'بعضی ردیف‌ها ذخیره نشدند: ${jsonEncode(other)}',
            ].join(' '),
            200,
          );
        }
      });

  // ---------------------------------------------------------------- ورودی‌ها و وضعیت افراد

  Future<void> _loadImportsQuiet() async {
    try {
      final r = await api.get('/admin/events/$eventCode/imports') as List;
      imports = r.map((e) => ImportBatch.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      imports = []; // افزونه‌ی قدیمی این مسیر را ندارد.
    }
  }

  Future<void> loadImports() => run('', _loadImportsQuiet);

  Future<void> deleteImport(ImportBatch b) => run('', () async {
        final r = (await api.delete('/admin/events/$eventCode/imports/${b.id}') as Map).cast<String, dynamic>();
        await _loadEvent(eventCode!);
        await _loadImportsQuiet();
        final kept = (r['kept'] as int?) ?? 0;
        message = '${faDigits((r['deleted'] as int?) ?? 0)} نفر حذف شد.'
            '${kept > 0 ? ' ${faDigits(kept)} نفر چون پذیرش یا وعده دارند ماندند.' : ''}';
      });

  /// غیرفعال یا فعال‌کردن یک نفر. غیرفعال در گوشی نیروها و گزارش دیده نمی‌شود.
  Future<void> setPersonStatus(String id, String status) =>
      run(status == 'active' ? 'دوباره فعال شد.' : 'غیرفعال شد.', () async {
        await api.post('/admin/events/$eventCode/attendees/status', {
          'ids': [id],
          'status': status,
        });
        await _loadEvent(eventCode!);
      });

  /// حذف یک نفر (حذف نرم). اگر پذیرش یا وعده دارد و [force] نیست، شمار آن‌ها برمی‌گردد و چیزی حذف نمی‌شود.
  Future<Map<String, dynamic>?> deletePerson(String id, {bool force = false}) async {
    Map<String, dynamic>? activity;
    await run('از رویداد حذف شد.', () async {
      try {
        await api.delete('/admin/events/$eventCode/attendees/$id${force ? '?force=1' : ''}');
        await _loadEvent(eventCode!);
      } on ApiException catch (e) {
        if (e.code != 'cd_person_has_activity') rethrow;
        activity = (((e.data as Map?)?['activity'] as Map?) ?? {}).cast<String, dynamic>();
      }
    });
    if (activity != null) {
      message = null;
      notifyListeners();
    }
    return activity;
  }

  /// حذف نوع، نقش یا وعده‌ای که روی سرور است. [kind]: registration-types، roles، meals.
  /// اگر استفاده شده، ApiException با کد cd_in_use و شمار وابسته‌ها پرتاب می‌شود.
  Future<void> deleteConfigItem(String kind, String code, {String? moveTo, bool clear = false}) async {
    final q = [
      if (moveTo != null) 'move_to=${Uri.encodeQueryComponent(moveTo)}',
      if (clear) 'clear=1',
    ].join('&');
    await api.delete('/admin/events/$eventCode/$kind/$code${q.isEmpty ? '' : '?$q'}');
    await _loadEvent(eventCode!);
    notifyListeners();
  }

  Future<void> setMealActive(String code, bool active) =>
      run(active ? 'وعده دوباره فعال شد.' : 'وعده غیرفعال شد.', () async {
        await api.post('/admin/events/$eventCode/meals/$code/active', {'active': active});
        await _loadEvent(eventCode!);
      });

  /// حذف کارت‌های رزروی که به کسی وصل نشده‌اند و در فهرست رخدادها هم نیامده‌اند.
  Future<void> deleteFreeReserves() => run('', () async {
        final r = (await api.delete('/admin/events/$eventCode/reserve-cards') as Map).cast<String, dynamic>();
        await _loadEvent(eventCode!);
        message = '${faDigits((r['deleted'] as int?) ?? 0)} کارت رزرو آزاد حذف شد.';
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

  /// قالب‌های کارت روی سرور تا اپ ویندوز و موبایل یک قالب ببینند (مسیر تصویرهای طرح محلی می‌ماند).
  Future<void> saveTemplate() => run('قالب کارت ذخیره شد.', () async {
        await save();
        final r = await api.post('/admin/events/$eventCode/card-template', {'template': cards.toJson()});
        // افزونه‌ی قدیمی فقط قالب تکی را نگه می‌دارد؛ بی‌صدا گم شدن قالب‌های جدا را خبر بده.
        final saved = r is Map ? r['template'] : null;
        if (cards.templates.length > 1 && saved is Map && saved['templates'] == null) {
          throw ApiException('old_plugin',
              'افزونه‌ی وردپرس قدیمی است و فقط قالب پیش‌فرض را نگه داشت؛ برای قالب‌های جدا افزونه را به‌روز کنید.', 200);
        }
      });

  /// قالب کارت یک نفر (قاعده‌ی نقش، بعد نوع، وگرنه پیش‌فرض).
  CardTemplate templateOf(Person p) => templateFor(cards, typeCode: p.typeCode, roleCode: p.roleCode);

  /// باطل‌کردن دسترسی یک دستگاه نیرو.
  Future<void> revokeDevice(int id) => run('دستگاه باطل شد.', () async {
        await api.post('/admin/devices/$id/revoke', {});
        report = await _fetchReport();
      });

  /// لغو پذیرش یک نفر از اپ مدیریت (در فهرست رخدادها با دلیل و فاعل ثبت می‌شود).
  /// سرور فقط برای فرد پذیرش‌شده قبول می‌کند.
  Future<void> undoCheckin(String attendeeId, {String reason = ''}) => run('پذیرش لغو شد.', () async {
        await api.post('/admin/events/$eventCode/attendees/$attendeeId/checkin-undo', {
          'reason': reason,
          // حضور روزانه: پذیرش امروز لغو می‌شود.
          if (settings.dailyAttendance) 'day': todayIso(),
        });
      });

  /// «لغو تحویل…»: برگرداندن یک تحویل وعده.
  Future<void> undoMeal(String attendeeId, String mealCode, {String reason = ''}) =>
      run('تحویل برگشت.', () async {
        await api.post('/admin/events/$eventCode/attendees/$attendeeId/meal-undo', {'meal': mealCode, 'reason': reason});
      });

  /// ویرایش یک نفر؛ فقط فیلدهای [fields] (کلیدهای API) فرستاده می‌شوند.
  Future<bool> patchPerson(String id, Map<String, dynamic> fields) async {
    var ok = false;
    await run('ذخیره شد.', () async {
      await api.patch('/admin/events/$eventCode/attendees/$id', fields);
      await _loadEvent(eventCode!);
      ok = true;
    });
    return ok;
  }

  /// «افزودن فرد»: ثبت دستی با کارت تازه (اگر رویداد کارت دارد).
  Future<bool> addPerson(Person p) async {
    var ok = false;
    await run('${p.fullName} اضافه شد.', () async {
      if (settings.usesCards && p.token == null) {
        p.token = _randomToken();
        p.serial = _nextSerial;
      }
      final r = (await api.post('/admin/events/$eventCode/attendees', {
        'attendees': [p.toUpload()],
        'source': 'manual',
      }) as Map)
          .cast<String, dynamic>();
      final errors = (r['errors'] as List?) ?? const [];
      if (errors.isNotEmpty) throw ApiException('partial', 'ذخیره نشد: ${jsonEncode(errors)}', 200);
      await _loadEvent(eventCode!);
      ok = true;
    });
    return ok;
  }

  /// ادغام [fromId] در [keepId]: تاریخچه و کارت منتقل می‌شود و [fromId] حذف می‌شود.
  Future<bool> mergePeople(String keepId, String fromId) async {
    var ok = false;
    await run('ادغام شد.', () async {
      await api.post('/admin/events/$eventCode/attendees/$keepId/merge', {'from': fromId});
      await _loadEvent(eventCode!);
      ok = true;
    });
    return ok;
  }

  /// «روز ۲» برای یک تاریخ در بازه‌ی رویداد، وگرنه خود تاریخ.
  String dayName(String iso) {
    final st = DateTime.tryParse(event?.startDate ?? ''), d = DateTime.tryParse(iso);
    if (st == null || d == null) return iso;
    final n = d.difference(st).inDays + 1;
    return n >= 1 ? 'روز ${faDigits(n)}' : iso;
  }

  /// کارت این افراد به چاپخانه رفت (PDF نهایی). خطا فقط پیام می‌شود؛ PDF ساخته شده است.
  Future<void> markPrinted(List<String> ids) => run('', () async {
        if (ids.isEmpty) return;
        await api.post('/admin/events/$eventCode/attendees/printed', {'ids': ids});
        await _loadEvent(eventCode!);
      });

  /// «کارت گم شد»: [mode] reserve = کارت رزرو آزاد، new = کارت تازه با همان شماره. کارت قبلی باطل می‌شود.
  /// خروجی: شماره‌ی کارت تازه، یا null اگر نشد.
  Future<int?> replaceCard(String id, String mode) async {
    int? serial;
    await run('', () async {
      final r = (await api.post('/admin/events/$eventCode/attendees/$id/replace-card', {'mode': mode}) as Map)
          .cast<String, dynamic>();
      serial = ((r['card'] as Map?)?['serial']) as int?;
      await _loadEvent(eventCode!);
      message = mode == 'reserve'
          ? 'کارت رزرو ${faDigits(serial ?? '')} به او داده شد؛ کارت قبلی باطل شد.'
          : 'کارت تازه با شماره‌ی ${faDigits(serial ?? '')} ساخته شد؛ کارت قبلی باطل شد. در «کارت‌ها ← چاپ‌نشده‌ها» چاپش کنید.';
    });
    return serial;
  }

  /// افراد فعال دیگری که موبایل یا ایمیل یکسان دارند («احتمالاً همان … است»).
  List<Person> possibleDuplicatesOf(Person p) => findPossibleDuplicates(p, people.values);

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
    final l = people.values.where((p) => p.token != null && p.source != 'walkin' && p.isActive).toList();
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

  Future<Map<String, dynamic>> _fetchReport() async =>
      (await api.get('/admin/events/$eventCode/report${reportDay == null ? '' : '?day=$reportDay'}') as Map)
          .cast<String, dynamic>();

  Future<void> loadReport() => run('', () async {
        report = await _fetchReport();
      });

  Future<void> setReportDay(String? day) {
    reportDay = day;
    return loadReport();
  }

  /// کل داده‌ی رویداد از سرور (برای «پشتیبان کامل» و «تاریخچه‌ی رویدادها»).
  Future<Map<String, dynamic>> fullSnapshot() async =>
      (await api.get('/admin/events/$eventCode/snapshot') as Map).cast<String, dynamic>();

  /// ردیف‌های فهرست حضور با فیلتر (خروجی و تب افراد ویندوز).
  Future<Map<String, dynamic>> exportRows({
    String who = 'all',
    String? type,
    String? role,
    String? day,
    bool includeInactive = false,
  }) async {
    final q = {
      'who': who,
      if (type != null) 'type': type,
      if (role != null) 'role': role,
      if (day != null) 'day': day,
      if (includeInactive) 'include_inactive': '1',
    };
    final r = await api.get('/admin/events/$eventCode/export?${Uri(queryParameters: q).query}');
    return (r as Map).cast<String, dynamic>();
  }

  /// غیرفعال، فعال یا حذف چند نفر با هم. خروجی: شمار تغییرکرده و کسانی که چون کار ثبت‌شده دارند ماندند.
  Future<(int, int)?> setPeopleStatusBulk(List<String> ids, String status, {bool force = false}) async {
    (int, int)? out;
    await run('', () async {
      final r = (await api.post('/admin/events/$eventCode/attendees/status', {
        'ids': ids,
        'status': status,
        if (force) 'force': true,
      }) as Map)
          .cast<String, dynamic>();
      await _loadEvent(eventCode!);
      out = ((r['changed'] as int?) ?? 0, ((r['kept'] as List?) ?? const []).length);
    });
    return out;
  }

  /// «دیدن فهرست» یک وعده: افراد دارای حق و هر کس تحویل گرفته.
  Future<List<Map<String, dynamic>>> mealPeople(String mealCode) async {
    final r = (await api.get('/admin/events/$eventCode/meals/$mealCode/people') as Map).cast<String, dynamic>();
    return ((r['people'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// تاریخچه‌ی یک نفر (PersonTimeline): پذیرش، وعده‌ها و موارد مشکوک به ترتیب زمان.
  /// نیازمند مسیر `GET /admin/events/{code}/attendees/{id}/timeline` در افزونه.
  Future<List<Map<String, dynamic>>> loadTimeline(String attendeeId) async {
    final r = await api.get('/admin/events/$eventCode/attendees/$attendeeId/timeline');
    final list = r is Map ? (r['events'] as List? ?? const []) : (r as List);
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}
