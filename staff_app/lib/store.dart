import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'models.dart';
import 'normalize.dart';

const _uuid = Uuid();

/// همه‌ی وضعیت اپ: داده‌ی رویداد، دفتر رخدادها، صف ارسال، و همگام‌سازی.
/// همه‌چیز روی گوشی ذخیره می‌شود، پس اپ بدون اینترنت کار می‌کند.
class AppStore extends ChangeNotifier {
  // ورود
  String? server;
  String? token;
  String? eventCode;
  String deviceLabel = '';
  int? staffId;
  String staffName = '';
  bool canCheckin = true;
  bool canServe = true;
  bool isAdmin = false;

  // داده‌ی رویداد
  String eventName = '';
  int configVersion = 0;
  List<NamedItem> types = [];
  List<NamedItem> roles = [];
  List<Meal> meals = [];
  List<Session> sessions = [];
  Map<String, Attendee> _baseAttendees = {};
  Map<String, PassCard> cards = {};
  Map<int, String> staffNames = {};

  // دفتر رخدادها
  List<LogEvent> serverLog = [];
  final Set<String> _serverUuids = {};
  List<LogEvent> pending = [];
  List<Map<String, dynamic>> rejected = [];
  int cursor = 0;

  // وضعیت همگام‌سازی
  DateTime? lastSyncOk;
  String? lastError;
  bool syncing = false;
  bool online = false;
  bool needsLogin = false;

  int? selectedMealId;

  /// «شناسایی در روز اجرا» (IdentifyMode) از پیکربندی رویداد:
  /// scan = کارت QR با اسکن، card = کارت بدون اسکن، none = بدون کارت.
  String identifyMode = 'scan';

  bool get scanEnabled => identifyMode == 'scan';
  bool get usesCards => identifyMode != 'none';

  /// دوربین فقط روی گوشی هست؛ روی ویندوز اسکن با بارکدخوان (ScanInput) است.
  static bool get hasCamera => Platform.isAndroid || Platform.isIOS;

  bool get cameraScan => scanEnabled && hasCamera;

  // وضعیت محاسبه‌شده
  Map<String, Attendee> attendees = {};
  Map<String, String> cardOwner = {}; // token → attendee id
  Map<String, CheckState> checkins = {};
  Map<String, Map<int, List<DateTime>>> mealsServed = {};

  Timer? _timer;
  Timer? _saveDebounce;
  bool _loaded = false;

  bool get loggedIn => token != null && server != null;
  bool get loaded => _loaded;

