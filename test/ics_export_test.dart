/// ICS 导出测试
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/services/ics_export.dart';

import 'test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Timetable tt;

  setUpAll(() {
    tt = Timetable.fromJson(loadSampleJson('timetable_2026_2027_1.json'));
  });

  test('课表可解析（真实样本自检）', () {
    expect(tt.courses.length, 8);
    expect(tt.student.xm, '黄之程');
    expect(tt.semesterName, '2026-2027-1');
    expect(tt.sectionTimes.length, 10);
  });

  test('事件数 = 所有时段的周次总和', () {
    final expected = tt.courses
        .expand((c) => c.slots)
        .fold<int>(0, (a, s) => a + s.weeks.length);
    final ics = IcsExport.generate(tt);
    final events = 'BEGIN:VEVENT'.allMatches(ics).length;
    expect(events, expected);
    expect(events, greaterThan(50)); // 真实数据约 68 个
  });

  test('ICS 结构完整', () {
    final ics = IcsExport.generate(tt);
    expect(ics.startsWith('BEGIN:VCALENDAR'), isTrue);
    expect(ics.trimRight().endsWith('END:VCALENDAR'), isTrue);
    expect('BEGIN:VEVENT'.allMatches(ics).length,
        'END:VEVENT'.allMatches(ics).length);
    expect(ics.contains('VERSION:2.0'), isTrue);
    expect(ics.contains('BEGIN:VALARM'), isTrue);
  });

  test('时间点正确：第1周周一 7-8节（15:55-17:30 北京时间 = 07:55-09:30Z）', () {
    final ics = IcsExport.generate(tt);
    // 物理实验B 第 1 周在周一 7-8 节
    expect(ics.contains('DTSTART:20260831T075500Z'), isTrue,
        reason: '第1周周一7-8节应导出为 20260831T075500Z');
    expect(ics.contains('DTEND:20260831T093000Z'), isTrue,
        reason: '7-8节结束 17:30 北京时间 = 09:30Z');
  });

  test('时间点正确：1-2 节 08:30-10:05 北京时间 = 00:30-02:05Z', () {
    final ics = IcsExport.generate(tt);
    // Python程序设计B 第 3 周周一 1-2 节 -> 2026-09-14
    expect(ics.contains('DTSTART:20260914T003000Z'), isTrue);
    expect(ics.contains('DTEND:20260914T020500Z'), isTrue);
  });

  test('第 1 周的事件没有被漏掉', () {
    final ics = IcsExport.generate(tt);
    final week1Slots = tt.courses
        .expand((c) => c.slots)
        .where((s) => s.weeks.contains(1))
        .length;
    expect(week1Slots, greaterThan(0));
    final starts = RegExp(r'DTSTART:(\S+)').allMatches(ics).map((m) => m.group(1)!).toList();
    // 第 1 周 = 2026-08-31 ~ 2026-09-06
    final week1 = starts.where((s) => s.startsWith('20260831') ||
        s.startsWith('20260901') || s.startsWith('20260902') ||
        s.startsWith('20260903') || s.startsWith('20260904') ||
        s.startsWith('20260905') || s.startsWith('20260906')).length;
    expect(week1, greaterThan(0), reason: '第1周应有事件');
  });

  test('事件里有课程名与教室', () {
    final ics = IcsExport.generate(tt);
    expect(ics.contains('SUMMARY:'), isTrue);
    expect(ics.contains('Python程序设计B'), isTrue);
    expect(ics.contains('1教408'), isTrue);
    expect(ics.contains('LOCATION:南校区'), isTrue);
  });

  test('ICS 转义：分号与逗号', () {
    final ics = IcsExport.generate(tt);
    // 教师 "潘记海,谭敏" 里的逗号必须转义成 \,
    expect(ics.contains('\\,'), isTrue);
  });

  test('UID 唯一（同一时段不同周次不能撞号）', () {
    final ics = IcsExport.generate(tt);
    final uids = RegExp(r'UID:(\S+)').allMatches(ics).map((m) => m.group(1)).toList();
    expect(uids.length, uids.toSet().length);
  });
}
