import 'normalize.dart';

int? _int(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));
String _str(dynamic v) => v == null ? '' : v.toString();

class NamedItem {
  final int id;
  final String code;
  final String name;
  NamedItem(this.id, this.code, this.name);

  factory NamedItem.fromJson(Map<String, dynamic> j) =>
      NamedItem(_int(j['id'])!, _str(j['code']), _str(j['name']));

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name};
}

class Meal {
  final int id;
  final String code;
  final String name;
  final String? day;
  final Set<int> typeIds;
  final Set<int> roleIds;

  /// ساعت شروع «13:00» (اختیاری).
  final String time;

  Meal(this.id, this.code, this.name, this.day, this.typeIds, this.roleIds, [this.time = '']);

  factory Meal.fromJson(Map<String, dynamic> j) {
    final rules = (j['rules'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Meal(
      _int(j['id'])!,
      _str(j['code']),
      _str(j['name']),
      j['day']?.toString(),
      ((rules['registration_type_ids'] as List?) ?? const []).map((e) => _int(e)!).toSet(),
      ((rules['role_ids'] as List?) ?? const []).map((e) => _int(e)!).toSet(),
      _str(j['time']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'day': day,
        'time': time,
        'rules': {'registration_type_ids': typeIds.toList(), 'role_ids': roleIds.toList()},
      };

  /// حق وعده: نوع ثبت‌نام، نقش، یا گزینه‌ی اضافه‌ی صفحه‌ی ثبت‌نام که به این وعده وصل است.
  bool entitles(Attendee a) =>
      typeIds.contains(a.registrationTypeId) ||
      (a.roleId != null && roleIds.contains(a.roleId)) ||
      a.extraMeals.contains(code);
}

class Attendee {
  final String id;
  final String title;
  final String firstName;
  final String lastName;
  final String email;
  final String mobile;
  final String organization;
  final String country;
  final int registrationTypeId;
  final String presentationKind;
  final int? roleId;
  final String source;
  late final String searchKey;

  /// از صفحه‌ی ثبت‌نام: کد وعده‌های گزینه‌های اضافه، مبلغ «تسویه در روز اجرا» و کد ثبت‌نام.
  final List<String> extraMeals;
  final int onsiteDue;
  final String onsiteNote;
  final String regCode;

  /// نامی که کارت با آن چاپ و در دسته چیده شده؛ اگر نیرو بعداً نام را تکمیل کند، دسته عوض نمی‌شود.
  String? printedLast;
  String? printedFirst;

  Attendee({
    required this.id,
    this.title = '',
    required this.firstName,
    required this.lastName,
    this.email = '',
    this.mobile = '',
    this.organization = '',
    this.country = '',
    required this.registrationTypeId,
    this.presentationKind = '',
    this.roleId,
    this.source = 'import',
    this.extraMeals = const [],
    this.onsiteDue = 0,
    this.onsiteNote = '',
    this.regCode = '',
  }) {
    searchKey = normalizeText('$firstName $lastName $mobile $email $organization $regCode');
  }

  /// نام یا نام خانوادگی در ثبت‌نام خالی مانده؛ هنگام پذیرش هشدار داده می‌شود.
  bool get missingName => firstName.trim().isEmpty || lastName.trim().isEmpty;

  String get _nameless {
    final c = email.isNotEmpty ? email : mobile;
    return c.isEmpty ? 'بی‌نام' : 'بی‌نام ($c)';
  }

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? _nameless : n;
  }

  String get displayName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? _nameless : '$title $n'.trim();
  }

  /// همین فرد با فیلدهای تکمیل‌شده؛ مقدار خالی چیزی را پاک نمی‌کند.
  Attendee completedWith(Map<String, dynamic> f) {
    String v(String k, String old) {
      final n = (f[k] ?? '').toString().trim();
      return n.isEmpty ? old : n;
    }

    return Attendee(
      id: id,
      title: title,
      firstName: v('first_name', firstName),
      lastName: v('last_name', lastName),
      email: v('email', email),
      mobile: v('mobile', mobile),
      organization: organization,
      country: country,
      registrationTypeId: registrationTypeId,
      presentationKind: presentationKind,
      roleId: roleId,
      source: source,
      extraMeals: extraMeals,
      onsiteDue: onsiteDue,
      onsiteNote: onsiteNote,
      regCode: regCode,
    )
      ..printedFirst = printedFirst ?? firstName
      ..printedLast = printedLast ?? lastName;
  }

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
        id: _str(j['id']).toLowerCase(),
        title: _str(j['title']),
        firstName: _str(j['first_name']),
        lastName: _str(j['last_name']),
        email: _str(j['email']),
        mobile: _str(j['mobile']),
        organization: _str(j['organization']),
        country: _str(j['country']),
        registrationTypeId: _int(j['registration_type_id']) ?? 0,
        presentationKind: _str(j['presentation_kind']),
        roleId: _int(j['role_id']),
        source: _str(j['source']).isEmpty ? 'import' : _str(j['source']),
        extraMeals: ((j['extra_meals'] as List?) ?? const []).map((e) => e.toString()).toList(),
        onsiteDue: _int(j['onsite_due']) ?? 0,
        onsiteNote: _str(j['onsite_note']),
        regCode: _str(j['reg_code']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'mobile': mobile,
        'organization': organization,
        'country': country,
        'registration_type_id': registrationTypeId,
        'presentation_kind': presentationKind,
        'role_id': roleId,
        'source': source,
        'extra_meals': extraMeals,
        'onsite_due': onsiteDue,
        'onsite_note': onsiteNote,
        'reg_code': regCode,
      };
}

class PassCard {
  final String token;
  final String? attendeeId;
  final int serial;
  final bool isReserve;
  PassCard(this.token, this.attendeeId, this.serial, this.isReserve);

  factory PassCard.fromJson(Map<String, dynamic> j) => PassCard(
        _str(j['token']),
        j['attendee_id']?.toString().toLowerCase(),
        _int(j['serial']) ?? 0,
        j['is_reserve'] == true || j['is_reserve'] == 1,
      );

  Map<String, dynamic> toJson() =>
      {'token': token, 'attendee_id': attendeeId, 'serial': serial, 'is_reserve': isReserve};
}

/// یک رخداد در دفتر رخدادها. seq برای رخدادهای هنوز ارسال‌نشده null است.
class LogEvent {
  final String uuid;
  final String kind;
  final String? cardToken;
  final String? attendeeId;
  final int? mealId;
  final Map<String, dynamic>? payload;
  final DateTime deviceTime;
  final int? staffId;
  final int? seq;
  final String? flag;

  LogEvent({
    required this.uuid,
    required this.kind,
    this.cardToken,
    this.attendeeId,
    this.mealId,
    this.payload,
    required this.deviceTime,
    this.staffId,
    this.seq,
    this.flag,
  });

  factory LogEvent.fromJson(Map<String, dynamic> j) => LogEvent(
        uuid: _str(j['uuid']).toLowerCase(),
        kind: _str(j['kind']),
        cardToken: j['card_token']?.toString(),
        attendeeId: j['attendee_id']?.toString().toLowerCase(),
        mealId: _int(j['meal_id']),
        payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
        deviceTime: DateTime.tryParse(_str(j['device_time'])) ?? DateTime.now().toUtc(),
        staffId: _int(j['staff_id']),
        seq: _int(j['seq']),
        flag: j['flag']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'kind': kind,
        'card_token': cardToken,
        'attendee_id': attendeeId,
        'meal_id': mealId,
        'payload': payload,
        'device_time': deviceTime.toUtc().toIso8601String(),
        'staff_id': staffId,
        'seq': seq,
        'flag': flag,
      };

  /// شکلی که به /device/sync فرستاده می‌شود.
  Map<String, dynamic> toPush() => {
        'uuid': uuid,
        'kind': kind,
        if (cardToken != null) 'card_token': cardToken,
        if (attendeeId != null) 'attendee_id': attendeeId,
        if (mealId != null) 'meal_id': mealId,
        if (payload != null) 'payload': payload,
        'device_time': deviceTime.toUtc().toIso8601String(),
      };
}

class Session {
  final String day;
  final String start;
  final String? end;
  final String title;
  final String hall;
  final String kind;
  Session(this.day, this.start, this.end, this.title, this.hall, this.kind);

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        _str(j['day']),
        _str(j['start_time']),
        j['end_time']?.toString(),
        _str(j['title']),
        _str(j['hall']),
        _str(j['kind']),
      );

  Map<String, dynamic> toJson() =>
      {'day': day, 'start_time': start, 'end_time': end, 'title': title, 'hall': hall, 'kind': kind};
}

class CheckState {
  final DateTime at;
  final int? staffId;
  CheckState(this.at, this.staffId);
}

enum MealVerdict { ok, duplicate, notEntitled }

class MealCheck {
  final MealVerdict verdict;
  final DateTime? previousAt;
  MealCheck(this.verdict, [this.previousAt]);
}
