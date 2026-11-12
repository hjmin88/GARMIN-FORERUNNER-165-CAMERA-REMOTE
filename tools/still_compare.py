"""Compare still-photo encodings for the FR165 post-shot preview.

Renders each input photo with every candidate (size, gray levels, dithering)
the way the watch would show it: whole photo letterboxed into a square,
upscaled by an integer factor, centered on a 390 px round screen.
Writes one PNG per photo/candidate plus index.html to compare side by side.

Transfer estimate uses stage-0 measurements: one message carries at most
CHUNK_B64 base64 chars (1.4 KB arrived, 2.1 KB failed) and takes ~1 s.
These are estimates, not measurements of chunked transfer.

Usage: uv run --with pillow python tools/still_compare.py OUT_DIR PHOTO [PHOTO...]
"""

import html
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

SCREEN = 390            # FR165 display diameter in px
INSCRIBED = 276         # largest square inside the round screen
CHUNK_B64 = 1200        # base64 chars per message, below the 1.4 KB that arrived
SEC_PER_CHUNK = 1.0     # stage-0: 1.4 KB round trip 992 ms
DETECT_SEC = 1.5        # assumed: camera saves photo + companion app notices it

# (size, bits per pixel, dither)
CANDIDATES = [
    (96, 4, False),
    (96, 4, True),
    (120, 4, False),
    (120, 4, True),
    (128, 2, True),
    (160, 2, True),
    (192, 1, True),
]


def transfer(size: int, bpp: int) -> tuple[int, int, float]:
    raw = size * size * bpp // 8
    b64 = math.ceil(raw / 3) * 4
    chunks = math.ceil(b64 / CHUNK_B64)
    return raw, chunks, DETECT_SEC + chunks * SEC_PER_CHUNK


def encode(photo: Image.Image, size: int, bpp: int, dither: bool) -> Image.Image:
    """Grayscale, stretch contrast, letterbox to size x size, reduce to 2**bpp grays."""
    gray = ImageOps.autocontrast(photo.convert("L"), cutoff=1)
    fitted = ImageOps.contain(gray, (size, size), Image.Resampling.LANCZOS)
    square = Image.new("L", (size, size), 0)
    square.paste(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))

    levels = 1 << bpp
    palette = []
    for i in range(levels):
        g = i * 255 // (levels - 1)
        palette += [g, g, g]
    pal_img = Image.new("P", (1, 1))
    pal_img.putpalette(palette + [0] * (768 - len(palette)))
    mode = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
    return square.convert("RGB").quantize(palette=pal_img, dither=mode).convert("L")


def watch_mockup(img: Image.Image) -> Image.Image:
    """Nearest-neighbour upscale to the inscribed square on a round black screen.

    The watch has no drawScaledBitmap, but it paints each run as a rectangle while
    decoding, so it can place rectangles at fractional scale (x * 276 / size).
    """
    big = img.resize((INSCRIBED, INSCRIBED), Image.Resampling.NEAREST)
    screen = Image.new("L", (SCREEN, SCREEN), 0)
    screen.paste(big, ((SCREEN - big.width) // 2, (SCREEN - big.height) // 2))
    mask = Image.new("L", (SCREEN, SCREEN), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, SCREEN - 1, SCREEN - 1), fill=255)
    out = Image.new("L", (SCREEN + 20, SCREEN + 20), 40)
    out.paste(screen, (10, 10), mask)
    return out


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    photos = [Path(p) for p in sys.argv[2:]]

    rows = []
    for pi, path in enumerate(photos, 1):
        photo = ImageOps.exif_transpose(Image.open(path))
        cells = []
        for size, bpp, dither in CANDIDATES:
            name = f"p{pi}_{size}_{bpp}b{'_d' if dither else ''}.png"
            watch_mockup(encode(photo, size, bpp, dither)).save(out / name)
            cells.append(name)
        rows.append(cells)

    head = "".join(
        "<th>{}×{} · {}단계{}<br><small>{}B · {}조각 · 약 {:.0f}초</small></th>".format(
            s, s, 1 << b, " · 디더링" if d else "", *transfer(s, b))
        for s, b, d in CANDIDATES)
    body = "".join(
        "<tr><td>사진 {}</td>{}</tr>".format(
            i, "".join(f'<td><img src="{html.escape(c)}" width="205"></td>' for c in cells))
        for i, cells in enumerate(rows, 1))
    (out / "index.html").write_text(f"""<!doctype html><meta charset="utf-8">
<title>Still photo candidates</title>
<style>body{{background:#111;color:#ddd;font:14px sans-serif}}td,th{{padding:4px;text-align:center}}</style>
<p>시계 실제 크기(지름 약 3cm)에 가깝게 보려면 화면에서 떨어져 보세요. 시간은 0단계 실측으로 낸 추정치입니다.</p>
<table><tr><th></th>{head}</tr>{body}</table>""", encoding="utf-8")
    for s, b, d in CANDIDATES:
        raw, chunks, sec = transfer(s, b)
        print(f"{s}x{s} {1 << b:>2} levels dither={d!s:5} raw={raw}B chunks={chunks} est={sec:.1f}s")


if __name__ == "__main__":
    main()
