/// 周视图课表
///
/// 布局：左侧节次时间轴 + 7 天网格 + 课程卡片（Positioned 精确覆盖跨节高度）
/// 设计参考 WakeUp：格子高度可调、圆角、非本周课程暗化、点击查看详情
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../services/slot_cluster.dart';
import 'unscheduled_panel.dart';

const double kSectionHeightDefault = 64;
const double kSectionRadiusDefault = 4;

/// 计算「第 [week] 周星期 [weekday]」对应的日期
///
/// 约定：学期第 1 周的周一是 [startDate]（与教务系统一致）。
/// 所以偏移天数 = (周次 - 1) × 7 + (星期 - 1)。
///
/// 抽成纯函数是为了可测 —— 日期算错一天是很容易犯、而且用户一眼能看出的错。
DateTime dateOfWeekday(DateTime startDate, int week, int weekday) {
  final base = DateTime(startDate.year, startDate.month, startDate.day);
  return base.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
}

/// 判断某列是否该作为"今天"高亮
///
/// 抽成纯函数是为了可测：只有"正在浏览本周"时才高亮今天，
/// 浏览其他周时不标（否则用户会误以为那天在本周）。
///
/// [todayWeekday] 1=周一…7=周日；[shownDays] 当前显示几列（隐藏周末时为 5）。
bool isTodayColumn({
  required bool isCurrentWeek,
  required int todayWeekday,
  required int column,
  int shownDays = 7,
}) {
  if (!isCurrentWeek) return false;
  if (todayWeekday < 1 || todayWeekday > shownDays) return false;
  return column == todayWeekday;
}

