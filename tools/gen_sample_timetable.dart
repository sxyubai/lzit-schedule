/// 从教务系统原始响应生成「已解析的课表 JSON」测试样本
///
/// 为什么要这个脚本：`tools/samples/timetable_2026_2027_1.json` 是**测试样本**，
/// 由 `sample_kb_api.json`（真实接口响应）转换而来。样本一旦丢失或过期，
/// 用它重新生成即可 —— **不要手写 JSON**，字段名/结构一定会写错。
///
/// 生成的格式与 App 里「从教务系统导入」走的是同一条链路（parseZfResponse），
/// 所以样本同时也验证了导入路径本身。
///
///     dart run tools/gen_sample_timetable.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/services/timetable_parser.dart';

void main() {
  final src = File('tools/samples/sample_kb_api.json');
  if (!src.existsSync()) {
    stderr.writeln('找不到 ${src.path}');
    exit(1);
  }
  final raw = jsonDecode(src.readAsStringSync()) as Map<String, dynamic>;
  final parsed = parseZfResponse(raw);

  final tt = Timetable(
    id: 'jwglxt-2026-2027-1',
    name: '大四上',
    semesterName: parsed.semesterName,
    xnm: parsed.xnm,
    xqm: parsed.xqm,
    startDate: DateTime(2026, 8, 24), // 第 1 周周一
    totalWeeks: 20,
    sectionsPerDay: 10,
    sectionTimes: lzhitSouthPreset().times,
    courses: parsed.courses,
    unscheduled: parsed.unscheduled
        .map((u) => UnscheduledCourse(
              name: u.name,
              weeks: u.weeks,
              teacher: u.teacher,
              credits: u.credits,
              kindMark: u.kindMark,
              retake: u.retake,
            ))
        .toList(),
    student: StudentInfo(
      xh: parsed.xh,
      xm: parsed.xm,
      className: parsed.className,
      major: parsed.major,
      grade: parsed.grade,
    ),
  );

  final out = File('tools/samples/timetable_2026_2027_1.json');
  out.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(tt.toJson()),
  );

  stdout.writeln('课程: ${tt.courses.length} 门（含 '
      '${tt.courses.fold<int>(0, (a, c) => a + c.slots.length)} 个时段）');
  stdout.writeln('无固定时段: ${tt.unscheduled.length} 门');
  for (final u in tt.unscheduled) {
    stdout.writeln('  ${u.name.padRight(24)} ${u.weeks.padRight(10)} '
        '${u.kindMark.padRight(5)} 重修=${u.retake}');
  }
  stdout.writeln('-> ${out.path}');
}
