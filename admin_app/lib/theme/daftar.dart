// «دفتر» — زبان طراحی مشترک اپ نیروها و اپ مدیریت.
// مقدارها از tokens.json سامانه‌ی طراحی آمده‌اند؛ این فایل در هر دو اپ یکسان است.
// صفحه‌ها رنگ وضعیت را از DaftarColors.of(context) و بقیه را از ThemeData می‌گیرند.
import 'package:flutter/material.dart';

/// رنگ‌هایی که در ColorScheme جا ندارند (وضعیت‌ها و رنگ شناسه).
@immutable
class DaftarColors extends ThemeExtension<DaftarColors> {
  final Color paper, surface, sunken, line, lineStrong, ink, inkMuted;
  final Color stamp, stampSoft, onStamp, action, onAction;
  final Color go, goSoft, goFill, onGo;
  final Color stop, stopSoft, stopFill, onStop;
  final Color wait, waitSoft, waitFill, onWait;
  final Color idleFill, onIdle, scrim, camera;

  const DaftarColors({
    required this.paper,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.stamp,
    required this.stampSoft,
    required this.onStamp,
    required this.action,
    required this.onAction,
    required this.go,
    required this.goSoft,
    required this.goFill,
    required this.onGo,
    required this.stop,
    required this.stopSoft,
    required this.stopFill,
    required this.onStop,
    required this.wait,
    required this.waitSoft,
    required this.waitFill,
    required this.onWait,
    required this.idleFill,
    required this.onIdle,
    required this.scrim,
    required this.camera,
  });

  static const light = DaftarColors(
    paper: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFE9ECF0),
    line: Color(0xFFDCE0E6),
    lineStrong: Color(0xFF7E8796),
    ink: Color(0xFF10141A),
    inkMuted: Color(0xFF505966),
    stamp: Color(0xFF2A42D4),
    stampSoft: Color(0xFFE6E9FC),
    onStamp: Color(0xFFFFFFFF),
    action: Color(0xFF10141A),
    onAction: Color(0xFFFFFFFF),
    go: Color(0xFF127A3B),
    goSoft: Color(0xFFE1F5E8),
    goFill: Color(0xFF3DD27A),
    onGo: Color(0xFF06210F),
    stop: Color(0xFFB42318),
    stopSoft: Color(0xFFFDE8E6),
    stopFill: Color(0xFFA3170F),
    onStop: Color(0xFFFFFFFF),
    wait: Color(0xFF8A5300),
    waitSoft: Color(0xFFFFF1D1),
    waitFill: Color(0xFFF5B000),
    onWait: Color(0xFF231600),
    idleFill: Color(0xFF59616E),
    onIdle: Color(0xFFFFFFFF),
    scrim: Color(0x8F080A0E), // rgba(8,10,14,0.56)
    camera: Color(0xFF000000),
  );

  static const dark = DaftarColors(
    paper: Color(0xFF0D1015),
    surface: Color(0xFF161A21),
    sunken: Color(0xFF08090C),
    line: Color(0xFF262C36),
    lineStrong: Color(0xFF6E7888),
    ink: Color(0xFFEDF0F4),
    inkMuted: Color(0xFFA0A9B6),
    stamp: Color(0xFF8E9CFF),
    stampSoft: Color(0xFF1E2552),
    onStamp: Color(0xFF0D1015),
    action: Color(0xFFEDF0F4),
    onAction: Color(0xFF0D1015),
    go: Color(0xFF5CD68B),
    goSoft: Color(0xFF112B1B),
    goFill: Color(0xFF3DD27A),
    onGo: Color(0xFF06210F),
    stop: Color(0xFFFF8A80),
    stopSoft: Color(0xFF3A1513),
    stopFill: Color(0xFFA3170F),
    onStop: Color(0xFFFFFFFF),
    wait: Color(0xFFF5B83D),
    waitSoft: Color(0xFF33260A),
    waitFill: Color(0xFFF5B000),
    onWait: Color(0xFF231600),
    idleFill: Color(0xFF59616E),
    onIdle: Color(0xFFFFFFFF),
    scrim: Color(0xA3000000), // rgba(0,0,0,0.64)
    camera: Color(0xFF000000),
  );

  static DaftarColors of(BuildContext context) => Theme.of(context).extension<DaftarColors>() ?? light;

  @override
  DaftarColors copyWith() => this;

  @override
  DaftarColors lerp(DaftarColors? other, double t) => t < .5 ? this : (other ?? this);
}

