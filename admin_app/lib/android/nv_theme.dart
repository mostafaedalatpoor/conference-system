// ظاهر تازه‌ی اپ نیروها روی اندروید (طرح «رویدادیار نیروها · اندروید»).
// ویندوز فعلاً همان «دفتر» را دارد. مقدارها از همان طرح آمده‌اند؛ نسخه‌ی تیره از همین رنگ‌ها ساخته شده.
import 'package:flutter/material.dart';

import '../theme/daftar.dart';

@immutable
class NvColors extends ThemeExtension<NvColors> {
  final Color brand, onBrand, brandSoft, brandText;
  final Color bg, surface, field, chip, tag, line, lineSoft;
  final Color ink, muted, faint;
  final Color go, goSoft, goInk, wait, waitSoft, waitInk, stop, stopSoft, stopInk, neutralSoft;
  final Color verdictOk, onVerdictOk, verdictBad, camera, scrim, shadow;

  const NvColors({
    required this.brand,
    required this.onBrand,
    required this.brandSoft,
    required this.brandText,
    required this.bg,
    required this.surface,
    required this.field,
    required this.chip,
    required this.tag,
    required this.line,
    required this.lineSoft,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.go,
    required this.goSoft,
    required this.goInk,
    required this.wait,
    required this.waitSoft,
    required this.waitInk,
    required this.stop,
    required this.stopSoft,
    required this.stopInk,
    required this.neutralSoft,
    required this.verdictOk,
    required this.onVerdictOk,
    required this.verdictBad,
    required this.camera,
    required this.scrim,
    required this.shadow,
  });

  static const light = NvColors(
    brand: Color(0xFF0B7A7B),
    onBrand: Color(0xFFFFFFFF),
    brandSoft: Color(0xFFE2F0F0),
    brandText: Color(0xFF0B7A7B),
    bg: Color(0xFFF2F6F6),
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFF2F6F6),
    chip: Color(0xFFE3EFEF),
    tag: Color(0xFFEAF1F1),
    line: Color(0xFFB7C6C7),
    lineSoft: Color(0xFFEDF2F2),
    ink: Color(0xFF0F1C1D),
    muted: Color(0xFF5B6B6C),
    faint: Color(0xFF8A9899),
    go: Color(0xFF138A43),
    goSoft: Color(0xFFE3F5EA),
    goInk: Color(0xFF0B5A2B),
    wait: Color(0xFF8A5300),
    waitSoft: Color(0xFFFFF1D1),
    waitInk: Color(0xFF4A2F00),
    stop: Color(0xFFB3261E),
    stopSoft: Color(0xFFFDE9E7),
    stopInk: Color(0xFF4A2623),
    neutralSoft: Color(0xFFE9EEEE),
    verdictOk: Color(0xFF3DD27A),
    onVerdictOk: Color(0xFF06210F),
    verdictBad: Color(0xFFA3170F),
    camera: Color(0xFF1C2526),
    scrim: Color(0x6B0F1C1D),
    shadow: Color(0x240B7A7B),
  );

  static const dark = NvColors(
    brand: Color(0xFF0B7A7B),
    onBrand: Color(0xFFFFFFFF),
    brandSoft: Color(0xFF123536),
    brandText: Color(0xFF5CC7C8),
    bg: Color(0xFF0C1213),
    surface: Color(0xFF162021),
    field: Color(0xFF0F1718),
    chip: Color(0xFF1F2E2F),
    tag: Color(0xFF1F2E2F),
    line: Color(0xFF3A4D4F),
    lineSoft: Color(0xFF223031),
    ink: Color(0xFFE8F0F0),
    muted: Color(0xFFA0B1B2),
    faint: Color(0xFF7D8F90),
    go: Color(0xFF5BD08A),
    goSoft: Color(0xFF12301E),
    goInk: Color(0xFFBFF0D1),
    wait: Color(0xFFF5B83D),
    waitSoft: Color(0xFF33260A),
    waitInk: Color(0xFFFFE3A6),
    stop: Color(0xFFFF8A80),
    stopSoft: Color(0xFF3A1512),
    stopInk: Color(0xFFFFD2CD),
    neutralSoft: Color(0xFF223031),
    verdictOk: Color(0xFF3DD27A),
    onVerdictOk: Color(0xFF06210F),
    verdictBad: Color(0xFFA3170F),
    camera: Color(0xFF000000),
    scrim: Color(0x99000000),
    shadow: Color(0x40000000),
  );

  static NvColors of(BuildContext context) => Theme.of(context).extension<NvColors>() ?? light;

  @override
  NvColors copyWith() => this;

  @override
  NvColors lerp(ThemeExtension<NvColors>? other, double t) => (t < .5 || other is! NvColors) ? this : other;
}

/// اندازه‌ها و گوشه‌های طرح.
abstract final class Nv {
  static const r12 = 12.0, r14 = 14.0, r16 = 16.0, r18 = 18.0, r22 = 22.0, r24 = 24.0, r28 = 28.0, r32 = 32.0;
  static const field = 54.0, button = 58.0, buttonXl = 62.0, row = 64.0;
  static const gutter = 16.0;
  static List<BoxShadow> raised(NvColors c) => [BoxShadow(color: c.shadow, blurRadius: 30, offset: const Offset(0, 10))];
}

/// تم اندروید: پایه‌ی «دفتر» (تا اجزای مشترک کار کنند) با رنگ‌ها و گوشه‌های طرح تازه.
ThemeData nvTheme(Brightness b) {
  final c = b == Brightness.dark ? NvColors.dark : NvColors.light;
  final base = daftarTheme(b);
  final d = (b == Brightness.dark ? DaftarColors.dark : DaftarColors.light);
  // اجزای مشترک (دیالوگ تکمیل اطلاعات، وصل کارت…) رنگ را از DaftarColors می‌گیرند؛ با رنگ‌های طرح تازه.
  final dx = DaftarColors(
    paper: c.bg,
    surface: c.surface,
    sunken: c.field,
    line: c.lineSoft,
    lineStrong: c.line,
    ink: c.ink,
    inkMuted: c.muted,
    stamp: c.brandText,
    stampSoft: c.brandSoft,
    onStamp: c.onBrand,
    action: c.brand,
    onAction: c.onBrand,
    go: c.go,
    goSoft: c.goSoft,
    goFill: d.goFill,
    onGo: d.onGo,
    stop: c.stop,
    stopSoft: c.stopSoft,
    stopFill: d.stopFill,
    onStop: d.onStop,
    wait: c.wait,
    waitSoft: c.waitSoft,
    waitFill: d.waitFill,
    onWait: d.onWait,
    idleFill: d.idleFill,
    onIdle: d.onIdle,
    scrim: c.scrim,
    camera: c.camera,
  );
  OutlineInputBorder border(Color color, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nv.r16),
        borderSide: BorderSide(color: color, width: w),
      );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: c.brand,
      onPrimary: c.onBrand,
      surface: c.surface,
      onSurface: c.ink,
      error: c.stop,
    ),
    extensions: [dx, c],
    cardTheme: base.cardTheme.copyWith(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r18)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: c.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(c.line, 1.5),
      enabledBorder: border(c.line, 1.5),
      focusedBorder: border(c.brand, 2),
      errorBorder: border(c.stop, 2),
      focusedErrorBorder: border(c.stop, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        minimumSize: const Size(64, Nv.button),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r18)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 17, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: c.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brandText,
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Nv.r28))),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nv.r16)),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: base.switchTheme,
  );
}
