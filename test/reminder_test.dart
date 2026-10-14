/// 上课提醒调度测试
///
/// planNotifications 是纯时间计算，最容易算错（周次映射、提前量、过去时间过滤），
/// 必须用确定的日期锁死。
///
/// 日期锚点（已实测确认）：
///   学期起始 2026-08-24 = 第 1 周周一
///   第 6 周周一 = 2026-09-28
///   第 7 周周一 = 2026-10-05
///   第 7 周周六 = 2026-10-10
///   now = 2026-10-03（周六）→ 属于第 6 周
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/services/reminder_service.dart';

Timetable ttWith(List<Course> courses) {
  final preset = lzhitSouthPreset();
  return Timetable(
    id: 't',
    name: '测试',
    startDate: DateTime(2026, 8, 24),
    totalWeeks: 20,
    sectionsPerDay: preset.sectionsPerDay,
    sectionTimes: preset.times,
    courses: courses,
  );
}

Course mk(String name, int weekday, int start, int end, Set<int> weeks,
    {String room = '1教101', String teacher = '张老师', String campus = '南校区'}) {
  return Course(
    id: name,
    name: name,
    slots: [
      CourseSlot(
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        room: room,
        teacher: teacher,
        campus: campus,
      ),
    ],
  );
}

void main() {
  final now = DateTime(2026, 10, 3, 12, 0); // 第 6 周 周六

  group('日期锚点（先确认基础，避免后面对错周）', () {
    test('学期起始日是第 1 周周一', () {
      final tt = ttWith([]);
      expect(tt.startDate.weekday, DateTime.monday);
      expect(tt.weekOf(DateTime(2026, 8, 24)), 1);
      expect(tt.weekOf(DateTime(2026, 8, 30)), 1); // 周日仍属第 1 周
      expect(tt.weekOf(DateTime(2026, 8, 31)), 2);
      expect(tt.weekOf(now), 6); // 10/3 属于第 6 周
    });
  });

  group('planNotifications 时间计算', () {
    test('已经过去的课不排（now 之后的才排）', () {
      // 第 6 周周一 = 9/28，早于 now(10/3)，不该排 —— 否则装好 App 会立刻弹一堆过期提醒
      final tt = ttWith([mk('操作系统', 1, 1, 2, {6})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      expect(plans, isEmpty, reason: '第 6 周周一(9/28)已过去');
    });

    test('第 7 周的课 → 提醒落在 10/5，且提前量正确', () {
      final tt = ttWith([mk('操作系统', 1, 1, 2, {7})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);

      expect(plans.length, 1);
      expect(plans.first.when.month, 10);
      expect(plans.first.when.day, 5, reason: '第 7 周周一 = 10/5');
      expect(plans.first.when.hour, 8);
      expect(plans.first.when.minute, 15, reason: '08:30 提前 15 分钟 = 08:15');
    });

    test('提前量可配：提前 30 分钟 → 08:00', () {
      final tt = ttWith([mk('操作系统', 1, 1, 2, {7})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 30);
      expect(plans.first.when.hour, 8);
      expect(plans.first.when.minute, 0);
    });

    test('规划窗口外的课不排（第 16 周的课在第 6 周不排）', () {
      final tt = ttWith([mk('形势与政策', 5, 1, 2, {16})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      expect(plans, isEmpty, reason: '只规划未来 4 周');
    });

    test('每周都上的课 → 4 周窗口排出 4 次', () {
      // 第 6~9 周，但第 6 周那次（9/28）已过去 → 实际 3 次
      final tt = ttWith([mk('高等数学', 1, 1, 2, {6, 7, 8, 9, 10})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      expect(plans.length, 3, reason: '第 7/8/9 周（10/5、10/12、10/19）；第 6 周已过去');
    });

    test('单双周正确过滤（只排单周）', () {
      final tt = Timetable(
        id: 't2',
        name: '测试',
        startDate: DateTime(2026, 8, 24),
        totalWeeks: 20,
        sectionTimes: lzhitSouthPreset().times,
        // 第 7、9 周（单周）周一 7-8 节
        courses: [mk('实验课', 1, 7, 8, {7, 9})],
      );
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      final days = plans.map((p) => p.when.day).toSet();
      expect(days.contains(5), isTrue, reason: '第 7 周周一 = 10/5');
      expect(days.contains(19), isTrue, reason: '第 9 周周一 = 10/19');
      expect(days.contains(12), isFalse, reason: '第 8 周是双周，不该排');
    });

    test('周末的课也排（周六有课）', () {
      // 第 7 周周六 = 10/10；9-10 节 19:30 → 提醒 19:15
      final tt = ttWith([mk('慕课', 6, 9, 10, {7})]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      expect(plans.length, 1);
      expect(plans.first.when.day, 10, reason: '第 7 周周六 = 10/10');
      expect(plans.first.when.hour, 19);
      expect(plans.first.when.minute, 15);
    });

    test('通知文案包含课程名、节次、教室、教师', () {
      final tt = ttWith([mk('操作系统', 1, 1, 2, {7}, room: '1实502', teacher: '王继军')]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      final p = plans.first;
      expect(p.title, contains('操作系统'));
      expect(p.title, contains('15'));
      expect(p.body, contains('第 1-2 节'));
      expect(p.body, contains('1实502'));
      expect(p.body, contains('王继军'));
    });

    test('多条提醒按时间升序', () {
      final tt = ttWith([
        mk('周三课', 3, 1, 2, {7}),
        mk('周一课', 1, 1, 2, {7}),
        mk('周二课', 2, 3, 4, {7}),
      ]);
      // 窗口覆盖第 6~7 周（now 在第 6 周，课在第 7 周）
      final plans = planNotifications(tt, now: now, weeksAhead: 2, minutesBefore: 15);
      expect(plans.length, 3);
      for (var i = 1; i < plans.length; i++) {
        expect(plans[i].when.isAfter(plans[i - 1].when), isTrue,
            reason: '第 $i 条应晚于前一条');
      }
    });

    test('通知 id 唯一（否则会互相覆盖）', () {
      final tt = ttWith([
        mk('A课', 1, 1, 2, {7, 8, 9}),
        mk('B课', 2, 3, 4, {7, 8, 9}),
      ]);
      final plans = planNotifications(tt, now: now, weeksAhead: 4, minutesBefore: 15);
      final ids = plans.map((p) => p.id).toList();
      expect(ids.length, 6, reason: '两门课 × 三周');
      expect(ids.length, ids.toSet().length);
    });

    test('空课表不报错', () {
      expect(planNotifications(ttWith([]), now: now, weeksAhead: 4), isEmpty);
    });

    test('节次时间表缺失时跳过（不崩）', () {
      final tt = Timetable(
        id: 't3',
        name: '测试',
        startDate: DateTime(2026, 8, 24),
        sectionTimes: const [],
        courses: [mk('课', 1, 1, 2, {7})],
      );
      expect(planNotifications(tt, now: now, weeksAhead: 4), isEmpty);
    });
  });
}
