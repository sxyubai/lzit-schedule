/// 解析器测试：验证 Dart 侧与 Python 侧解析结果一致
///
/// 样本来自柳州工学院正方教务系统「学生课表查询」接口的真实响应。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/services/timetable_parser.dart';

import 'test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('周次解析 parseWeeks', () {
    test('连续区间', () {
      expect(parseWeeks('1-5周'), {1, 2, 3, 4, 5});
    });

    test('单周', () {
      expect(parseWeeks('7-11周(单)'), {7, 9, 11});
    });

    test('双周', () {
      expect(parseWeeks('2-6周(双)'), {2, 4, 6});
    });

    test('单周写法', () {
      expect(parseWeeks('第7周'), {7});
    });

    test('混合多段', () {
      expect(parseWeeks('1-5周,7-11周(单),12-13周'), {1, 2, 3, 4, 5, 7, 9, 11, 12, 13});
    });

    test('双周加后续区间（真实数据）', () {
      // 概率论与数理统计：2-6周(双),7-15周
      final weeks = parseWeeks('2-6周(双),7-15周');
      expect(weeks.containsAll({2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}), isTrue);
      expect(weeks.contains(3), isFalse);
      expect(weeks.contains(5), isFalse);
    });

    test('多段不连续（线性代数A）', () {
      final weeks = parseWeeks('3-4周,6-13周,15-16周');
      expect(weeks.length, 2 + 8 + 2);
      expect(weeks.contains(5), isFalse);
      expect(weeks.contains(14), isFalse);
    });
  });

  group('节次解析 parseSections', () {
    test('区间', () => expect(parseSections('1-2'), (start: 1, end: 2)));
    test('单节', () => expect(parseSections('7'), (start: 7, end: 7)));
    test('带节字', () => expect(parseSections('9-10节'), (start: 9, end: 10)));
  });

  group('正方接口响应解析', () {
    late ZfTimetableResponse resp;

    setUpAll(() async {
      resp = parseZfResponse(loadSampleJson('sample_kb_api.json'));
    });

    test('学生信息', () {
      expect(resp.xh, '20222441');
      expect(resp.xm, '黄之程');
      expect(resp.className, '软件232');
      expect(resp.major, '软件工程');
      expect(resp.grade, '2023');
    });

    test('学年学期', () {
      expect(resp.xnm, '2026');
      expect(resp.xqm, '3');
      expect(resp.semesterName, '2026-2027-1');
    });

    test('课程数与时段数（与 Python 转换器一致：8 门 / 25 时段）', () {
      expect(resp.courses.length, 8);
      final slots = resp.courses.fold<int>(0, (a, c) => a + c.slots.length);
      expect(slots, 25);
    });

    test('星期几被正确解析（纯文本复制会丢这一列）', () {
      final allWeekdays = resp.courses
          .expand((c) => c.slots)
          .map((s) => s.weekday)
          .toSet();
      // 真实数据覆盖周一~周六
      expect(allWeekdays.containsAll({1, 2, 3, 4, 5, 6}), isTrue);
      // 周日没有课
      expect(allWeekdays.contains(7), isFalse);
    });

    test('重修课被保留（用户要求照实导入）', () {
      final retakeNames = resp.courses.map((c) => c.name).toSet();
      expect(retakeNames.contains('概率论与数理统计'), isTrue);
      expect(retakeNames.contains('线性代数A'), isTrue);
      expect(retakeNames.contains('毛泽东思想和中国特色社会主义理论体系概论'), isTrue);
    });

    test('无固定时段的实践课进入 unscheduled', () {
      final names = resp.unscheduled.map((u) => u.name).toList();
      expect(names.contains('毕业实习'), isTrue);
      expect(names.contains('软件开发综合实训'), isTrue);
      expect(names.contains('离散数学'), isTrue);
    });

    test('sjkList 的类型标记与重修标记不能丢', () {
      // 这两个信息都不在 kcmc 里：类型符号藏在 sjkcgs（"操作系统○卢光云(共8周)/6-13周"），
      // 重修看 cxbj/cxbjmc。曾经漏解过 → 导入后实践课面板上没有任何标记。
      expect(resp.unscheduled.length, 9);

      final byKey = {
        for (final u in resp.unscheduled) '${u.name}|${u.kindMark}': u,
      };
      expect(byKey.containsKey('毕业实习|实践'), isTrue, reason: 'sjkcgs 里的 ●');
      expect(byKey.containsKey('软件开发综合实训|实践'), isTrue);
      expect(byKey.containsKey('操作系统|理论'), isTrue, reason: 'sjkcgs 里的 ○');
      expect(byKey.containsKey('操作系统|上机'), isTrue, reason: 'sjkcgs 里的 ▲');
      expect(byKey.containsKey('计算机网络|上机'), isTrue);

      // 重修：cxbj=1 / cxbjmc='重修'
      expect(byKey['操作系统|理论']!.retake, isTrue);
      expect(byKey['离散数学|理论']!.retake, isTrue);
      expect(byKey['计算机网络|上机']!.retake, isTrue);
      expect(byKey['毕业实习|实践']!.retake, isFalse, reason: '实习不是重修');

      // 周次范围照实带过来
      expect(byKey['毕业实习|实践']!.weeks, '11-14周');
      expect(byKey['认识实习|实践']!.weeks, '第17周');
    });

    test('教室与教师', () {
      final py = resp.courses.firstWhere((c) => c.name == 'Python程序设计B');
      final rooms = py.slots.map((s) => s.room).toSet();
      expect(rooms.contains('1教408'), isTrue);
      expect(py.slots.first.teacher, '陈稳中');
      expect(py.credits, 2);
    });

    test('理论/上机被区分为不同课程条目', () {
      final pyKinds = resp.courses
          .where((c) => c.name == 'Python程序设计B')
          .map((c) => c.kindMark)
          .toSet();
      expect(pyKinds.contains('理论'), isTrue);
      expect(pyKinds.contains('上机'), isTrue);
    });
  });
}
