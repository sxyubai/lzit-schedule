/// ICS（iCalendar）导出
///
/// 用途：把课表导进手机自带日历，用系统日历的提醒功能替代自研通知
///      （省事、可靠、不用申请通知权限，也不用做后台保活）
///
/// 采用 UTC 时间（`Z` 后缀）+ TZID 前缀的方式表达北京时间，
/// 兼容性最好：不依赖对方日历是否认识 Asia/Shanghai。
library;

import '../models/timetable.dart';

class IcsExport {
  /// 生成 ICS 文本
  ///
  /// [expandWeeks] 为 true 时把每个时段按周次展开成独立事件（推荐，
  /// 这样日历里每节课都是具体日期，能正常提醒）。
  /// 为 false 时生成带 `RRULE` 的重复事件（更紧凑，但单双周表达受限）。
  static String generate(
    Timetable tt, {
    bool expandWeeks = true,
    int alarmMinutesBefore = 20,
    int maxEvents = 4000,
  }) {
    final buf = StringBuffer();
    buf.writeln('BEGIN:VCALENDAR');
    buf.writeln('VERSION:2.0');
    buf.writeln('PRODID:-//lzit_schedule//timetable//CN');
    buf.writeln('CALSCALE:GREGORIAN');
    buf.writeln('METHOD:PUBLISH');
    buf.writeln('X-WR-CALNAME:${_escape(tt.name)}');
    if (tt.semesterName.isNotEmpty) {
      buf.writeln('X-WR-CALDESC:${_escape(tt.semesterName)} 课表');
    }

    final now = DateTime.now().toUtc();
    final stamp = _fmtUtc(now);
    var count = 0;
    var slotIndex = 0;

    for (final course in tt.courses) {
      for (final slot in course.slots) {
        slotIndex++;
        if (slot.weeks.isEmpty) continue;
        final weeks = slot.weeks.toList()..sort();
        for (final week in weeks) {
          if (count >= maxEvents) break;
          final date = tt.startDate.add(Duration(days: (week - 1) * 7 + (slot.weekday - 1)));
          final start = _atTime(date, _startTimeOf(tt, slot.startSection));
          final end = _atTime(date, _endTimeOf(tt, slot.endSection));
          if (start == null || end == null) continue;

          buf.writeln('BEGIN:VEVENT');
          // UID 必须唯一：同一门课同一时段可能有多个教室/教师（正方数据如此），
          // 所以带上 slot 索引，避免日历把不同事件当同一个互相覆盖。
          buf.writeln('UID:lzit-${tt.id}-s$slotIndex-w$week-${slot.weekday}-'
              '${slot.startSection}@lzit_schedule');
          buf.writeln('DTSTAMP:$stamp');
          buf.writeln('DTSTART:${_fmtUtc(start.toUtc())}');
          buf.writeln('DTEND:${_fmtUtc(end.toUtc())}');
          buf.writeln('SUMMARY:${_escape(_summary(course, slot))}');
          buf.writeln('LOCATION:${_escape(_location(slot))}');
          buf.writeln('DESCRIPTION:${_escape(_description(course, slot, week))}');
          if (alarmMinutesBefore > 0) {
            buf.writeln('BEGIN:VALARM');
            buf.writeln('ACTION:DISPLAY');
            buf.writeln('TRIGGER:-PT${alarmMinutesBefore}M');
            buf.writeln('DESCRIPTION:${_escape(course.name)}');
            buf.writeln('END:VALARM');
          }
          buf.writeln('END:VEVENT');
          count++;
        }
      }
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  static String _summary(Course c, CourseSlot s) {
    final parts = [c.name];
    if (s.room.isNotEmpty) parts.add('@${s.room}');
    return parts.join(' ');
  }

  static String _location(CourseSlot s) {
    final parts = <String>[];
    if (s.campus.isNotEmpty) parts.add(s.campus);
    if (s.room.isNotEmpty) parts.add(s.room);
    return parts.join(' ');
  }

  static String _description(Course c, CourseSlot s, int week) {
    final lines = <String>[
      '第 $week 周',
      '节次：${s.startSection}-${s.endSection}节',
      if (s.teacher.isNotEmpty) '教师：${s.teacher}',
      if (c.classNo.isNotEmpty) '教学班：${c.classNo}',
      if (c.credits > 0) '学分：${c.credits}',
      if (c.assessType.isNotEmpty) '考核：${c.assessType}',
      if (c.kindMark.isNotEmpty) '类型：${c.kindMark}',
      if (c.classComposition.isNotEmpty) '组成：${c.classComposition}',
    ];
    return lines.join('\\n');
  }

  /// 从课表的节次时间表里取开始时间
  static ({int h, int m})? _startTimeOf(Timetable tt, int section) {
    for (final t in tt.sectionTimes) {
      if (t.section == section) {
        final parsed = _parseHm(t.start);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static ({int h, int m})? _endTimeOf(Timetable tt, int section) {
    for (final t in tt.sectionTimes) {
      if (t.section == section) {
        final parsed = _parseHm(t.end);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static ({int h, int m})? _parseHm(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    return (h: int.parse(m.group(1)!), m: int.parse(m.group(2)!));
  }

  /// 构造"某天的某时刻"（本地时间，导出时再转 UTC）
  static DateTime? _atTime(DateTime day, ({int h, int m})? hm) {
    if (hm == null) return null;
    return DateTime(day.year, day.month, day.day, hm.h, hm.m);
  }

  /// iCalendar UTC 时间格式：20260831T003000Z
  static String _fmtUtc(DateTime utc) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${p2(utc.month)}${p2(utc.day)}T'
        '${p2(utc.hour)}${p2(utc.minute)}${p2(utc.second)}Z';
  }

  /// ICS 文本转义：反斜杠、分号、逗号、换行
  static String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');
}
