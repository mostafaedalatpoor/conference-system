// نام محصول و سازنده (MakerCredit). نام‌های فنی (شناسه‌ی بسته، مسیر API) عوض نمی‌شوند.
const productName = 'رویدادیار';
const productLatin = 'RoydadYar';
const appName = 'رویدادیار مدیریت';
const appNameLatin = 'RoydadYar Admin';

/// نسخه از pubspec.yaml؛ ساخت گیت‌هاب آن را با --dart-define می‌دهد. پیش‌فرض برای ساخت محلی است.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.4.0');

/// شماره‌ی ساخت گیت‌هاب؛ هر ساخت شماره‌ی جدا دارد تا نسخه‌ها هنگام نصب قاطی نشوند.
const appBuild = String.fromEnvironment('APP_BUILD');

/// برای «درباره»: «0.3.0 (ساخت 57)».
const appVersionLabel = appBuild == '' ? appVersion : '$appVersion (ساخت $appBuild)';

const makerFull = 'ساخته‌ی تیم راهکارهای نرم‌افزاری نگاه جدید';
const makerTeam = 'تیم راهکارهای نرم‌افزاری نگاه جدید';
const makerShort = 'ساخته‌ی تیم نگاه جدید';
const makerLatin = 'by NewVisionteam';
const makerWebsite = 'newvisionteam.ir';
