/// 生成一份"假课表"JSON，用于在模拟器上验证界面
///
/// 不手写 JSON —— 直接用项目自己的模型 `toJson()`，避免字段名/格式对不上。
/// 产物推到模拟器的 `<app 文档目录>/timetables/emu1.json` 即可生效。
///
///     dart run tools/gen_emu_fixture.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';

void main() {
  final preset = lzhitSouthPreset();
  final all = {for (var w = 1; w <= 20; w++) w};

  Course c(String id, String name, int wd, int s, int e, Set<int> weeks,
      String room, String teacher) {
    return Course(
      id: id,
      name: name,
      slots: [
        CourseSlot(
          weekday: wd,
          startSection: s,
          endSection: e,
          weeks: weeks,
          room: room,
          teacher: teacher,
        ),
      ],
    );
  }

  final tt = Timetable(
    id: 'emu1',
    name: '2026课表',
    semesterName: '2026-2027-1',
    startDate: DateTime(2026, 8, 24), // 第 1 周周一
    totalWeeks: 20,
    sectionsPerDay: preset.sectionsPerDay,
    sectionTimes: preset.times,
    courses: [
      c('c1', '高等数学', 1, 1, 2, all, '1教408', '陈稳中'),
      c('c2', '计算机网络', 2, 3, 4, {for (var w = 1; w <= 10; w++) w}, '2教201', '李老师'),
      c('c3', '操作系统', 3, 5, 6, {for (var w = 7; w <= 12; w++) w}, '2教305', '王老师'),
      // 只在 1~6 周上，第 8 周应该看不到（用来验证周次过滤）
      c('c4', '已经结课的课', 4, 7, 8, {for (var w = 1; w <= 6; w++) w}, '3教101', '赵老师'),
    ],
    unscheduled: const [
      UnscheduledCourse(
          name: '毕业实习', teacher: '谭超,唐爱龙', weeks: '11-14周',
          credits: '4', kindMark: '实践'),
      UnscheduledCourse(
          name: '操作系统', teacher: '卢光云', weeks: '6-13周',
          credits: '3.0', kindMark: '理论', retake: true),
      UnscheduledCourse(
          name: '操作系统', teacher: '卢光云', weeks: '14-17周',
          credits: '3', kindMark: '上机', retake: true),
      UnscheduledCourse(
          name: '演讲的艺术（智慧树网络教学）', teacher: '李颖,杨文涛', weeks: '1-16周',
          credits: '2.0', kindMark: '理论'),
    ],
    events: [
      TimetableEvent(
        id: 'ev1',
        title: '临时开会',
        date: DateTime(2026, 10, 15), // 第 8 周 周四
        startSection: 3,
        endSection: 4,
        location: '1教101',
      ),
    ],
  );

  // 输出到 tools/samples/（已被 .gitignore 覆盖）——不要在 tools/ 根目录留产物
  final out = File('tools/samples/emu_timetable.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(tt.toJson()),
  );
  stdout.writeln('已写出 ${out.absolute.path}');
  stdout.writeln('课程 ${tt.courses.length} 门 / 事件 ${tt.events.length} 个');
  stdout.writeln('周次覆盖：高数 ${tt.courses[0].slots.first.weeks.length} 周');
}