/// 按课程名稳定地分配一个颜色
Color colorForCourse(String name, {int? override}) {
  if (override != null) return Color(override);
  const palette = [
    Color(0xFF5B8DEF), Color(0xFFEF7C8E), Color(0xFF57B9A4), Color(0xFFE0A458),
    Color(0xFF9B7EDE), Color(0xFF6FB1E0), Color(0xFFD97D9B), Color(0xFF7FB069),
    Color(0xFFC97FB0), Color(0xFF4FA3A5), Color(0xFFE08A5D), Color(0xFF8C9EFF),
  ];
  var h = 0;
  for (final r in name.runes) {
    h = (h * 31 + r) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

class WeekView extends StatelessWidget {
  final Timetable timetable;
  final int week;
  final int? highlightWeekday;
  final double sectionHeight;
  final double radius;
  final bool showWeekend;
  final void Function(Course course, CourseSlot slot)? onTapCourse;

  /// 课程卡片不透明度（外观设置可调；1.0 = 完全不透明）
  final double cardOpacity;

  /// 点击空白格（星期, 节次）—— 用来手动添加课程或事件
  final void Function(int weekday, int section)? onTapEmpty;

  /// 点击一次性事件卡片
  final void Function(TimetableEvent event)? onTapEvent;

  /// 取"该时段当前显示第几门课"（由外部持久化的冲突偏好提供）
  final int Function(int weekday, int startSection, int endSection)? indexOfSlot;

  /// 用户点击冲突卡片时回调：要求外部弹出选择列表
  final void Function(List<SlotItem> cluster, int weekday, int selected)? onSelectConflict;

  const WeekView({
    super.key,
    required this.timetable,
    required this.week,
    this.highlightWeekday,
    this.sectionHeight = kSectionHeightDefault,
    this.radius = kSectionRadiusDefault,
    this.showWeekend = true,
    this.cardOpacity = 0.90,
    this.onTapEmpty,
    this.onTapEvent,
    this.onTapCourse,
    this.indexOfSlot,
    this.onSelectConflict,
  });

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final days = showWeekend ? 7 : 5;
    final sections = timetable.sectionsPerDay;
    final times = {for (final t in timetable.sectionTimes) t.section: t};

    final today = DateTime.now();
    final todayWeek = timetable.weekOf(today);
    final todayWeekday = today.weekday;
    final isCurrentWeek = todayWeek == week;
    // 今天是否高亮，逐列判断（只有在浏览本周时才高亮，其他周不误导）
    bool isToday(int column) => isTodayColumn(
          isCurrentWeek: isCurrentWeek,
          todayWeekday: todayWeekday,
          column: column,
          shownDays: days,
        );

    /// 本视图内第 [weekday] 列对应的日期
    DateTime dateOf(int weekday) => dateOfWeekday(timetable.startDate, week, weekday);

    return Column(
      children: [
        // 表头：星期 + 日期（今天用胶囊底色标出来）
        SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 40), // 与左侧时间轴对齐
              for (var d = 1; d <= days; d++)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: isToday(d)
                          ? BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(9),
                            )
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '周${_weekdayNames[d - 1]}',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.1,
                              fontWeight: isToday(d) ? FontWeight.bold : FontWeight.normal,
                              color: isToday(d)
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : (isCurrentWeek
                                      ? Theme.of(context).colorScheme.primary
                                      : null),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            // 今天直接写"今天"，比看日期数字更快
                            isToday(d)
                                ? '今天'
                                : '${dateOf(d).month}/${dateOf(d).day}',
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1.1,
                              fontWeight: isToday(d) ? FontWeight.bold : FontWeight.w500,
                              color: isToday(d)
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : (isCurrentWeek
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 网格 + 下方「无固定时间课程」面板（面板可折叠，默认一行摘要）
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: sections * sectionHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧节次时间轴
                        SizedBox(
                          width: 40,
                          child: Column(
                            children: [
                              for (var s = 1; s <= sections; s++)
                                SizedBox(
                                  height: sectionHeight,
                                  // FittedBox：格子小的时候整块等比缩放，
                                  // 避免"序号 + 起止时间"三行在高 40 的格子里溢出
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('$s',
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w600)),
                                        if (times[s] != null) ...[
                                          const SizedBox(height: 2),
                                          Text(times[s]!.start,
                                              style: TextStyle(
                                                  fontSize: 8, color: Colors.grey[600], height: 1.1)),
                                          Text(times[s]!.end,
                                              style: TextStyle(
                                                  fontSize: 8, color: Colors.grey[600], height: 1.1)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // 7 天网格
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final colW = constraints.maxWidth / days;
                              // 找出"今天"是第几列（没有则为 null）
                              int? todayColumn;
                              for (var c = 1; c <= days; c++) {
                                if (isToday(c)) {
                                  todayColumn = c;
                                  break;
                                }
                              }
                              return Stack(
                                children: [
                                  // 今天整列的背景高亮（画在网格线之下）
                                  if (todayColumn != null)
                                    Positioned(
                                      key: const Key('today_column_highlight'),
                                      left: (todayColumn - 1) * colW,
                                      top: 0,
                                      bottom: 0,
                                      width: colW,
                                      child: Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.075),
                                      ),
                                    ),
                                  // 背景网格线
                                  ..._gridLines(context, days, sections, colW),
                                  // 空白格点击层：放在课程卡片**下面**，
                                  // 这样点已有卡片时不会误触发"添加"
                                  ..._emptyCells(days, sections, colW),
                                  // 课程卡片
                                  ..._courseCards(context, days, sections, colW),
                                  // 一次性事件（画在课程之上，方便看到）
                                  ..._eventCards(days, sections, colW),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 无固定时段的实践/实习/网课：塞不进网格，但必须让用户看见
              UnscheduledPanel(items: timetable.unscheduled),
            ],
          ),
        ),
      ],
    );
  }

  /// 空白格的透明点击层：点一下就能添加课程 / 事件
  List<Widget> _emptyCells(int days, int sections, double colW) {
    if (onTapEmpty == null) return const [];
    final out = <Widget>[];
    for (var d = 1; d <= days; d++) {
      for (var s = 1; s <= sections; s++) {
        out.add(Positioned(
          left: (d - 1) * colW,
          top: (s - 1) * sectionHeight,
          width: colW,
          height: sectionHeight,
          child: GestureDetector(
            key: ValueKey('empty_${d}_$s'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onTapEmpty!(d, s),
          ),
        ));
      }
    }
    return out;
  }

  /// 一次性事件卡片
  ///
  /// 事件绑定的是**具体日期**，所以先换算成「第几周 + 星期几」，
  /// 只画在当前正在看的那一周里。
  /// 样式上与课程区分：紫色底 + 图钉图标。
  List<Widget> _eventCards(int days, int sections, double colW) {
    final out = <Widget>[];
    for (final ev in timetable.events) {
      if (timetable.weekOf(ev.date) != week) continue;
      final wd = ev.date.weekday;
      if (wd < 1 || wd > days) continue;
      final start = ev.startSection.clamp(1, sections);
      final end = ev.endSection.clamp(start, sections);
      final top = (start - 1) * sectionHeight;
      final height = (end - start + 1) * sectionHeight - 2;

      out.add(Positioned(
        left: (wd - 1) * colW + 2,
        top: top + 1,
        width: colW - 4,
        height: height,
        child: GestureDetector(
          key: ValueKey('event_${ev.id}'),
          onTap: onTapEvent == null ? null : () => onTapEvent!(ev),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF8E5BD9).withValues(alpha: cardOpacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.push_pin, size: 9, color: Colors.white),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(ev.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (ev.location.isNotEmpty)
                  Text(ev.location,
                      style: const TextStyle(color: Colors.white70, fontSize: 8.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _gridLines(BuildContext context, int days, int sections, double colW) {
    final out = <Widget>[];
    final lineColor = Theme.of(context).dividerColor.withValues(alpha: 0.35);
    for (var s = 0; s <= sections; s++) {
      out.add(Positioned(
        left: 0,
        right: 0,
        top: s * sectionHeight,
        child: Container(height: 0.5, color: lineColor),
      ));
    }
    for (var d = 0; d <= days; d++) {
      out.add(Positioned(
        left: d * colW,
        top: 0,
        bottom: 0,
        child: Container(width: 0.5, color: lineColor),
      ));
    }
    return out;
  }

  /// 生成课程卡片，并处理**同一时段多门课冲突**的情况。
  ///
  /// 策略（用户指定）：**任何冲突都只画一张卡 + 右上角角标 `N/M`**，
  /// 点击卡片弹出选择面板切换显示的课（选择按「时段槽位」记忆，跨周次同步）。
  ///
  /// 为什么不再并排：手机上一列只有 ~42dp，平分给两张卡后中文被挤成一字一行
  /// （实测"物理实验B"变成竖排），完全没法读。角标方案让卡片始终占满列宽。
  ///
  /// 注意：同一门课同一时段的多条记录（正方常见：不同教室或教师，例如实验分班）
  /// 同样走角标 —— 因为那也是"两条安排只能去一个"，切换一下就知道另一条在哪。
  List<Widget> _courseCards(BuildContext context, int days, int sections, double colW) {
    final out = <Widget>[];
    final gap = 1.5;

    for (var d = 1; d <= days; d++) {
      final items = timetable.slotsAt(d, week);
      if (items.isEmpty) continue;

      for (final cluster in clusterSlots(items)) {
        final n = cluster.length;
        final first = cluster.first.slot;
        final selected =
            safeSlotIndex(indexOfSlot?.call(d, first.startSection, first.endSection) ?? 0, n);
        final item = cluster[selected];

        final top = (first.startSection - 1) * sectionHeight;
        final height = (first.endSection - first.startSection + 1) * sectionHeight - 3;
        final left = (d - 1) * colW + gap;

        out.add(Positioned(
          left: left,
          top: top + 1.5,
          width: colW - gap * 2,
          height: height,
          child: _CourseCard(
            course: item.course,
            slot: item.slot,
            color: colorForCourse(item.course.name, override: item.course.color),
            radius: radius,
            opacity: cardOpacity,
            badge: n > 1 ? '${selected + 1}/$n' : null,
            onTap: () {
              if (n > 1 && onSelectConflict != null) {
                onSelectConflict!(cluster, d, selected);
              } else if (onTapCourse != null) {
                onTapCourse!(item.course, item.slot);
              }
            },
          ),
        ));
      }
    }
    return out;
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final CourseSlot slot;
  final Color color;
  final double radius;

  /// 卡片不透明度（来自外观设置）
  final double opacity;

  /// 冲突角标文本，如 "2/3"；null 表示该时段没有冲突，不显示角标
  final String? badge;
  final VoidCallback? onTap;

  const _CourseCard({
    required this.course,
    required this.slot,
    required this.color,
    required this.radius,
    this.opacity = 0.90,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          // 卡片主体
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: const EdgeInsets.all(3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (slot.room.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '@${slot.room}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 8.5,
                                    height: 1.15),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (slot.teacher.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                slot.teacher,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 8,
                                    height: 1.15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 右下角角标（放右边上方会压住课程名，所以贴底部）
          if (badge != null)
            Positioned(
              bottom: 1.5,
              right: 1.5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
