/// 删除课程 / 删除单个时段
///
/// 删除是破坏性操作，必须保证：删对了对象、没误伤别的课、原对象没被改坏。
/// 这些用模型层的纯函数测最准（界面只负责问一句"确定吗"）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';

Timetable build({
  required List<Course> courses,
  List<TimetableEvent> events = const [],
  List<UnscheduledCourse> unscheduled = const [],
}) {
  final preset = lzhitSouthPreset();
  return Timetable(
    id: 't',
    name: '测试',
    startDate: DateTime(2026, 8, 24),
    totalWeeks: 20,
    sectionsPerDay: preset.sectionsPerDay,
    sectionTimes: preset.times,
    courses: courses,
    events: events,
    unscheduled: unscheduled,
  );
}

CourseSlot slot(int weekday, int from, int to, [Set<int>? weeks]) => CourseSlot(
      weekday: weekday,
      startSection: from,
      endSection: to,
      weeks: weeks ?? {1, 2, 3},
      room: '1教408',
      teacher: '陈稳中',
    );

void main() {
  group('removeCourse：删掉整门课', () {
    test('目标课消失，其它课原样保留', () {
      final a = Course(id: 'a', name: '高等数学', slots: [slot(1, 1, 2)]);
      final b = Course(id: 'b', name: '计算机网络', slots: [slot(2, 3, 4)]);
      final tt = build(courses: [a, b]);

      final after = tt.removeCourse(a);

      expect(after.courses, hasLength(1));
      expect(after.courses.single.name, '计算机网络');
      expect(identical(after.courses.single, b), isTrue);
    });

    test('一门课的多个时段一起消失', () {
      final a = Course(id: 'a', name: '高等数学', slots: [slot(1, 1, 2), slot(3, 5, 6)]);
      final tt = build(courses: [a]);

      expect(tt.removeCourse(a).courses, isEmpty);
    });

    test('删不存在的课 → 什么都没变', () {
      final a = Course(id: 'a', name: '高等数学', slots: [slot(1, 1, 2)]);
      final ghost = Course(id: 'ghost', name: '幽灵课', slots: [slot(1, 1, 2)]);
      final tt = build(courses: [a]);

      expect(tt.removeCourse(ghost).courses, hasLength(1));
    });

    test('原对象不被修改（只读模型）', () {
      final a = Course(id: 'a', name: '高等数学', slots: [slot(1, 1, 2)]);
      final tt = build(courses: [a]);

      tt.removeCourse(a);

      expect(tt.courses, hasLength(1), reason: 'removeCourse 必须返回新对象');
    });
  });

  group('removeSlotOf：只删一个时段', () {
    test('多时段课：只少一个时段，课还在', () {
      final s1 = slot(1, 1, 2);
      final s2 = slot(3, 5, 6);
      final a = Course(id: 'a', name: '高等数学', slots: [s1, s2]);
      final tt = build(courses: [a]);

      final after = tt.removeSlotOf(a, s1);

      expect(after.courses, hasLength(1));
      final kept = after.courses.single.slots;
      expect(kept, hasLength(1));
      expect(identical(kept.single, s2), isTrue);
      expect(after.courses.single.name, '高等数学');
    });

    test('① 删掉最后一个时段 → 整门课一起消失（不留空壳）', () {
      final s1 = slot(1, 1, 2);
      final a = Course(id: 'a', name: '只有一节', slots: [s1]);
      final tt = build(courses: [a]);

      final after = tt.removeSlotOf(a, s1);

      expect(after.courses, isEmpty,
          reason: '留下一个 slots 为空的课程，界面上看不见又删不掉');
    });

    test('两个时段删到最后一个 → 第二次删除让整门课消失', () {
      final s1 = slot(1, 1, 2);
      final s2 = slot(3, 5, 6);
      final a = Course(id: 'a', name: '两节的课', slots: [s1, s2]);
      final tt = build(courses: [a]);

      final once = tt.removeSlotOf(a, s1);
      final twice = once.removeSlotOf(once.courses.single, s2);

      expect(once.courses, hasLength(1));
      expect(twice.courses, isEmpty);
    });

    test('别的课完全不受影响', () {
      final s1 = slot(1, 1, 2);
      final s2 = slot(3, 5, 6);
      final a = Course(id: 'a', name: '高等数学', slots: [s1, s2]);
      final b = Course(id: 'b', name: '计算机网络', slots: [slot(2, 3, 4)]);
      final tt = build(courses: [a, b]);

      final after = tt.removeSlotOf(a, s1);

      expect(after.courses, hasLength(2));
      final other = after.courses.firstWhere((c) => c.name == '计算机网络');
      expect(identical(other, b), isTrue, reason: '别的课连对象都不该换');
    });

    test('两条内容完全相同的时段，只删被点的那一条', () {
      // 接口重复返回同一格时会出现这种情况：按值删会一次删掉两条
      final s1 = slot(1, 1, 2);
      final s2 = slot(1, 1, 2);
      final a = Course(id: 'a', name: '重复格', slots: [s1, s2]);
      final tt = build(courses: [a]);

      final after = tt.removeSlotOf(a, s1);

      expect(after.courses.single.slots, hasLength(1));
      expect(identical(after.courses.single.slots.single, s2), isTrue);
    });

    test('传入不属于这门课的时段 → 原样返回', () {
      final a = Course(id: 'a', name: '高等数学', slots: [slot(1, 1, 2)]);
      final tt = build(courses: [a]);

      final after = tt.removeSlotOf(a, slot(5, 9, 10));

      expect(after.courses.single.slots, hasLength(1));
    });

    test('不碰事件和无固定时段课程', () {
      final s1 = slot(1, 1, 2);
      final a = Course(id: 'a', name: '高等数学', slots: [s1, slot(3, 5, 6)]);
      final tt = build(
        courses: [a],
        events: [
          TimetableEvent(
            id: 'e1',
            title: '开会',
            date: DateTime(2026, 10, 7),
            startSection: 3,
            endSection: 4,
          ),
        ],
        unscheduled: const [UnscheduledCourse(name: '毕业实习', kindMark: '实践')],
      );

      final after = tt.removeSlotOf(a, s1);

      expect(after.events, hasLength(1));
      expect(after.events.single.title, '开会');
      expect(after.unscheduled, hasLength(1));
      expect(after.unscheduled.single.kindMark, '实践');
    });

    test('删除后 JSON 往返仍然一致', () {
      final s1 = slot(1, 1, 2);
      final a = Course(id: 'a', name: '高等数学', slots: [s1, slot(3, 5, 6)]);
      final tt = build(courses: [a]);

      final after = tt.removeSlotOf(a, s1);
      final back = Timetable.fromJson(
          jsonDecode(jsonEncode(after.toJson())) as Map<String, dynamic>);

      expect(back.courses, hasLength(1));
      expect(back.courses.single.slots, hasLength(1));
      expect(back.courses.single.slots.single.startSection, 5);
    });
  });
}
