/// 「点空白格添加」的底部弹窗
///
/// 两种类型：
///   · 课程 —— 按「周次 + 星期」重复，每周同一时间都会出现
///   · 事件 —— 绑定具体日期，只出现一次
///
/// 为了让事件也能画进课表网格，两者都用「节次」表示时段。
library;

import 'package:flutter/material.dart';

import '../models/timetable.dart';

/// 添加结果（二选一）
class AddEntryResult {
  final Course? course;
  final TimetableEvent? event;

  const AddEntryResult.course(Course c)
      : course = c,
        event = null;
  const AddEntryResult.event(TimetableEvent e)
      : course = null,
        event = e;
}

/// 弹出添加面板；用户取消则返回 null
Future<AddEntryResult?> showAddEntrySheet(
  BuildContext context, {
  required int weekday,
  required int section,
  required int week,
  required Timetable timetable,
}) {
  return showModalBottomSheet<AddEntryResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TypeChooser(
      weekday: weekday,
      section: section,
      week: week,
      timetable: timetable,
    ),
  );
}

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

class _TypeChooser extends StatelessWidget {
  final int weekday;
  final int section;
  final int week;
  final Timetable timetable;

  const _TypeChooser({
    required this.weekday,
    required this.section,
    required this.week,
    required this.timetable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wdName = _weekdayNames[weekday - 1];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第 $week 周 · 星期$wdName · 第 $section 节',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.menu_book_outlined, color: cs.onPrimaryContainer, size: 20),
              ),
              title: const Text('添加课程'),
              subtitle: const Text('每周的同一时间都会显示（可填周次范围）',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () async {
                final r = await Navigator.of(context).push<AddEntryResult>(
                  MaterialPageRoute(
                    builder: (_) => _CourseForm(
                      weekday: weekday,
                      section: section,
                      totalWeeks: timetable.totalWeeks,
                      sectionsPerDay: timetable.sectionsPerDay,
                    ),
                  ),
                );
                if (r != null && context.mounted) Navigator.pop(context, r);
              },
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF8E5BD9).withValues(alpha: 0.18),
                child: const Icon(Icons.push_pin_outlined,
                    color: Color(0xFF8E5BD9), size: 20),
              ),
              title: const Text('添加事件'),
              subtitle: const Text('只在某一天出现一次（如临时开会、讲座）',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () async {
                // 事件默认落在"当前查看的这一周的那一天"
                final base = timetable.startDate
                    .add(Duration(days: (week - 1) * 7 + (weekday - 1)));
                final r = await Navigator.of(context).push<AddEntryResult>(
                  MaterialPageRoute(
                    builder: (_) => _EventForm(
                      defaultDate: base,
                      section: section,
                      sectionsPerDay: timetable.sectionsPerDay,
                    ),
                  ),
                );
                if (r != null && context.mounted) Navigator.pop(context, r);
              },
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- 公共：一行滑块
/// 一行「标签 + 滑块 + 当前值」。
///
/// 当 `max <= min` 时（例如"结束节次"的下限已经顶到当天最大节次），
/// 内部把上界撑成 `min + 1`，否则 Slider 会因区间为空而不可用。
class _SectionSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// 把数值渲染成文字；默认直接输出数字
  final String Function(int)? formatter;

  const _SectionSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = formatter ?? (int v) => '$v';
    final lo = min.toDouble();
    final hi = max <= min ? lo + 1 : max.toDouble();
    final v = value.toDouble().clamp(lo, hi);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Expanded(
            child: Slider(
              value: v,
              min: lo,
              max: hi,
              divisions: (hi - lo) <= 0 ? null : (hi - lo).round(),
              label: fmt(value),
              onChanged: (x) => onChanged(x.round()),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(fmt(value),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ 课程表单
class _CourseForm extends StatefulWidget {
  final int weekday;
  final int section;
  final int totalWeeks;
  final int sectionsPerDay;

  const _CourseForm({
    required this.weekday,
    required this.section,
    required this.totalWeeks,
    required this.sectionsPerDay,
  });

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _name = TextEditingController();
  final _room = TextEditingController();
  final _teacher = TextEditingController();
  late int _weekday = widget.weekday;
  late int _start = widget.section;
  late int _end = widget.section;
  late int _fromWeek = 1;
  late int _toWeek = widget.totalWeeks;

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _teacher.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('课程名称不能为空')),
      );
      return;
    }
    // CourseSlot.weeks 是 Set<int>
    final weeks = <int>{};
    for (var w = _fromWeek; w <= _toWeek; w++) {
      weeks.add(w);
    }
    // Course.id 是必填字段
    final course = Course(
      id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      slots: [
        CourseSlot(
          weekday: _weekday,
          startSection: _start,
          endSection: _end,
          weeks: weeks,
          room: _room.text.trim(),
          teacher: _teacher.text.trim(),
        ),
      ],
    );
    Navigator.pop(context, AddEntryResult.course(course));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加课程'),
        actions: [
          TextButton(onPressed: _submit, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '课程名称 *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _room,
                  decoration: const InputDecoration(
                    labelText: '地点', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _teacher,
                  decoration: const InputDecoration(
                    labelText: '教师', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionSlider(
            label: '星期',
            value: _weekday,
            min: 1,
            max: 7,
            formatter: (v) => '周${_weekdayNames[v - 1]}',
            onChanged: (v) => setState(() => _weekday = v),
          ),
          _SectionSlider(
            label: '开始节次',
            value: _start,
            min: 1,
            max: widget.sectionsPerDay,
            onChanged: (v) => setState(() {
              _start = v;
              if (_end < _start) _end = _start;
            }),
          ),
          _SectionSlider(
            label: '结束节次',
            value: _end,
            min: _start,
            max: widget.sectionsPerDay,
            onChanged: (v) => setState(() => _end = v),
          ),
          _SectionSlider(
            label: '起始周',
            value: _fromWeek,
            min: 1,
            max: widget.totalWeeks,
            onChanged: (v) => setState(() {
              _fromWeek = v;
              if (_toWeek < _fromWeek) _toWeek = _fromWeek;
            }),
          ),
          _SectionSlider(
            label: '结束周',
            value: _toWeek,
            min: _fromWeek,
            max: widget.totalWeeks,
            onChanged: (v) => setState(() => _toWeek = v),
          ),
          const SizedBox(height: 8),
          Text('提示：这是「每周重复」的课，第 $_fromWeek~$_toWeek 周都会显示',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ 事件表单
class _EventForm extends StatefulWidget {
  final DateTime defaultDate;
  final int section;
  final int sectionsPerDay;

  const _EventForm({
    required this.defaultDate,
    required this.section,
    required this.sectionsPerDay,
  });

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _title = TextEditingController();
  final _room = TextEditingController();
  late DateTime _date = widget.defaultDate;
  late int _start = widget.section;
  late int _end = widget.section;

  @override
  void dispose() {
    _title.dispose();
    _room.dispose();
    super.dispose();
  }

  String get _dateText =>
      '${_date.year}/${_date.month.toString().padLeft(2, '0')}/'
      '${_date.day.toString().padLeft(2, '0')}'
      '（周${_weekdayNames[_date.weekday - 1]}）';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1, 1, 1),
      lastDate: DateTime(_date.year + 2, 12, 31),
      helpText: '选择事件日期',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('事件标题不能为空')),
      );
      return;
    }
    Navigator.pop(
      context,
      AddEntryResult.event(TimetableEvent(
        id: 'event-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        date: _date,
        startSection: _start,
        endSection: _end,
        location: _room.text.trim(),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加事件'),
        actions: [
          TextButton(onPressed: _submit, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '事件标题 *',
              hintText: '例如：班会、讲座、交作业',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _room,
            decoration: const InputDecoration(
              labelText: '地点', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '日期',
                helperText: '事件只在这一天出现，不按周次重复',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  Text(_dateText),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_outlined, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionSlider(
            label: '开始节次',
            value: _start,
            min: 1,
            max: widget.sectionsPerDay,
            onChanged: (v) => setState(() {
              _start = v;
              if (_end < _start) _end = _start;
            }),
          ),
          _SectionSlider(
            label: '结束节次',
            value: _end,
            min: _start,
            max: widget.sectionsPerDay,
            onChanged: (v) => setState(() => _end = v),
          ),
          const SizedBox(height: 8),
          Text('提示：事件在课表里显示为紫色卡片带图钉图标，与课程区分',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
