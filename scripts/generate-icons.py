#!/usr/bin/env python3
"""
Renders the macOS app icon and the .appiconset PNGs.

Why hand-rolled rather than an existing converter: the icon is a handful of
rounded rectangles and quadrilaterals, so a small signed-distance rasterizer
gives exact control over macOS icon geometry (Apple's 824/1024 body ratio and
185/824 corner radius) with anti-aliasing, and keeps the build free of binary
tooling that would otherwise have to be installed.

Outputs (all opaque RGB, as App Store validation requires):
  app/Assets.xcassets/AppIcon.appiconset/icon_*.png
  assets/icon/AppIcon-1024.png        (source/preview)
  assets/icon/safari-toolbar-*.png    (toolbar glyph, transparent)
"""
from __future__ import annotations

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- Brand palette (matches the upstream logotype's blue) -------------------
TOP = (0x2B, 0xA0, 0xF5)
MID = (0x1F, 0x8A, 0xE4)
BOTTOM = (0x15, 0x71, 0xC9)
WHITE = (0xFF, 0xFF, 0xFF)


# ---------------------------------------------------------------------------
# Minimal PNG writer (RGBA, 8-bit, no filtering -> small and dependency-free)
# ---------------------------------------------------------------------------
def write_png(path: str, width: int, height: int, pixels: bytearray) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw += pixels[y * stride : (y + 1) * stride]

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", ihdr))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        fh.write(chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Signed-distance helpers, all in a normalized 0..1 coordinate space so the
# icon is resolution independent. Distances are in units of the canvas.
# ---------------------------------------------------------------------------
def sd_rounded_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax, ay = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - r


def sd_segment(px, py, ax, ay, bx, by, r):
    """Distance to a capsule of radius r from segment a->b."""
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    denom = bax * bax + bay * bay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / denom)) if denom else 0.0
    return math.hypot(pax - bax * h, pay - bay * h) - r


def sd_quad(px, py, pts):
    """Approximate signed distance to a convex quad (used for the K strokes)."""
    # Even-odd point-in-quad plus min distance to each edge: accurate enough
    # for anti-aliased strokes at this scale.
    inside = False
    n = len(pts)
    dist = float("inf")
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        if (ay > py) != (by > py):
            if px < ax + (py - ay) / (by - ay) * (bx - ax):
                inside = not inside
        dist = min(dist, sd_segment(px, py, ax, ay, bx, by, 0.0))
    return -dist if inside else dist


def mix(c1, c2, t):
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def alpha_from_sd(d, size):
    """Coverage from a signed distance expressed in normalized canvas units.

    ``d`` is in 0..1 units; one pixel is ``1/size`` of that, so the transition
    band is half a pixel wide on either side of the true edge.
    """
    return max(0.0, min(1.0, 0.5 - d * size))


# ---------------------------------------------------------------------------
# Icon geometry (0..1 space). Apple's macOS grid: 824/1024 body, r=185/1024.
# ---------------------------------------------------------------------------
BODY_INSET = 100 / 1024
BODY_RADIUS = 185 / 1024
BODY_CX = BODY_CY = 0.5
BODY_HW = BODY_HH = (512 - 100) / 1024


def kt_strokes():
    """The "KT" mark as (kind, args) primitives in normalized 0..1 space.

    Built from a compact geometric spec so the strokes actually meet:
      * vertical stems run from y=0.28 to y=0.72, stroke width 0.078
      * the K's diagonals span that stem's full height and start exactly on
        its right edge (x = 0.212 + 0.078 = 0.290) at the vertical centre
      * the T bar sits on the same top line as the K stem, its stem centred
    """
    w = 78 / 1024        # stroke width
    top, bottom = 280 / 1024, 744 / 1024
    cy = (top + bottom) / 2
    r = w / 2            # rounded cap / joint radius

    k_left = 212 / 1024
    k_right = k_left + w                 # 0.2832
    t_left = 466 / 1024
    t_right = 822 / 1024
    t_cx = (t_left + t_right) / 2

    dx = 150 / 1024                      # horizontal reach of each diagonal
    dy = (bottom - top) / 2              # each diagonal covers half the height

    return {
        # Capsules: (ax, ay, bx, by, radius)
        "segments": [
            # K stem
            (k_left + r, top + r, k_left + r, bottom - r, r),
            # K upper diagonal: stem middle -> up-right
            (k_right - r * 0.2, cy, k_right + dx, top + r, r),
            # K lower diagonal: stem middle -> down-right
            (k_right - r * 0.2, cy, k_right + dx, bottom - r, r),
            # T bar
            (t_left + r, top + r, t_right - r, top + r, r),
            # T stem
            (t_cx, top + r, t_cx, bottom - r, r),
        ],
        "quads": [],
        "dx": dx,
        "dy": dy,
    }


