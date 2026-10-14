/// 外观设置页：自定义背景图、透明度、圆角、格子高度
///
/// 交互设计：
///   1) 选图 → 进入裁剪页（**可拖动选区 + 双指缩放**）→ 确认
///   2) 拖动滑块时**实时预览**（页面顶部有一条示例带），不用退回主页看
///   3) 每项改动立即回调给主页并持久化
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/appearance.dart';

/// 裁剪页：拖动选区 + 缩放图片
class CropBackgroundPage extends StatefulWidget {
  final Uint8List imageBytes;

  const CropBackgroundPage({super.key, required this.imageBytes});

  @override
  State<CropBackgroundPage> createState() => _CropBackgroundPageState();
}

class _CropBackgroundPageState extends State<CropBackgroundPage> {
  final CropController _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调整背景图'),
        actions: [
          TextButton(
            onPressed: _cropping
                ? null
                : () {
                    setState(() => _cropping = true);
                    _controller.crop();
                  },
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              interactive: true, // 允许双指缩放、拖动
              fixCropRect: false, // 允许调整选区大小
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure(:final cause):
                    setState(() => _cropping = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('裁剪失败：$cause')),
                    );
                }
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pinch, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 6),
                      Text('双指缩放图片 · 拖动边角调整选区',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('建议选竖图（背景是竖屏铺满的）',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 外观设置页
class AppearancePage extends StatefulWidget {
  final Appearance appearance;

  /// 改动时实时回调（父级据此刷新主页并持久化）
  final ValueChanged<Appearance> onChanged;

  const AppearancePage({
    super.key,
    required this.appearance,
    required this.onChanged,
  });

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late Appearance _a = widget.appearance;
  final AppearanceStore _store = AppearanceStore();
  bool _busy = false;

  void _update(Appearance next) {
    setState(() => _a = next);
    widget.onChanged(next);
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => CropBackgroundPage(imageBytes: bytes)),
      );
      if (cropped == null || !mounted) return;

      final path = await _store.saveBackgroundBytes(cropped);
      _update(_a.copyWith(backgroundPath: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('背景图已设置')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选图失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage() async {
    await _store.removeBackground();
    _update(_a.copyWith(backgroundPath: null));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已移除背景图')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('外观设置'),
        actions: [
          TextButton(
            onPressed: () async {
              await _store.removeBackground();
              _update(const Appearance());
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ---- 实时预览 ----
          _sectionTitle('实时预览'),
          _preview(cs),
          const SizedBox(height: 18),

          // ---- 背景图 ----
          _sectionTitle('背景图'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_busy ? '处理中…' : (_a.hasBackground ? '更换图片' : '选择图片')),
                  onPressed: _busy ? null : _pickImage,
                ),
              ),
              if (_a.hasBackground) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('移除'),
                    onPressed: _busy ? null : _removeImage,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '图片会复制到 App 目录，之后换手机壳/清理相册都不影响',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 18),

          // ---- 透明度与样式 ----
          _sectionTitle('透明度与样式'),
          _slider(
            label: '背景图透明度',
            value: _a.backgroundOpacity,
            min: 0.05,
            max: 1.0,
            hint: '调低 → 背景更淡，课表更清晰',
            onChanged: (v) => _update(_a.copyWith(backgroundOpacity: v)),
          ),
          _slider(
            label: '背景压暗',
            value: _a.backgroundDim,
            min: 0.0,
            max: 0.8,
            hint: '背景图太亮/太花时调高，压暗它',
            onChanged: (v) => _update(_a.copyWith(backgroundDim: v)),
          ),
          _slider(
            label: '课程卡片不透明度',
            value: _a.cardOpacity,
            min: 0.25,
            max: 1.0,
            hint: '调低 → 卡片半透明，能看到背景',
            onChanged: (v) => _update(_a.copyWith(cardOpacity: v)),
          ),
          _slider(
            label: '卡片圆角',
            value: _a.cardRadius,
            min: 0.0,
            max: 20.0,
            hint: '0 = 直角，20 = 很圆',
            decimals: 0,
            onChanged: (v) => _update(_a.copyWith(cardRadius: v)),
          ),
          _slider(
            label: '单节高度',
            value: _a.sectionHeight,
            min: 36,
            max: 120,
            hint: '格子太挤/太空可以调这里',
            decimals: 0,
            onChanged: (v) => _update(_a.copyWith(sectionHeight: v)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            )),
      );

  /// 一条示例带：背景图 + 压暗 + 两张示例卡片，效果与主页一致
  Widget _preview(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 130,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景层
            if (_a.hasBackground)
              Opacity(
                opacity: _a.backgroundOpacity,
                child: Image.file(
                  File(_a.backgroundPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: cs.surface),
                ),
              )
            else
              ColoredBox(color: cs.surfaceContainerHighest),
            // 压暗层
            ColoredBox(color: Colors.black.withValues(alpha: _a.backgroundDim)),
            // 示例卡片
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: _demoCard('高等数学', '@1教206', const Color(0xFF5B8DEF), cs),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _demoCard('大学物理', '@1实331', const Color(0xFFE0A458), cs),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoCard(String name, String room, Color color, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: _a.cardOpacity),
        borderRadius: BorderRadius.circular(_a.cardRadius),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(room, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? hint,
    int decimals = 2,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5)),
            const Spacer(),
            Text(value.toStringAsFixed(decimals),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                )),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(hint, style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ),
      ],
    );
  }
}
