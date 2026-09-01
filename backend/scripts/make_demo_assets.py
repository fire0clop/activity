"""Картинки для витринных данных: обложки событий и аватары организаторов.

Запускается на машине разработчика (нужны системные шрифты), результат
коммитится в репозиторий — на сервере рисовать нечем.

    python3 scripts/make_demo_assets.py
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = pathlib.Path(__file__).parent / "demo_assets"
W, H, K = 1400, 900, 4

SCENES = {
    "run":     ((252, 186, 108), (176, 52, 66)),
    "tennis":  ((136, 204, 154), (18, 74, 88)),
    "board":   ((240, 154, 100), (82, 38, 88)),
    "coffee":  ((234, 184, 140), (94, 50, 40)),
    "photo":   ((180, 176, 222), (40, 36, 84)),
    "volley":  ((250, 206, 118), (198, 82, 54)),
    "concert": ((238, 112, 138), (44, 24, 80)),
    "bike":    ((154, 208, 214), (22, 68, 104)),
    "quiz":    ((242, 164, 124), (66, 30, 62)),
}


def gradient(c1, c2, size):
    img = Image.new("RGB", size)
    px = img.load()
    step = 8
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            t = min(1.0, x / size[0] * 0.55 + y / size[1] * 0.45)
            c = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
            for dy in range(step):
                for dx in range(step):
                    if x + dx < size[0] and y + dy < size[1]:
                        px[x + dx, y + dy] = c
    return img


def motif(name, d, c):
    cx, cy = W * K * 0.62, H * K * 0.56

    def circle(x, y, r, fill=None, width=0):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill,
                  outline=None if fill else c, width=width)

    if name == "run":
        circle(cx, cy - 90 * K, 150 * K, fill=c)
        for off in (0, 90, 180):
            y = cy + (110 + off) * K
            d.arc([cx - (420 + off) * K, y - 90 * K, cx + (420 + off) * K, y + 90 * K],
                  185, 355, fill=c, width=15 * K)
    elif name == "tennis":
        d.ellipse([cx - 150 * K, cy - 230 * K, cx + 150 * K, cy + 130 * K],
                  outline=c, width=22 * K)
        for gx in range(-100, 101, 50):
            d.line([(cx + gx * K, cy - 218 * K), (cx + gx * K, cy + 118 * K)],
                   fill=(255, 246, 232, 60), width=6 * K)
        for gy in range(-180, 91, 54):
            d.line([(cx - 138 * K, cy + gy * K), (cx + 138 * K, cy + gy * K)],
                   fill=(255, 246, 232, 60), width=6 * K)
        d.line([(cx, cy + 130 * K), (cx, cy + 300 * K)], fill=c, width=26 * K)
        circle(cx + 250 * K, cy + 180 * K, 62 * K, fill=c)
    elif name == "board":
        for i, (dx, dy, a) in enumerate(((-190, 40, -12), (60, -30, 8), (240, 90, -6))):
            s = 150 * K
            die = Image.new("RGBA", (int(s * 1.5), int(s * 1.5)), (0, 0, 0, 0))
            dd = ImageDraw.Draw(die)
            dd.rounded_rectangle([0, 0, s, s], s * 0.18, fill=c)
            for px_, py_ in ((0.3, 0.3), (0.7, 0.7), (0.5, 0.5))[: i + 1]:
                dd.ellipse([s * px_ - s * 0.07, s * py_ - s * 0.07,
                            s * px_ + s * 0.07, s * py_ + s * 0.07],
                           fill=(255, 246, 232, 150))
            die = die.rotate(a, resample=Image.BICUBIC, expand=False)
            d._image.alpha_composite(die, (int(cx + dx * K - s * 0.75),
                                           int(cy + dy * K - s * 0.75)))
    elif name == "coffee":
        circle(cx, cy, 200 * K, width=14 * K)
        circle(cx, cy, 140 * K, fill=c)
        circle(cx, cy, 92 * K, fill=(255, 246, 232, 90))
        d.rounded_rectangle([cx + 200 * K, cy - 34 * K, cx + 300 * K, cy + 34 * K],
                            34 * K, outline=c, width=14 * K)
    elif name == "photo":
        d.rounded_rectangle([cx - 250 * K, cy - 150 * K, cx + 250 * K, cy + 160 * K],
                            36 * K, fill=c)
        circle(cx, cy + 10 * K, 110 * K, fill=(255, 246, 232, 110))
        circle(cx, cy + 10 * K, 62 * K, fill=c)
        d.rounded_rectangle([cx - 210 * K, cy - 200 * K, cx - 90 * K, cy - 140 * K],
                            18 * K, fill=c)
    elif name == "volley":
        R = 180 * K
        circle(cx, cy, R, fill=c)
        band = Image.new("RGBA", d._image.size, (0, 0, 0, 0))
        bd = ImageDraw.Draw(band, "RGBA")
        for ox, oy, rr in ((-330, -60, 330), (140, -320, 330), (120, 300, 330)):
            bd.ellipse([cx + ox * K - rr * K, cy + oy * K - rr * K,
                        cx + ox * K + rr * K, cy + oy * K + rr * K],
                       outline=(255, 246, 232, 130), width=18 * K)
        mask = Image.new("L", d._image.size, 0)
        ImageDraw.Draw(mask).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
        band.putalpha(ImageChops.multiply(band.split()[3], mask))
        d._image.alpha_composite(band)
    elif name == "concert":
        import math
        for a in (-42, -18, 8, 34):
            r = math.radians(a - 90)
            d.polygon([(cx, cy - 260 * K),
                       (cx + math.cos(r) * 700 * K - 40 * K,
                        cy - 260 * K + math.sin(r) * -700 * K),
                       (cx + math.cos(r) * 700 * K + 40 * K,
                        cy - 260 * K + math.sin(r) * -700 * K)],
                      fill=(255, 246, 232, 40))
        circle(cx, cy - 260 * K, 46 * K, fill=c)
        for i in range(7):
            circle(cx - 300 * K + i * 100 * K, cy + 250 * K, 40 * K, fill=c)
    elif name == "bike":
        for dx in (-210, 210):
            circle(cx + dx * K, cy + 40 * K, 150 * K, width=16 * K)
        d.line([(cx - 210 * K, cy + 40 * K), (cx - 40 * K, cy - 110 * K),
                (cx + 210 * K, cy + 40 * K), (cx - 60 * K, cy + 40 * K),
                (cx - 40 * K, cy - 110 * K)], fill=c, width=16 * K, joint="curve")
    elif name == "quiz":
        d.rounded_rectangle([cx - 260 * K, cy - 190 * K, cx + 120 * K, cy + 60 * K],
                            48 * K, fill=c)
        d.polygon([(cx - 180 * K, cy + 55 * K), (cx - 120 * K, cy + 55 * K),
                   (cx - 170 * K, cy + 150 * K)], fill=c)
        d.rounded_rectangle([cx - 60 * K, cy + 20 * K, cx + 280 * K, cy + 230 * K],
                            44 * K, fill=(255, 246, 232, 70))


def cover(name, c1, c2):
    base = gradient(c1, c2, (W * K, H * K)).convert("RGBA")
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    d._image = layer
    motif(name, d, (255, 246, 232, 88))
    base.alpha_composite(layer)
    img = base.convert("RGB").resize((W, H), Image.LANCZOS)

    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse([-380, -420, 760, 480], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(260)).point(lambda v: int(v * 0.30))
    img = Image.composite(Image.new("RGB", (W, H), (255, 248, 236)), img, m)
    n = Image.effect_noise((W, H), 9).convert("L")
    img = Image.blend(img, ImageChops.overlay(img, Image.merge("RGB", (n,) * 3)), 0.45)
    img.save(OUT / f"cover_{name}.jpg", quality=92)


def avatar(idx, letter, c1, c2):
    S = 600
    img = gradient(c1, c2, (S, S))
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 300)
    ImageDraw.Draw(img).text((S / 2, S / 2 - 18), letter, font=font,
                             fill=(255, 250, 242), anchor="mm")
    img.save(OUT / f"avatar_{idx}.jpg", quality=92)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for n, (a, b) in SCENES.items():
        cover(n, a, b)
    for i, (ch, a, b) in enumerate([("А", (246, 178, 122), (198, 84, 74)),
                                    ("М", (150, 196, 210), (44, 84, 118)),
                                    ("Л", (204, 172, 214), (98, 60, 122)),
                                    ("Т", (176, 206, 166), (56, 96, 76))]):
        avatar(i, ch, a, b)
    print("готово:", len(list(OUT.glob("*.jpg"))), "файлов в", OUT)
