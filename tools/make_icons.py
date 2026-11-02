#!/usr/bin/env python3
"""Generate the app icon + PWA icon set.

    python3 tools/make_icons.py

Writes game/icon_source.png (1024) and the PWA sizes into
game/assets/icons/ (144/180/512). The dark tile with a green tape line is
kept visually consistent with the in-game chart palette.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "icons"

BG = (11, 15, 20)          # #0b0f14
GRID = (26, 36, 47)
GREEN = (38, 208, 124)     # #26d07c
RED = (255, 77, 94)


def rounded_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def make(size: int) -> Image.Image:
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # tile
    d.rectangle([0, 0, s, s], fill=BG)

    # grid
    lw = max(1, s // 128)
    for i in range(1, 4):
        y = int(s * (0.18 + 0.21 * i))
        d.line([(int(s * 0.10), y), (int(s * 0.90), y)], fill=GRID, width=lw)

    # tape line (rising, with a dip) in normalized coords
    pts_n = [
        (0.10, 0.72), (0.20, 0.66), (0.27, 0.70), (0.36, 0.52),
        (0.45, 0.58), (0.53, 0.40), (0.62, 0.46), (0.72, 0.28),
        (0.80, 0.34), (0.90, 0.18),
    ]
    pts = [(x * s, y * s) for x, y in pts_n]

    # area fill under the line
    area = pts + [(pts[-1][0], s * 0.88), (pts[0][0], s * 0.88)]
    fill = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fill)
    fd.polygon(area, fill=GREEN + (60,))
    img = Image.alpha_composite(img, fill)
    d = ImageDraw.Draw(img)

    # the line itself
    d.line(pts, fill=GREEN, width=max(3, s // 24), joint="curve")

    # last-tick dot
    r = max(3, s // 22)
    x, y = pts[-1]
    d.ellipse([x - r, y - r, x + r, y + r], fill=GREEN)

    # small red tick stub (a little market drama)
    x2, y2 = pts[3]
    r2 = max(2, s // 40)
    d.ellipse([x2 - r2, y2 - r2, x2 + r2, y2 + r2], fill=RED)

    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask(s))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for size in (144, 180, 512):
        p = OUT / f"icon_{size}x{size}.png"
        make(size).save(p)
        print(f"wrote {p.relative_to(ROOT)}")
    big = OUT / "icon_source.png"
    make(1024).save(big)
    print(f"wrote {big.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