def render_icon(size: int) -> bytearray:
    px = bytearray(size * size * 4)
    strokes = kt_strokes()
    inv = 1.0 / size

    for y in range(size):
        py = (y + 0.5) * inv
        row = y * size * 4
        # Vertical brand gradient across the icon body.
        t = (py - BODY_INSET) / (BODY_HH * 2)
        t = max(0.0, min(1.0, t))
        base = mix(TOP, MID, t / 0.55) if t < 0.55 else mix(MID, BOTTOM, (t - 0.55) / 0.45)
        # Outside the rounded plate the canvas matches the plate edge colour so
        # no visible fringe appears once the alpha channel is dropped.
        outside = mix(MID, BOTTOM, max(0.0, min(1.0, (t - 0.55) / 0.45)))

        for x in range(size):
            px_x = (x + 0.5) * inv

            sd = sd_rounded_rect(
                px_x, py, BODY_CX, BODY_CY, BODY_HW, BODY_HH, BODY_RADIUS
            )
            body = alpha_from_sd(sd, size)
            # App Store validation rejects icons with an alpha channel, so the
            # plate is always painted fully opaque (coverage clamped to 0.0 at
            # the very edge is not enough: macOS masks the corners itself).
            body = 1.0 if sd < 0.0 else max(body, 0.0)

            r, g, b = (base if body > 0.0 else outside)

            # Top sheen: brightens the upper third slightly for depth.
            if t < 0.42:
                sheen = 0.20 * (1.0 - t / 0.42) ** 1.6
                r += (255 - r) * sheen
                g += (255 - g) * sheen
                b += (255 - b) * sheen

            # Composite the white "KT" mark over the body.
            cov = 0.0
            for ax, ay, bx, by, rad in strokes["segments"]:
                cov = max(cov, alpha_from_sd(sd_segment(px_x, py, ax, ay, bx, by, rad), size))
                if cov >= 1.0:
                    break

            r = r + (WHITE[0] - r) * cov
            g = g + (WHITE[1] - g) * cov
            b = b + (WHITE[2] - b) * cov

            i = row + x * 4
            px[i] = int(r + 0.5)
            px[i + 1] = int(g + 0.5)
            px[i + 2] = int(b + 0.5)
            px[i + 3] = 255

    return px


def render_toolbar_glyph(size: int) -> bytearray:
    """Transparent glyph for Safari's toolbar: the KT mark alone, no plate.

    Safari renders toolbar icons as template images, so this is drawn in black
    and the system tints it to match the active appearance.
    """
    px = bytearray(size * size * 4)
    strokes = kt_strokes()

    # The mark occupies roughly x 212..822, y 286..760 of the 1024 grid. Fit
    # it into the unit square with a little breathing room on every side.
    sx0, sx1 = 212 / 1024, 822 / 1024
    sy0, sy1 = 286 / 1024, 760 / 1024
    pad = 0.05
    scale = (1.0 - 2 * pad) / max(sx1 - sx0, sy1 - sy0)
    ox = 0.5 - scale * (sx0 + sx1) / 2
    oy = 0.5 - scale * (sy0 + sy1) / 2

    def fit(v, offset):
        return v * scale + offset

    for y in range(size):
        py = (y + 0.5) / size
        row = y * size * 4
        for x in range(size):
            px_x = (x + 0.5) / size
            cov = 0.0
            for ax, ay, bx, by, rad in strokes["segments"]:
                cov = max(
                    cov,
                    alpha_from_sd(
                        sd_segment(
                            px_x, py,
                            fit(ax, ox), fit(ay, oy),
                            fit(bx, ox), fit(by, oy),
                            rad * scale,
                        ),
                        size,
                    ),
                )
                if cov >= 1.0:
                    break
            i = row + x * 4
            px[i] = px[i + 1] = px[i + 2] = 0
            px[i + 3] = int(cov * 255 + 0.5)
    return px


# Apple's macOS AppIcon slots: (size, scale)
SLOTS = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def main() -> None:
    icon_set = os.path.join(ROOT, "app", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(icon_set, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "assets", "icon"), exist_ok=True)

    # Each slot is rasterized directly at its target size: the shapes are
    # analytic, so this is both crisp and cheaper than downsampling.
    images: dict[int, bytearray] = {}
    for size, scale in SLOTS:
        target = size * scale
        if target not in images:
            images[target] = render_icon(target)
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        write_png(os.path.join(icon_set, name), target, target, images[target])
        print(f"  {name:22s} {target:4d}x{target}")

    contents = {
        "images": [
            {
                "filename": f"icon_{s}x{s}{'@2x' if sc == 2 else ''}.png",
                "idiom": "mac",
                "scale": f"{sc}x",
                "size": f"{s}x{s}",
            }
            for s, sc in SLOTS
        ],
        "info": {"author": "xcode", "version": 1},
    }
    import json

    with open(os.path.join(icon_set, "Contents.json"), "w") as fh:
        json.dump(contents, fh, indent=2)
        fh.write("\n")

    write_png(
        os.path.join(ROOT, "assets", "icon", "AppIcon-1024.png"),
        1024,
        1024,
        render_icon(1024),
    )
    # Toolbar glyphs at 1x and 2x for the sizes macOS asks for.
    for s in (16, 19, 32, 48):
        write_png(
            os.path.join(ROOT, "assets", "icon", f"safari-toolbar-{s}.png"),
            s, s, render_toolbar_glyph(s),
        )
        write_png(
            os.path.join(ROOT, "assets", "icon", f"safari-toolbar-{s}@2x.png"),
            s * 2, s * 2, render_toolbar_glyph(s * 2),
        )
    print("  assets/icon/AppIcon-1024.png + safari-toolbar-*.png")


if __name__ == "__main__":
    main()
