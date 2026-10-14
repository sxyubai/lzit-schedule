/// 手动添加课程 / 事件 的测试
///
/// 覆盖三块：
///   1) 周视图的空白格点击层与事件卡片（渲染 + 回调）
///   2) 两个表单真正产出什么数据（Course 的 id / Set 周次、TimetableEvent 的日期）
///   3) 模型层：事件与课程共存、JSON 往返
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lzit_schedule/models/section_presets.dart';
import 'package:lzit_schedule/models/timetable.dart';
import 'package:lzit_schedule/pages/add_entry_sheet.dart';
import 'package:lzit_schedule/widgets/week_view.dart';

Timetable buildTimetable({
  List<Course> courses = const [],
  List<TimetableEvent> events = const [],
  int? sectionsPerDay,
}) {
  final preset = lzhitSouthPreset();
  final n = sectionsPerDay ?? preset.sectionsPerDay;
  return Timetable(
    id: 't',
    name: '测试',
    startDate: DateTime(2026, 8, 24), // 第 1 周周一
    totalWeeks: 20,
    sectionsPerDay: n,
    sectionTimes: preset.times.take(n).toList(),
    courses: courses,
    events: events,
  );
}

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
        body: SizedBox(width: 420, height: 2200, child: child),
      ),
    );

void main() {
  // ------------------------------------------------- 空白格点击层
  group('点空白格', () {
    testWidgets('触发 onTapEmpty，带正确的星期与节次', (tester) async {
      final tt = buildTimetable();
      int? gotD;
      int? gotS;

      await tester.pumpWidget(wrap(WeekView(
        timetable: tt,
        week: 7,
        sectionHeight: 60,
        onTapEmpty: (d, s) {
          gotD = d;
          gotS = s;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('empty_3_2')));
      await tester.pump();

      expect(gotD, 3, reason: '点的是第 3 列 → 星期三');
      expect(gotS, 2, reason: '点的是第 2 行 → 第 2 节');
    });

    testWidgets('没传 onTapEmpty 时不铺点击层（不误吞手势）', (tester) async {
      final tt = buildTimetable();
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('empty_1_1')), findsNothing);
    });
  });

  // ------------------------------------------------- 事件卡片
  group('事件卡片', () {
    final ev = TimetableEvent(
      id: 'e1',
      title: '临时开会',
      date: DateTime(2026, 10, 7), // 第 7 周 周三
      startSection: 3,
      endSection: 4,
      location: '1教101',
    );

    testWidgets('日期落在当前周 → 画出来', (tester) async {
      final tt = buildTimetable(events: [ev]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('event_e1')), findsOneWidget);
      expect(find.text('临时开会'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsWidgets);
    });

    testWidgets('日期不在当前周 → 不画', (tester) async {
      final tt = buildTimetable(events: [ev]);
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 8, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('event_e1')), findsNothing);
      expect(find.text('临时开会'), findsNothing);
    });

    testWidgets('点事件卡 → onTapEvent 收到同一个事件', (tester) async {
      final tt = buildTimetable(events: [ev]);
      TimetableEvent? got;
      await tester.pumpWidget(wrap(WeekView(
        timetable: tt,
        week: 7,
        sectionHeight: 60,
        onTapEvent: (e) => got = e,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('event_e1')));
      await tester.pump();

      expect(got?.id, 'e1');
      expect(got?.title, '临时开会');
    });

    testWidgets('事件与课程共存，互不挤掉', (tester) async {
      final tt = buildTimetable(
        courses: [mk('高等数学', 3, 1, 2, {7})],
        events: [ev],
      );
      await tester.pumpWidget(wrap(WeekView(timetable: tt, week: 7, sectionHeight: 60)));
      await tester.pumpAndSettle();

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('临时开会'), findsOneWidget);
    });
  });

  // ------------------------------------------------- 添加面板与两个表单
  group('添加面板', () {
    testWidgets('面板标题带周次/星期/节次，且有课程与事件两项', (tester) async {
      final tt = buildTimetable();
      AddEntryResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showAddEntrySheet(ctx,
                    weekday: 2, section: 3, week: 7, timetable: tt);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('第 7 周 · 星期二 · 第 3 节'), findsOneWidget);
      expect(find.text('添加课程'), findsOneWidget);
      expect(find.text('添加事件'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('课程表单保存 → 产出带 id 的 Course，周次是 1..20 的集合', (tester) async {
      final tt = buildTimetable();
      AddEntryResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showAddEntrySheet(ctx,
                    weekday: 2, section: 3, week: 7, timetable: tt);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '手动加的课');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final c = result!.course;
      expect(c, isNotNull, reason: '走的应该是课程分支');
      expect(c!.name, '手动加的课');
      expect(c.id, isNotEmpty, reason: 'Course.id 是必填，自动生成');
      expect(c.slots, hasLength(1));
      expect(c.slots.first.weekday, 2);
      expect(c.slots.first.startSection, 3);
      expect(c.slots.first.endSection, 3);
      expect(c.slots.first.weeks, hasLength(20), reason: '默认覆盖 1~20 周');
      expect(c.slots.first.weeks.contains(1), isTrue);
      expect(c.slots.first.weeks.contains(20), isTrue);
    });

    testWidgets('课程名称为空 → 不关闭表单，也不产出结果', (tester) async {
      final tt = buildTimetable();
      AddEntryResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showAddEntrySheet(ctx,
                    weekday: 2, section: 3, week: 7, timetable: tt);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('课程名称不能为空'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('事件表单保存 → 产出落在「第 7 周 星期二」的 TimetableEvent', (tester) async {
      final tt = buildTimetable();
      AddEntryResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showAddEntrySheet(ctx,
                    weekday: 2, section: 3, week: 7, timetable: tt);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加事件'));
      await tester.pumpAndSettle();

      // 第 7 周星期二的日期：2026-08-24 + 6*7 + 1 = 2026-10-06
      expect(find.textContaining('2026/10/06'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '临时开会');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final e = result!.event;
      expect(e, isNotNull, reason: '走的应该是事件分支');
      expect(e!.title, '临时开会');
      expect(e.date, DateTime(2026, 10, 6));
      expect(tt.weekOf(e.date), 7, reason: '落在正在看的这一周');
      expect(e.startSection, 3);
      expect(e.endSection, 3);
    });

    testWidgets('一天只有 1 节时表单不崩（滑块区间退化）', (tester) async {
      final tt = buildTimetable(sectionsPerDay: 1);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAddEntrySheet(ctx,
                  weekday: 1, section: 1, week: 1, timetable: tt),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      // 能渲染出表单即算通过（区间处理不当会在 Slider 处抛断言）
      expect(find.text('添加课程'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------- 模型层
  group('事件模型', () {
    test('copyWith(events:) 不会弄丢课程', () {
      final tt = buildTimetable(courses: [mk('高等数学', 1, 1, 2, {1, 2})]);
      final ev = TimetableEvent(
        id: 'e9',
        title: '讲座',
        date: DateTime(2026, 10, 8),
        startSection: 5,
        endSection: 6,
      );

      final updated = tt.copyWith(events: [...tt.events, ev]);

      expect(updated.courses, hasLength(1));
      expect(updated.courses.first.name, '高等数学');
      expect(updated.events, hasLength(1));
      expect(updated.events.first.title, '讲座');
      // 其余字段原样带过去
      expect(updated.id, tt.id);
      expect(updated.startDate, tt.startDate);
      expect(updated.totalWeeks, tt.totalWeeks);
    });

    test('JSON 往返：事件与课程都还在', () {
      final tt = buildTimetable(
        courses: [mk('高等数学', 1, 1, 2, {1, 2})],
        events: [
          TimetableEvent(
            id: 'e9',
            title: '讲座',
            date: DateTime(2026, 10, 8),
            startSection: 5,
            endSection: 6,
            location: '图书馆',
          ),
        ],
      );

      final back = Timetable.fromJson(tt.toJson());

      expect(back.events, hasLength(1));
      expect(back.events.first.id, 'e9');
      expect(back.events.first.title, '讲座');
      expect(back.events.first.date, DateTime(2026, 10, 8));
      expect(back.events.first.location, '图书馆');
      expect(back.courses, hasLength(1));
    });

    test('删除事件：按 id 过滤，课程不受影响', () {
      final ev = TimetableEvent(
        id: 'e9',
        title: '讲座',
        date: DateTime(2026, 10, 8),
        startSection: 5,
        endSection: 6,
      );
      final tt = buildTimetable(courses: [mk('高等数学', 1, 1, 2, {1, 2})], events: [ev]);

      final updated =
          tt.copyWith(events: tt.events.where((e) => e.id != 'e9').toList());

      expect(updated.events, isEmpty);
      expect(updated.courses, hasLength(1));
    });
  });
}
