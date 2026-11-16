#!/usr/bin/env python3
"""Draws Panda's app icon and the browser-extension icons.

The geometry mirrors Sources/Panda/PandaView.swift (a 100 x 100 design space), so the icon
and the in-app mascot are the same character. Run from the repository root:

    python3 Scripts/make_icon.py

Needs Pillow. The generated PNGs are committed, so the normal build does not need Python.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

INK = (22, 22, 22, 255)
WHITE = (255, 255, 255, 255)
CREAM = (232, 232, 230, 255)
CREAM_DEEP = (206, 206, 203, 255)
BLUSH = (204, 204, 204, 205)


def ellipse_points(cx, cy, w, h, angle=0.0, steps=120):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = (w / 2) * math.cos(t)
        y = (h / 2) * math.sin(t)
        xr = x * math.cos(angle) - y * math.sin(angle)
        yr = x * math.sin(angle) + y * math.cos(angle)
        pts.append((cx + xr, cy + yr))
    return pts


def capsule_points(cx, cy, w, h, angle):
    r = w / 2
    pts = []
    for i in range(0, 181, 6):
        t = math.radians(180 + i)
        pts.append((r * math.cos(t), -h / 2 + r + r * math.sin(t)))
    for i in range(0, 181, 6):
        t = math.radians(i)
        pts.append((r * math.cos(t), h / 2 - r + r * math.sin(t)))
    out = []
    for x, y in pts:
        out.append((cx + x * math.cos(angle) - y * math.sin(angle), cy + x * math.sin(angle) + y * math.cos(angle)))
    return out


def quad(p0, c, p1, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
        pts.append((x, y))
    return pts


class Pen:
    def __init__(self, draw, scale, ox, oy):
        self.d, self.s, self.ox, self.oy = draw, scale, ox, oy

    def tr(self, pts):
        return [(self.ox + x * self.s, self.oy + y * self.s) for x, y in pts]

    def fill(self, pts, color):
        self.d.polygon(self.tr(pts), fill=color)

    def outline(self, pts, color, width):
        p = self.tr(pts)
        self.d.line(p + [p[0], p[1]], fill=color, width=max(1, round(width * self.s)), joint="curve")

    def stroke(self, pts, color, width):
        p = self.tr(pts)
        w = max(1, round(width * self.s))
        self.d.line(p, fill=color, width=w, joint="curve")
        r = w / 2
        for x, y in (p[0], p[-1]):
            self.d.ellipse((x - r, y - r, x + r, y + r), fill=color)


def draw_panda(pen, face_only=False):
    if not face_only:
        pen.fill(ellipse_points(35, 90, 21, 13), INK)
        pen.fill(ellipse_points(65, 90, 21, 13), INK)
        body = ellipse_points(50, 76, 52, 38)
        pen.fill(body, WHITE)
        pen.outline(body, INK, 2.2)
        pen.fill(ellipse_points(50, 80, 26, 20), (228, 228, 226, 255))
        pen.fill(capsule_points(27, 75, 12, 24, 0.32), INK)
        pen.fill(capsule_points(73, 75, 12, 24, -0.32), INK)

    pen.fill(ellipse_points(25, 19, 25, 25), INK)
    pen.fill(ellipse_points(75, 19, 25, 25), INK)
    head = ellipse_points(50, 43, 78, 66)
    pen.fill(head, WHITE)
    pen.outline(head, INK, 2.2)
    pen.fill(ellipse_points(34, 44, 20, 25, 0.38), INK)
    pen.fill(ellipse_points(66, 44, 20, 25, -0.38), INK)
    pen.fill(ellipse_points(21, 57, 10, 5.5), BLUSH)
    pen.fill(ellipse_points(79, 57, 10, 5.5), BLUSH)
    pen.fill(ellipse_points(35, 44, 9.5, 9.5), WHITE)
    pen.fill(ellipse_points(65, 44, 9.5, 9.5), WHITE)
    pen.fill(ellipse_points(35.8, 44.6, 5, 5), INK)
    pen.fill(ellipse_points(64.2, 44.6, 5, 5), INK)
    pen.fill(ellipse_points(37, 43.2, 1.8, 1.8), WHITE)
    pen.fill(ellipse_points(65.4, 43.2, 1.8, 1.8), WHITE)
    pen.fill(ellipse_points(50, 54.5, 8.5, 5.5), INK)
    pen.stroke(quad((45, 60), (50, 69), (55, 60)), INK, 1.9)


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def app_icon(size=1024):
    ss = 4
    big = size * ss
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    # macOS icon grid: the rounded square sits inside a margin.
    margin = int(big * 0.098)
    plate_size = big - 2 * margin
    plate = Image.new("RGBA", (plate_size, plate_size), CREAM)
    pd = ImageDraw.Draw(plate)
    # Soft bamboo-free, two-tone cream backdrop
    pd.ellipse((-plate_size * 0.2, plate_size * 0.62, plate_size * 1.2, plate_size * 1.5), fill=CREAM_DEEP)
    # Film grain, so the plate reads as a matte material
    import random
    rng = random.Random(7)
    grain = Image.new("L", (plate_size // 4, plate_size // 4))
    grain.putdata([rng.randint(0, 255) for _ in range(grain.size[0] * grain.size[1])])
    grain = grain.resize((plate_size, plate_size), Image.NEAREST)
    shade = Image.new("RGBA", (plate_size, plate_size), (0, 0, 0, 0))
    shade.putalpha(grain.point(lambda v: int(v * 0.075)))
    plate.alpha_composite(shade)
    pd = ImageDraw.Draw(plate)
    scale = plate_size / 100 * 0.80
    pen = Pen(pd, scale, plate_size * 0.10, plate_size * 0.115)
    draw_panda(pen)
    mask = rounded_mask(plate_size, int(plate_size * 0.2237))
    # Drop shadow
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = int(big * 0.012)
    sd.rounded_rectangle((margin, margin + off, margin + plate_size, margin + plate_size + off),
                         radius=int(plate_size * 0.2237), fill=(0, 0, 0, 60))
    from PIL import ImageFilter
    shadow = shadow.filter(ImageFilter.GaussianBlur(big * 0.012))
    canvas.alpha_composite(shadow)
    canvas.paste(plate, (margin, margin), mask)
    return canvas.resize((size, size), Image.LANCZOS)


def face_icon(size):
    ss = 8
    big = size * ss
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Face only, cropped tight: design box x 8..92, y 4..78
    scale = big / 88
    pen = Pen(d, scale, -6 * scale, 2 * scale)
    draw_panda(pen, face_only=True)
    return img.resize((size, size), Image.LANCZOS)


def mascot_preview(size=512):
    ss = 4
    big = size * ss
    img = Image.new("RGBA", (big, big), CREAM)
    pen = Pen(ImageDraw.Draw(img), big / 100, 0, 0)
    draw_panda(pen)
    return img.resize((size, size), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    app_icon().save(os.path.join(root, "Resources", "AppIcon-1024.png"))
    ext = os.path.join(root, "Extension", "chrome", "icons")
    os.makedirs(ext, exist_ok=True)
    for s in (16, 32, 48, 128):
        face_icon(s).save(os.path.join(ext, f"icon{s}.png"))
    if len(sys.argv) > 1:
        mascot_preview().save(sys.argv[1])
    print("icons written")


if __name__ == "__main__":
    main()
