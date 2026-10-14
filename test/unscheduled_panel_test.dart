/// 无固定时段课程面板测试
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/widgets/unscheduled_panel.dart';

import 'test_data.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnscheduledPanel 面板', () {
    const items = [
      UnscheduledCourse(name: '毕业实习', weeks: '11-14周', teacher: '谭超,唐爱龙', credits: '4', kindMark: '实践'),
      UnscheduledCourse(name: '离散数学', weeks: '1-12周', teacher: '周磊', credits: '3.0', kindMark: '理论', retake: true),
      UnscheduledCourse(name: '软件开发综合实训', weeks: '1-8周', teacher: '谭超', credits: '8', kindMark: '实践'),
    ];

    testWidgets('空列表不占空间', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: [])));
      expect(find.text('无固定时间课程'), findsNothing);
    });

    testWidgets('默认折叠：只显示摘要，不显示课程明细', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: items)));
      expect(find.text('无固定时间课程'), findsOneWidget);
      expect(find.text('3 门'), findsOneWidget, reason: '摘要应显示门数');
      // 折叠状态不该出现课程名
      expect(find.text('毕业实习'), findsNothing);
      expect(find.text('离散数学'), findsNothing);
    });

    testWidgets('点击展开：显示全部课程与周次/学分/教师', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: items)));
      await tester.tap(find.text('无固定时间课程'));
      await tester.pumpAndSettle();

      expect(find.text('毕业实习'), findsOneWidget);
      expect(find.text('离散数学'), findsOneWidget);
      expect(find.text('软件开发综合实训'), findsOneWidget);
      // 元信息
      expect(find.textContaining('11-14周'), findsOneWidget);
      expect(find.textContaining('4学分'), findsOneWidget);
      expect(find.textContaining('谭超,唐爱龙'), findsOneWidget);
    });

    testWidgets('重修课带「重修」标签', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: items)));
      await tester.tap(find.text('无固定时间课程'));
      await tester.pumpAndSettle();
      expect(find.text('重修'), findsOneWidget, reason: '只有离散数学是重修');
    });

    testWidgets('再次点击可折叠回去', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: items)));
      await tester.tap(find.text('无固定时间课程'));
      await tester.pumpAndSettle();
      expect(find.text('毕业实习'), findsOneWidget);

      await tester.tap(find.text('无固定时间课程'));
      await tester.pumpAndSettle();
      expect(find.text('毕业实习'), findsNothing);
    });

    testWidgets('摘要只显示门数（不显示学分合计）', (tester) async {
      await tester.pumpWidget(wrap(const UnscheduledPanel(items: items)));
      expect(find.text('3 门'), findsOneWidget);
      expect(find.textContaining('合计'), findsNothing, reason: '用户要求不显示学分合计');
    });
  });

  group('真实数据：课表 JSON 里的实践课', () {
    test('内置课表包含 9 门无固定时段课程', () async {
      final tt = Timetable.fromJson(loadSampleJson('timetable_2026_2027_1.json'));

      expect(tt.unscheduled.length, 9, reason: '正方 sjkList 共 9 条');
      final names = tt.unscheduled.map((e) => e.name).toSet();
      expect(names.contains('毕业实习'), isTrue);
      expect(names.contains('认识实习'), isTrue);
      expect(names.contains('软件开发综合实训'), isTrue);
      expect(names.contains('离散数学'), isTrue);
      expect(names.contains('演讲的艺术（智慧树网络教学）'), isTrue);

      // 重修标记应被识别（操作系统/离散数学/计算机网络 各有一条或多条）
      final retakes = tt.unscheduled.where((e) => e.retake).map((e) => e.name).toSet();
      expect(retakes.contains('离散数学'), isTrue);
      expect(retakes.contains('操作系统'), isTrue);
    });

    test('工程类标记解析正确', () async {
      final tt = Timetable.fromJson(loadSampleJson('timetable_2026_2027_1.json'));
      final byName = {for (final u in tt.unscheduled) '${u.name}|${u.kindMark}': u};

      expect(byName.containsKey('毕业实习|实践'), isTrue);
      expect(byName.containsKey('操作系统|理论'), isTrue);
      expect(byName.containsKey('操作系统|上机'), isTrue);
    });

    test('序列化往返不丢数据', () async {
      final tt = Timetable.fromJson(loadSampleJson('timetable_2026_2027_1.json'));
      final round = Timetable.fromJson(
          jsonDecode(jsonEncode(tt.toJson())) as Map<String, dynamic>);
      expect(round.unscheduled.length, tt.unscheduled.length);
      expect(round.unscheduled.first.name, tt.unscheduled.first.name);
      expect(round.startDate, tt.startDate);
    });
  });
}
