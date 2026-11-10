from PIL import Image

im = Image.open(
    r"c:\Users\danza\hrms_plaridel\frontend\assets\images\memo_official_letterhead.png"
).convert("RGB")
w, h = im.size
px = im.load()

def ink(x0, y0, x1, y1, thresh=245):
    x0 = max(0, int(x0 * w))
    x1 = min(w, int(x1 * w))
    y0 = max(0, int(y0 * h))
    y1 = min(h, int(y1 * h))
    dark = 0
    total = 0
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            r, g, b = px[x, y]
            total += 1
            if r < thresh or g < thresh or b < thresh:
                dark += 1
    return dark, total, (dark / total if total else 0)

regions = {
    "header_art": (0.0, 0.0, 1.0, 0.16),
    "title_MEMORANDUM": (0.11, 0.215, 0.89, 0.255),
    "metadata_to_date": (0.11, 0.262, 0.89, 0.48),
    "body_band": (0.11, 0.34, 0.89, 0.49),
    "prepared_by": (0.13, 0.523, 0.43, 0.608),
    "noted_by": (0.56, 0.523, 0.88, 0.608),
    "release": (0.56, 0.40, 0.89, 0.50),
    "approved_by": (0.50, 0.628, 0.88, 0.713),
    "cc": (0.11, 0.70, 0.49, 0.78),
    "footer_art": (0.0, 0.85, 1.0, 1.0),
}
print("image", w, h)
for name, rect in regions.items():
    dark, total, ratio = ink(*rect)
    print(f"{name:22} dark={dark:6} sampled={total:6} ratio={ratio:.4f}")
