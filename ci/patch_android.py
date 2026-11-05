"""بعد از flutter create: مجوز اینترنت، نام نمایشی اپ و (اختیاری) پیش‌نیازهای قفل اثر انگشت.

python3 ci/patch_android.py <android dir> --label "رویدادیار نیروها" [--biometric]
نام‌های فنی (شناسه‌ی بسته) عوض نمی‌شوند تا نسخه‌ی تازه روی نسخه‌ی قبلی نصب شود.
"""
import argparse
import re
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("android_dir")
ap.add_argument("--label", required=True)
ap.add_argument("--biometric", action="store_true")
args = ap.parse_args()

root = Path(args.android_dir)
manifest = root / "app/src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")


def add_permission(text: str, name: str) -> str:
    if name in text:
        return text
    return re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{name}"/>', text, count=1)


text = add_permission(text, "android.permission.INTERNET")
if args.biometric:
    text = add_permission(text, "android.permission.USE_BIOMETRIC")
text = re.sub(r'android:label="[^"]*"', f'android:label="{args.label}"', text, count=1)
manifest.write_text(text, encoding="utf-8")
print("patched", manifest)

if args.biometric:
    # local_auth به FragmentActivity نیاز دارد.
    for f in (root / "app/src/main").rglob("MainActivity.*"):
        src = f.read_text(encoding="utf-8")
        src = src.replace("io.flutter.embedding.android.FlutterActivity", "io.flutter.embedding.android.FlutterFragmentActivity")
        src = re.sub(r"\bFlutterActivity\(\)", "FlutterFragmentActivity()", src)
        src = re.sub(r"extends FlutterActivity\b", "extends FlutterFragmentActivity", src)
        f.write_text(src, encoding="utf-8")
        print("patched", f)
