"""Install Hesabaty's provided wallet/H launcher artwork in Flutter Android.

Run after flutter create, before flutter build. No Flutter package is required.
The source WebP is a resized, icon-friendly crop of the owner's supplied logo.
"""
from pathlib import Path
from PIL import Image

APP = Path("android/app/src/main")
LOGO = Path("branding/hesabaty_launcher.webp")
if not LOGO.is_file():
    raise SystemExit("Hesabaty brand icon missing: " + str(LOGO))
image = Image.open(LOGO).convert("RGBA")
if image.width != image.height or image.width < 192:
    raise SystemExit("Expected a square Hesabaty launcher icon >= 192px")
res = APP / "res"
sizes = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
for dpi, width in sizes.items():
    destination = res / ("mipmap-" + dpi)
    destination.mkdir(parents=True, exist_ok=True)
    image.resize((width, width), Image.Resampling.LANCZOS).save(
        destination / "ic_launcher.png", optimize=True
    )
# Adaptive foreground is inset so the wallet/H remains inside safe masks.
foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
mark = image.resize((300, 300), Image.Resampling.LANCZOS)
foreground.alpha_composite(mark, ((432-300)//2, (432-300)//2))
drawable = res / "drawable"
drawable.mkdir(parents=True, exist_ok=True)
foreground.save(drawable / "hesabaty_icon_foreground.png", optimize=True)

colors = res / "values"
colors.mkdir(parents=True, exist_ok=True)
(colors / "hesabaty_icon_colors.xml").write_text(
    '<resources><color name="hesabaty_icon_background">#FFFFFF</color></resources>\n',
    encoding="utf-8"
)
adaptive = res / "mipmap-anydpi-v26"
adaptive.mkdir(parents=True, exist_ok=True)
(adaptive / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <background android:drawable="@color/hesabaty_icon_background"/>\n'
    '  <foreground android:drawable="@drawable/hesabaty_icon_foreground"/>\n'
    '</adaptive-icon>\n',
    encoding="utf-8"
)
print("Installed Hesabaty brand launcher icons at 5 densities + adaptive icon")
