# 应用图标生成

源图：`source.png`（1254x1254，柳州工学院萌系校徽）

## 用法

```bash
cd tools/icon
python make_icons.py      # 生成全套图标资源到 android/app/src/main/res/
python fix_preview.py     # 生成真实裁切预览（圆形/圆角方形）
python validate_icons.py  # 校验尺寸/透明度/内容占比
```

换图时把新图覆盖成 `source.png` 再跑一遍即可。

## 关键规范（踩过坑）

**自适应图标不是"整张图缩放到各尺寸"**：

- 画布 **108dp**，但系统**只保留中心 72dp**（= 2/3），外圈会被裁切
- 所以前景内容要占 **2/3 左右** —— 我第一次按 72% 做，会被裁掉一圈
- **背景单独一层**（这里用纯白 `#FFFFFF`，因为源图底色是白的）

产出结构：

```
mipmap-{mdpi..xxxhdpi}/ic_launcher.png             # 传统图标（旧系统整图缩放）
mipmap-{mdpi..xxxhdpi}/ic_launcher_foreground.png  # 自适应前景（徽章占 2/3）
values/ic_launcher_background.xml                   # 背景色
mipmap-anydpi-v26/ic_launcher{,_round}.xml          # 自适应描述
```

## 校验要点

- 传统图标尺寸：48 / 72 / 96 / 144 / 192
- 自适应前景尺寸：108 / 162 / 216 / 324 / 432（带 alpha）
- **前景四角必须透明**，内容包围盒约占画布 2/3
- 构建后用 `aapt dump badging app-release.apk` 确认
  `application-icon` 指向 `res/XX.xml`（说明走的是自适应图标，不是 PNG）

## 应用名

在 `android/app/src/main/AndroidManifest.xml`：

```xml
android:label="柳工课表"
android:icon="@mipmap/ic_launcher"
android:roundIcon="@mipmap/ic_launcher_round"
```
