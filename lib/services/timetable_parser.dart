/// 正方课表文本解析器
///
/// 处理两种来源：
///   A) 正方导出的课表文本（PDF/打印页复制），格式：
///      "(1-2节)1-5周,7-11周(单),12-13周/校区:南校区/场地:2教311/教师:韦丽丽/"
///      "教学班:(2025-2026-2)-SZ0100801-01/教学班组成:产品241;产品242/考核方式:考试/"
///      "选课备注:/课程学时组成:理论:40,实践:8/周学时:4/总学时:40/学分:3"
///   B) 正方 Web 课表接口返回的 JSON 数组（字段名待实测确认，见 parseWebRecords）
library;

import '../models/timetable.dart';

/// 解析周次表达式，支持：
///   "1-5周"          -> 1,2,3,4,5
///   "7-11周(单)"     -> 7,9,11
///   "4-6周(双)"      -> 4,6
///   "3周"            -> 3
///   "1-5周,7周,9-11周" -> 合并
Set<int> parseWeeks(String expr) {
  final weeks = <int>{};
  if (expr.trim().isEmpty) return weeks;

  // 统一括号与减号
  var s = expr
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('—', '-')
      .replaceAll('～', '-')
      .replaceAll('~', '-')
      .replaceAll(' ', '');

  // 判断整段是否带单/双周限定（作用于本段所有区间）
  for (final part in s.split(RegExp(r'[,，;；]'))) {
    if (part.isEmpty) continue;
    final isOdd = part.contains('单');
    final isEven = part.contains('双');
    // 去掉"周"和"(单)/(双)"等修饰
    final cleaned = part
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll('周', '')
        .replaceAll('第', '');
    if (cleaned.isEmpty) continue;

    final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(cleaned);
    if (m == null) {
      // 容错：抓出所有数字，至少别丢数据
      final nums = RegExp(r'\d+').allMatches(cleaned).map((e) => int.parse(e.group(0)!)).toList();
      if (nums.length == 1) {
        final w = nums.first;
        if (isOdd && w.isEven) continue;
        if (isEven && w.isOdd) continue;
        weeks.add(w);
      } else if (nums.length >= 2) {
        for (var w = nums.first; w <= nums[1]; w++) {
          if (isOdd && w.isEven) continue;
          if (isEven && w.isOdd) continue;
          weeks.add(w);
        }
      }
      continue;
    }

    final a = int.parse(m.group(1)!);
    final b = m.group(2) == null ? a : int.parse(m.group(2)!);
    for (var w = a; w <= b; w++) {
      if (isOdd && w.isEven) continue;
      if (isEven && w.isOdd) continue;
      weeks.add(w);
    }
  }
  return weeks;
}

/// 解析节次表达式，如 "1-2" / "3-4" / "9-10" / "7"
({int start, int end})? parseSections(String expr) {
  final cleaned = expr.replaceAll('节', '').replaceAll('第', '').replaceAll(' ', '');
  final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(cleaned);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = m.group(2) == null ? a : int.parse(m.group(2)!);
  return (start: a, end: b);
}

/// 课程名后的类型标记
const _kindMarks = {
  '●': '实践',
  '★': '实验上机',
  '○': '理论',
  '▲': '上机',
  '■': '实验',
};

