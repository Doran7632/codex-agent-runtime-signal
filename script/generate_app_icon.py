#!/usr/bin/env python3
"""Generate a deterministic macOS .icns icon for codex-agent-runtime-signal."""

from __future__ import annotations

import argparse
import math
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


ICON_FILES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate AppIcon.icns")
    parser.add_argument("output", type=Path, help="Destination .icns path")
    return parser.parse_args()


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> None:
    rows = []
    for y in range(height):
        row = bytearray([0])
        for red, green, blue, alpha in pixels[y * width : (y + 1) * width]:
            row.extend((red, green, blue, alpha))
        rows.append(bytes(row))

    raw = b"".join(rows)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(raw, level=9))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def blend(dst: tuple[float, float, float, float], src: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    out_a = sa + da * (1.0 - sa)
    if out_a <= 0:
        return (0, 0, 0, 0)
    return (
        (sr * sa + dr * da * (1.0 - sa)) / out_a,
        (sg * sa + dg * da * (1.0 - sa)) / out_a,
        (sb * sa + db * da * (1.0 - sa)) / out_a,
        out_a,
    )


def in_rounded_rect(x: float, y: float, left: float, top: float, right: float, bottom: float, radius: float) -> bool:
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius**2


def in_circle(x: float, y: float, cx: float, cy: float, radius: float) -> bool:
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius**2


def scene(x: float, y: float) -> tuple[float, float, float, float]:
    color = (0.0, 0.0, 0.0, 0.0)

    if in_rounded_rect(x, y, 0.10, 0.36, 0.90, 0.72, 0.18):
        color = blend(color, (0.0, 0.0, 0.0, 0.16))

    if in_rounded_rect(x, y, 0.08, 0.31, 0.92, 0.69, 0.18):
        color = blend(color, (0.035, 0.04, 0.05, 1.0))

    lights = [
        (0.265, 0.50, 0.94, 0.18, 0.18),
        (0.500, 0.50, 0.98, 0.76, 0.15),
        (0.735, 0.50, 0.11, 0.78, 0.28),
    ]
    for cx, cy, red, green, blue in lights:
        if in_circle(x, y, cx, cy, 0.116):
            color = blend(color, (red, green, blue, 1.0))
        if in_circle(x, y, cx - 0.038, cy - 0.038, 0.028):
            color = blend(color, (1.0, 1.0, 1.0, 0.36))

    if in_rounded_rect(x, y, 0.13, 0.35, 0.28, 0.42, 0.03):
        color = blend(color, (1.0, 1.0, 1.0, 0.06))

    return color


def render_icon(size: int) -> list[tuple[int, int, int, int]]:
    if size >= 512:
        samples = 1
    elif size >= 128:
        samples = 2
    else:
        samples = 4
    pixels: list[tuple[int, int, int, int]] = []

    for y in range(size):
        for x in range(size):
            acc = (0.0, 0.0, 0.0, 0.0)
            sample_count = samples * samples
            for sy in range(samples):
                for sx in range(samples):
                    nx = (x + (sx + 0.5) / samples) / size
                    ny = (y + (sy + 0.5) / samples) / size
                    acc = tuple(a + b for a, b in zip(acc, scene(nx, ny)))
            red, green, blue, alpha = (value / sample_count for value in acc)
            pixels.append(
                (
                    max(0, min(255, round(red * 255))),
                    max(0, min(255, round(green * 255))),
                    max(0, min(255, round(blue * 255))),
                    max(0, min(255, round(alpha * 255))),
                )
            )

    return pixels


def main() -> int:
    args = parse_args()
    iconutil = shutil.which("iconutil")
    if iconutil is None:
        raise SystemExit("iconutil is required to generate a macOS .icns file")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="codex-agent-runtime-signal-icon-") as temp_dir:
        iconset = Path(temp_dir) / "AppIcon.iconset"
        iconset.mkdir()
        for filename, size in ICON_FILES:
            write_png(iconset / filename, size, size, render_icon(size))
        subprocess.run([iconutil, "-c", "icns", str(iconset), "-o", str(args.output)], check=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
