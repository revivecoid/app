"""Build the respondent app's launcher icon and in-app logo.

Source assets/images/revive_logo.png is an opaque white-background PNG, so the
background is flood-filled from the four edges (not a global white mask, which
would also punch holes in the light parts inside the mark).

Outputs:
  android/app/src/main/res/mipmap-*/ic_launcher.png      legacy launcher icon
  android/app/src/main/res/mipmap-anydpi-v26/...         adaptive icon (fg+bg)
  assets/images/respondent_logo.png                      in-app header logo
"""

from collections import deque
import os

from PIL import Image, ImageDraw, ImageFont

SRC = "assets/images/revive_logo.png"
RES = "android/app/src/main/res"
WHITE_CUTOFF = 238          # near-white counts as background for the flood fill
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
# Adaptive icons: 108dp canvas, everything inside the middle 72dp circle is
# guaranteed visible. The wordmark therefore stays within that safe zone.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def strip_white_background(img: Image.Image) -> Image.Image:
    """Flood-fill near-white from the border inward, leaving interior white."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r >= WHITE_CUTOFF and g >= WHITE_CUTOFF and b >= WHITE_CUTOFF

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and not seen[y * w + x]:
                seen[y * w + x] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (255, 255, 255, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and is_bg(nx, ny):
                seen[ny * w + nx] = 1
                q.append((nx, ny))
    return img


def trim(img: Image.Image) -> Image.Image:
    box = img.getbbox()
    return img.crop(box) if box else img


def load_font(size: int):
    for path in (
        "C:/Windows/Fonts/seguisb.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def build_icon(mark: Image.Image, size: int, adaptive: bool, label: bool = True) -> Image.Image:
    """Card background + centred mark, optionally with the AI TRAINING wordmark."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    radius = int(size * (0.22 if not adaptive else 0.0))
    d.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=radius,
        fill=(237, 34, 40, 255),
    )

    # Same two-tone diagonal sheen the customer icon uses. Painted on its own
    # layer and masked to the card, otherwise it spills past the rounded
    # corners on the top-right and bottom-left.
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon(
        [(size, 0), (size, size), (0, size)],
        fill=(196, 21, 27, 255),
    )
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=255
    )
    canvas.alpha_composite(Image.composite(sheen, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask))

    # Mark: white on red. Leave room at the bottom for the wordmark.
    target_w = size * (0.42 if adaptive else 0.50)
    if not label:
        # Customer icon: mark only, so it can sit larger and centred.
        target_w = size * (0.58 if adaptive else 0.68)
    ratio = target_w / mark.width
    mw, mh = int(mark.width * ratio), int(mark.height * ratio)
    m = mark.resize((mw, mh), Image.LANCZOS)
    m = m.convert("RGBA")
    solid = Image.new("RGBA", m.size, (255, 255, 255, 255))
    solid.putalpha(m.getchannel("A"))

    f1 = load_font(int(size * (0.15 if not adaptive else 0.13)))
    f2 = load_font(int(size * (0.095 if not adaptive else 0.085)))

    # Lay out mark + two text lines as one block, then centre it vertically.
    # The mark is 384x447 (taller than wide), so its height must come from the
    # scaled ratio, not from the target width - that is what pushed the text
    # off the bottom edge before.
    gap = size * 0.02
    b1 = d.textbbox((0, 0), "AI", font=f1)
    b2 = d.textbbox((0, 0), "TRAINING", font=f2)
    h1, h2 = b1[3] - b1[1], b2[3] - b2[1]
    if label:
        block_h = mh + gap + h1 + gap * 0.4 + h2
    else:
        block_h = mh
    top = (size - block_h) / 2

    mx = (size - mw) // 2
    canvas.alpha_composite(solid, (mx, int(top)))

    if not label:
        return canvas

    y = top + mh + gap
    for text, font, box, th in (("AI", f1, b1, h1), ("TRAINING", f2, b2, h2)):
        tw = box[2] - box[0]
        d.text(
            ((size - tw) / 2 - box[0], y - box[1]),
            text,
            font=font,
            fill=(255, 255, 255, 255),
        )
        y += th + gap * 0.4
    return canvas


def write_flavor(name: str, mark: Image.Image, label: bool) -> None:
    """Write one flavor's icon set.

    Flavor resource dirs (src/<flavor>/res) override src/main/res for that
    flavor only. Writing both apps into src/main/res made the customer app
    inherit the AI Learning artwork, because AGP merges main into every
    flavor and the adaptive-icon XML wins over the legacy PNG.
    """
    base = f"android/app/src/{name}/res"
    for density, size in DENSITIES.items():
        out_dir = f"{base}/mipmap-{density}"
        os.makedirs(out_dir, exist_ok=True)
        build_icon(mark, size, adaptive=False, label=label).save(
            f"{out_dir}/ic_launcher.png"
        )

    a26 = f"{base}/mipmap-anydpi-v26"
    os.makedirs(a26, exist_ok=True)
    for density, size in ADAPTIVE.items():
        out_dir = f"{base}/mipmap-{density}"
        os.makedirs(out_dir, exist_ok=True)
        build_icon(mark, size, adaptive=True, label=label).save(
            f"{out_dir}/ic_launcher_foreground.png"
        )
        Image.new("RGBA", (size, size), (237, 34, 40, 255)).save(
            f"{out_dir}/ic_launcher_background.png"
        )

    with open(f"{a26}/ic_launcher.xml", "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            "</adaptive-icon>\n"
        )
    print(f"wrote {base}/ (label={label})")


def main() -> None:
    original = Image.open(SRC).convert("RGBA")
    mark = trim(strip_white_background(original))
    print(f"mark trimmed to {mark.size}")

    # In-app logo: keep the mark, drop the white plate.
    mark.resize((512, int(512 * mark.height / mark.width)), Image.LANCZOS).save(
        "assets/images/respondent_logo.png"
    )

    # Customer app: Re-V mark only. Respondent app: mark + AI TRAINING.
    write_flavor("customer", mark, label=False)
    write_flavor("respondent", mark, label=True)


if __name__ == "__main__":
    main()
