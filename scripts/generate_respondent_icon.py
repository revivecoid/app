"""Generate the respondent app launcher icon: Re-V logo + "AI training" caption.

Writes every density for Android and the iOS AppIcon set. The source logo has a
transparent background, so it is composited onto the app's dark surface colour
to avoid a white halo on launchers that do not honour alpha.
"""
from PIL import Image, ImageDraw, ImageFont
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "assets", "images", "revive_logo.png")

# Dark surface matching the app; keeps the logo legible on any wallpaper.
BG = (18, 18, 20, 255)
ACCENT = (229, 57, 53, 255)  # AppColors.fireRed

ANDROID_SIZES = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
}
IOS_SIZES = {  # filename -> px (1x values; @2x/@3x handled below)
    "Icon-App-20x20@1x": 20, "Icon-App-20x20@2x": 40, "Icon-App-20x20@3x": 60,
    "Icon-App-29x29@1x": 29, "Icon-App-29x29@2x": 58, "Icon-App-29x29@3x": 87,
    "Icon-App-40x40@1x": 40, "Icon-App-40x40@2x": 80, "Icon-App-40x40@3x": 120,
    "Icon-App-60x60@2x": 120, "Icon-App-60x60@3x": 180,
    "Icon-App-76x76@1x": 76, "Icon-App-76x76@2x": 152,
    "Icon-App-83.5x83.5@2x": 167, "Icon-App-1024x1024@1x": 1024,
}


def _font(px):
    """Largest available sans font; falls back to PIL's bitmap default."""
    for name in ("DejaVuSans-Bold.ttf", "arialbd.ttf", "Arial Bold.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, px)
        except OSError:
            continue
    return ImageFont.load_default()


def build(size: int) -> Image.Image:
    # Render at 4x then downscale: the caption must stay crisp at 48px.
    s = size * 4
    img = Image.new("RGBA", (s, s), BG)
    d = ImageDraw.Draw(img)

    logo = Image.open(LOGO).convert("RGBA")

    # Below ~72px the caption compresses into an unreadable smudge, so the small
    # densities carry the logo alone, sized up to fill the space it frees.
    show_caption = size >= 72
    logo_px = int(s * (0.60 if show_caption else 0.78))
    logo = logo.resize((logo_px, logo_px), Image.LANCZOS)

    if not show_caption:
        img.alpha_composite(logo, ((s - logo_px) // 2, (s - logo_px) // 2))
        return img.resize((size, size), Image.LANCZOS)

    text_px = max(8, int(s * 0.155))
    font = _font(text_px)
    caption = "AI training"
    box = d.textbbox((0, 0), caption, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]

    # Stack logo above caption, the pair vertically centred.
    gap = int(s * 0.045)
    total = logo_px + gap + th
    top = (s - total) // 2
    img.alpha_composite(logo, ((s - logo_px) // 2, top))

    cx, ty = (s - tw) // 2 - box[0], top + logo_px + gap - box[1]
    d.text((cx, ty), caption, font=font, fill=ACCENT)

    return img.resize((size, size), Image.LANCZOS)


def main():
    written = []

    for density, px in ANDROID_SIZES.items():
        path = os.path.join(
            ROOT, "android", "app", "src", "main", "res",
            f"mipmap-{density}", "ic_launcher.png",
        )
        build(px).save(path)
        written.append(path)

    ios_dir = os.path.join(
        ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    if os.path.isdir(ios_dir):
        for name, px in IOS_SIZES.items():
            path = os.path.join(ios_dir, f"{name}.png")
            if os.path.exists(path):
                # iOS icons must be fully opaque, no alpha channel.
                build(px).convert("RGB").save(path)
                written.append(path)

    print(f"wrote {len(written)} icons")
    for p in written[:5]:
        print(" ", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
