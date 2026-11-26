"""Generate the AI Learning (respondent) launcher icon.

The customer icon is the plain red R monogram. The respondent app must be
visually distinguishable on a home screen where both apps sit side by side,
so this stamps an "AI TRAINING" band across the bottom of the same mark.

Outputs every Android mipmap density plus the web icons. Run from repo root:
    python tool/make_respondent_icon.py
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "images", "revive_logo.png")

RED = (229, 37, 40, 255)
WHITE = (255, 255, 255, 255)

# Android adaptive-icon safe zone: the outer ~15% can be cropped by the
# launcher mask, so the band sits above the bottom edge.
BAND_TOP = 0.755
BAND_H = 0.155


def _font(size):
    """Best available bold sans; falls back to PIL's bitmap default."""
    for path in (
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def build(size):
    base = Image.open(SRC).convert("RGBA")

    # Trim the white surround so the monogram fills the tile.
    bbox = base.convert("RGB").point(lambda p: 0 if p > 245 else 255).getbbox()
    if bbox:
        base = base.crop(bbox)

    # Square canvas, mark inset from the edge, on white like the source.
    canvas = Image.new("RGBA", (size, size), WHITE)
    inner = int(size * 0.72)
    mark = base.resize((inner, inner), Image.LANCZOS)
    # Push the mark up so the band does not cover its leg.
    canvas.paste(mark, ((size - inner) // 2, int(size * 0.045)), mark)

    draw = ImageDraw.Draw(canvas)
    top = int(size * BAND_TOP)
    height = int(size * BAND_H)
    draw.rectangle([0, top, size, top + height], fill=RED)

    label = "AI TRAINING"
    # Shrink the text until it fits the band with margins.
    for scale in (0.115, 0.105, 0.095, 0.085, 0.075, 0.065):
        font = _font(max(6, int(size * scale)))
        l, t, r, b = draw.textbbox((0, 0), label, font=font)
        if (r - l) <= size * 0.86 and (b - t) <= height * 0.72:
            break
    tw, th = r - l, b - t
    draw.text(
        ((size - tw) / 2 - l, top + (height - th) / 2 - t),
        label,
        font=font,
        fill=WHITE,
    )
    return canvas


def main():
    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for name, px in densities.items():
        out_dir = os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{name}")
        os.makedirs(out_dir, exist_ok=True)
        build(px).save(os.path.join(out_dir, "ic_launcher.png"))
        print("wrote", os.path.join(out_dir, "ic_launcher.png"))

    # Master + Play Store / web sizes.
    assets = os.path.join(ROOT, "assets", "images")
    build(1024).save(os.path.join(assets, "ai_training_icon.png"))
    print("wrote", os.path.join(assets, "ai_training_icon.png"))

    for px in (192, 512):
        build(px).save(os.path.join(ROOT, "web", "icons", f"Icon-{px}.png"))
        print("wrote", os.path.join(ROOT, "web", "icons", f"Icon-{px}.png"))


if __name__ == "__main__":
    main()
