/// 节次时间预设
///
/// 数据来源：用户 WakeUp 课程表截图（柳州工学院-南校区，每节 45 分钟）
///   上午：1节 08:30-09:15 / 2节 09:20-10:05 / 3节 10:25-11:10 / 4节 11:15-12:00
///   下午：5节 14:00-14:45 / 6节 14:50-15:35 / 7节 15:55-16:40 / 8节 16:45-17:30
///   晚上：9节 19:30-20:15（截图只到第 9 节，第 10 节按同日节奏补 20:20-21:05）
library;

import '../models/timetable.dart';

class SectionPreset {
  final String id;
  final String name;
  final int sectionsPerDay;
  final List<SectionTime> times;

  const SectionPreset({
    required this.id,
    required this.name,
    required this.sectionsPerDay,
    required this.times,
  });
}

/// 柳州工学院（南校区）默认作息
SectionPreset lzhitSouthPreset() => SectionPreset(
      id: 'lzhit-south',
      name: '柳州工学院-南校区',
      sectionsPerDay: 10,
      times: const [
        SectionTime(1, '08:30', '09:15'),
        SectionTime(2, '09:20', '10:05'),
        SectionTime(3, '10:25', '11:10'),
        SectionTime(4, '11:15', '12:00'),
        SectionTime(5, '14:00', '14:45'),
        SectionTime(6, '14:50', '15:35'),
        SectionTime(7, '15:55', '16:40'),
        SectionTime(8, '16:45', '17:30'),
        SectionTime(9, '19:30', '20:15'),
        SectionTime(10, '20:20', '21:05'),
      ],
    );

List<SectionPreset> defaultSectionPresets() => [lzhitSouthPreset()];
