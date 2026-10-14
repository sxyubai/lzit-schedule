/// 冲突分组测试
///
/// 背景：课表里同一时段多门课如果直接叠放，后画的会盖住先画的，
/// 用户看不到被盖的那门 —— 必须并排显示，而并排的前提是正确分簇。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/services/slot_cluster.dart';

Course course(String name, {Set<int>? weeks, int weekday = 1, int start = 1, int end = 2, String room = ''}) {
  return Course(
    id: name,
    name: name,
    slots: [
      CourseSlot(
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks ?? {1},
        room: room,
      ),
    ],
  );
}

SlotItem item(String name, int start, int end, {Set<int>? weeks}) {
  final c = course(name, start: start, end: end, weeks: weeks);
  return (course: c, slot: c.slots.first);
}

void main() {
  group('clusterSlots 时间冲突分簇', () {
    test('空列表', () {
      expect(clusterSlots([]), isEmpty);
    });

    test('单个时段 → 一簇', () {
      final r = clusterSlots([item('A', 1, 2)]);
      expect(r.length, 1);
      expect(r.first.length, 1);
    });

    test('不重叠（1-2 与 3-4）→ 两簇', () {
      final r = clusterSlots([item('A', 1, 2), item('B', 3, 4)]);
      expect(r.length, 2);
      expect(r[0].length, 1);
      expect(r[1].length, 1);
    });

    test('完全重叠（都是 7-8）→ 一簇三张', () {
      final r = clusterSlots([item('A', 7, 8), item('B', 7, 8), item('C', 7, 8)]);
      expect(r.length, 1);
      expect(r.first.length, 3);
    });

    test('部分重叠（1-2 与 2-3 共享第 2 节）→ 一簇', () {
      final r = clusterSlots([item('A', 1, 2), item('B', 2, 3)]);
      expect(r.length, 1);
      expect(r.first.length, 2);
    });

    test('一个长时段包住两个短时段 → 一簇', () {
      final r = clusterSlots([item('长', 4, 6), item('短1', 4, 4), item('短2', 6, 6)]);
      expect(r.length, 1);
      expect(r.first.length, 3);
    });

    test('链式重叠（1-2, 2-3, 3-4）→ 全部同簇（区间连通）', () {
      final r = clusterSlots([item('A', 1, 2), item('B', 2, 3), item('C', 3, 4)]);
      expect(r.length, 1);
      expect(r.first.length, 3);
    });

    test('相邻但不重叠（1-2 与 3-4，2+1=3 也算相邻）→ 两簇', () {
      // 关键边界：结束节 2、下一段起始 3，二者不相交
      final r = clusterSlots([item('A', 1, 2), item('B', 3, 4)]);
      expect(r.length, 2);
    });

    test('乱序输入也能正确分簇（内部会排序）', () {
      final r = clusterSlots([item('C', 9, 10), item('A', 1, 2), item('B', 1, 2)]);
      expect(r.length, 2);
      expect(r[0].length, 2); // 1-2 的两门
      expect(r[0].first.slot.startSection, 1);
      expect(r[1].first.slot.startSection, 9);
    });

    test('真实场景：物理实验B 周一 7-8 节三条记录 → 并排三张', () {
      // 用户真实数据：同一节次有 3 条（不同教室/教师），其中两条在第 2、7 周重叠
      final r = clusterSlots([
        item('物理实验B', 7, 8, weeks: {1}),            // 教201 潘记海,谭敏
        item('物理实验B', 7, 8, weeks: {2, 3, 4, 7}),   // 1实331 潘记海
        item('物理实验B', 7, 8, weeks: {2, 3, 4, 5, 7}) // 1实331 谭敏
      ]);
      expect(r.length, 1, reason: '三条同节次必须归为一簇，否则会互相覆盖');
      expect(r.first.length, 3);
    });

    test('复杂一天：多个独立冲突簇', () {
      final r = clusterSlots([
        item('A', 1, 2),
        item('B', 1, 2),
        item('C', 5, 6),
        item('D', 9, 10),
        item('E', 9, 10),
        item('F', 9, 10),
      ]);
      expect(r.length, 3);
      expect(r[0].length, 2);
      expect(r[1].length, 1);
      expect(r[2].length, 3);
    });
  });
}
