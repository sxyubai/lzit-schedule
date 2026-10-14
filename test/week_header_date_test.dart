/// 表头日期显示测试
///
/// 日期算错一天是最容易犯的错（而且用户一看就知道错了），必须用固定日期锁死。
///
/// 日期锚点（已实测）：学期起始 2026-08-24 是第 1 周周一
///   第 1 周周一 = 8/24   第 1 周周日 = 8/30
///   第 2 周周一 = 8/31
///   第 7 周周一 = 10/5   第 7 周周六 = 10/10
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/widgets/week_view.dart';

Timetable ttWithStart(DateTime start) {
  final preset = lzhitSouthPreset();
  return Timetable(
    id: 't',
    name: '测试',
    startDate: start,
    totalWeeks: 20,
    sectionsPerDay: preset.sectionsPerDay,
    sectionTimes: preset.times,
    courses: const [],
  );
}

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 420, height: 2200, child: child)));

/// 把测试画布放大到能装下整张课表（默认 800x600 会把 10 节全裁掉 → 大量溢出报错）
void useBigCanvas(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final start = DateTime(2026, 8, 24); // 第 1 周周一

  group('dateOfWeekday 日期计算', () {
    test('第 1 周周一 = 开学当天（8/24）', () {
      expect(dateOfWeekday(start, 1, 1), DateTime(2026, 8, 24));
    });

    test('第 1 周周日 = 8/30', () {
      expect(dateOfWeekday(start, 1, 7), DateTime(2026, 8, 30));
    });

    test('第 2 周周一 = 8/31（跨月）', () {
      expect(dateOfWeekday(start, 2, 1), DateTime(2026, 8, 31));
    });

    test('★ 第 7 周周一 = 10/5（与实测一致）', () {
      expect(dateOfWeekday(start, 7, 1), DateTime(2026, 10, 5));
    });

    test('★ 第 7 周周六 = 10/10（今天）', () {
      expect(dateOfWeekday(start, 7, 6), DateTime(2026, 10, 10));
    });

    test('第 7 周周日 = 10/11', () {
      expect(dateOfWeekday(start, 7, 7), DateTime(2026, 10, 11));
    });

    test('第 20 周周一 = 2027-01-04（跨年）', () {
      // 手工核对：8/24 + 19*7(133) 天
      //   8月余 7 天 → 8/31；9月 30 → 61；10月 31 → 92；11月 30 → 122；12月 31 → 153
      //   第 133 天落在 12 月：8/24 + 129 天 = 12/31，再 +4 天 = 2027-01-04
      expect(dateOfWeekday(start, 20, 1), DateTime(2027, 1, 4));
    });

    test('相邻天只差一天（防止整体偏移）', () {
      for (var d = 1; d < 7; d++) {
        final a = dateOfWeekday(start, 5, d);
        final b = dateOfWeekday(start, 5, d + 1);
        expect(b.difference(a).inDays, 1, reason: '第 5 周 周$d → 周${d + 1} 应差 1 天');
      }
    });

    test('相邻周同一星期差 7 天', () {
      for (var w = 1; w < 20; w++) {
        final a = dateOfWeekday(start, w, 3);
        final b = dateOfWeekday(start, w + 1, 3);
        expect(b.difference(a).inDays, 7, reason: '第 $w 周 → 第 ${w + 1} 周应差 7 天');
      }
    });

    test('传入的 startDate 若带时分秒也不影响（只取日期）', () {
      final messy = DateTime(2026, 8, 24, 23, 59, 59);
      expect(dateOfWeekday(messy, 1, 1).day, 24);
      expect(dateOfWeekday(messy, 7, 6).day, 10);
    });
  });

  group('渲染层：表头显示日期', () {
    testWidgets('第 7 周表头显示 10/5 ~ 10/11', (tester) async {
      useBigCanvas(tester);
      final tt = ttWithStart(start);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 40)));
      await tester.pumpAndSettle();

      // 周一到周日分别对应 10/5 … 10/11；
      // 但若当前正好是第 7 周，今天那列会显示「今天」而非日期（设计如此）
      final now = DateTime.now();
      final viewingCurrentWeek = tt.weekOf(now) == 7;

      for (var d = 1; d <= 7; d++) {
        final date = dateOfWeekday(start, 7, d);
        final label = '${date.month}/${date.day}';
        if (viewingCurrentWeek && d == now.weekday) {
          expect(find.text('今天'), findsOneWidget, reason: '今天那列应显示「今天」');
          expect(find.text(label), findsNothing, reason: '$label 已被「今天」替代');
        } else {
          expect(find.text(label), findsOneWidget, reason: '表头应显示 $label');
        }
      }
    });

    testWidgets('★ 今天那列显示「今天」而不是日期', (tester) async {
      useBigCanvas(tester);
      final tt = ttWithStart(start);
      final now = DateTime.now();
      final currentWeek = tt.weekOf(now);
      await tester.pumpWidget(
          wrap(WeekView(timetable: tt, week: currentWeek, sectionHeight: 40)));
      await tester.pumpAndSettle();

      expect(find.text('今天'), findsOneWidget, reason: '今天那列应写「今天」');
      // 今天对应的日期数字不应再单独出现
      final today = dateOfWeekday(start, currentWeek, now.weekday);
      expect(find.text('${today.month}/${today.day}'), findsNothing,
          reason: '今天那列已用「今天」替代日期');
    });

    testWidgets('非本周也显示日期（只是不高亮）', (tester) async {
      useBigCanvas(tester);
      final tt = ttWithStart(start);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 3, sectionHeight: 40)));
      await tester.pumpAndSettle();

      expect(find.text('今天'), findsNothing, reason: '非本周不该出现「今天」');
      expect(find.byKey(const Key('today_column_highlight')), findsNothing);
      // 但仍要有日期
      expect(find.text('9/7'), findsOneWidget, reason: '第 3 周周一 = 9/7');
    });
  });
}
