#!/usr/bin/env python3
"""Generate alternate iOS app icons from the primary logo.png."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "FlowApp" / "Assets.xcassets"
SRC = ROOT / "AppIcon.appiconset" / "logo.png"
SIZE = 1024

VARIANTS = {
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
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Missing source icon: {SRC}")
    logo = Image.open(SRC).convert("RGBA")
    logo = logo.resize((int(SIZE * 0.62), int(SIZE * 0.62)), Image.Resampling.LANCZOS)

    for name, hex_color in VARIANTS.items():
        folder = ROOT / f"{name}.appiconset"
        folder.mkdir(parents=True, exist_ok=True)
        bg = Image.new("RGBA", (SIZE, SIZE), hex_color)
        if name == "Monochrome":
            gray = logo.convert("LA").convert("RGBA")
            fg = gray
        else:
            fg = logo
        offset = ((SIZE - fg.width) // 2, (SIZE - fg.height) // 2)
        composed = bg.copy()
        composed.alpha_composite(fg, offset)
        composed.save(folder / "icon.png")
        (folder / "Contents.json").write_text(CONTENTS)
        print(f"Wrote {folder.name}")

if __name__ == "__main__":
    main()