/// 解析单条"课程格子"文本（正方打印页/PDF 里一个格子 = 一门课的一个时段）
///
/// 输入示例：
/// "马克思主义基本原理○(1-2节)1-5周,7-11周(单),12-13周/校区:南校区/场地:2教311/
///  教师:韦丽丽/教学班:(2025-2026-2)-SZ0100801-01/教学班组成:产品241;产品242/
///  考核方式:考试/选课备注:/课程学时组成:理论:40,实践:8/周学时:4/总学时:40/学分:3"
Course? parseCourseCell(String raw, {required int weekday}) {
  var text = raw.replaceAll('\r', '').replaceAll('\n', ' ').trim();
  if (text.isEmpty) return null;

  // 1) 节次：第一个 "(n-m节)"
  final secMatch = RegExp(r'\((\d+)(?:-(\d+))?\s*节\)').firstMatch(text);
  if (secMatch == null) return null;
  final startSec = int.parse(secMatch.group(1)!);
  final endSec = secMatch.group(2) == null ? startSec : int.parse(secMatch.group(2)!);

  // 2) 课程名 = 节次前的部分，去掉类型符号
  var namePart = text.substring(0, secMatch.start).trim();
  var kind = '';
  for (final entry in _kindMarks.entries) {
    if (namePart.endsWith(entry.key)) {
      kind = entry.value;
      namePart = namePart.substring(0, namePart.length - entry.key.length).trim();
      break;
    }
  }
  if (namePart.isEmpty) return null;

  // 3) 周次 = 节次后到第一个 "/" 前的部分
  final afterSec = text.substring(secMatch.end);
  final slashIdx = afterSec.indexOf('/');
  final weekExpr = slashIdx >= 0 ? afterSec.substring(0, slashIdx) : afterSec;
  final weeks = parseWeeks(weekExpr);

  // 4) 其余字段按 "标签:值" 切分
  final rest = slashIdx >= 0 ? afterSec.substring(slashIdx + 1) : '';
  String field(String label) {
    final m = RegExp('$label\\s*[:：]\\s*([^/]*)').firstMatch(rest);
    return m == null ? '' : m.group(1)!.trim();
  }

  final room = field('场地');
  final roomAlt = room.isEmpty ? field('教室') : room;
  final campus = field('校区');
  final teacher = field('教师');
  final classNo = field('教学班');
  final comp = field('教学班组成');
  final assess = field('考核方式');
  final hours = field('课程学时组成');
  final creditStr = field('学分');
  final credits = double.tryParse(creditStr) ?? 0;

  final slot = CourseSlot(
    weekday: weekday,
    startSection: startSec,
    endSection: endSec,
    weeks: weeks.isEmpty ? {1} : weeks,
    room: roomAlt,
    campus: campus,
    teacher: teacher,
  );

  return Course(
    id: '$namePart|$classNo',
    name: namePart,
    classNo: classNo,
    classComposition: comp,
    assessType: assess,
    credits: credits,
    hourComposition: hours,
    kindMark: kind,
    slots: [slot],
  );
}

/// 把同名同教学班的多条记录合并成一门课（多个时段）
List<Course> mergeCourses(List<Course> cells) {
  final map = <String, Course>{};
  for (final c in cells) {
    final existing = map[c.id];
    if (existing == null) {
      map[c.id] = c;
    } else {
      map[c.id] = existing.copyWith(slots: [...existing.slots, ...c.slots]);
    }
  }
  return map.values.toList();
}

/// 解析一整周的课表网格文本（7 列 × N 行，用 tab/多空格分隔）
///
/// 说明：正方打印页的行列顺序是"先节次后星期"，同一节次行的 7 个格子按周一..周日排列。
/// 这里按行解析：每行取第 2..8 个字段作为周一..周日的格子。
List<Course> parseGrid(String gridText) {
  final cells = <Course>[];
  final lines = gridText.split('\n');
  for (final line in lines) {
    final parts = line.split(RegExp(r'\t+|\s{3,}')).map((e) => e.trim()).toList();
    if (parts.length < 2) continue;
    // 第一个字段通常是节次（如 "1-2" 或 "1"），后面 7 个是周一..周日
    for (var i = 1; i < parts.length && i <= 7; i++) {
      final cell = parts[i];
      if (cell.isEmpty) continue;
      final c = parseCourseCell(cell, weekday: i);
      if (c != null) cells.add(c);
    }
  }
  return mergeCourses(cells);
}

