"""بعد از flutter create: مجوز اینترنت و نام اپ را در AndroidManifest می‌گذارد."""
import re
import sys
from pathlib import Path

manifest = Path(sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml")
text = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in text:
    text = re.sub(
        r"(<manifest[^>]*>)",
        r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
        text,
        count=1,
    )

text = re.sub(r'android:label="[^"]*"', 'android:label="نیروهای کنفرانس"', text, count=1)
manifest.write_text(text, encoding="utf-8")
print("patched", manifest)
