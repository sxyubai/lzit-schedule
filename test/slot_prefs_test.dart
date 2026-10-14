/// 冲突偏好持久化测试
///
/// 这条链路的逻辑正确性必须用测试锁死，不能靠"点屏幕看结果"——
/// 坐标猜错会导致误判成功能坏了。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/services/slot_cluster.dart';
import 'package:lzit_schedule/services/slot_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SlotPrefs 槽位记忆', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认返回 0（第一条）', () async {
      final p = await SlotPrefs.load();
      expect(p.indexOf(2, 3, 4), 0);
    });

    test('保存后能读回同一个值', () async {
      final p = await SlotPrefs.load();
      await p.setChoice(2, 3, 4, 1);
      expect(p.indexOf(2, 3, 4), 1);
    });

    test('写入后重新 load 仍然是新值（持久化生效）', () async {
      final p1 = await SlotPrefs.load();
      await p1.setChoice(2, 3, 4, 1);

      // 模拟重启：重新从存储加载
      final p2 = await SlotPrefs.load();
      expect(p2.indexOf(2, 3, 4), 1, reason: '重启后必须记住用户的选择');
    });

    test('★ 关键：按「时段槽位」记忆，不同周次共享同一选择', () async {
      final p = await SlotPrefs.load();
      // 周二 3-4 节选择了第 2 门
      await p.setChoice(2, 3, 4, 1);

      // 第 5 周、第 7 周、第 13 周的「周二 3-4 节」都应读到这个选择
      // —— 因为 key 不含周次，这正是"跨周同步"的实现基础
      expect(p.indexOf(2, 3, 4), 1);
      expect(p.indexOf(2, 3, 4), 1);
      expect(p.indexOf(2, 3, 4), 1);
    });

    test('不同节次互不影响', () async {
      final p = await SlotPrefs.load();
      await p.setChoice(2, 3, 4, 1);
      await p.setChoice(4, 1, 2, 0);
      expect(p.indexOf(2, 3, 4), 1);
      expect(p.indexOf(4, 1, 2), 0);
    });

    test('不同星期互不影响', () async {
      final p = await SlotPrefs.load();
      await p.setChoice(2, 3, 4, 1);
      expect(p.indexOf(3, 3, 4), 0, reason: '周三没设置过，应是默认 0');
    });

    test('clear 清空', () async {
      final p = await SlotPrefs.load();
      await p.setChoice(2, 3, 4, 1);
      await p.clear();
      expect(p.indexOf(2, 3, 4), 0);
      expect(p.count, 0);
    });

    test('存储损坏不会崩（容错）', () async {
      SharedPreferences.setMockInitialValues({
        'conflict_slot_choice_v1': '这不是合法 JSON {{{',
      });
      final p = await SlotPrefs.load();
      expect(p.indexOf(2, 3, 4), 0, reason: '损坏数据应回退为默认值而不是抛异常');
    });

    test('slotKey 格式固定（避免改坏兼容性）', () {
      expect(slotKey(1, 7, 8), '1-7-8');
      expect(slotKey(7, 9, 10), '7-9-10');
    });
  });

  group('safeSlotIndex 下标容错', () {
    test('正常范围直接返回', () {
      expect(safeSlotIndex(0, 3), 0);
      expect(safeSlotIndex(2, 3), 2);
    });

    test('越界收敛到边界（课程增删后不崩）', () {
      expect(safeSlotIndex(5, 3), 2);
      expect(safeSlotIndex(-1, 3), 0);
    });

    test('空簇返回 0', () {
      expect(safeSlotIndex(0, 0), 0);
    });
  });
}