/// فاصله‌ها، گوشه‌ها و اندازه‌ها (شبکه‌ی ۴px).
abstract final class DaftarSize {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space7 = 48.0;

  static const radiusXs = 4.0;
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 20.0;
  static const radiusPill = 999.0;

  static const tapMin = 48.0;
  static const tapLg = 56.0;
  static const tapXl = 64.0;
  static const controlDesk = 36.0;
  static const rowDesk = 40.0;
}

/// سایه فقط برای باتم‌شیت و منوهای بازشو؛ بقیه‌ی سطوح با خط line جدا می‌شوند.
List<BoxShadow> daftarShadowPop(Brightness b) => [
      BoxShadow(
        offset: const Offset(0, 8),
        blurRadius: 28,
        color: b == Brightness.dark ? const Color(0x99000000) : const Color(0x2910141A),
      ),
    ];

/// ارقام ثابت‌عرض برای شمارنده، ساعت و جدول.
const tabularFigures = [FontFeature.tabularFigures()];

const _fontFamily = 'Vazirmatn';

// فاصله‌ی حروف روی متن فارسی همیشه صفر است؛ letterSpacing اتصال حروف را می‌شکند.
TextStyle _t(double size, double line, FontWeight w, {bool tabular = false}) => TextStyle(
      fontSize: size,
      height: line / size,
      fontWeight: w,
      letterSpacing: 0,
      fontFeatures: tabular ? tabularFigures : null,
    );

/// مقیاس اپ نیروها (موبایل).
final _mobileText = TextTheme(
  displayLarge: _t(40, 48, FontWeight.w800, tabular: true), // t-count
  displayMedium: _t(32, 42, FontWeight.w800), // t-verdict
  displaySmall: _t(32, 42, FontWeight.w800),
  headlineLarge: _t(26, 38, FontWeight.w700),
  headlineMedium: _t(26, 38, FontWeight.w700),
  headlineSmall: _t(26, 38, FontWeight.w700), // t-name
  titleLarge: _t(20, 30, FontWeight.w700), // t-title
  titleMedium: _t(17, 28, FontWeight.w600), // t-body-lg
  titleSmall: _t(15, 22, FontWeight.w600),
  bodyLarge: _t(16, 24, FontWeight.w400),
  bodyMedium: _t(15, 24, FontWeight.w400), // t-body
  bodySmall: _t(13, 20, FontWeight.w500), // t-caption
  labelLarge: _t(15, 22, FontWeight.w600), // t-label
  labelMedium: _t(13, 20, FontWeight.w600),
  labelSmall: _t(13, 20, FontWeight.w500),
);

/// مقیاس اپ مدیریت (ویندوز).
final _deskText = TextTheme(
  displayLarge: _t(30, 40, FontWeight.w800, tabular: true),
  displayMedium: _t(30, 40, FontWeight.w800, tabular: true),
  displaySmall: _t(30, 40, FontWeight.w800, tabular: true), // td-display
  headlineLarge: _t(20, 30, FontWeight.w700),
  headlineMedium: _t(20, 30, FontWeight.w700),
  headlineSmall: _t(20, 30, FontWeight.w700),
  titleLarge: _t(20, 30, FontWeight.w700), // td-title
  titleMedium: _t(16, 26, FontWeight.w700), // td-heading
  titleSmall: _t(14, 22, FontWeight.w600),
  bodyLarge: _t(14, 22, FontWeight.w400),
  bodyMedium: _t(14, 22, FontWeight.w400), // td-body
  bodySmall: _t(12, 18, FontWeight.w500), // td-caption
  labelLarge: _t(13, 20, FontWeight.w600), // td-label
  labelMedium: _t(12, 18, FontWeight.w600),
  labelSmall: _t(12, 18, FontWeight.w500),
);