/// 解析正方 Web 课表接口返回的记录列表
///
/// 注意：字段名以实测为准，这里对常见别名做兼容。
/// 正方 web 端典型字段：kcmc(课程名称) xqj(星期几) jcs(节次) zcd(周次段)
///   cdmc(场地名称) xm(教师姓名) xnm/xqm(学年学期) jxbmc(教学班)
List<Course> parseWebRecords(List<dynamic> records) {
  final cells = <Course>[];
  for (final raw in records) {
    if (raw is! Map) continue;
    final m = raw.cast<String, dynamic>();
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    final name = pick(['kcmc', 'courseName', 'kcmcBz', '课程名称']);
    if (name.isEmpty) continue;

    final xqj = int.tryParse(pick(['xqj', 'weekday'])) ?? 1;
    final jcsRaw = pick(['jcs', 'jcsBz', '节次']); // 可能是 "1-2" 或 "0102"
    final jcList = pick(['jcList', 'jcsList']);

    int startSec, endSec;
    final parsed = parseSections(jcsRaw);
    if (parsed != null) {
      startSec = parsed.start;
      endSec = parsed.end;
    } else if (jcsRaw.length == 4) {
      // "0102" 形式
      startSec = int.tryParse(jcsRaw.substring(0, 2)) ?? 1;
      endSec = int.tryParse(jcsRaw.substring(2, 4)) ?? startSec;
    } else if (jcList.isNotEmpty) {
      final p2 = parseSections(jcList);
      startSec = p2?.start ?? 1;
      endSec = p2?.end ?? startSec;
    } else {
      startSec = endSec = 1;
    }

    // 周次：zcd 形如 "1-5,7-11" 或 "1-5周,7-11周(单)"
    var weekExpr = pick(['zcd', 'zcdBz', '周次']);
    if (!weekExpr.contains('周')) weekExpr = '$weekExpr周';
    final weeks = parseWeeks(weekExpr);

    final room = pick(['cdmc', 'cdmcBz', '教室', '场地', 'jsmc']);
    final teacher = pick(['xm', 'jsxm', '教师', 'teacher']);
    final classNo = pick(['jxbmc', 'jxb_id', '教学班']);
    final credits = double.tryParse(pick(['xf', '学分'])) ?? 0;
    final assess = pick(['khfsmc', 'khfs', '考核方式']);
    final comp = pick(['jxbzc', '教学班组成', 'bz']);
    final kind = _kindBySymbol(pick(['xslxbj', '课程性质符号']));

    cells.add(Course(
      id: '$name|$classNo|$kind',
      name: name,
      classNo: classNo,
      classComposition: comp,
      assessType: assess,
      credits: credits,
      hourComposition: pick(['kcxszc', '课程学时组成']),
      kindMark: kind,
      slots: [
        CourseSlot(
          weekday: xqj,
          startSection: startSec,
          endSection: endSec,
          weeks: weeks.isEmpty ? {1} : weeks,
          room: room,
          campus: pick(['xqmc', '校区']),
          teacher: teacher,
        ),
      ],
    ));
  }
  return mergeCourses(cells);
}

String _kindBySymbol(String symbol) {
  switch (symbol) {
    case '●':
      return '实践';
    case '★':
      return '实验上机';
    case '■':
      return '实验';
    case '▲':
      return '上机';
    case '○':
      return '理论';
    default:
      return '';
  }
}

/// sjkList 里的一条「无固定时段课程」（实践/实习/网课）
///
/// 这类课只有周次范围（`qsjsz`），没有星期和节次，塞不进周视图网格。
/// 两个附加信息都不能丢：
///   · 类型标记 —— 藏在 `sjkcgs` 里，形如 "毕业实习●谭超.../11-14周"，
///     末尾那个 ●○▲■★ 才是课程性质（kcmc 本身不带符号）
///   · 是否重修 —— `cxbj == '1'` 或 `cxbjmc` 非空
typedef ZfUnscheduled = ({
  String name,
  String weeks,
  String teacher,
  String credits,
  String kindMark,
  bool retake,
});

/// 正方「学生课表查询」接口完整响应
class ZfTimetableResponse {
  final List<Course> courses;

  /// 学生信息（来自 xsxx）
  final String xh;
  final String xm;
  final String className;
  final String major;
  final String grade;

  /// 学年学期
  final String xnm;
  final String xqm;
  final String xnmc; // 2026-2027

  /// 实践课程 / 其它课程（无固定时段的课，来自 sjkList）
  final List<ZfUnscheduled> unscheduled;

  const ZfTimetableResponse({
    required this.courses,
    this.xh = '',
    this.xm = '',
    this.className = '',
    this.major = '',
    this.grade = '',
    this.xnm = '',
    this.xqm = '',
    this.xnmc = '',
    this.unscheduled = const [],
  });

  String get semesterName {
    if (xnmc.isNotEmpty) {
      final term = _termNumber(xqm);
      return term.isEmpty ? xnmc : '$xnmc-$term';
    }
    return '';
  }

  static String _termNumber(String xqm) {
    switch (xqm) {
      case '1':
        return '1';
      case '12':
        return '2';
      case '3':
        return '1';
      case '16':
        return '2';
      default:
        return '';
    }
  }
}

/// 解析正方课表接口的完整 JSON 响应
///
/// 结构（实测）：
/// {
///   "xsxx": {"XH":"20222441","XM":"黄之程","BJMC":"软件232","ZYMC":"软件工程",
///            "NJDM_ID":"2023","XNM":"2026","XQM":"3","XNMC":"2026-2027"},
///   "kbList": [ 有固定时段的课，含 xqj/jcs/zcd/cdmc/xm ... ],
///   "sjkList": [ 实践课/其它课，只有 qsjsz 周次范围，无节次 ],
///   "xqjmcMap": {"1":"星期一", ...}
/// }
ZfTimetableResponse parseZfResponse(Map<String, dynamic> json) {
  final xsxx = (json['xsxx'] as Map?)?.cast<String, dynamic>() ?? const {};
  String sv(String k) => (xsxx[k] ?? '').toString();

  final kbList = (json['kbList'] as List?) ?? const [];
  final courses = parseWebRecords(kbList);

  final unscheduled = <ZfUnscheduled>[];
  for (final raw in (json['sjkList'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final m = raw.cast<String, dynamic>();
    var name = (m['kcmc'] ?? '').toString().trim();
    if (name.isEmpty) continue;

    // 类型标记：kcmc 通常不带符号，要从 sjkcgs 里认
    // （sjkcgs 形如 "操作系统○卢光云(共8周)/6-13周"）。
    // 兼容 kcmc 自带符号的写法（"毕业实习●"），优先级更高。
    var kind = '';
    for (final e in _kindMarks.entries) {
      if (name.endsWith(e.key)) {
        kind = e.value;
        name = name.substring(0, name.length - e.key.length).trim();
        break;
      }
    }
    if (kind.isEmpty) {
      final group = (m['sjkcgs'] ?? '').toString();
      for (final e in _kindMarks.entries) {
        if (group.contains(e.key)) {
          kind = e.value;
          break;
        }
      }
    }

    final cxbj = (m['cxbj'] ?? '').toString();
    final cxbjmc = (m['cxbjmc'] ?? '').toString();

    unscheduled.add((
      name: name,
      weeks: (m['qsjsz'] ?? '').toString().trim(),
      teacher: (m['jsxm'] ?? '').toString().trim(),
      credits: (m['xf'] ?? '').toString().trim(),
      kindMark: kind,
      retake: cxbj == '1' || cxbjmc.isNotEmpty,
    ));
  }

  return ZfTimetableResponse(
    courses: courses,
    xh: sv('XH'),
    xm: sv('XM'),
    className: sv('BJMC'),
    major: sv('ZYMC'),
    grade: sv('NJDM_ID'),
    xnm: sv('XNM'),
    xqm: sv('XQM'),
    xnmc: sv('XNMC'),
    unscheduled: unscheduled,
  );
}
