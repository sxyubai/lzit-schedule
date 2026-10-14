/// 外观配置（背景图 / 透明度 / 圆角等）
///
/// 设计要点：
///   1) 背景图**复制到应用目录**再使用 —— image_picker 返回的是临时缓存路径，
///      系统随时可能清掉，不复制的话下次打开背景就没了
///   2) 透明度分层调节，保证任何背景图下课程名都能看清：
///        背景图透明度 → 背景压暗层 → 卡片透明度
///      课程文字画在卡片之上，所以哪怕背景是全黑图，字也不会看不清
///   3) 所有值都有安全范围（用 clamp），避免用户拖到极端值后界面不可用
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Appearance {
  /// 背景图本地绝对路径（已复制到应用目录）；null = 无背景图
  final String? backgroundPath;

  /// 背景图整体透明度 0.05~1.0（默认 0.55，不至于盖住课表）
  final double backgroundOpacity;

  /// 背景压暗程度 0~0.8（默认 0.15，深色图也能看清浅色文字）
  final double backgroundDim;

  /// 课程卡片不透明度 0.25~1.0（默认 0.9）
  final double cardOpacity;

  /// 课程卡片圆角 0~20（默认 6）
  final double cardRadius;

  /// 单节高度 36~120（默认 64）
  final double sectionHeight;

  /// 主题色（ARGB）；null = 用默认
  final int? seedColor;

  const Appearance({
    this.backgroundPath,
    this.backgroundOpacity = 0.55,
    this.backgroundDim = 0.15,
    this.cardOpacity = 0.90,
    this.cardRadius = 6,
    this.sectionHeight = 64,
    this.seedColor,
  });

  static const _minOpacity = 0.05;
  static const _minCardOpacity = 0.25;

  Appearance copyWith({
    Object? backgroundPath = _sentinel,
    double? backgroundOpacity,
    double? backgroundDim,
    double? cardOpacity,
    double? cardRadius,
    double? sectionHeight,
    Object? seedColor = _sentinel,
  }) {
    return Appearance(
      backgroundPath: identical(backgroundPath, _sentinel)
          ? this.backgroundPath
          : backgroundPath as String?,
      backgroundOpacity: _clamp(backgroundOpacity ?? this.backgroundOpacity, _minOpacity, 1.0),
      backgroundDim: _clamp(backgroundDim ?? this.backgroundDim, 0.0, 0.8),
      cardOpacity: _clamp(cardOpacity ?? this.cardOpacity, _minCardOpacity, 1.0),
      cardRadius: _clamp(cardRadius ?? this.cardRadius, 0.0, 20.0),
      sectionHeight: _clamp(sectionHeight ?? this.sectionHeight, 36.0, 120.0),
      seedColor: identical(seedColor, _sentinel) ? this.seedColor : seedColor as int?,
    );
  }

  /// 有背景图且文件真的存在（文件可能被用户清理掉）
  bool get hasBackground {
    final p = backgroundPath;
    if (p == null || p.isEmpty) return false;
    return File(p).existsSync();
  }

  Map<String, dynamic> toJson() => {
        'backgroundPath': backgroundPath,
        'backgroundOpacity': backgroundOpacity,
        'backgroundDim': backgroundDim,
        'cardOpacity': cardOpacity,
        'cardRadius': cardRadius,
        'sectionHeight': sectionHeight,
        'seedColor': seedColor,
      };

  factory Appearance.fromJson(Map<String, dynamic> j) {
    double d(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    return Appearance(
      backgroundPath: j['backgroundPath'] as String?,
      backgroundOpacity: _clamp(d(j['backgroundOpacity'], 0.55), _minOpacity, 1.0),
      backgroundDim: _clamp(d(j['backgroundDim'], 0.15), 0.0, 0.8),
      cardOpacity: _clamp(d(j['cardOpacity'], 0.90), _minCardOpacity, 1.0),
      cardRadius: _clamp(d(j['cardRadius'], 6), 0.0, 20.0),
      sectionHeight: _clamp(d(j['sectionHeight'], 64), 36.0, 120.0),
      seedColor: (j['seedColor'] as num?)?.toInt(),
    );
  }

  static double _clamp(double v, double lo, double hi) =>
      v.isNaN ? lo : (v < lo ? lo : (v > hi ? hi : v));
}

const Object _sentinel = Object();

/// 外观配置的持久化 + 背景图文件管理
class AppearanceStore {
  static const _prefsKey = 'appearance_v1';
  static const _bgDirName = 'appearance';
  static const _bgFileName = 'background_img';

  Future<Appearance> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const Appearance();
      return Appearance.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      // 配置损坏不该让 App 起不来
      return const Appearance();
    }
  }

  Future<void> save(Appearance a) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(a.toJson()));
    } catch (_) {}
  }

  /// 应用私有目录下的背景图目录
  Future<Directory> _bgDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_bgDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 把（已裁剪的）图片字节保存为背景图，返回新路径
  ///
  /// 传入字节而不是文件：crop_your_image 的裁剪结果就是 `Uint8List`。
  Future<String> saveBackgroundBytes(Uint8List bytes, {String ext = '.jpg'}) async {
    final dir = await _bgDir();
    // 文件名固定，先清掉旧图（换扩展名时会残留）
    await for (final e in dir.list()) {
      if (e is File) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
    final safeExt = _normalizeExt(ext);
    final dest = File('${dir.path}/$_bgFileName$safeExt');
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  /// 删除已保存的背景图
  Future<void> removeBackground() async {
    try {
      final dir = await _bgDir();
      await for (final e in dir.list()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static String _normalizeExt(String ext) {
    var e = ext.toLowerCase();
    if (!e.startsWith('.')) e = '.$e';
    const ok = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
    return ok.contains(e) ? e : '.jpg';
  }
}