/// ThemeData کامل «دفتر». [desktop] برای اپ ویندوز: کنترل ۳۶px، گوشه‌ی ۴px، متن فشرده‌تر.
ThemeData daftarTheme(Brightness b, {bool desktop = false}) {
  final dark = b == Brightness.dark;
  final x = dark ? DaftarColors.dark : DaftarColors.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: x.action,
    onPrimary: x.onAction,
    primaryContainer: x.sunken,
    onPrimaryContainer: x.ink,
    secondary: x.stamp,
    onSecondary: x.onStamp,
    secondaryContainer: x.stampSoft,
    onSecondaryContainer: x.ink,
    tertiary: x.stamp,
    onTertiary: x.onStamp,
    error: x.stop,
    onError: dark ? x.paper : Colors.white,
    errorContainer: x.stopSoft,
    onErrorContainer: x.ink,
    surface: x.paper,
    onSurface: x.ink,
    onSurfaceVariant: x.inkMuted,
    surfaceContainerLowest: x.surface,
    surfaceContainerLow: x.surface,
    surfaceContainer: x.surface,
    surfaceContainerHigh: x.surface,
    surfaceContainerHighest: x.sunken,
    surfaceTint: Colors.transparent,
    outline: x.lineStrong,
    outlineVariant: x.line,
    inverseSurface: x.action,
    onInverseSurface: x.onAction,
    shadow: Colors.black,
    scrim: x.scrim,
  );

  final text = (desktop ? _deskText : _mobileText).apply(
    fontFamily: _fontFamily,
    bodyColor: x.ink,
    displayColor: x.ink,
  );
  final r = desktop ? DaftarSize.radiusXs : DaftarSize.radiusSm;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  final h = desktop ? DaftarSize.controlDesk : DaftarSize.tapLg;
  final border = desktop ? 1.0 : 1.5;
  final buttonText = text.labelLarge;
  final pad = EdgeInsets.symmetric(horizontal: desktop ? 16 : 20);

  OutlineInputBorder box(Color c, double w) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    textTheme: text,
    scaffoldBackgroundColor: x.paper,
    canvasColor: x.paper,
    dividerColor: x.line,
    extensions: [x],
    visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
    materialTapTargetSize: desktop ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
    focusColor: x.stamp.withValues(alpha: .12),
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: x.paper,
      foregroundColor: x.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: x.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(64, h),
        padding: pad,
        shape: shape,
        textStyle: buttonText,
        backgroundColor: x.action,
        foregroundColor: x.onAction,
        disabledBackgroundColor: x.sunken,
        disabledForegroundColor: x.inkMuted,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: Size(64, h),
        padding: pad,
        shape: shape,
        textStyle: buttonText,
        elevation: 0,
        backgroundColor: x.action,
        foregroundColor: x.onAction,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(64, h),
        padding: pad,
        shape: shape,
        textStyle: buttonText,
        foregroundColor: x.ink,
        backgroundColor: x.surface,
        disabledForegroundColor: x.inkMuted,
        side: BorderSide(color: x.lineStrong, width: border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(48, desktop ? DaftarSize.controlDesk : DaftarSize.tapMin),
        shape: shape,
        textStyle: buttonText,
        foregroundColor: x.stamp,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size.square(desktop ? DaftarSize.controlDesk : DaftarSize.tapMin),
        foregroundColor: x.ink,
        shape: shape,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: Size(48, desktop ? DaftarSize.controlDesk : DaftarSize.tapMin),
        textStyle: buttonText,
        backgroundColor: x.surface,
        foregroundColor: x.ink,
        selectedBackgroundColor: x.action,
        selectedForegroundColor: x.onAction,
        side: BorderSide(color: x.lineStrong, width: border),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: x.surface,
      isDense: desktop,
      contentPadding: EdgeInsets.symmetric(horizontal: desktop ? 10 : 14, vertical: desktop ? 10 : 16),
      hintStyle: text.bodyMedium?.copyWith(color: x.inkMuted),
      helperStyle: text.bodySmall?.copyWith(color: x.inkMuted),
      errorStyle: text.bodySmall?.copyWith(color: x.stop),
      labelStyle: text.bodyMedium?.copyWith(color: x.inkMuted),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: x.ink),
      prefixIconColor: x.inkMuted,
      suffixIconColor: x.inkMuted,
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: box(x.lineStrong, border),
      enabledBorder: box(x.lineStrong, border),
      disabledBorder: box(x.line, border),
      focusedBorder: box(x.stamp, 2),
      errorBorder: box(x.stop, 2),
      focusedErrorBorder: box(x.stop, 2),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: x.lineStrong, width: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: x.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: x.action,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DaftarSize.radiusSm)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? x.ink : x.inkMuted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? x.onAction : x.inkMuted)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: x.surface,
      modalBackgroundColor: x.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: x.scrim,
      showDragHandle: true,
      dragHandleColor: x.lineStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DaftarSize.radiusLg)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: x.action,
      contentTextStyle: text.bodyMedium?.copyWith(color: x.onAction),
      actionTextColor: x.onAction,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DaftarSize.radiusSm)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: x.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: x.scrim,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DaftarSize.radiusMd)),
    ),
    cardTheme: CardThemeData(
      color: x.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DaftarSize.radiusMd),
        side: BorderSide(color: x.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: x.inkMuted,
      textColor: x.ink,
      titleTextStyle: desktop ? text.bodyMedium : text.titleMedium,
      subtitleTextStyle: text.bodySmall?.copyWith(color: x.inkMuted),
      minVerticalPadding: desktop ? 4 : 8,
    ),
    dividerTheme: DividerThemeData(color: x.line, space: 1, thickness: 1),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
      side: BorderSide(color: x.line),
      backgroundColor: x.surface,
      selectedColor: x.stampSoft,
      checkmarkColor: x.ink,
      labelStyle: text.labelMedium?.copyWith(color: x.ink),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: x.action,
      linearTrackColor: x.sunken,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(x.lineStrong),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: x.action, borderRadius: BorderRadius.circular(DaftarSize.radiusXs)),
      textStyle: text.bodySmall?.copyWith(color: x.onAction),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: x.surface,
      indicatorColor: x.stampSoft,
      selectedIconTheme: IconThemeData(color: x.ink),
      unselectedIconTheme: IconThemeData(color: x.inkMuted),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(x.sunken),
      headingRowHeight: DaftarSize.controlDesk,
      dataRowMinHeight: DaftarSize.rowDesk,
      dataRowMaxHeight: DaftarSize.rowDesk,
      headingTextStyle: text.labelLarge?.copyWith(color: x.ink),
      dataTextStyle: text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
      dividerThickness: 1,
      horizontalMargin: DaftarSize.space3,
      columnSpacing: DaftarSize.space5,
      decoration: BoxDecoration(
        color: x.surface,
        border: Border.all(color: x.line),
        borderRadius: BorderRadius.circular(DaftarSize.radiusXs),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: x.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: BorderSide(color: x.line),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(x.surface),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: x.stampSoft,
      contentTextStyle: text.bodyMedium,
      dividerColor: Colors.transparent,
    ),
  );
}

/// دکمه‌ی «تأیید» (go): فقط برای «تیک پذیرش» و «ثبت، پذیرش و تحویل کارت».
ButtonStyle daftarGoStyle(BuildContext context, {bool xl = true}) {
  final x = DaftarColors.of(context);
  return FilledButton.styleFrom(
    backgroundColor: x.goFill,
    foregroundColor: x.onGo,
    minimumSize: Size.fromHeight(xl ? DaftarSize.tapXl : DaftarSize.tapLg),
    textStyle: Theme.of(context).textTheme.titleMedium,
  );
}

/// دکمه‌ی «خطرناک» (danger): کار برگشت‌ناپذیر در دیالوگ تأیید.
ButtonStyle daftarDangerStyle(BuildContext context) {
  final x = DaftarColors.of(context);
  return FilledButton.styleFrom(backgroundColor: x.stopFill, foregroundColor: x.onStop);
}

/// دکمه‌ی اصلی تمام‌عرض (xl ۶۴px یا lg ۵۶px).
ButtonStyle daftarWideStyle(BuildContext context, {bool xl = false}) => FilledButton.styleFrom(
      minimumSize: Size.fromHeight(xl ? DaftarSize.tapXl : DaftarSize.tapLg),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );
