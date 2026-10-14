/// 课表核心数据模型
///
/// 字段命名对齐正方教务系统（v9）导出的课表文本：
///   (1-2节)1-5周,7-11周(单),12-13周/校区:南校区/场地:2教311/教师:韦丽丽/
///   教学班:(2025-2026-2)-SZ0100801-01/教学班组成:产品241;产品242/考核方式:考试/
///   选课备注:/课程学时组成:理论:40,实践:8/周学时:4/总学时:40/学分:3
library;

/// 单次上课时段（同一门课可能一学期有多个时段，各自周次可能不同）
class CourseSlot {
  /// 星期几：1=周一 ... 7=周日
  final int weekday;

  /// 起始节次（含），1-based
  final int startSection;

  /// 结束节次（含），1-based
  final int endSection;

  /// 上课周次集合（1-based，如 {1,2,3,4,5}）
  final Set<int> weeks;

  /// 场地/教室（正方文本里叫"场地"，Web 接口里多为"教室"）
  final String room;

  /// 校区（正方文本里叫"校区"）
  final String campus;

  /// 教师（可能多人，用逗号分隔）
  final String teacher;

  const CourseSlot({
    required this.weekday,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    this.room = '',
    this.campus = '',
    this.teacher = '',
  });

  int get span => endSection - startSection + 1;

  /// 该时段是否在指定周上课
  bool inWeek(int week) => weeks.contains(week);

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'startSection': startSection,
        'endSection': endSection,
        'weeks': weeks.toList()..sort(),
        'room': room,
        'campus': campus,
        'teacher': teacher,
      };

  factory CourseSlot.fromJson(Map<String, dynamic> j) => CourseSlot(
        weekday: j['weekday'] as int,
        startSection: j['startSection'] as int,
        endSection: j['endSection'] as int,
        weeks: ((j['weeks'] as List?) ?? const []).map((e) => e as int).toSet(),
        room: (j['room'] ?? '') as String,
        campus: (j['campus'] ?? '') as String,
        teacher: (j['teacher'] ?? '') as String,
      );
}

/// 一门课程（含它的所有时段）
class Course {
  final String id;
  final String name;

  /// 教学班编号，如 (2025-2026-2)-SZ0100801-01
  final String classNo;

  /// 教学班组成，如 "产品241;产品242"
  final String classComposition;

  /// 考核方式：考试 / 考查 / 未安排
  final String assessType;

  /// 学分
  final double credits;

  /// 课程学时组成，如 "理论:40,实践:8"
  final String hourComposition;

  /// 课程类型标记（从课程名后的符号解析）：理论○ / 上机▲ / 实验■ / 实践● / 实验上机★
  final String kindMark;

  final List<CourseSlot> slots;

  /// 卡片颜色（ARGB），为空时由 UI 按名称哈希分配
  final int? color;

  const Course({
    required this.id,
    required this.name,
    this.classNo = '',
    this.classComposition = '',
    this.assessType = '',
    this.credits = 0,
    this.hourComposition = '',
    this.kindMark = '',
    this.slots = const [],
    this.color,
  });

