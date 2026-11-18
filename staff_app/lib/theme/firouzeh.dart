// «فیروزه» — سیستم طراحی مشترک اپ نیروها و اپ مدیریت (فیروزه‌ای #0B7A7B، هدر خمیده، کارت شناور).
// مقدارها از tokens.json سامانه‌ی طراحی آمده‌اند؛ این فایل در هر دو اپ یکسان است.
// صفحه‌ها رنگ وضعیت را از FirouzehColors.of(context) و بقیه را از ThemeData می‌گیرند.
import 'package:flutter/material.dart';

/// رنگ‌هایی که در ColorScheme جا ندارند (وضعیت‌ها و رنگ شناسه).
@immutable
class FirouzehColors extends ThemeExtension<FirouzehColors> {
  final Color paper, surface, sunken, line, lineStrong, ink, inkMuted;
  final Color stamp, stampSoft, onStamp, action, onAction;
  final Color go, goSoft, goFill, onGo;
  final Color stop, stopSoft, stopFill, onStop;
  final Color wait, waitSoft, waitFill, onWait;
  final Color idleFill, onIdle, scrim, camera;

  const FirouzehColors({
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

  static const light = FirouzehColors(
    paper: Color(0xFFF2F6F6), // ground
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEAF1F1), // surface-2
    line: Color(0xFFDCE7E7),
    lineStrong: Color(0xFF7B8C8D),
    ink: Color(0xFF0F1C1D),
    inkMuted: Color(0xFF5B6B6C),
    stamp: Color(0xFF0B7A7B), // brand-text
    stampSoft: Color(0xFFE1F1F1), // brand-soft
    onStamp: Color(0xFFFFFFFF),
    action: Color(0xFF0B7A7B), // brand
    onAction: Color(0xFFFFFFFF), // on-brand
    go: Color(0xFF138A43),
    goSoft: Color(0xFFE3F5EA),
    goFill: Color(0xFF3DD27A), // scan-go
    onGo: Color(0xFF06210F),
    stop: Color(0xFFB3261E),
    stopSoft: Color(0xFFFDE9E7),
    stopFill: Color(0xFFA3170F), // scan-stop
    onStop: Color(0xFFFFFFFF),
    wait: Color(0xFF8A5300),
    waitSoft: Color(0xFFFFF1D1),
    waitFill: Color(0xFFF5B000), // scan-wait
    onWait: Color(0xFF231600),
    idleFill: Color(0xFF59616E), // scan-idle
    onIdle: Color(0xFFFFFFFF),
    scrim: Color(0x730F1C1D),
    camera: Color(0xFF000000),
  );

  static const dark = FirouzehColors(
    paper: Color(0xFF0D1415),
    surface: Color(0xFF162022),
    sunken: Color(0xFF1E2A2C),
    line: Color(0xFF2A3A3C),
    lineStrong: Color(0xFF6B7F80),
    ink: Color(0xFFEAF1F1),
    inkMuted: Color(0xFF9FB0B1),
    stamp: Color(0xFF6FD0D1),
    stampSoft: Color(0xFF12302F),
    onStamp: Color(0xFF0D1415),
    action: Color(0xFF0B7A7B),
    onAction: Color(0xFFFFFFFF),
    go: Color(0xFF5CD68B),
    goSoft: Color(0xFF12301F),
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
    scrim: Color(0xA0000000),
    camera: Color(0xFF000000),
  );

  static FirouzehColors of(BuildContext context) => Theme.of(context).extension<FirouzehColors>() ?? light;

  @override
  FirouzehColors copyWith() => this;

  @override
  FirouzehColors lerp(FirouzehColors? other, double t) => t < .5 ? this : (other ?? this);
}

/// فاصله‌ها، گوشه‌ها و اندازه‌ها (شبکه‌ی ۴px).
abstract final class FirouzehSize {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space7 = 48.0;

  static const radiusXs = 8.0;
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 28.0;
  static const radiusPill = 999.0;

