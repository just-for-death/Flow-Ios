#!/usr/bin/env python3
"""Generate primary + alternate iOS app icons (1024x1024, no alpha).

actool rejects:
  - wrong dimensions (must be exactly 1024x1024 for single-size iOS icons)
  - alpha channel in app icons
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "FlowApp" / "Assets.xcassets"
# Prefer Android asset if present; fall back to existing iOS logo.
CANDIDATES = [
    Path(__file__).resolve().parent.parent.parent / "Flow-main" / "Assets" / "logo.png",
    ROOT / "AppIcon.appiconset" / "logo.png",
]
SIZE = 1024

VARIANTS = {
    "AppIcon": "#0B0B0B",
    "FlowLight": "#FFFFFF",
    "FlowPlay": "#FFFFFF",
    "Amoled": "#000000",
    "Monochrome": "#FFFFFF",
    "Ghost": "#121212",
    "MaterialSky": "#D7E3FF",
    "MaterialMint": "#C7E8D4",
    "FlowRed": "#0F0F0F",
}

CONTENTS = """{
  "images" : [
    {
      "filename" : "%s",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

CATALOG_CONTENTS = """{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def flatten_rgb(img: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Composite onto opaque background and drop alpha (required by actool)."""
    base = Image.new("RGBA", img.size, (*bg, 255))
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    base.alpha_composite(img)
    return base.convert("RGB")


def main() -> None:
    src = next((p for p in CANDIDATES if p.exists()), None)
    if src is None:
        raise SystemExit("Missing source logo.png")

    logo = Image.open(src).convert("RGBA")
    # Upscale small source with LANCZOS for 1024 canvas
    fg_size = int(SIZE * 0.62)
    logo = logo.resize((fg_size, fg_size), Image.Resampling.LANCZOS)

    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "Contents.json").write_text(CATALOG_CONTENTS)

    for name, hex_color in VARIANTS.items():
        folder = ROOT / f"{name}.appiconset"
        folder.mkdir(parents=True, exist_ok=True)
        bg = hex_to_rgb(hex_color)

        if name == "Monochrome":
            # Desaturate logo then tint dark on light bg
            gray = logo.convert("LA").convert("RGBA")
            fg = gray
        else:
            fg = logo

        canvas = Image.new("RGBA", (SIZE, SIZE), (*bg, 255))
        offset = ((SIZE - fg.width) // 2, (SIZE - fg.height) // 2)
        canvas.alpha_composite(fg, offset)
        out = canvas.convert("RGB")

        filename = "logo.png" if name == "AppIcon" else "icon.png"
        out_path = folder / filename
        out.save(out_path, format="PNG", optimize=True)
        (folder / "Contents.json").write_text(CONTENTS % filename)

        # Verify
        check = Image.open(out_path)
        assert check.size == (SIZE, SIZE), check.size
        assert check.mode == "RGB", check.mode
        print(f"Wrote {folder.name}/{filename} {check.size} {check.mode}")


if __name__ == "__main__":
    main()
