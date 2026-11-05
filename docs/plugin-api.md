# تغییرهای لازم در افزونه‌ی وردپرس (رویدادیار)

اپ‌های این مخزن بخش کلاینتِ سامانه‌ی طراحی «دفتر» را پیاده کرده‌اند. چند بخش به افزونه‌ی وردپرس نیاز دارد که در این مخزن نیست. تا وقتی افزونه این‌ها را ندارد، اپ‌ها با حالت پیش‌فرض کار می‌کنند و چیزی نمی‌شکند.

## ۱. تنظیم‌های رویداد (`settings`)

`POST /admin/events/{code}/config` حالا علاوه بر انواع ثبت‌نام، نقش‌ها، وعده‌ها و برنامه یک کلید `settings` هم می‌فرستد:

```json
{
  "settings": {
    "identify_mode": "scan | card | none",
    "qr_behavior": "person | redirect | vcard",
    "qr_redirect_url": "https://…",
    "contact_fields": {"name": true, "organization": true, "email": false, "mobile": false, "country": false},
    "show_maker_credit": true
  }
}
```

- افزونه این شیء را برای رویداد ذخیره کند و با تغییرش `config_version` را بالا ببرد.
- همان شیء در `GET /admin/events/{code}/snapshot` و `GET /device/snapshot` برگردانده شود، یا در سطح بالا (`settings`) یا داخل `event.settings`.
- اپ نیروها `identify_mode` را می‌خواند. بدون آن، پیش‌فرض `scan` است. اپ مدیریت تا وقتی سرور برنگرداند، نسخه‌ی محلی را نگه می‌دارد.

## ۲. صفحه‌ی عمومی `/c/<token>` (QrBehavior، PublicPass)

- `person`: همان صفحه‌ی فرد؛ اگر `contact_fields` اجازه دهد دکمه‌ی «ذخیره در مخاطبین» (فایل `.vcf` ساخته‌ی سرور با همان فیلدهای مجاز).
- `redirect`: انتقال ۳۰۲ به `qr_redirect_url`؛ اگر خالی یا خراب بود، صفحه‌ی فرد.
- `vcard`: محتوای QR خود vCard است و اپ مدیریت هنگام ساخت PDF آن را می‌سازد؛ `URL` آن همیشه `/c/<token>` است، پس صفحه‌ی فرد هم باید کار کند.
- `show_maker_credit`: خط «ساخته‌شده با رویدادیار · نگاه جدید» زیر برنامه.
- کارت‌های رزرو همیشه `person`.
- ستون اختیاری «اشتراک اطلاعات تماس» در اکسل هنوز در اپ مدیریت نگاشت نمی‌شود.

## ۳. ثبت‌نام در محل بدون کارت

در حالت `identify_mode = none`، رخداد `walkin_register` و `checkin` بدون `card_token` می‌آیند. `/device/sync` باید آن‌ها را بپذیرد.

## ۴. تاریخچه‌ی یک نفر (PersonTimeline)

```
GET /admin/events/{code}/attendees/{attendee_id}/timeline
→ {"events": [{"kind": "checkin|checkin_undo|meal_served|walkin_register",
               "meal_name": "…", "device_time": "ISO-8601", "device_label": "…",
               "staff": "…", "flag": null | "duplicate…", "flag_label": "…"}]}
```

تا وقتی نیست، اپ مدیریت در صفحه‌ی فرد می‌گوید «تاریخچه از سرور در دسترس نیست».

## ۵. هنوز در اپ‌ها نیامده، چون به افزونه وابسته است

- قالب کارت روی سرور (تا ویندوز و موبایل یک قالب ببینند). فعلاً روی هر دستگاه جداست.
- کلید API جدا برای گوشی مدیر، قابل باطل‌کردن در وردپرس (M1). قفل اثر انگشت سمت اپ انجام شده است.
- باطل‌کردن یک دستگاه از اپ مدیریت (`DeviceRow`). فعلاً با حذف نیرو.
- لغو پذیرش از اپ مدیریت در صفحه‌ی فرد.
- سربرگ، منو و پانویس افزونه با نام «رویدادیار» و سازنده (`MakerCredit`).
