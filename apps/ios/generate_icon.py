"""
Generiert das Rolify App-Icon: Spotify-Style (runder Kreis, 3 gewellte Linien)
in Rolify-Blau (#3B82F6).
"""
from PIL import Image, ImageDraw
import os

SIZE = 1024
BG_COLOR = (59, 130, 246)
BG_COLOR_2 = (29, 78, 216)
FG_COLOR = (255, 255, 255)

def make_gradient(size, start_rgb, end_rgb):
    img = Image.new("RGB", (size, size), start_rgb)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / size
        r = int(start_rgb[0] + (end_rgb[0] - start_rgb[0]) * t)
        g = int(start_rgb[1] + (end_rgb[1] - start_rgb[1]) * t)
        b = int(start_rgb[2] + (end_rgb[2] - start_rgb[2]) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    return img

def draw_waves(img):
    """3 konzentrische schmale Boegen mit Gap. PIL arc zeichnet eine Linie,
    width gibt die Linien-Dicke. Radien mit klarem Abstand damit Boegen sichtbar sind."""
    d = ImageDraw.Draw(img)
    cx, cy = SIZE / 2, SIZE / 2 + SIZE * 0.10  # leicht nach unten

    # jeweils nur dünne Linie, aber grosse Radius-Unterschiede
    layers = [
        {"r": SIZE * 0.38, "w": int(SIZE * 0.055)},
        {"r": SIZE * 0.27, "w": int(SIZE * 0.048)},
        {"r": SIZE * 0.17, "w": int(SIZE * 0.042)},
    ]
    # Bogen-Winkel: 205..335 = oben mit leichter Krümmung nach unten (Spotify-Stil)
    start = 205
    end = 335

    for layer in layers:
        r = layer["r"]
        w = layer["w"]
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.arc(bbox, start=start, end=end, fill=FG_COLOR, width=w)

def main():
    img = make_gradient(SIZE, BG_COLOR, BG_COLOR_2)
    draw_waves(img)

    out_dir = os.path.join(os.path.dirname(__file__), "Rolify", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "icon-1024.png")
    img.save(out_path, "PNG", optimize=True)
    print(f"Saved: {out_path}  ({SIZE}x{SIZE})")

    contents = '''{
  "images" : [
    {
      "filename" : "icon-1024.png",
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
'''
    with open(os.path.join(out_dir, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(contents)
    print("Contents.json updated")

if __name__ == "__main__":
    main()
