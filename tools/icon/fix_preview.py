"""修正后的预览：系统只保留中心 72dp 区域，然后放大显示。

之前预览的错误：用整个画布直径做圆形裁切，
但 Android 实际是「保留中心 72dp（108dp 的 2/3）→ 放大到显示尺寸」。
所以正确的预览必须：裁中心 2/3 → 再放大。
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "source.png")
src = Image.open(SRC).convert("RGBA")

CANVAS = 432
SAFE = 2.0 / 3.0
inner = int(round(CANVAS * SAFE))          # 288 = 72dp 区域

badge = src.resize((inner, inner), Image.LANCZOS)
canvas = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 255))
off = (CANVAS - inner) // 2
canvas.paste(badge, (off, off), badge)

# 系统裁切：只取中心 72dp
box = (off, off, off + inner, off + inner)
visible = canvas.crop(box)                 # 288x288

# 圆形（最常见的启动器形状）
m1 = Image.new("L", (inner, inner), 0)
ImageDraw.Draw(m1).ellipse([0, 0, inner - 1, inner - 1], fill=255)
c1 = visible.copy()
c1.putalpha(m1)
c1.resize((CANVAS, CANVAS), Image.LANCZOS).save(os.path.join(HERE, "preview_circle.png"))

# 圆角方形（另一种常见形态）
m2 = Image.new("L", (inner, inner), 0)
ImageDraw.Draw(m2).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=int(inner * 0.22), fill=255)
c2 = visible.copy()
c2.putalpha(m2)
c2.resize((CANVAS, CANVAS), Image.LANCZOS).save(os.path.join(HERE, "preview_square.png"))

# 圆形 + 方形并排对比图
combo = Image.new("RGBA", (CANVAS * 2 + 24, CANVAS), (240, 240, 240, 255))
combo.paste(Image.open(os.path.join(HERE, "preview_circle.png")), (0, 0))
combo.paste(Image.open(os.path.join(HERE, "preview_square.png")), (CANVAS + 24, 0))
combo.save(os.path.join(HERE, "preview_both.png"))

print("inner(72dp区域) =", inner)
print("已生成 preview_circle.png / preview_square.png / preview_both.png")
