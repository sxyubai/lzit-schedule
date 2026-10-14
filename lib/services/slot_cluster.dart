/// 课程时段冲突分组（纯函数，便于单元测试）
///
/// 课表里一个格子（星期 + 节次区间）可能同时有多门课 —— 例如：
///   - 真正的选课冲突（学校允许同时选，或重修课撞了必修课）
///   - 同一门课同一时段有多条记录（不同教室/教师，正方常见）
///
/// 如果直接叠放，后画的会盖住先画的，用户完全看不到被盖的那门。
/// 所以先把它们按"时间是否重叠"分簇，再由渲染层决定怎么呈现：
/// 本项目采用**只画一张 + 右上角角标 `N/M` + 点击切换**（卡片始终占满列宽，
/// 避免窄屏并排把中文挤成一字一行）。簇就是"可切换的一组课"。
library;

import '../models/timetable.dart';

typedef SlotItem = ({Course course, CourseSlot slot});

/// 安全地取"该时段显示第几门课"的下标
int safeSlotIndex(int wanted, int length) =>
    length <= 0 ? 0 : (wanted < 0 ? 0 : (wanted >= length ? length - 1 : wanted));

/// 把同一天的时段按时间重叠关系分簇。
///
/// 规则：按起始节次升序扫描；若某时段的起始节次 <= 当前簇已覆盖的最大节次，
/// 说明与簇内某个时段重叠 → 归入同一簇；否则另起一簇。
///
/// 例（节次区间）：
///   [1-2], [3-4]        -> [[1-2], [3-4]]         两个独立簇（无冲突）
///   [7-8], [7-8], [7-8] -> [[7-8, 7-8, 7-8]]      一个簇，角标 1/3，可切换
///   [1-2], [1-3], [5-6] -> [[1-2, 1-3], [5-6]]    前两个重叠成簇
List<List<SlotItem>> clusterSlots(List<SlotItem> items) {
  if (items.isEmpty) return const [];

  final sorted = [...items]
    ..sort((a, b) => a.slot.startSection.compareTo(b.slot.startSection));

  final clusters = <List<SlotItem>>[];
  var current = <SlotItem>[];
  var clusterEnd = 0;

  for (final item in sorted) {
    final start = item.slot.startSection;
    final end = item.slot.endSection;
    if (current.isEmpty) {
      current = [item];
      clusterEnd = end;
    } else if (start <= clusterEnd) {
      current.add(item);
      if (end > clusterEnd) clusterEnd = end;
    } else {
      clusters.add(current);
      current = [item];
      clusterEnd = end;
    }
  }
  if (current.isNotEmpty) clusters.add(current);
  return clusters;
}
