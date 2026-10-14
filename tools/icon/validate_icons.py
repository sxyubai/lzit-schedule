"""校验生成的图标资源尺寸/格式/透明度。"""
import os

from PIL import Image

RES = r"D:\Shiraha\Projects\AI\lzit_schedule\android\app\src\main\res"

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FG = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

ok = True
print("--- 传统图标 ---")
for d, s in LEGACY.items():
    p = os.path.join(RES, f"mipmap-{d}", "ic_launcher.png")
    if not os.path.exists(p):
        print(f"  {d}: 文件不存在!")
        ok = False
        continue
    im = Image.open(p)
    good = im.size == (s, s)
    ok = ok and good
    print(f"  {d:8} {str(im.size):12} mode={im.mode:6} {'OK' if good else 'SIZE MISMATCH'}")

print("\n--- 自适应前景 ---")
for d, s in FG.items():
    p = os.path.join(RES, f"mipmap-{d}", "ic_launcher_foreground.png")
    if not os.path.exists(p):
        print(f"  {d}: 文件不存在!")
        ok = False
        continue
    im = Image.open(p)
    good = im.size == (s, s)
    ok = ok and good
    has_alpha = im.mode in ("RGBA", "LA")
    ok = ok and has_alpha
    print(f"  {d:8} {str(im.size):12} mode={im.mode:6} alpha={has_alpha} {'OK' if good and has_alpha else 'PROBLEM'}")

print("\n--- 前景透明边检查（四角应为透明）---")
fg = Image.open(os.path.join(RES, "mipmap-xxxhdpi", "ic_launcher_foreground.png")).convert("RGBA")
w, h = fg.size
corners = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]
alphas = [fg.getpixel(xy)[3] for xy in corners]
print("  四角 alpha:", alphas, "->", "全部透明 OK" if all(a == 0 for a in alphas) else "有非透明角!")

print("\n--- 中心内容占比检查（应约 2/3）---")
# 找非透明像素的包围盒
bbox = fg.getbbox()
if bbox:
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    print(f"  内容包围盒 {bw}x{bh} / 画布 {w}x{h} = {bw / w:.3f}")
    print("  ", "符合 2/3 规范" if abs(bw / w - 2 / 3) < 0.02 else "偏离 2/3")

print("\n结论:", "全部通过" if ok else "有问题")
