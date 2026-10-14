/// 课表管理页：切换 / 重命名 / 删除多套课表
///
/// 一个学期里可能同时存在好几套课表（大一、大二、当前学期…），
/// 所以导入时可以选择「覆盖」或「新增」，这里负责管理它们。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';

class TimetableManagerPage extends StatelessWidget {
  /// 全部课表
  final List<Timetable> timetables;

  /// 当前正在使用的那份
  final String? currentId;

  /// 切换当前课表
  final Future<void> Function(String id) onSwitch;

  /// 重命名
  final Future<void> Function(Timetable tt, String newName) onRename;

  /// 删除（调用方负责确认）
  final Future<void> Function(Timetable tt) onDelete;

  /// 去导入一份新的
  final VoidCallback onImportNew;

  const TimetableManagerPage({
    super.key,
    required this.timetables,
    required this.currentId,
    required this.onSwitch,
    required this.onRename,
    required this.onDelete,
    required this.onImportNew,
  });

  Future<void> _rename(BuildContext context, Timetable tt) async {
    final ctl = TextEditingController(text: tt.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名课表'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '课表名称',
            hintText: '例如 2026课表、大四上',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (newName == null || newName.isEmpty || newName == tt.name) return;
    await onRename(tt, newName);
  }

  Future<void> _confirmDelete(BuildContext context, Timetable tt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课表'),
        content: Text('确定删除「${tt.name}」吗？\n'
            '（共 ${tt.courses.length} 门课，删除后无法恢复）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await onDelete(tt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表管理'),
        actions: [
          IconButton(
            tooltip: '导入新课表',
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.pop(context);
              onImportNew();
            },
          ),
        ],
      ),
      body: timetables.isEmpty
          ? const Center(child: Text('还没有课表'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: timetables.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (ctx, i) {
                final tt = timetables[i];
                final isCurrent = tt.id == currentId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent ? cs.primary : cs.surfaceContainerHighest,
                    child: Icon(
                      isCurrent ? Icons.check : Icons.calendar_month_outlined,
                      size: 20,
                      color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(tt.name,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('使用中',
                              style: TextStyle(fontSize: 9, color: cs.onPrimaryContainer)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${tt.semesterName} · ${tt.courses.length} 门课'
                    '${tt.unscheduled.isNotEmpty ? ' · ${tt.unscheduled.length} 门无固定时段' : ''}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: isCurrent ? null : () => onSwitch(tt.id),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) async {
                      if (v == 'rename') await _rename(context, tt);
                      // 上一个 await 之后 context 可能已失效，重新确认
                      if (!context.mounted) return;
                      if (v == 'delete') await _confirmDelete(context, tt);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
