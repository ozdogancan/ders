"""
Koala launcher icon + splash builder.
Input : assets/images/koala_hero.webp
Output: assets/launcher/{icon.png, icon_foreground.png, splash.png}
"""
from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "assets" / "images" / "koala_hero.webp"
OUT  = ROOT / "assets" / "launcher"
OUT.mkdir(parents=True, exist_ok=True)

BRAND = (107, 91, 230, 255)  # #6B5BE6
SIZE  = 1024

def place(canvas, src, scale):
    sw, sh = src.size
    th = int(SIZE * scale)
    tw = int(sw * (th / sh))
    if tw > SIZE * 0.90:
        tw = int(SIZE * 0.90)
        th = int(sh * (tw / sw))
    r = src.resize((tw, th), Image.LANCZOS)
    x = (SIZE - tw) // 2
    y = int((SIZE - th) * 0.48)
    canvas.paste(r, (x, y), r)
    return canvas

def main():
    koala = Image.open(SRC).convert("RGBA")

    icon = place(Image.new("RGBA", (SIZE, SIZE), BRAND), koala, 0.78)
    icon.save(OUT / "icon.png", "PNG")

    fg = place(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), koala, 0.58)
    fg.save(OUT / "icon_foreground.png", "PNG")

    splash = place(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), koala, 0.55)
    splash.save(OUT / "splash.png", "PNG")

    print(f"Wrote: {OUT}")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name}  ({f.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    main()
