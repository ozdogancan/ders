"""
Rebuild launcher icons with proper padding for Android adaptive icons.

Adaptive icon spec: 108x108 dp canvas, 72x72 dp safe zone.
Content must fit inside ~66% of canvas, rest gets clipped by system mask.

Source: assets/launcher/icon.png (our good square icon)
Outputs:
  - icon_foreground.png: koala centered at 66% on transparent bg (adaptive foreground)
  - splash.png:          koala centered at ~40% on transparent bg (native splash)

Run: python scripts/rebuild_icons.py
Then: flutter pub run flutter_launcher_icons
      flutter pub run flutter_native_splash:create
"""

from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "launcher" / "icon.png"
FG_OUT = ROOT / "assets" / "launcher" / "icon_foreground.png"
SPLASH_OUT = ROOT / "assets" / "launcher" / "splash.png"

CANVAS = 1024

def compose(inner_ratio: float, out_path: Path) -> None:
    src = Image.open(SRC).convert("RGBA")
    inner_size = int(CANVAS * inner_ratio)
    src_resized = src.resize((inner_size, inner_size), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - inner_size) // 2
    canvas.paste(src_resized, (offset, offset), src_resized)
    canvas.save(out_path, "PNG", optimize=True)
    print(f"  {out_path.name}: {inner_size}px icon on {CANVAS}px transparent canvas")

print("Rebuilding launcher + splash assets...")
print(f"Source: {SRC}")

# Adaptive icon foreground: fill full canvas (1.0), Android mask clips outer ~20%.
# Scaling smaller just shrinks the icon and makes the solid background dominate.
compose(1.00, FG_OUT)

# Splash: smaller centered icon on large purple canvas
compose(0.40, SPLASH_OUT)

print("Done. Now run:")
print("  flutter pub run flutter_launcher_icons")
print("  flutter pub run flutter_native_splash:create")
