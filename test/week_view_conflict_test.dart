/// 周视图冲突卡片交互测试
///
/// 为什么不靠"adb 点屏幕"验证：截图坐标受 DPI、状态栏、面板高度多层影响，
/// 算错一次就会误判成"功能坏了"。widget test 直接模拟点击，精确且可重复。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/services/slot_cluster.dart';
import 'package:lzit_schedule/widgets/week_view.dart';

Timetable buildTimetable({required List<Course> courses}) {
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

/// 构造一门在指定星期/节次/周次上课的课
Course mk(String name, int weekday, int start, int end, Set<int> weeks) {
  return Course(
    id: name,
    name: name,
    slots: [
      CourseSlot(
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        room: '1教101',
        teacher: '某老师',
      ),
    ],
  );
}

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 2200,
          child: child,
        ),
      ),
    );

void main() {
  group('冲突卡片：角标 + 点击切换', () {
    testWidgets('无冲突时不显示角标', (tester) async {
      final tt = buildTimetable(courses: [mk('单独课', 1, 1, 2, {7})]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.text('单独课'), findsOneWidget);
      // 角标形如 "1/2"（个位数/个位数）；表头日期形如 "10/5"（两位数月份）。
      // 用严格形式判断，避免把日期误认成角标。
      final badgePattern = RegExp(r'^\d/\d$');
      final badges = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => badgePattern.hasMatch(s))
          .toList();
      expect(badges, isEmpty, reason: '没有冲突就不该有 N/M 角标');
    });

    testWidgets('两门课冲突 → 只画一张 + 角标 1/2', (tester) async {
      final tt = buildTimetable(courses: [
        mk('大学物理B', 2, 3, 4, {7}),
        mk('线性代数A', 2, 3, 4, {7}),
      ]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget, reason: '应显示角标 1/2');
      // 默认显示第一门（按起始节次、同节次时按原始顺序）
      expect(find.text('大学物理B'), findsOneWidget);
      expect(find.text('线性代数A'), findsNothing, reason: '冲突时只画一张，不该同时出现两门');
    });

    testWidgets('点击冲突卡片 → 触发 onSelectConflict 回调（带簇和星期）', (tester) async {
      final tt = buildTimetable(courses: [
        mk('大学物理B', 2, 3, 4, {7}),
        mk('线性代数A', 2, 3, 4, {7}),
      ]);
      List<SlotItem>? gotCluster;
      int? gotWeekday;
      int? gotSelected;

      await tester.pumpWidget(wrap(WeekView(
        timetable: tt,
        week: 7,
        sectionHeight: 60,
        onSelectConflict: (cluster, weekday, selected) {
          gotCluster = cluster;
          gotWeekday = weekday;
          gotSelected = selected;
        },
        onTapCourse: (_, _) => fail('冲突时应走 onSelectConflict，而不是详情'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('大学物理B'));
      await tester.pumpAndSettle();

      expect(gotCluster, isNotNull, reason: '点冲突卡片必须触发选择面板回调');
      expect(gotCluster!.length, 2);
      expect(gotWeekday, 2);
      expect(gotSelected, 0);
    });

    testWidgets('indexOfSlot 返回 1 → 显示第二门 + 角标 2/2', (tester) async {
      final tt = buildTimetable(courses: [
        mk('大学物理B', 2, 3, 4, {7}),
        mk('线性代数A', 2, 3, 4, {7}),
      ]);
      await tester.pumpWidget(wrap(WeekView(
        timetable: tt,
        week: 7,
        sectionHeight: 60,
        indexOfSlot: (_, _, _) => 1, // 用户之前选了第二门
      )));
      await tester.pumpAndSettle();

      expect(find.text('线性代数A'), findsOneWidget, reason: '应显示用户记住的那一门');
      expect(find.text('大学物理B'), findsNothing);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('indexOfSlot 越界 → 收敛到最后一项而不崩', (tester) async {
      final tt = buildTimetable(courses: [
        mk('A课', 2, 3, 4, {7}),
        mk('B课', 2, 3, 4, {7}),
      ]);
      await tester.pumpWidget(wrap(WeekView(
        timetable: tt,
        week: 7,
        sectionHeight: 60,
        indexOfSlot: (_, _, _) => 99,
      )));
      await tester.pumpAndSettle();
      expect(find.text('B课'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('三门课冲突 → 角标 1/3，只有一张卡', (tester) async {
      final tt = buildTimetable(courses: [
        mk('甲', 3, 1, 2, {7}),
        mk('乙', 3, 1, 2, {7}),
        mk('丙', 3, 1, 2, {7}),
      ]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsNothing);
      expect(find.text('丙'), findsNothing);
    });

    testWidgets('同名课的多条记录同样走角标（不再并排）', (tester) async {
      // 用户真实数据：物理实验B 周一 7-8 节有 3 条不同教室/教师的记录，
      // 各自周次不同（第 1 周那条不在第 7 周）
      final tt = buildTimetable(courses: [
        mk('物理实验B', 1, 7, 8, {1}),                 // 仅第 1 周（教201）
        mk('物理实验B', 1, 7, 8, {1, 2, 3, 4, 7}),     // 潘记海
        mk('物理实验B', 1, 7, 8, {1, 2, 3, 4, 5, 7}),  // 谭敏
      ]);

      // 第 1 周：三条都在 → 角标 1/3
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 1, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget, reason: '第 1 周三条记录都在，角标应为 1/3');
      expect(find.text('物理实验B'), findsOneWidget, reason: '只画一张，不并排');

      // 第 7 周：只有两条 → 角标 1/2
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget, reason: '第 7 周只有两条记录，角标应为 1/2');
      expect(find.text('物理实验B'), findsOneWidget);
    });

    testWidgets('非本周的课不画（周次过滤正确）', (tester) async {
      final tt = buildTimetable(courses: [mk('只在第3周', 1, 1, 2, {3})]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 9, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(find.text('只在第3周'), findsNothing);
    });
  });
}