  Course copyWith({List<CourseSlot>? slots, int? color}) => Course(
        id: id,
        name: name,
        classNo: classNo,
        classComposition: classComposition,
        assessType: assessType,
        credits: credits,
        hourComposition: hourComposition,
        kindMark: kindMark,
        slots: slots ?? this.slots,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'classNo': classNo,
        'classComposition': classComposition,
        'assessType': assessType,
        'credits': credits,
        'hourComposition': hourComposition,
        'kindMark': kindMark,
        'color': color,
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String,
        name: j['name'] as String,
        classNo: (j['classNo'] ?? '') as String,
        classComposition: (j['classComposition'] ?? '') as String,
        assessType: (j['assessType'] ?? '') as String,
        credits: ((j['credits'] ?? 0) as num).toDouble(),
        hourComposition: (j['hourComposition'] ?? '') as String,
        kindMark: (j['kindMark'] ?? '') as String,
        color: j['color'] as int?,
        slots: ((j['slots'] as List?) ?? const [])
            .map((e) => CourseSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 一节次的时间配置
class SectionTime {
  final int section; // 1-based
  final String start; // "08:30"
  final String end; // "09:15"

  const SectionTime(this.section, this.start, this.end);

  Map<String, dynamic> toJson() => {'section': section, 'start': start, 'end': end};

  factory SectionTime.fromJson(Map<String, dynamic> j) => SectionTime(
        j['section'] as int,
        j['start'] as String,
        j['end'] as String,
      );
}

/// 无固定时段的课程（实践课 / 实习 / 网课）
///
/// 来源：正方接口 `sjkList`（实践课程 + 其它课程），只有周次范围，没有星期和节次。
/// 例如：毕业实习、认识实习、软件开发综合实训、慕课类课程。
/// 这类课不会出现在周视图网格里，需要单独在课表下方展示，否则用户完全看不到。
class UnscheduledCourse {
  final String name;

  /// 周次范围原文，如 "11-14周"、"第17周"、"1-16周"
  final String weeks;

  /// 教师（可能多人，逗号分隔）
  final String teacher;

  /// 学分（字符串，来源就是字符串，可能为空）
  final String credits;

  /// 课程类型标记：实践● / 实验■ / 理论○ / 上机▲
  final String kindMark;

  /// 是否重修（cxbj=1）
  final bool retake;

  const UnscheduledCourse({
    required this.name,
    this.weeks = '',
    this.teacher = '',
    this.credits = '',
    this.kindMark = '',
    this.retake = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'weeks': weeks,
        'teacher': teacher,
        'credits': credits,
        'kindMark': kindMark,
        'retake': retake,
      };

  factory UnscheduledCourse.fromJson(Map<String, dynamic> j) => UnscheduledCourse(
        name: (j['name'] ?? '') as String,
        weeks: (j['weeks'] ?? '') as String,
        teacher: (j['teacher'] ?? '') as String,
        credits: (j['credits'] ?? '') as String,
        kindMark: (j['kindMark'] ?? '') as String,
        retake: (j['retake'] ?? false) as bool,
      );
}

/// 学生信息（从教务系统带回来，仅本地展示用）
class StudentInfo {
  final String xh; // 学号
  final String xm; // 姓名
  final String className; // 班级
  final String major; // 专业
  final String grade; // 年级

  const StudentInfo({
    this.xh = '',
    this.xm = '',
    this.className = '',
    this.major = '',
    this.grade = '',
  });

  Map<String, dynamic> toJson() =>
      {'xh': xh, 'xm': xm, 'className': className, 'major': major, 'grade': grade};

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        xh: (j['xh'] ?? '') as String,
        xm: (j['xm'] ?? '') as String,
        className: (j['className'] ?? '') as String,
        major: (j['major'] ?? '') as String,
        grade: (j['grade'] ?? '') as String,
      );
}

/// 一张课表（对应一个学期）
class Timetable {
  final String id;
  final String name; // 如 "大四上"
  final String semesterName; // 如 "2026-2027-1"
  final String xnm; // 正方学年码，如 "2026"
  final String xqm; // 正方学期码，如 "3"
  final DateTime startDate; // 第 1 周周一
  final int totalWeeks; // 学期总周数
  final int sectionsPerDay; // 一天节数
  final int weekdayStart; // 每周起始日 1=周一
  final List<SectionTime> sectionTimes;
  final List<Course> courses;
  final StudentInfo student;

  /// 无固定时段的课程（实践/实习/网课），在课表下方单独展示
  final List<UnscheduledCourse> unscheduled;

  /// 校历节假日/调休（日期 -> 是否为上课日）
  final Map<String, bool> holidays;

  /// 手动添加的一次性事件（只在某一天，不按周次重复）
  final List<TimetableEvent> events;

  const Timetable({
    required this.id,
    required this.name,
    this.semesterName = '',
    this.xnm = '',
    this.xqm = '',
    required this.startDate,
    this.totalWeeks = 20,
    this.sectionsPerDay = 10,
    this.weekdayStart = 1,
    this.sectionTimes = const [],
    this.courses = const [],
    this.student = const StudentInfo(),
    this.unscheduled = const [],
    this.holidays = const {},
    this.events = const [],
  });

  /// 计算某日期属于第几周（可能为 0 或负，表示学期外）
  int weekOf(DateTime date) {
    final d0 = DateTime(startDate.year, startDate.month, startDate.day);
    final d = DateTime(date.year, date.month, date.day);
    final diffDays = d.difference(d0).inDays;
    return (diffDays / 7).floor() + 1;
  }

  /// 当前周（相对今天）
  int currentWeek([DateTime? now]) => weekOf(now ?? DateTime.now());

  /// 取某周某天的课程时段（用于渲染单周网格）
  List<({Course course, CourseSlot slot})> slotsAt(int weekday, int week) {
    final out = <({Course course, CourseSlot slot})>[];
    for (final c in courses) {
      for (final s in c.slots) {
        if (s.weekday == weekday && s.inWeek(week)) {
          out.add((course: c, slot: s));
        }
      }
    }
    return out;
  }

  Timetable copyWith({
    String? id,
    String? name,
    String? semesterName,
    String? xnm,
    String? xqm,
    DateTime? startDate,
    int? totalWeeks,
    int? sectionsPerDay,
    int? weekdayStart,
    List<SectionTime>? sectionTimes,
    List<Course>? courses,
    StudentInfo? student,
    List<UnscheduledCourse>? unscheduled,
    Map<String, bool>? holidays,
    List<TimetableEvent>? events,
  }) =>
      Timetable(
        id: id ?? this.id,
        name: name ?? this.name,
        semesterName: semesterName ?? this.semesterName,
        xnm: xnm ?? this.xnm,
        xqm: xqm ?? this.xqm,
        startDate: startDate ?? this.startDate,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        sectionsPerDay: sectionsPerDay ?? this.sectionsPerDay,
        weekdayStart: weekdayStart ?? this.weekdayStart,
        sectionTimes: sectionTimes ?? this.sectionTimes,
        courses: courses ?? this.courses,
        student: student ?? this.student,
        unscheduled: unscheduled ?? this.unscheduled,
        holidays: holidays ?? this.holidays,
        events: events ?? this.events,
      );

  /// 删掉某门课的**某一个时段**（周X 第N-M节）
  ///
  /// 返回新的 Timetable（本类是只读的，不改自己）。
  /// 如果这是该课最后一个时段，整门课会一起消失 ——
  /// 否则会留下一个没有任何时段的空课程，在界面上看不见却又删不掉。
  ///
  /// 定位用 `identical` 而不是 `==`：同一门课的 slots 里可能存在两条
  /// 内容完全一样的记录（接口重复返回），按值删会一次删掉两条。
  Timetable removeSlotOf(Course course, CourseSlot slot) {
    final i = course.slots.indexWhere((s) => identical(s, slot));
    if (i < 0) return this;
    final kept = List<CourseSlot>.from(course.slots)..removeAt(i);
    if (kept.isEmpty) return removeCourse(course);
    return copyWith(
      courses: courses
          .map((c) => identical(c, course) ? c.copyWith(slots: kept) : c)
          .toList(),
    );
  }

  /// 删掉整门课（一周里的所有时段）
  Timetable removeCourse(Course course) => copyWith(
        courses: courses.where((c) => !identical(c, course)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'semesterName': semesterName,
        'xnm': xnm,
        'xqm': xqm,
        'startDate': startDate.toIso8601String(),
        'totalWeeks': totalWeeks,
        'sectionsPerDay': sectionsPerDay,
        'weekdayStart': weekdayStart,
        'sectionTimes': sectionTimes.map((s) => s.toJson()).toList(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'student': student.toJson(),
        'unscheduled': unscheduled.map((u) => u.toJson()).toList(),
        'holidays': holidays,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory Timetable.fromJson(Map<String, dynamic> j) => Timetable(
        id: j['id'] as String,
        name: j['name'] as String,
        semesterName: (j['semesterName'] ?? '') as String,
        xnm: (j['xnm'] ?? '') as String,
        xqm: (j['xqm'] ?? '') as String,
        startDate: DateTime.parse(j['startDate'] as String),
        totalWeeks: (j['totalWeeks'] ?? 20) as int,
        sectionsPerDay: (j['sectionsPerDay'] ?? 10) as int,
        weekdayStart: (j['weekdayStart'] ?? 1) as int,
        sectionTimes: ((j['sectionTimes'] as List?) ?? const [])
            .map((e) => SectionTime.fromJson(e as Map<String, dynamic>))
            .toList(),
        courses: ((j['courses'] as List?) ?? const [])
            .map((e) => Course.fromJson(e as Map<String, dynamic>))
            .toList(),
        student: j['student'] == null
            ? const StudentInfo()
            : StudentInfo.fromJson((j['student'] as Map).cast<String, dynamic>()),
        unscheduled: ((j['unscheduled'] as List?) ?? const [])
            .map((e) => UnscheduledCourse.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        holidays: ((j['holidays'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as bool)),
        events: ((j['events'] as List?) ?? const [])
            .map((e) => TimetableEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}


/// 推断默认的「学期第一天」（第 1 周周一）
///
/// 为什么需要默认值：教务系统的课表接口**只给周次、不给日期**，
/// 所有日期都靠这个基准往后推。所以给一个合理猜测让用户微调，
/// 比让他从零选好得多。
///
/// 规则：8 月及以后 → 当年 9 月 1 日；否则 → 当年 3 月 1 日
/// （对应国内高校普遍的秋季/春季学期）。
DateTime defaultSemesterStart([DateTime? now]) {
  final d = now ?? DateTime.now();
  return d.month >= 8 ? DateTime(d.year, 9, 1) : DateTime(d.year, 3, 1);
}

/// 生成默认课表名，如 `2026课表`
String defaultTimetableName(DateTime startDate) => '${startDate.year}课表';


/// 一次性事件（只在某一天发生，不按周次重复）
///
/// 与 [Course] 的区别：
///   · Course 按「周次 + 星期几」重复出现（每周同一时间）
///   · TimetableEvent 绑定在**具体日期**上，如「10 月 20 日 下午开会」
///
/// 为了让事件也能画进课表网格，这里用节次（而不是具体时刻）表示时段。
class TimetableEvent {
  final String id;
  final String title;

  /// 具体日期（只用到年月日）
  final DateTime date;

  /// 起始/结束节次（复用课表的节次网格摆放）
  final int startSection;
  final int endSection;

  final String location;

  const TimetableEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.startSection,
    required this.endSection,
    this.location = '',
  });

  /// 只保留年月日的日期
  DateTime get day => DateTime(date.year, date.month, date.day);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'startSection': startSection,
        'endSection': endSection,
        'location': location,
      };

  factory TimetableEvent.fromJson(Map<String, dynamic> j) => TimetableEvent(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
        startSection: ((j['startSection'] as num?)?.toInt() ?? 1).clamp(1, 20),
        endSection: ((j['endSection'] as num?)?.toInt() ?? 1).clamp(1, 20),
        location: (j['location'] ?? '').toString(),
      );
}
