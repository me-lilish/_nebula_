"""
Builds the mini-game sprites from the team's puzzle art.

    python tools/build_minigames.py "C:/Users/<you>/Desktop/puzzels"

Same treatment as tools/build_props.py (background removed, thick ink
outline, cropped). Art painted on a light / checkerboard background is cut
out with a light flood fill instead of a black one.
Writes assets/minigames/<name>.png.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props as bp  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "minigames")
MAX_SIDE = 360

# name -> (file, background: "auto" | "light")
ART = {
    "space_sheep": ("0056dee6-5126-4014-855e-201900ddf346.png", "auto"),
    "crater_fence": ("10a81d03-0bed-4631-b8bc-311098fadbb6.png", "auto"),
    "sponge": ("19b1b6ba-7566-4c03-b4b2-22fa5175c1be.png", "auto"),
    "zzz": ("687f496a-0ca3-48a3-921d-38aa3242c6c6.png", "auto"),
    "fogged_mirror": ("7270c1fa-8ea0-4264-9584-9682fcf02089.png", "auto"),
    "oven": ("7b2f0f6f-60fc-4c9a-944a-f2746358934e.png", "auto"),
    "ration_burnt": ("84a0b552-61a7-43ed-ba84-0430a11874ac.png", "auto"),
    "filter_housing": ("Boitier_filtrant_futuriste_ouvert.png", "auto"),
    "mag_brush": ("Brosse_magnetique_futuriste_neon.png", "auto"),
    "dust_clump": ("Eclats_lunaires_et_energie_cyan.png", "auto"),
    "hepa_clean": ("Filtre_HEPA_cylindrique_bleu_argente.png", "auto"),
    "hepa_dirty": ("Filtre_HEPA_encrasse_sur_fond_noir.png", "auto"),
    "valve_wheel": ("asd.jpg", "auto"),
    "pipette": ("dfghjk.jpg", "auto"),
    "dust_processor": ("drftyhujik.jpg", "auto"),
    "ration_cooked": ("e9f5bbe9-1549-42c7-b834-e5644e7d3886.png", "auto"),
    "ration_raw": ("fbbe2029-37ee-44ff-8074-a405cecf7088.png", "auto"),
    "seed_pod": ("fghjk.jpg", "auto"),
    "pipe_straight": ("image0.jpg", "light"),
    "pipe_tee": ("imassge0.jpg", "auto"),
    "pressure_gauge": ("sadf.jpg", "auto"),
    "shears": ("sedrtyhu.jpg", "auto"),
    "crop_plant": ("tyui.jpg", "auto"),
    "basket": ("tyuty7.jpg", "auto"),
}


def light_background_mask(rgb):
    """255 where the pixel is part of a light / checkerboard background."""
    w, h = rgb.size
    work = rgb.copy()
    marker = (255, 0, 255)
    for s in [(x, 0) for x in range(0, w, 12)] + [(x, h - 1) for x in range(0, w, 12)] \
            + [(0, y) for y in range(0, h, 12)] + [(w - 1, y) for y in range(0, h, 12)]:
        if min(work.getpixel(s)) >= 180:
            ImageDraw.floodfill(work, s, marker, thresh=180)
    r, g, b = work.split()
    mask = Image.eval(r, lambda v: 255 if v == 255 else 0)
    mask = ImageChops.multiply(mask, Image.eval(g, lambda v: 255 if v == 0 else 0))
    mask = ImageChops.multiply(mask, Image.eval(b, lambda v: 255 if v == 255 else 0))
    return mask


def build(src, name, file, mode):
    im = Image.open(os.path.join(src, file))
    if mode == "light":
        rgb = im.convert("RGB")
        im = rgb.convert("RGBA")
        im.putalpha(ImageChops.invert(light_background_mask(rgb)))
    elif bp.has_real_alpha(im):
        im = im.convert("RGBA")
    else:
        rgb = im.convert("RGB")
        im = rgb.convert("RGBA")
        im.putalpha(ImageChops.invert(bp.black_background_mask(rgb)))
    a = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MedianFilter(5))
    bbox = a.getbbox()
    pad = 24
    im = im.crop((bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad))
    im = bp.add_outline(im, 8)
    im = im.crop(im.getchannel("A").getbbox())
    s = MAX_SIDE / max(im.size)
    if s < 1:
        im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))), Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"))
    return im.size


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[2:])
    sizes = {}
    for name, (file, mode) in ART.items():
        if only and name not in only:
            continue
        sizes[name] = build(sys.argv[1], name, file, mode)
        print(f"{name:16s} {sizes[name][0]}x{sizes[name][1]}")


if __name__ == "__main__":
    main()
