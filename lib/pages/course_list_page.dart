/// 课程列表页：按课程分组显示所有时段
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../widgets/week_view.dart';

class CourseListPage extends StatelessWidget {
  final Timetable timetable;

  /// 设置入口（从周视图的 AppBar 挪过来：AppBar 上 4 个图标太挤且难找）
  final VoidCallback? onOpenReminder;
  final VoidCallback? onImport;

  /// 设置「本学期第 1 周周一」的日期
  ///
  /// 教务系统的课表里**只有周次、没有日期**，所以所有日期都靠这个基准推算。
  /// 算错一周，整张表头的日期就全错 —— 必须让用户能改。
  final VoidCallback? onEditSemesterStart;

  /// 外观设置（背景图 / 透明度 / 圆角 / 格子高度）
  final VoidCallback? onOpenAppearance;

  /// 打开「关于」页（作者 / 交流群 / GitHub）
  final VoidCallback? onOpenAbout;

  /// 打开课表管理（切换 / 重命名 / 删除多套课表）
  final VoidCallback? onManageTimetables;

  const CourseListPage({
    super.key,
    required this.timetable,
    this.onOpenReminder,
    this.onImport,
    this.onEditSemesterStart,
    this.onOpenAppearance,
    this.onOpenAbout,
    this.onManageTimetables,
  });

  static const _wd = ['', '一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final courses = [...timetable.courses]
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: courses.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, i) {
        if (i == 0) return _header(context, courses.length);
        final c = courses[i - 1];
        final color = colorForCourse(c.name, override: c.color);
        return ListTile(
          leading: Container(
            width: 10,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in c.slots)
                Text(
                  '周${_wd[s.weekday]} ${s.startSection}-${s.endSection}节 · '
                  '${_weeksText(s.weeks)} · ${s.room}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 2),
              Text(
                [
                  if (c.kindMark.isNotEmpty) c.kindMark,
                  if (c.credits > 0) '${c.credits}学分',
                  if (c.assessType.isNotEmpty) c.assessType,
                  if (c.slots.isNotEmpty && c.slots.first.teacher.isNotEmpty)
                    c.slots.first.teacher,
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, int count) {
    final s = timetable.student;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count 门课程',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            [
              timetable.semesterName,
              if (s.xm.isNotEmpty) s.xm,
              if (s.className.isNotEmpty) s.className,
              if (s.major.isNotEmpty) s.major,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          // 功能入口（比塞在 AppBar 上更好点、更容易找）
          const SizedBox(height: 12),
          Row(
            children: [
              if (onOpenReminder != null)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_active_outlined, size: 17),
                    label: const Text('上课提醒', style: TextStyle(fontSize: 12.5)),
                    onPressed: onOpenReminder,
                  ),
                ),
              if (onOpenReminder != null && onOpenAbout != null)
                const SizedBox(width: 8),
              if (onOpenAbout != null)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline, size: 17),
                    label: const Text('关于', style: TextStyle(fontSize: 12.5)),
                    onPressed: onOpenAbout,
                  ),
                ),
            ],
          ),
          // 课表管理：多套课表（大一/大二/当前学期）的切换、重命名、删除
          if (onManageTimetables != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onManageTimetables,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.library_books_outlined, size: 17, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text('课表管理',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
                    const Spacer(),
                    Text(timetable.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        )),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text('可重命名、切换、删除；导入时也能选覆盖或新增',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
            ),
          ],
          // 学期第一天：决定所有日期与"当前第几周"，必须可调
          if (onEditSemesterStart != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onEditSemesterStart,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 17, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text('学期第一天', style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
                    const Spacer(),
                    Text(
                      '${timetable.startDate.year}/'
                      '${timetable.startDate.month}/${timetable.startDate.day}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                '课表本身不含日期，所有日期都由这个基准往后推算，不对就改这里',
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
              ),
            ),
          ],
          if (onImport != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('从教务系统重新导入', style: TextStyle(fontSize: 12.5)),
                onPressed: onImport,
              ),
            ),
          ],
          if (onOpenAppearance != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 17),
                label: const Text('外观设置（背景图 / 透明度）', style: TextStyle(fontSize: 12.5)),
                onPressed: onOpenAppearance,
              ),
            ),
          ],
          const SizedBox(height: 4),
          const Divider(height: 16),
        ],
      ),
    );
  }

  String _weeksText(Set<int> weeks) {
    final sorted = weeks.toList()..sort();
    if (sorted.isEmpty) return '周次未定';
    final parts = <String>[];
    var start = sorted.first, prev = sorted.first;
    for (final w in sorted.skip(1)) {
      if (w == prev + 1) {
        prev = w;
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = prev = w;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    return '${parts.join(',')}周';
  }
}
