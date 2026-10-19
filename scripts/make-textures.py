#!/usr/bin/env python3
"""Generate every .tga texture CrowdCalm Lab ships (brief task 7).

All output is 32-bit RGBA, power-of-two, under CrowdCalmLab/Media/.
The static gate (scripts/check-lua.js) asserts the manifest, dimensions,
and the 1 MB total budget — keep that list in sync with MEDIA below.

Usage: python scripts/make-textures.py
"""

from __future__ import annotations

import math
import os
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
MEDIA_DIR = REPO_ROOT / "CrowdCalmLab" / "Media"

GOLD = (217, 164, 65, 255)
GOLD_BRIGHT = (255, 210, 90, 255)
OBSIDIAN = (10, 12, 16, 255)
PANEL = (18, 21, 28, 255)


def save(img: Image.Image, name: str) -> None:
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    path = MEDIA_DIR / name
    img.save(path, format="TGA")
    print(f"  wrote {name} {img.size[0]}x{img.size[1]}")


def power_of_two_floor(n: int) -> int:
    p = 1
    while p * 2 <= n:
        p *= 2
    return p


def radial_alpha(size: int, center_falloff: float, invert: bool = False) -> Image.Image:
    """Grayscale radial mask as an alpha channel (white = opaque)."""
    img = Image.new("L", (size, size), 0)
    px = img.load()
    half = size / 2.0
    for y in range(size):
        for x in range(size):
            dx = (x - half) / half
            dy = (y - half) / half
            d = math.sqrt(dx * dx + dy * dy)
            if invert:
                a = d**center_falloff
            else:
                a = max(0.0, 1.0 - d) ** center_falloff
            px[x, y] = int(max(0.0, min(1.0, a)) * 255)
    return img


def make_shadow() -> None:
    size = 256
    mask = radial_alpha(size, 2.2, invert=True).filter(ImageFilter.GaussianBlur(18))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    img = Image.composite(black, img, mask)
    # keep alpha soft: scale down so the shadow stays subtle
    a = img.getchannel("A").point(lambda v: int(v * 0.55))
    img.putalpha(a)
    save(img, "shadow.tga")


def make_vignette() -> None:
    size = 256
    mask = radial_alpha(size, 1.6, invert=True).filter(ImageFilter.GaussianBlur(6))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    a = mask.point(lambda v: int(v * 0.7))
    img.putalpha(a)
    save(img, "vignette.tga")


def make_noise() -> None:
    size = 128
    rng = random.Random(20261018)  # deterministic
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = rng.randint(0, 40)
            px[x, y] = (v, v, v, 255)
    save(img, "noise.tga")


def make_glow() -> None:
    size = 64
    mask = radial_alpha(size, 3.0)
    img = Image.new("RGBA", (size, size), GOLD[:3] + (0,))
    a = mask.point(lambda v: int(v * 0.9))
    img.putalpha(a)
    save(img, "glow.tga")


def make_sweep() -> None:
    """Vertical shimmer strip used by button hover sweeps and ring swipes."""
    size = 64
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        # bright core in the middle columns, soft edges
        for x in range(size):
            dx = abs(x - size / 2) / (size / 2)
            a = max(0.0, 1.0 - dx) ** 1.5
            px[x, y] = (255, 255, 255, int(a * 160))
    save(img, "sweep.tga")


def make_arc() -> None:
    """Single arc-gauge segment: rounded vertical bar, gold, mostly opaque."""
    w, h = 16, 32
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([4, 2, w - 5, h - 3], radius=4, fill=GOLD_BRIGHT)
    save(img, "arc.tga")


# ------------------------------------------------ pre.4 chrome textures ----


def _vgrad(w: int, h: int, top, bottom) -> Image.Image:
    """Vertical gradient fill (top/bottom are RGB tuples)."""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    denom = max(1, h - 1)
    for y in range(h):
        t = y / denom
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return img


def make_buttons() -> None:
    """Button face gradients (Skin.Button stretches these over any size)."""
    save(_vgrad(32, 32, (44, 49, 60), (14, 16, 21)), "btn_dark.tga")
    save(_vgrad(32, 32, (242, 214, 130), (146, 112, 44)), "btn_gold.tga")


def make_ring() -> None:
    """Smooth circle outline (minimap bezel, 64px, soft 3px edge)."""
    size = 64
    radius = 29.0
    half = 1.7
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            a = max(0.0, min(1.0, 1.0 - abs(d - radius) / half))
            px[x, y] = (255, 255, 255, int((a**0.9) * 235))
    save(img, "ring.tga")


