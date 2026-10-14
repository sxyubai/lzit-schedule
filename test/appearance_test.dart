/// 外观配置测试
///
/// 重点测三件事：
///   1) 序列化往返不丢字段（配置存不下就等于没做）
///   2) **越界值必须被 clamp**（用户拖到极端值、或旧数据格式变化时不能崩/不可用）
///   3) copyWith 能把 backgroundPath 显式置回 null（移除背景图）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/appearance.dart';

void main() {
  group('默认值', () {
    test('初始配置合理（有背景但保守）', () {
      const a = Appearance();
      expect(a.backgroundPath, isNull);
      expect(a.backgroundOpacity, 0.55);
      expect(a.cardOpacity, 0.90);
      expect(a.cardRadius, 6);
      expect(a.sectionHeight, 64);
      expect(a.hasBackground, isFalse, reason: '没设路径就没有背景');
    });
  });

  group('序列化往返', () {
    test('所有字段都能存回来', () {
      const a = Appearance(
        backgroundPath: r'C:\x\bg.jpg',
        backgroundOpacity: 0.42,
        backgroundDim: 0.33,
        cardOpacity: 0.71,
        cardRadius: 13,
        sectionHeight: 88,
        seedColor: 0xFF2B6CB0,
      );
      final back = Appearance.fromJson(a.toJson());

      expect(back.backgroundPath, r'C:\x\bg.jpg');
      expect(back.backgroundOpacity, closeTo(0.42, 1e-9));
      expect(back.backgroundDim, closeTo(0.33, 1e-9));
      expect(back.cardOpacity, closeTo(0.71, 1e-9));
      expect(back.cardRadius, closeTo(13, 1e-9));
      expect(back.sectionHeight, closeTo(88, 1e-9));
      expect(back.seedColor, 0xFF2B6CB0);
    });

    test('空 JSON 回退默认值', () {
      final a = Appearance.fromJson(const {});
      expect(a.backgroundOpacity, 0.55);
      expect(a.cardOpacity, 0.90);
    });

    test('字段类型不对时不崩（用默认值兜底）', () {
      final a = Appearance.fromJson(const {
        'backgroundOpacity': 'not-a-number',
        'cardOpacity': null,
      });
      expect(a.backgroundOpacity, 0.55);
      expect(a.cardOpacity, 0.90);
    });
  });

  group('★ 越界值 clamp（防止界面被拖坏）', () {
    test('透明度不能低于 0.05（否则背景彻底看不见）', () {
      final a = Appearance.fromJson(const {'backgroundOpacity': 0.0});
      expect(a.backgroundOpacity, 0.05);
      final b = Appearance.fromJson(const {'backgroundOpacity': -3});
      expect(b.backgroundOpacity, 0.05);
    });

    test('透明度不能超过 1.0', () {
      expect(Appearance.fromJson(const {'backgroundOpacity': 9}).backgroundOpacity, 1.0);
    });

    test('卡片不透明度下限 0.25（再低字就糊了）', () {
      expect(Appearance.fromJson(const {'cardOpacity': 0.01}).cardOpacity, 0.25);
      expect(Appearance.fromJson(const {'cardOpacity': 5}).cardOpacity, 1.0);
    });

    test('压暗层 0~0.8', () {
      expect(Appearance.fromJson(const {'backgroundDim': -1}).backgroundDim, 0.0);
      expect(Appearance.fromJson(const {'backgroundDim': 2}).backgroundDim, 0.8);
    });

    test('圆角 0~20', () {
      expect(Appearance.fromJson(const {'cardRadius': -5}).cardRadius, 0.0);
      expect(Appearance.fromJson(const {'cardRadius': 99}).cardRadius, 20.0);
    });

    test('单节高度 36~120（太低会重叠、太高要滑半天）', () {
      expect(Appearance.fromJson(const {'sectionHeight': 5}).sectionHeight, 36.0);
      expect(Appearance.fromJson(const {'sectionHeight': 999}).sectionHeight, 120.0);
    });

    test('NaN 不传播', () {
      final a = Appearance.fromJson(const {'backgroundOpacity': double.nan});
      expect(a.backgroundOpacity, 0.05, reason: 'NaN 应被兜底成合法值');
      expect(a.backgroundOpacity.isNaN, isFalse);
    });
  });

  group('copyWith', () {
    test('只改指定字段', () {
      const a = Appearance(cardRadius: 6, cardOpacity: 0.9, sectionHeight: 64);
      final b = a.copyWith(cardRadius: 12);
      expect(b.cardRadius, 12);
      expect(b.cardOpacity, 0.9);
      expect(b.sectionHeight, 64);
    });

    test('★ 能把 backgroundPath 显式置回 null（移除背景）', () {
      const a = Appearance(backgroundPath: r'C:\x\bg.jpg');
      final b = a.copyWith(backgroundPath: null);
      expect(b.backgroundPath, isNull, reason: '移除背景必须能生效');
    });

    test('不传 backgroundPath 时保持原值', () {
      const a = Appearance(backgroundPath: r'C:\x\bg.jpg');
      final b = a.copyWith(cardRadius: 10);
      expect(b.backgroundPath, r'C:\x\bg.jpg');
    });

    test('copyWith 也会 clamp（拖滑块不能越界）', () {
      const a = Appearance();
      expect(a.copyWith(backgroundOpacity: -10).backgroundOpacity, 0.05);
      expect(a.copyWith(cardOpacity: 0).cardOpacity, 0.25);
      expect(a.copyWith(sectionHeight: 1000).sectionHeight, 120.0);
    });
  });

  group('hasBackground', () {
    test('路径为空串 → false', () {
      expect(const Appearance(backgroundPath: '').hasBackground, isFalse);
    });

    test('路径指向不存在的文件 → false（文件可能被清理掉）', () {
      const a = Appearance(backgroundPath: r'C:\definitely\not\exist\bg.jpg');
      expect(a.hasBackground, isFalse);
    });
  });
}
