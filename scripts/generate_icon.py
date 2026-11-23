from PIL import Image, ImageDraw
import math
from pathlib import Path

size = 1024
image = Image.new("RGB", (size, size), "#FCE7F1")
pixels = image.load()
for y in range(size):
    for x in range(size):
        d = math.sqrt((x - size * 0.48) ** 2 + (y - size * 0.42) ** 2) / (size * 0.9)
        t = min(1, d)
        a = (255, 245, 250)
        b = (244, 177, 207)
        pixels[x, y] = tuple(int(a[i] * (1-t) + b[i] * t) for i in range(3))

draw = ImageDraw.Draw(image, "RGBA")
wing = (255, 255, 255, 235)
shadow = (202, 91, 143, 70)
draw.ellipse((250, 215, 545, 525), fill=shadow)
draw.ellipse((470, 215, 765, 525), fill=shadow)
draw.ellipse((285, 455, 535, 735), fill=shadow)
draw.ellipse((485, 455, 735, 735), fill=shadow)
draw.ellipse((238, 195, 530, 500), fill=wing)
draw.ellipse((494, 195, 786, 500), fill=wing)
draw.ellipse((285, 435, 530, 720), fill=(255, 250, 253, 245))
draw.ellipse((494, 435, 739, 720), fill=(255, 250, 253, 245))
draw.rounded_rectangle((493, 365, 531, 665), radius=19, fill=(207, 91, 147, 255))
draw.arc((440, 270, 520, 420), 190, 285, fill=(207, 91, 147, 255), width=12)
draw.arc((505, 270, 585, 420), 255, 350, fill=(207, 91, 147, 255), width=12)
line = (231, 143, 181, 155)
draw.line((500, 420, 380, 315), fill=line, width=8)
draw.line((520, 420, 650, 315), fill=line, width=8)
draw.line((500, 510, 390, 610), fill=line, width=7)
draw.line((520, 510, 630, 610), fill=line, width=7)

out = Path("Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
out.parent.mkdir(parents=True, exist_ok=True)
image.save(out, format="PNG", optimize=True)
print(f"Created {out}")
