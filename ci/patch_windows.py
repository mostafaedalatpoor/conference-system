"""بعد از flutter create: عنوان پنجره، نام فایل اجرایی، مشخصات فایل (MakerCredit) و آیکن.

python ci/patch_windows.py <windows dir> --binary RoydadYarStaff --title "رویدادیار نیروها" --icon branding/windows/app_icon.ico
"""
import argparse
import re
import shutil
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("windows_dir")
ap.add_argument("--binary", required=True)
ap.add_argument("--title", required=True)
ap.add_argument("--icon", required=True)
args = ap.parse_args()

root = Path(args.windows_dir)

# عنوان پنجره با \u تا به کدگذاری فایل منبع وابسته نباشد.
main_cpp = root / "runner/main.cpp"
src = main_cpp.read_text(encoding="utf-8")
escaped = "".join(c if ord(c) < 128 else f"\\u{ord(c):04X}" for c in args.title)
src, n = re.subn(r'window\.Create\(L"[^"]*"', lambda _: f'window.Create(L"{escaped}"', src)
assert n == 1, "window.Create not found"
main_cpp.write_text(src, encoding="utf-8")

cmake = root / "CMakeLists.txt"
src = cmake.read_text(encoding="utf-8")
src, n = re.subn(r'set\(BINARY_NAME "[^"]*"\)', lambda _: f'set(BINARY_NAME "{args.binary}")', src)
assert n == 1, "BINARY_NAME not found"
cmake.write_text(src, encoding="utf-8")

# مشخصات فایل در Properties ← Details. Runner.rc با code_page(65001) است، پس فارسی مجاز است.
rc = root / "runner/Runner.rc"
src = rc.read_text(encoding="utf-8")
values = {
    "CompanyName": "NewVisionteam - تیم راهکارهای نرم‌افزاری نگاه جدید",
    "FileDescription": args.title,
    "InternalName": args.binary,
    "LegalCopyright": "© 2026 NewVisionteam",
    "OriginalFilename": f"{args.binary}.exe",
    "ProductName": "RoydadYar - رویدادیار",
}
for key, value in values.items():
    src, n = re.subn(rf'VALUE "{key}", "[^"]*"', lambda _: f'VALUE "{key}", "{value}"', src)
    assert n == 1, f"{key} not found"
rc.write_text(src, encoding="utf-8")

shutil.copyfile(args.icon, root / "runner/resources/app_icon.ico")
print("patched", root)