  // ---------------------------------------------------------------- ذخیره‌سازی

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/conference_state.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _fromJson(j);
      }
    } catch (e) {
      lastError = 'خواندن داده‌ی ذخیره‌شده ناموفق بود: $e';
    }
    _recompute();
    _loaded = true;
    notifyListeners();
    if (loggedIn) startSyncLoop();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _save);
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_toJson()), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      lastError = 'ذخیره‌ی داده روی گوشی ناموفق بود: $e';
      notifyListeners();
    }
  }

  Map<String, dynamic> _toJson() => {
        'server': server,
        'token': token,
        'event_code': eventCode,
        'device_label': deviceLabel,
        'staff_id': staffId,
        'staff_name': staffName,
        'can_checkin': canCheckin,
        'can_serve': canServe,
        'is_admin': isAdmin,
        'event_name': eventName,
        'config_version': configVersion,
        'types': types.map((e) => e.toJson()).toList(),
        'roles': roles.map((e) => e.toJson()).toList(),
        'meals': meals.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'attendees': _baseAttendees.values.map((e) => e.toJson()).toList(),
        'cards': cards.values.map((e) => e.toJson()).toList(),
        'staff': staffNames.entries.map((e) => {'id': e.key, 'name': e.value}).toList(),
        'log': serverLog.map((e) => e.toJson()).toList(),
        'pending': pending.map((e) => e.toJson()).toList(),
        'rejected': rejected,
        'cursor': cursor,
        'last_sync_ok': lastSyncOk?.toIso8601String(),
        'selected_meal_id': selectedMealId,
        'approvers': approvers,
        'desk_staff_ids': deskStaffIds.toList(),
        'settings': {'identify_mode': identifyMode},
      };

  void _fromJson(Map<String, dynamic> j) {
    server = j['server'] as String?;
    token = j['token'] as String?;
    eventCode = j['event_code'] as String?;
    deviceLabel = (j['device_label'] as String?) ?? '';
    staffId = j['staff_id'] as int?;
    staffName = (j['staff_name'] as String?) ?? '';
    canCheckin = (j['can_checkin'] as bool?) ?? true;
    canServe = (j['can_serve'] as bool?) ?? true;
    isAdmin = (j['is_admin'] as bool?) ?? false;
    _applyConfig(j);
    serverLog = _list(j['log']).map(LogEvent.fromJson).toList();
    _serverUuids
      ..clear()
      ..addAll(serverLog.map((e) => e.uuid));
    // کارهای ذخیره‌شده پیش از «تعویض نیرو» توکن ندارند: مال نیروی فعلی‌اند.
    pending = _list(j['pending']).map(LogEvent.fromJson).map((e) => e.sendToken == null ? e.withSendToken(token) : e).toList();
    rejected = _list(j['rejected']);
    cursor = (j['cursor'] as int?) ?? 0;
    lastSyncOk = DateTime.tryParse((j['last_sync_ok'] as String?) ?? '');
    selectedMealId = j['selected_meal_id'] as int?;
    approvers = ((j['approvers'] as List?) ?? const []).map((e) => e.toString()).toList();
    deskStaffIds = {for (final e in (j['desk_staff_ids'] as List?) ?? const []) if (e is int) e};
  }

  /// فقط برای آزمون: داده‌ی ذخیره‌شده را بدون شبکه بار می‌کند.
  @visibleForTesting
  void loadForTest(Map<String, dynamic> j) {
    _fromJson(j);
    _recompute();
    _loaded = true;
  }

  static List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  /// پیکربندی رویداد از snapshot سرور یا فایل ذخیره‌شده.
  void _applyConfig(Map<String, dynamic> j) {
    final ev = (j['event'] as Map?)?.cast<String, dynamic>();
    if (ev != null) {
      eventName = (ev['name'] ?? '').toString();
      configVersion = (ev['config_version'] as int?) ?? 0;
      eventCode = (ev['code'] ?? eventCode)?.toString();
    } else {
      eventName = (j['event_name'] as String?) ?? eventName;
      configVersion = (j['config_version'] as int?) ?? configVersion;
    }
    final settings = ((j['settings'] as Map?) ?? (ev?['settings'] as Map?))?.cast<String, dynamic>();
    final mode = settings?['identify_mode']?.toString();
    identifyMode = const ['scan', 'card', 'none'].contains(mode) ? mode! : 'scan';
    types = _list(j['types'] ?? j['registration_types']).map(NamedItem.fromJson).toList();
    roles = _list(j['roles']).map(NamedItem.fromJson).toList();
    meals = _list(j['meals']).map(Meal.fromJson).toList();
    sessions = _list(j['sessions']).map(Session.fromJson).toList();
    _baseAttendees = {for (final a in _list(j['attendees']).map(Attendee.fromJson)) a.id: a};
    cards = {for (final c in _list(j['cards']).map(PassCard.fromJson)) c.token: c};
    staffNames = {
      for (final s in _list(j['staff'])) (s['id'] as int): (s['name'] ?? '').toString(),
    };
  }

  // ---------------------------------------------------------------- محاسبه‌ی وضعیت

  /// وضعیت هر نفر از روی دفتر رخدادهای سرور و بعد رخدادهای ارسال‌نشده.
  void _recompute() {
    final att = Map<String, Attendee>.from(_baseAttendees);
    final owner = <String, String>{};
    for (final c in cards.values) {
      if (c.attendeeId != null) owner[c.token] = c.attendeeId!;
    }
    final chk = <String, CheckState>{};
    final served = <String, Map<int, List<DateTime>>>{};
    final settled = <String, CheckState>{};

    final all = [...serverLog, ...pending];
    for (final e in all) {
      String? aid = e.attendeeId ?? (e.cardToken != null ? owner[e.cardToken] : null);
      switch (e.kind) {
        case 'walkin_register':
          final a = (e.payload?['attendee'] as Map?)?.cast<String, dynamic>();
          if (a != null) {
            final w = Attendee.fromJson({...a, 'source': 'walkin'});
            att.putIfAbsent(w.id, () => w);
            aid = w.id;
            if (e.cardToken != null) owner.putIfAbsent(e.cardToken!, () => w.id);
          }
          break;
        case 'checkin':
          if (aid != null) chk.putIfAbsent(aid, () => CheckState(e.deviceTime, e.staffId));
          break;
        case 'checkin_undo':
          if (aid != null) chk.remove(aid);
          break;
        case 'onsite_settled':
          if (aid != null) settled.putIfAbsent(aid, () => CheckState(e.deviceTime, e.staffId));
          break;
        case 'card_link':
          // کارت رزرو که بعداً به کسی وصل شد که بدون کارت ثبت‌نام کرده بود.
          if (aid != null && e.cardToken != null && !owner.containsKey(e.cardToken)) {
            owner[e.cardToken!] = aid;
          }
          break;
        case 'attendee_update':
          final f = (e.payload?['fields'] as Map?)?.cast<String, dynamic>();
          final cur = aid == null ? null : att[aid];
          if (cur != null && f != null) {
            // نام چاپی از «پیش از اولین تکمیل» است؛ snapshot سرور نام تازه را دارد.
            final before = (e.payload?['before'] as Map?)?.cast<String, dynamic>();
            final u = cur.completedWith(f);
            if (before != null && cur.printedLast == null) {
              u
                ..printedFirst = (before['first_name'] ?? '').toString()
                ..printedLast = (before['last_name'] ?? '').toString();
            }
            att[aid!] = u;
          }
          break;
        case 'meal_served':
          if (aid != null && e.mealId != null) {
            served.putIfAbsent(aid, () => {}).putIfAbsent(e.mealId!, () => []).add(e.deviceTime);
          }
          break;
      }
    }
    attendees = att;
    cardOwner = owner;
    checkins = chk;
    mealsServed = served;
    onsiteSettled = settled;
  }

  /// «تسویه در روز اجرا»ی گزینه‌های صفحه‌ی ثبت‌نام: چه کسی، کی، توسط چه نیرویی.
  Map<String, CheckState> onsiteSettled = {};

  /// مبلغی که این فرد باید در روز اجرا بدهد و هنوز «تسویه شد» نخورده.
  int onsiteOwed(Attendee a) => a.onsiteDue > 0 && !onsiteSettled.containsKey(a.id) ? a.onsiteDue : 0;

  void settleOnsite(Attendee a) =>
      _record('onsite_settled', attendeeId: a.id, payload: {'amount': a.onsiteDue, 'note': a.onsiteNote});

  // ---------------------------------------------------------------- پرس‌وجو

  Attendee? attendeeForToken(String token) {
    final id = cardOwner[token];
    return id == null ? null : attendees[id];
  }

  PassCard? cardOf(String attendeeId) {
    for (final e in cardOwner.entries) {
      if (e.value == attendeeId) return cards[e.key];
    }
    return null;
  }

  String typeName(int id) => types.firstWhere((t) => t.id == id, orElse: () => NamedItem(id, '', '')).name;
  String roleName(int? id) =>
      id == null ? '' : roles.firstWhere((r) => r.id == id, orElse: () => NamedItem(id, '', '')).name;

  /// جستجو با چند حرف از نام، موبایل، ایمیل یا سازمان. همه‌ی کلمه‌ها باید پیدا شوند.
  List<Attendee> search(String query, {int limit = 60}) {
    final q = normalizeText(query);
    if (q.isEmpty) return const [];
    final words = q.split(' ');
    final digits = normalizeMobile(query);
    final out = <Attendee>[];
    for (final a in attendees.values) {
      final hit = words.every(a.searchKey.contains) ||
          (digits.length >= 4 && normalizeMobile(a.mobile).contains(digits));
      if (hit) out.add(a);
    }
    out.sort((x, y) {
      final xs = normalizeText(x.fullName).startsWith(q) ? 0 : 1;
      final ys = normalizeText(y.fullName).startsWith(q) ? 0 : 1;
      if (xs != ys) return xs - ys;
      return x.lastName.compareTo(y.lastName);
    });
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  Attendee? findByMobile(String mobile) {
    final m = normalizeMobile(mobile);
    if (m.isEmpty) return null;
    for (final a in attendees.values) {
      if (normalizeMobile(a.mobile) == m) return a;
    }
    return null;
  }

  Meal? get selectedMeal {
    for (final m in meals) {
      if (m.id == selectedMealId) return m;
    }
    return null;
  }

  void selectMeal(int? id) {
    selectedMealId = id;
    _scheduleSave();
    notifyListeners();
  }

  MealCheck checkMeal(Attendee a, Meal m) {
    final prev = mealsServed[a.id]?[m.id];
    if (prev != null && prev.isNotEmpty) return MealCheck(MealVerdict.duplicate, prev.first);
    if (!m.entitles(a)) return MealCheck(MealVerdict.notEntitled);
    return MealCheck(MealVerdict.ok);
  }

  int servedCount(int mealId) =>
      mealsServed.values.where((m) => (m[mealId]?.isNotEmpty ?? false)).length;

  int entitledCount(Meal m) => attendees.values.where(m.entitles).length;

  List<PassCard> get freeReserveCards => cards.values
      .where((c) => c.isReserve && !cardOwner.containsKey(c.token))
      .toList()
    ..sort((a, b) => a.serial.compareTo(b.serial));

  // ---------------------------------------------------------------- ثبت رخداد

  LogEvent _record(String kind, {String? cardToken, String? attendeeId, int? mealId, Map<String, dynamic>? payload}) {
    final e = LogEvent(
      uuid: _uuid.v4(),
      kind: kind,
      cardToken: cardToken,
      attendeeId: attendeeId,
      mealId: mealId,
      payload: payload,
      deviceTime: DateTime.now().toUtc(),
      staffId: staffId,
      sendToken: token,
    );
    pending.add(e);
    _recompute();
    _scheduleSave();
    notifyListeners();
    Future.microtask(sync);
    return e;
  }

  void checkin(Attendee a) => _record('checkin', attendeeId: a.id, cardToken: cardOf(a.id)?.token);

  void undoCheckin(Attendee a) => _record('checkin_undo', attendeeId: a.id);

  /// تکمیل اطلاعات فردی که ناقص ثبت‌نام کرده؛ آفلاین هم ثبت می‌شود و با همگام‌سازی به سرور می‌رود.
  void completeInfo(Attendee a, {String firstName = '', String lastName = '', String mobile = '', String email = ''}) {
    final f = <String, String>{
      if (firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
      if (lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
      if (mobile.trim().isNotEmpty) 'mobile': normalizeMobile(mobile),
      if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
    };
    if (f.isEmpty) return;
    _record('attendee_update', attendeeId: a.id, payload: {
      'fields': f,
      'before': {'first_name': a.printedFirst ?? a.firstName, 'last_name': a.printedLast ?? a.lastName},
    });
  }

  /// کارت رزرو از روی شماره («R5001»، «۵۰۰۱») یا لینک اسکن‌شده. خروجی: کارت آزاد، یا پیام خطا.
  (PassCard?, String?) reserveCardFrom(String input) {
    final scanned = tokenFromScan(latinizeLayout(input));
    String? token = scanned;
    if (token == null) {
      final cleaned = latinDigits(input.trim()).replaceFirst(RegExp(r'^[Rrر]\s*'), '');
      final n = int.tryParse(cleaned);
      if (n == null) return (null, 'شماره‌ی روی کارت را بنویسید، مثلاً ۵۰۰۱.');
      final match = cards.values.where((c) => c.isReserve && c.serial == n);
      if (match.isEmpty) return (null, 'کارت رزرو با شماره‌ی ${faDigits(n)} پیدا نشد.');
      token = match.first.token;
    }
    final c = cards[token];
    if (c == null) return (null, 'این کارت در لیست نیست. اگر کارت تازه است، از «وضعیت» لیست را دوباره بگیرید.');
    if (!c.isReserve) return (null, 'این کارت رزرو نیست؛ مال ${attendeeForToken(token)?.fullName ?? 'شخص دیگری'} است.');
    if (cardOwner.containsKey(token)) {
      return (null, 'این کارت رزرو قبلاً به ${attendeeForToken(token)?.fullName ?? 'کسی'} وصل شده.');
    }
    return (c, null);
  }

  /// وصل‌کردن کارت رزرو به کسی که بدون کارت ثبت شده بود (کارت رزرو تمام شده بود).
  void linkCard(Attendee a, PassCard c) => _record('card_link', attendeeId: a.id, cardToken: c.token);

  /// افراد دیگری که همین ایمیل یا موبایل را دارند (مثلاً ایمیل مشترک شرکت).
  List<Attendee> sharingContact(Attendee a) {
    final m = normalizeMobile(a.mobile);
    final e = a.email.trim().toLowerCase();
    if (m.isEmpty && e.isEmpty) return const [];
    return [
      for (final o in attendees.values)
        if (o.id != a.id &&
            ((m.isNotEmpty && normalizeMobile(o.mobile) == m) || (e.isNotEmpty && o.email.trim().toLowerCase() == e)))
          o,
    ];
  }

  /// [overrideBy]: «تحویل با مجوز شفاهی»؛ نام کسی که اجازه داد. در گزارش مدیر علامت می‌خورد.
  void serveMeal(Attendee a, Meal m, {String? overrideBy}) {
    final by = overrideBy?.trim() ?? '';
    if (by.isNotEmpty) {
      approvers = [by, ...approvers.where((x) => x != by)].take(6).toList();
    }
    _record('meal_served', attendeeId: a.id, mealId: m.id, cardToken: cardOf(a.id)?.token,
        payload: by.isEmpty ? null : {'override_by': by});
  }

  /// نام‌های اجازه‌دهنده‌ی اخیر برای انتخاب سریع.
  List<String> approvers = [];

  /// «خبر به مدیر» برای کاری که سرور نپذیرفت؛ در موارد مشکوک گزارش می‌آید.
  void reportToAdmin(Map<String, dynamic> rejectedItem, String text) {
    _record('staff_note', attendeeId: rejectedItem['attendee_id']?.toString(), payload: {
      'text': text,
      'reason': rejectedItem['reason'],
      'uuid': rejectedItem['uuid'],
    });
    dismissRejected(rejectedItem);
  }

  void dismissRejected(Map<String, dynamic> item) {
    rejected.remove(item);
    _scheduleSave();
    notifyListeners();
  }

  /// کارهای ارسال‌نشده به تفکیک: «۲ پذیرش و ۱ تحویل ناهار».
  String pendingSummary() {
    final parts = <String, int>{};
    for (final e in pending) {
      final label = switch (e.kind) {
        'checkin' => 'پذیرش',
        'checkin_undo' => 'لغو پذیرش',
        'walkin_register' => 'ثبت‌نام در محل',
        'meal_served' => 'تحویل ${meals.where((m) => m.id == e.mealId).firstOrNull?.name ?? 'وعده'}',
        'attendee_update' => 'تکمیل اطلاعات',
        'card_link' => 'وصل کارت',
        'onsite_settled' => 'تسویه',
        _ => 'کار دیگر',
      };
      parts[label] = (parts[label] ?? 0) + 1;
    }
    return parts.entries.map((e) => '${faDigits(e.value)} ${e.key}').join(' و ');
  }

  /// وعده‌ی «الان» امروز: آخرین وعده‌ای که ساعتش رسیده، وگرنه اولین وعده‌ی امروز.
  Meal? currentMealFor(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final hm = '${two(now.hour)}:${two(now.minute)}';
    final list = meals.where((m) => m.day != null && m.day!.startsWith(today)).toList()
      // وعده‌ی بی‌ساعت آخر می‌آید.
      ..sort((a, b) => (a.time.isEmpty ? '99' : a.time).compareTo(b.time.isEmpty ? '99' : b.time));
    if (list.isEmpty) return null;
    final started = list.where((m) => m.time.isNotEmpty && m.time.compareTo(hm) <= 0).toList();
    return started.isNotEmpty ? started.last : list.first;
  }

  /// ثبت‌نام در محل: شرکت‌کننده‌ی جدید + وصل‌کردن کارت رزرو + پذیرش.
  Attendee walkin({
    required String firstName,
    required String lastName,
    required String mobile,
    required String email,
    required int registrationTypeId,
    required PassCard? card,
  }) {
    final a = Attendee(
      id: _uuid.v4(),
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      mobile: normalizeMobile(mobile),
      email: email.trim(),
      registrationTypeId: registrationTypeId,
      source: 'walkin',
    );
    _record('walkin_register', cardToken: card?.token, attendeeId: a.id, payload: {
      'attendee': {
        'id': a.id,
        'first_name': a.firstName,
        'last_name': a.lastName,
        'mobile': a.mobile,
        'email': a.email,
        'registration_type_id': registrationTypeId,
      },
    });
    _record('checkin', attendeeId: a.id, cardToken: card?.token);
    return attendees[a.id] ?? a;
  }

  // ---------------------------------------------------------------- سرور

  Future<void> login({
    required String server,
    required String eventCode,
    required String pin,
    required String label,
  }) async {
    final api = Api(server);
    final r = await api.post('/device/login', {
      'event_code': eventCode.trim(),
      'pin': latinDigits(pin.trim()),
      'label': label.trim(),
    });
    final sameEvent = this.eventCode == eventCode.trim();
    this.server = server;
    token = r['token'] as String;
    this.eventCode = eventCode.trim();
    deviceLabel = label.trim();
    final me = (r['me'] as Map).cast<String, dynamic>();
    _applyMe(me);
    if (!sameEvent) {
      // رویداد دیگر: داده‌ی قبلی به درد نمی‌خورد. صف ارسالِ رویداد قبلی هم معتبر نیست.
      pending = [];
      rejected = [];
    }
    needsLogin = false;
    await refreshSnapshot();
    startSyncLoop();
  }

  void _applyMe(Map<String, dynamic> me) {
    staffId = me['staff_id'] as int?;
    staffName = (me['staff_name'] ?? '').toString();
    canCheckin = me['can_checkin'] == true;
    canServe = me['can_serve'] == true;
    isAdmin = me['is_admin'] == true;
    if (staffId != null) deskStaffIds.add(staffId!);
  }

  /// نیروهایی که روی همین دستگاه وارد شده‌اند؛ برای «این میز امروز».
  Set<int> deskStaffIds = {};

  /// پذیرش‌های امروزِ این دستگاه (همه‌ی نیروهایی که اینجا وارد شده‌اند) و زمان اولینشان.
  (int, DateTime?) deskCheckinsToday([DateTime? now]) {
    final n = (now ?? DateTime.now()).toLocal();
    bool today(DateTime t) {
      final l = t.toLocal();
      return l.year == n.year && l.month == n.month && l.day == n.day;
    }

    var count = 0;
    DateTime? first;
    for (final e in [...serverLog, ...pending]) {
      if (e.kind != 'checkin' || !deskStaffIds.contains(e.staffId) || !today(e.deviceTime)) continue;
      count++;
      if (first == null || e.deviceTime.isBefore(first)) first = e.deviceTime;
    }
    return (count, first?.toLocal());
  }

  /// «تعویض نیرو»: نیروی دیگری با PIN خودش روی همین دستگاه وارد می‌شود.
  /// لیست و کارهای ارسال‌نشده می‌مانند؛ کارهای نیروی قبلی به نام خودش فرستاده می‌شوند.
  Future<void> switchStaff(String pin) =>
      login(server: server!, eventCode: eventCode!, pin: pin, label: deviceLabel);

  /// گرفتن کل داده‌ی رویداد از سرور. صف ارسال دست نمی‌خورد.
  Future<void> refreshSnapshot() async {
    final api = Api(server!, token);
    final s = await api.get('/device/snapshot', timeout: const Duration(seconds: 60));
    _applyConfig(s);
    final me = (s['me'] as Map?)?.cast<String, dynamic>();
    if (me != null) _applyMe(me);
    serverLog = _list(s['log']).map(LogEvent.fromJson).toList();
    _serverUuids
      ..clear()
      ..addAll(serverLog.map((e) => e.uuid));
    pending.removeWhere((e) => _serverUuids.contains(e.uuid));
    cursor = (s['cursor'] as int?) ?? 0;
    if (selectedMealId != null && !meals.any((m) => m.id == selectedMealId)) selectedMealId = null;
    lastSyncOk = DateTime.now();
    online = true;
    lastError = null;
    _recompute();
    _scheduleSave();
    notifyListeners();
  }

  void startSyncLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => sync());
    Future.microtask(sync);
  }

  /// یک دور همگام‌سازی: ارسال صف و گرفتن رخدادهای جدید. خطای شبکه فقط ثبت می‌شود.
  Future<void> sync() async {
    if (syncing || !loggedIn || needsLogin) return;
    syncing = true;
    notifyListeners();
    try {
      var more = true;
      var rounds = 0;
      while (more && rounds < 10) {
        rounds++;
        // اول کارهای نیروی قبلی (پیش از «تعویض نیرو») با دسترسی خودش، بعد کارهای نیروی فعلی.
        final old = pending.where((e) => e.sendToken != null && e.sendToken != token);
        final useToken = old.isNotEmpty ? old.first.sendToken : token;
        final batch = pending.where((e) => (e.sendToken ?? token) == useToken).take(200).toList();
        final api = Api(server!, useToken);
        final Map<String, dynamic> r;
        try {
          r = await api.post('/device/sync', {
            'events': batch.map((e) => e.toPush()).toList(),
            'since': cursor,
          });
        } on ApiException catch (e) {
          if (!e.isAuth || useToken == token) rethrow;
          // دسترسی نیروی قبلی باطل شده: کارهایش از بین نمی‌رود و با دسترسی نیروی فعلی فرستاده می‌شود.
          pending = [for (final p in pending) p.sendToken == useToken ? p.withSendToken(token) : p];
          continue;
        }

        final sent = batch.map((e) => e.uuid).toSet();
        for (final rej in _list(r['rejected'])) {
          rejected.add({...rej, 'at': DateTime.now().toIso8601String()});
        }
        if (rejected.length > 100) rejected = rejected.sublist(rejected.length - 100);

        for (final ev in _list(r['events']).map(LogEvent.fromJson)) {
          if (_serverUuids.add(ev.uuid)) serverLog.add(ev);
        }
        pending.removeWhere((e) => sent.contains(e.uuid) || _serverUuids.contains(e.uuid));
        cursor = (r['cursor'] as int?) ?? cursor;
        more = r['more'] == true || pending.isNotEmpty;

        final cv = (r['config_version'] as int?) ?? configVersion;
        if (cv != configVersion) {
          await refreshSnapshot();
        }
      }
      lastSyncOk = DateTime.now();
      online = true;
      lastError = null;
      _recompute();
      _scheduleSave();
    } on ApiException catch (e) {
      online = !e.isAuth && e.status > 0;
      lastError = e.message;
      if (e.isAuth) needsLogin = true;
    } on TimeoutException {
      online = false;
      lastError = 'سرور جواب نداد؛ اپ آفلاین کار می‌کند.';
    } on SocketException {
      online = false;
      lastError = 'اینترنت وصل نیست؛ اپ آفلاین کار می‌کند.';
    } on ClientException {
      online = false;
      lastError = 'اینترنت وصل نیست؛ اپ آفلاین کار می‌کند.';
    } catch (e) {
      online = false;
      lastError = 'خطای همگام‌سازی: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// خروج. داده‌ی رویداد پاک می‌شود؛ اگر صف ارسال خالی نباشد، caller باید قبلش هشدار بدهد.
  Future<void> logout() async {
    _timer?.cancel();
    token = null;
    needsLogin = false;
    pending = [];
    rejected = [];
    serverLog = [];
    _serverUuids.clear();
    _baseAttendees = {};
    cards = {};
    meals = [];
    types = [];
    roles = [];
    sessions = [];
    cursor = 0;
    configVersion = 0;
    eventName = '';
    _recompute();
    await _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