def _gauge_band(fill_frac: float) -> Image.Image:
    """Upper-half annulus band, centered on the bottom edge; the left
    `fill_frac` of the arc (from 180 deg leftward toward 0 deg) is opaque,
    the rest transparent. White RGB so Skin tints it at runtime (the lit
    layer uses gainColor, the dim layer line color — colorblind safe).
    128x64 keeps four states inside the 1 MB media budget."""
    w, h = 128, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    cx, cy = w / 2.0, h - 1.0
    r_out = w * 0.485  # 62 px
    r_in = r_out - 10.0
    fill_from = math.pi * (1.0 - max(0.0, min(1.0, fill_frac)))
    for y in range(h):
        for x in range(w):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            d = math.hypot(dx, dy)
            cov = max(0.0, min(1.0, min(d - (r_in - 0.5), (r_out + 0.5) - d)))
            if cov <= 0.0 or dy > 0.5:  # upper half only
                continue
            angle = math.atan2(-dy, dx)
            if angle + 1e-9 < fill_from:
                continue
            px[x, y] = (255, 255, 255, int(cov * 255))
    return img


def make_gauges() -> None:
    """Overview crowd gauge states: one dim full band + three lit masks
    (quiet 25%, busy 60%, packed 95% filled from the left)."""
    save(_gauge_band(1.0), "gauge_dim.tga")
    save(_gauge_band(0.25), "gauge_q.tga")
    save(_gauge_band(0.60), "gauge_b.tga")
    save(_gauge_band(0.95), "gauge_p.tga")


# ------------------------------------------------ pre.6 visual pass ----------


def make_accent() -> None:
    """Horizontal accent strip (64x16): opaque at the left, fading to the
    right. White RGB — hero cards tint it gold, selected Lab tiles reuse
    the same strip along their top edge (no rotated twin needed)."""
    w, h = 64, 16
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for x in range(w):
        t = x / max(1, w - 1)
        a = int(max(0.0, 1.0 - t) ** 0.7 * 255)
        for y in range(h):
            px[x, y] = (255, 255, 255, a)
    save(img, "accent.tga")


def make_spark_bar() -> None:
    """Sparkline bar fill (8x32): denser at the baseline (bottom), airy at
    the top — tinted gain-green at runtime (Overview sparkline v2)."""
    w, h = 8, 32
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)  # 0 = top, 1 = bottom
        a = int((0.45 + 0.55 * t) * 255)
        for x in range(w):
            px[x, y] = (255, 255, 255, a)
    save(img, "spark_bar.tga")


def make_bars() -> None:
    """Top-3 gain bars: a track (flat low-alpha white) and a fill
    (solid, soft fade in the last 15% of the width)."""
    tw, th = 32, 16
    track = Image.new("RGBA", (tw, th))
    tpx = track.load()
    for y in range(th):
        for x in range(tw):
            tpx[x, y] = (255, 255, 255, 42)
    save(track, "bar_track.tga")

    fw = 32
    fill = Image.new("RGBA", (fw, th))
    fpx = fill.load()
    fade_from = fw * 0.85
    for y in range(th):
        for x in range(fw):
            if x < fade_from:
                a = 255
            else:
                a = int(max(0.0, 1.0 - (x - fade_from) / (fw - fade_from)) * 255)
            fpx[x, y] = (255, 255, 255, a)
    save(fill, "bar_fill.tga")


def make_pip() -> None:
    """Gauge pivot pip (16x16): soft-edged solid dot at the arc baseline."""
    size = 16
    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = size / 2.0
    radius = 6.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            a = max(0.0, min(1.0, (radius + 1.0 - d) / 1.5))
            px[x, y] = (255, 255, 255, int((a**0.8) * 255))
    save(img, "gauge_pip.tga")


def make_pre6() -> None:
    make_accent()
    make_spark_bar()
    make_bars()
    make_pip()


def _load_font(size: int):
    for candidate in (
        "C:/Windows/Fonts/frizquadrata.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _letter_tile(size: int, letter: str, fill, outline) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = max(1, size // 16)
    draw.rounded_rectangle(
        [margin, margin, size - margin - 1, size - margin - 1],
        radius=size // 6,
        fill=fill,
        outline=outline,
        width=max(1, size // 24),
    )
    font = _load_font(int(size * 0.55))
    bbox = draw.textbbox((0, 0), letter, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (size - tw) / 2 - bbox[0]
    ty = (size - th) / 2 - bbox[1]
    draw.text((tx, ty), letter, font=font, fill=(10, 12, 16, 255))
    return img


def make_emblem() -> None:
    save(_letter_tile(64, "C", GOLD, GOLD_BRIGHT), "emblem.tga")


def make_icon() -> None:
    save(_letter_tile(64, "C", GOLD, GOLD_BRIGHT), "icon.tga")


RAIL_TILES = {
    "icon_overview.tga": "O",
    "icon_lab.tga": "L",
    "icon_results.tga": "R",
    "icon_stutter.tga": "S",
    "icon_addons.tga": "A",
    "icon_settings.tga": "E",
    "icon_about.tga": "B",
}


def main() -> None:
    print(f"generating textures into {MEDIA_DIR}")
    make_shadow()
    make_vignette()
    make_noise()
    make_glow()
    make_sweep()
    make_arc()
    make_emblem()
    make_icon()
    make_buttons()
    make_ring()
    make_gauges()
    make_pre6()
    for name, letter in RAIL_TILES.items():
        save(_letter_tile(32, letter, PANEL, GOLD), name)
    print("done.")


if __name__ == "__main__":
    main()
