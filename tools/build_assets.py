"""
Builds the game's image assets from the team's source art.

    python tools/build_assets.py <source folder>

<source folder> must contain:
    character mouvement/IMG_0129.png ... IMG_0132.png  (Vulcan idle + 3 walk frames)
    moon/Moon_Surface.png                               (repeating crater pattern)
    room style/Game map.ai                              (station map, PDF-compatible)

Writes into assets/:
    vulcan_idle.png, vulcan_walk1..3.png  white background removed, cropped, 256 px tall
    moon_tile.png                         one seamless pattern tile, 512 x 512
    room_water.png, room_comms.png, room_air.png
                                          drawn rooms rendered from the .ai at 2x world scale

Needs Pillow and PyMuPDF (pip install pillow pymupdf).
"""
import os
import sys

from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets")
WORLD = 2400            # the .ai artboard (3840 pt) maps to a 2400-unit world
ROOM_SCALE = 2          # room art is rendered at 2x world scale for sharpness

# Rooms whose interiors are drawn in the .ai (world coordinates)
ROOM_ART = {
    "room_water.png": (849, 0, 1622, 673),
    "room_comms.png": (1993, 782, 2400, 1260),
    "room_air.png": (885, 1614, 1580, 1965),
}


def cut_out_white(path):
    """Removes the white background by flood-filling from the image border.
    White areas enclosed by the black outline (the suit) are kept."""
    im = Image.open(path).convert("RGBA")
    marker = (255, 0, 255, 255)
    w, h = im.size
    seeds = [(x, 0) for x in range(0, w, 64)] + [(x, h - 1) for x in range(0, w, 64)] \
        + [(0, y) for y in range(0, h, 64)] + [(w - 1, y) for y in range(0, h, 64)]
    for s in seeds:
        r, g, b, a = im.getpixel(s)
        if r > 230 and g > 230 and b > 230:
            ImageDraw.floodfill(im, s, marker, thresh=60)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == marker:
                px[x, y] = (255, 255, 255, 0)
    im = im.crop(im.getbbox())
    return im


def build_vulcan(src):
    frames = {
        "vulcan_idle.png": "IMG_0129.png",
        "vulcan_walk1.png": "IMG_0130.png",
        "vulcan_walk2.png": "IMG_0131.png",
        "vulcan_walk3.png": "IMG_0132.png",
    }
    cut = {name: cut_out_white(os.path.join(src, "character mouvement", f)) for name, f in frames.items()}
    # One common canvas so frames line up (feet on the bottom edge, centred)
    cw = max(im.width for im in cut.values())
    ch = max(im.height for im in cut.values())
    target_h = 256
    for name, im in cut.items():
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.paste(im, ((cw - im.width) // 2, ch - im.height), im)
        canvas = canvas.resize((round(cw * target_h / ch), target_h), Image.LANCZOS)
        canvas.save(os.path.join(OUT, name))
        print("wrote", name, canvas.size)


def build_moon(src):
    im = Image.open(os.path.join(src, "moon", "Moon_Surface.png")).convert("RGB")
    period = find_period(im)
    tile = im.crop((0, 0, period, period)).resize((512, 512), Image.LANCZOS)
    tile.save(os.path.join(OUT, "moon_tile.png"))
    print("wrote moon_tile.png (pattern period", period, "px)")


def find_period(im):
    """The crater pattern repeats; find the horizontal repeat length by
    comparing a strip of the image with shifted copies of itself."""
    small_scale = 8
    sm = im.resize((im.width // small_scale, im.height // small_scale)).convert("L")
    row = [sm.getpixel((x, y)) for y in range(0, 60) for x in range(0, 300)]
    best, best_err = None, None
    for p in range(60, 250):
        err = 0
        for y in range(0, 60, 3):
            for x in range(0, 300 - p if 300 - p < 300 else 0, 3):
                err += abs(sm.getpixel((x, y)) - sm.getpixel((x + p, y)))
        if best_err is None or err < best_err:
            best, best_err = p, err
    return best * small_scale


def build_rooms(src):
    import fitz
    doc = fitz.open(os.path.join(src, "room style", "Game map.ai"))
    page = doc[0]
    zoom = WORLD * ROOM_SCALE / page.rect.width
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom))
    full = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    for name, (x0, y0, x1, y1) in ROOM_ART.items():
        box = tuple(v * ROOM_SCALE for v in (x0, y0, x1, y1))
        full.crop(box).save(os.path.join(OUT, name))
        print("wrote", name, full.crop(box).size)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    os.makedirs(OUT, exist_ok=True)
    source = sys.argv[1]
    build_vulcan(source)
    build_moon(source)
    build_rooms(source)
