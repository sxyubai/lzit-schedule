/// 无固定时段课程面板（实践课 / 实习 / 网课）
///
/// 这些课在教务系统里只有周次范围，没有星期和节次（正方接口的 sjkList），
/// 塞不进周视图网格。但它们是真实要上的课（毕业实习、认识实习、软件开发综合实训…），
/// 不展示的话用户会以为"这学期没这些课"。
///
/// 设计：贴在周视图下方，**默认折叠**只显示一行摘要（避免挤占课表空间），
/// 点一下展开成小标签列表。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';

class UnscheduledPanel extends StatefulWidget {
  final List<UnscheduledCourse> items;

  const UnscheduledPanel({super.key, required this.items});

  @override
  State<UnscheduledPanel> createState() => _UnscheduledPanelState();
}

class _UnscheduledPanelState extends State<UnscheduledPanel> {
  bool _expanded = false;

  static const _kindColors = {
    '实践': Color(0xFFE08A5D),
    '实验': Color(0xFFD97D9B),
    '理论': Color(0xFF5B8DEF),
    '上机': Color(0xFF57B9A4),
    '实验上机': Color(0xFF9B7EDE),
  };

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 8, 6, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 摘要行（点击展开/收起）
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '无固定时间课程',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.items.length} 门',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          // 展开：课程标签
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  for (final c in widget.items) _row(context, c),
                  const SizedBox(height: 2),
                  Text(
                    '注：这些课没有固定节次，具体安排以老师通知为准',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, UnscheduledCourse c) {
    final color = _kindColors[c.kindMark] ?? Colors.grey;
    final meta = [
      if (c.weeks.isNotEmpty) c.weeks,
      if (c.credits.isNotEmpty) '${c.credits}学分',
      if (c.teacher.isNotEmpty) c.teacher,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3.5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.name,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.kindMark.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          c.kindMark,
                          style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    if (c.retake) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '重修',
                          style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[700], height: 1.3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
