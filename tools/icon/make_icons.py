"""生成安卓图标资源（修正版）。

关键规范（之前理解错了）：
  自适应图标画布 108dp，但系统只保留**中心 72dp**（66.7%），
  外圈会被裁切/用于动画。所以前景内容应占 66.7% 左右，
  **不是 72%** —— 否则会被裁掉一圈。

产出：
  mipmap-*/ic_launcher.png            传统图标（整图，兼容旧系统）
  mipmap-*/ic_launcher_foreground.png 自适应前景（徽章占 66.7%）
  values/ic_launcher_background.xml   背景色
  mipmap-anydpi-v26/ic_launcher*.xml  自适应描述
  preview_circle.png / preview_square.png  真实裁切预览
"""
import io
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "source.png")
RES = r"D:\Shiraha\Projects\AI\lzit_schedule\android\app\src\main\res"

LEGACY = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
FOREGROUND = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]

# 108dp 画布里系统保留中心 72dp -> 2/3
SAFE_RATIO = 2.0 / 3.0
BG_COLOR = "#FFFFFF"

src = Image.open(SRC).convert("RGBA")
print("源图:", src.size, src.mode, " -> 前景徽章占比:", round(SAFE_RATIO, 4))


def save(img, *parts):
    p = os.path.join(RES, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, "PNG", optimize=True)
    return p


print("\n--- 传统图标（整图缩放，兼容 Android 7 及以下）---")
for density, size in LEGACY:
    im = src.resize((size, size), Image.LANCZOS)
    p = save(im, f"mipmap-{density}", "ic_launcher.png")
    print(f"  {size:>3}px -> mipmap-{density}/ic_launcher.png ({os.path.getsize(p):,}B)")

print("\n--- 自适应前景（徽章占中心 2/3）---")
for density, size in FOREGROUND:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(round(size * SAFE_RATIO))
    badge = src.resize((inner, inner), Image.LANCZOS)
    off = (size - inner) // 2
    canvas.paste(badge, (off, off), badge)
    p = save(canvas, f"mipmap-{density}", "ic_launcher_foreground.png")
    print(f"  画布{size:>3} 徽章{inner:>3} -> mipmap-{density}/ic_launcher_foreground.png ({os.path.getsize(p):,}B)")

print("\n--- 背景色 & 自适应描述 ---")
p = os.path.join(RES, "values", "ic_launcher_background.xml")
os.makedirs(os.path.dirname(p), exist_ok=True)
io.open(p, "w", encoding="utf-8", newline="\n").write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    f'    <color name="ic_launcher_background">{BG_COLOR}</color>\n</resources>\n'
)
anydpi = os.path.join(RES, "mipmap-anydpi-v26")
os.makedirs(anydpi, exist_ok=True)
for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
    io.open(os.path.join(anydpi, name), "w", encoding="utf-8", newline="\n").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
print("  values/ic_launcher_background.xml", BG_COLOR)
print("  mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_round.xml")

# ---------- 预览：真实模拟系统裁切 ----------
SIZE = 432
inner = int(round(SIZE * SAFE_RATIO))
badge = src.resize((inner, inner), Image.LANCZOS)
canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
off = (SIZE - inner) // 2
canvas.paste(badge, (off, off), badge)

# 圆形裁切（系统最常见）
mask = Image.new("L", (SIZE, SIZE), 0)
r = SIZE / 2.0
ImageDraw.Draw(mask).ellipse([SIZE / 2 - r, SIZE / 2 - r, SIZE / 2 + r, SIZE / 2 + r], fill=255)
circle = canvas.copy()
circle.putalpha(mask)
circle.save(os.path.join(HERE, "preview_circle.png"))

# 圆角方形裁切（另一种常见形态）
mask2 = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask2).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.22), fill=255)
squircle = canvas.copy()
squircle.putalpha(mask2)
squircle.save(os.path.join(HERE, "preview_square.png"))

# 传统图标预览
src.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(HERE, "preview_legacy.png"))

print("\n预览已生成：preview_circle.png / preview_square.png / preview_legacy.png")