  static const tapMin = 48.0;
  static const tapLg = 56.0;
  static const tapXl = 64.0;
  static const controlDesk = 40.0;
  static const rowDesk = 46.0;
  static const sideNav = 264.0;
}

/// shadow-float: ناوبری شناور پایین، باتم‌شیت و منوهای بازشو.
List<BoxShadow> firouzehShadowPop(Brightness b) => const [
      BoxShadow(offset: Offset(0, 10), blurRadius: 30, color: Color(0x2E000000)),
    ];

/// shadow-card: تنها کارت اصلی هر صفحه که روی هدر خمیده می‌نشیند.
const firouzehShadowCard = [
  BoxShadow(offset: Offset(0, 10), blurRadius: 30, color: Color(0x240B7A7B)),
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

/// ThemeData کامل «فیروزه». [desktop] برای اپ ویندوز: کنترل ۴۰px، گوشه‌ی ۱۲px، متن فشرده‌تر.
ThemeData firouzehTheme(Brightness b, {bool desktop = false}) {
  final dark = b == Brightness.dark;
  final x = dark ? FirouzehColors.dark : FirouzehColors.light;
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
  // radius-sm (۱۲) برای کنترل دسکتاپ، radius-md (۱۶) برای دکمه و فیلد موبایل.
  final r = desktop ? FirouzehSize.radiusSm : FirouzehSize.radiusMd;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  final h = desktop ? FirouzehSize.controlDesk : FirouzehSize.tapLg;
  const border = 1.0;
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
    // هدر خمیده: پر از brand، پایین با radius-xl، متن on-brand.
    appBarTheme: AppBarTheme(
      backgroundColor: x.action,
      foregroundColor: x.onAction,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: text.titleLarge?.copyWith(color: x.onAction, fontWeight: FontWeight.w800),
      iconTheme: IconThemeData(color: x.onAction),
      actionsIconTheme: IconThemeData(color: x.onAction),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(FirouzehSize.radiusXl)),
      ),
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
        minimumSize: Size(48, desktop ? FirouzehSize.controlDesk : FirouzehSize.tapMin),
        shape: shape,
        textStyle: buttonText,
        foregroundColor: x.stamp,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size.square(desktop ? FirouzehSize.controlDesk : FirouzehSize.tapMin),
        foregroundColor: x.ink,
        shape: shape,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: Size(48, desktop ? FirouzehSize.controlDesk : FirouzehSize.tapMin),
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
      fillColor: x.sunken,
      isDense: desktop,
      contentPadding: EdgeInsets.symmetric(horizontal: desktop ? 12 : 16, vertical: desktop ? 12 : 17),
      hintStyle: text.bodyMedium?.copyWith(color: x.inkMuted),
      helperStyle: text.bodySmall?.copyWith(color: x.inkMuted),
      errorStyle: text.bodySmall?.copyWith(color: x.stop),
      labelStyle: text.bodyMedium?.copyWith(color: x.inkMuted),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: x.ink),
      prefixIconColor: x.inkMuted,
      suffixIconColor: x.inkMuted,
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: box(x.line, border),
      enabledBorder: box(x.line, border),
      disabledBorder: box(x.line, border),
      focusedBorder: box(x.action, 2),
      errorBorder: box(x.stop, 2),
      focusedErrorBorder: box(x.stop, 2),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: x.lineStrong, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? x.action : Colors.transparent),
      checkColor: WidgetStateProperty.all(x.onAction),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FirouzehSize.radiusXs)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: x.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: x.action,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FirouzehSize.radiusMd)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? x.stamp : x.inkMuted,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(FirouzehSize.radiusXl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: x.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: x.paper),
      actionTextColor: dark ? x.action : const Color(0xFF6FD0D1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FirouzehSize.radiusMd)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: x.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: x.scrim,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FirouzehSize.radiusLg)),
    ),
    // کارت شناور: surface، radius-lg، بدون قاب پررنگ.
    cardTheme: CardThemeData(
      color: x.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FirouzehSize.radiusLg),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FirouzehSize.radiusPill)),
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
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? x.onAction : x.lineStrong),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? x.action : x.sunken),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: x.ink, borderRadius: BorderRadius.circular(FirouzehSize.radiusXs)),
      textStyle: text.bodySmall?.copyWith(color: x.paper),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: x.surface,
      indicatorColor: x.stampSoft,
      selectedIconTheme: IconThemeData(color: x.ink),
      unselectedIconTheme: IconThemeData(color: x.inkMuted),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(x.sunken),
      headingRowHeight: FirouzehSize.controlDesk,
      dataRowMinHeight: FirouzehSize.rowDesk,
      dataRowMaxHeight: FirouzehSize.rowDesk,
      headingTextStyle: text.labelLarge?.copyWith(color: x.ink),
      dataTextStyle: text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
      dividerThickness: 1,
      horizontalMargin: FirouzehSize.space3,
      columnSpacing: FirouzehSize.space5,
      decoration: BoxDecoration(
        color: x.surface,
        border: Border.all(color: x.line),
        borderRadius: BorderRadius.circular(FirouzehSize.radiusSm),
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
ButtonStyle firouzehGoStyle(BuildContext context, {bool xl = true}) {
  final x = FirouzehColors.of(context);
  return FilledButton.styleFrom(
    backgroundColor: x.goFill,
    foregroundColor: x.onGo,
    minimumSize: Size.fromHeight(xl ? FirouzehSize.tapXl : FirouzehSize.tapLg),
    textStyle: Theme.of(context).textTheme.titleMedium,
  );
}

/// دکمه‌ی «خطرناک» (danger): کار برگشت‌ناپذیر در دیالوگ تأیید.
ButtonStyle firouzehDangerStyle(BuildContext context) {
  final x = FirouzehColors.of(context);
  return FilledButton.styleFrom(backgroundColor: x.stopFill, foregroundColor: x.onStop);
}

/// دکمه‌ی اصلی تمام‌عرض (xl ۶۴px یا lg ۵۶px).
ButtonStyle firouzehWideStyle(BuildContext context, {bool xl = false}) => FilledButton.styleFrom(
      minimumSize: Size.fromHeight(xl ? FirouzehSize.tapXl : FirouzehSize.tapLg),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );
