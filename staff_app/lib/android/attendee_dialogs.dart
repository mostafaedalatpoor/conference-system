// کارهای مشترک روی یک نفر: حرف دسته‌ی کارت.
import '../models.dart';



/// حرف دسته‌ی کارت چاپی (همان قاعده‌ی چیدن کارت‌ها در اپ مدیریت).
String batchLetter(Attendee a) {
  // همان قاعده‌ی چیدن کارت‌ها در اپ مدیریت: نام خانوادگی، اگر نبود نام، اگر هیچ نبود «؟» (آخر دسته‌ها).
  final last = a.lastName;
  var first = a.firstName;
  if (first.startsWith('بی‌نام (ردیف ')) first = ''; // نام جایگزین ردیف بی‌نام اپ مدیریت
  final s = (last.trim().isNotEmpty ? last : first).trim();
  if (s.isEmpty) return '؟';
  final ch = String.fromCharCode(s.runes.first);
  return ch == 'آ' ? 'ا' : ch;
}


