/// 「今天」高亮测试
///
/// 需求：自动定位到当前周 + 高亮今天的列。
/// 高亮判断抽成了纯函数 isTodayColumn，这里把边界锁死。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/widgets/week_view.dart';

Timetable emptyTimetable() {
  final preset = lzhitSouthPreset();
  return Timetable(
    id: 't',
    name: '测试',
    startDate: DateTime(2026, 8, 24), // 周一
    totalWeeks: 20,
    sectionsPerDay: preset.sectionsPerDay,
    sectionTimes: preset.times,
    courses: const [],
  );
}

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 420, height: 2200, child: child)));

void main() {
  group('isTodayColumn 判断逻辑', () {
    test('正在看本周 + 该列就是今天 → 高亮', () {
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 5, column: 5), isTrue);
    });

    test('正在看本周但不是今天那列 → 不高亮', () {
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 5, column: 3), isFalse);
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 5, column: 6), isFalse);
    });

    test('★ 看的是其他周 → 一律不高亮（否则会误导）', () {
      for (var c = 1; c <= 7; c++) {
        expect(isTodayColumn(isCurrentWeek: false, todayWeekday: 5, column: c), isFalse,
            reason: '第 $c 列在非本周时不该高亮');
      }
    });

    test('隐藏周末时，今天是周六/周日 → 不高亮（那个列不存在）', () {
      expect(
        isTodayColumn(isCurrentWeek: true, todayWeekday: 6, column: 6, shownDays: 5),
        isFalse,
        reason: '只显示周一到周五时，周六的课不显示，也就不该有高亮',
      );
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 5, column: 5, shownDays: 5), isTrue);
    });

    test('非法星期值 → 不高亮（不崩）', () {
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 0, column: 0), isFalse);
      expect(isTodayColumn(isCurrentWeek: true, todayWeekday: 8, column: 8), isFalse);
    });
  });

  group('渲染层：整列背景高亮', () {
    // 用 Key 定位高亮节点最可靠：
    // Container(color: ...) 的 color 不走 decoration，按颜色统计会漏掉。
    final highlightFinder = find.byKey(const Key('today_column_highlight'));

    testWidgets('本周视图 → 恰好一处列高亮', (tester) async {
      final tt = emptyTimetable();
      final currentWeek = tt.weekOf(DateTime.now());
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: currentWeek, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(highlightFinder, findsOneWidget, reason: '本周应有且仅有一列被高亮');
    });

    testWidgets('★ 非本周视图 → 没有任何列高亮', (tester) async {
      final tt = emptyTimetable();
      final currentWeek = tt.weekOf(DateTime.now());
      final otherWeek = currentWeek == 1 ? 5 : 1;
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: otherWeek, sectionHeight: 60)));
      await tester.pumpAndSettle();
      expect(highlightFinder, findsNothing, reason: '看其他周时不该高亮任何列');
    });

    testWidgets('表头仍然渲染 7 个星期标签', (tester) async {
      final tt = emptyTimetable();
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 1, sectionHeight: 60)));
      await tester.pumpAndSettle();
      for (final w in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(w), findsOneWidget, reason: '$w 标签应存在');
      }
    });
  });
}
