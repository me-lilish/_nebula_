"""
Builds the room furniture / machine sprites from the team's prop art.

    python tools/build_props.py "C:/Users/<you>/Downloads/game"

Every prop is cut out, given a thick black ink outline (cel-shaded comic
style), cropped and scaled so its longest side is MAX_SIDE pixels.
Writes assets/props/<name>.png.

Props painted on a black background are cut out by flood-filling the
near-black border region, then "opening" that mask so the thin black ink
lines inside the drawing (which touch the background) are kept.

Needs Pillow (pip install pillow).
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "props")
MAX_SIDE = 440
INK = (16, 14, 30, 255)

# output name -> (source file, optional crop box as fractions x0, y0, x1, y1)
PROPS = {
    "door_slide": ("0971408e-4c57-4b8a-b59c-cee68d58f179.png", None),
    "breaker": ("0aa30586-39eb-4aa8-8ef7-c5f757bdc229.png", None),
    "wall_window": ("0c258793-34bc-4104-9692-21271fe8133a.png", None),
    "vault_door": ("0d5c6b15-6ba5-49db-92be-853343cdee2f.png", None),
    "geiger": ("1e7f13e5-408f-487a-aa97-b701db803377.png", None),
    "power_console": ("2039464b-7941-4ae3-9480-ac97106a91ee.png", None),
    "regolith_hopper": ("2356a55e-31fa-46f5-ac02-b4c183122d1e.png", None),
    "chute": ("2aa6da96-539d-411c-b240-697e4d1aa9e4.png", None),
    "battery_rack": ("7c9ba8ec-2e41-4608-8aef-4f619624e1ee.png", None),
    "rubber_mat": ("88f91b52-1b12-4a7c-a2fe-1b8e7ef06d34.png", None),
    "reactor": ("8dd96a03-6f4e-403f-90a7-544f82ba7bf6.png", None),
    "eng_desk": ("911181eb-9ca6-481d-b76e-25134d15da5a.png", None),
    "hv_sign": ("974877b6-322f-455e-b2eb-64b845171cb6.png", None),
    "amber_beacon": ("Amber Warning Beacon and Vent Duct.png", None),
    "biohazard": ("Bold Biohazard Waste Barrels.png", None),
    "co2_scrubber": ("Cartoon Sci-Fi Air Purifier Unit.png", None),
    "air_filter": ("Cel-Shaded Industrial Air Filtration Unit.png", None),
    "ladder": ("Cel-Shaded Maintenance Ladder and Vent.png", None),
    "o2_masks": ("Emergency Oxygen Masks Cabinet.png", None),
    "workstation": ("Futuristic Blue Sci-Fi Workstation.png", None),
    "ration_crates": ("Futuristic Blue-Accented Food Ration Crates.png", None),
    "bunk": ("Futuristic Bunk Bed in Space.png", None),
    "composter": ("Futuristic Composting Machine.png", None),
    "filter_crate": ("Futuristic Filter Cartridge Supply Crate.png", None),
    "fold_table": ("Futuristic Fold-Down Space Station Table.png", None),
    "food_lockers": ("Futuristic Food Storage Lockers.png", None),
    "hydroponics": ("Futuristic Hydroponic Garden Module.png", None),
    "freezer": ("Futuristic Industrial Freezer Unit.png", None),
    "vent_hood": ("Futuristic Industrial Kitchen Ventilation Hood.png", None),
    "bench": ("Futuristic Industrial Metal Bench.png", None),
    "prep_counter": ("Futuristic Kitchen Prep Station.png", None),
    "lockers": ("Futuristic Lockers and Gear Rack.png", (0.0, 0.0, 0.62, 1.0)),
    "gear_hooks": ("Futuristic Lockers and Gear Rack.png", (0.62, 0.0, 1.0, 1.0)),
    "first_aid": ("Futuristic Medical Bay Equipment.png", (0.0, 0.0, 0.5, 1.0)),
    "vitals_monitor": ("Futuristic Medical Bay Equipment.png", (0.53, 0.0, 1.0, 1.0)),
    "o2_generator": ("Futuristic Oxygen Generator Droid.png", None),
    "restroom": ("Futuristic Sci-Fi Restroom Pod.png", None),
    "food_dispenser": ("Futuristic Space Food Dispenser.png", None),
    "temp_panel": ("Futuristic Temperature Control Panel.png", None),
    "clipboard": ("Futuristic Wall-Mounted Data Clipboard.png", None),
    "sink": ("Futuristic Wall-Mounted Sink Station.png", None),
    "brush_station": ("Industrial Cleaning Rack and Floor Mat.png", None),
    "gas_rack": ("Industrial Gas Cylinder Rack.png", None),
    "shredder": ("Industrial Recycling Shredder Machine.png", None),
    "jug_rack": ("Industrial Water Jug Storage Rack.png", None),
    "salvage_bench": ("Industrial Workshop Workbench Scene.png", None),
    "pipes": ("Sci-Fi Parallel Pipe Assembly.png", None),
    "pressure_panel": ("Sci-Fi Pressure Control Panel.png", None),
    "purifier": ("Sci-Fi Water Purifier and Storage Tank Icons.png", (0.0, 0.0, 0.5, 1.0)),
    "water_tank": ("Sci-Fi Water Purifier and Storage Tank Icons.png", (0.5, 0.0, 1.0, 1.0)),
    "plumbing_bench": ("Stylised Industrial Mechanic Workbench.png", None),
    "holo_table": ("c92353cf-2a7f-4c64-b5da-692f0d281db0.png", None),
    "siren": ("e711a477-9592-430b-8202-6057c29526c1.png", None),
}


def black_background_mask(rgb):
    """255 where the pixel belongs to the black background."""
    w, h = rgb.size
    work = rgb.copy()
    marker = (255, 0, 255)
    step = 16
    seeds = [(x, 0) for x in range(0, w, step)] + [(x, h - 1) for x in range(0, w, step)] \
        + [(0, y) for y in range(0, h, step)] + [(w - 1, y) for y in range(0, h, step)]
    for s in seeds:
        if max(work.getpixel(s)) <= 14:
            ImageDraw.floodfill(work, s, marker, thresh=24)
    r, g, b = work.split()
    mask = Image.eval(r, lambda v: 255 if v == 255 else 0)
    mask = ImageChops.multiply(mask, Image.eval(g, lambda v: 255 if v == 0 else 0))
    mask = ImageChops.multiply(mask, Image.eval(b, lambda v: 255 if v == 255 else 0))
    # opening: thin ink lines reached through the outline go back to the drawing
    k = 17
    mask = mask.filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))
    return mask


def has_real_alpha(im):
    if im.mode != "RGBA":
        return False
    lo, _ = im.getchannel("A").getextrema()
    return lo < 250


def add_outline(im, width):
    """Thick ink outline around the opaque shape."""
    a = im.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", im.size, INK)
    out.putalpha(grown)
    out.alpha_composite(im)
    return out


def build(src_dir, name, file, box):
    im = Image.open(os.path.join(src_dir, file))
    if box:
        w, h = im.size
        im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
    if has_real_alpha(im):
        im = im.convert("RGBA")
    else:
        rgb = im.convert("RGB")
        bg = black_background_mask(rgb)
        im = rgb.convert("RGBA")
        im.putalpha(ImageChops.invert(bg))
    # drop specks, then crop with a margin for the outline
    a = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MedianFilter(5))
    bbox = a.getbbox()
    pad = 24
    im = im.crop((bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad))
    im = add_outline(im, 9)
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
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[2:])
    for name, (file, box) in PROPS.items():
        if only and name not in only:
            continue
        size = build(src, name, file, box)
        print(f"{name:16s} {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
