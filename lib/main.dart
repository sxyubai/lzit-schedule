import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'models/appearance.dart';
import 'models/timetable.dart';
import 'pages/about_page.dart';
import 'pages/appearance_page.dart';
import 'pages/course_list_page.dart';
import 'pages/import_page.dart';
import 'pages/reminder_settings.dart';
import 'services/ics_export.dart';
import 'services/reminder_service.dart';
import 'services/slot_cluster.dart';
import 'services/slot_prefs.dart';
import 'services/timetable_store.dart';
import 'widgets/week_view.dart';

void main() {
  runApp(const LzitScheduleApp());
}

class LzitScheduleApp extends StatelessWidget {
  const LzitScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '柳工课表',
      debugShowCheckedModeBanner: false,
      // 系统自带组件的中文化（不加这段，showDatePicker 等是英文界面）
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2B6CB0),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2B6CB0),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Timetable? _timetable;
  Object? _error;
  int _week = 1;
  int _tab = 0;
  bool _followToday = true;
  SlotPrefs _slotPrefs = SlotPrefs.empty();
  final ReminderService _reminders = ReminderService();

  /// 周视图分页控制器：支持左右滑动切换周
  final PageController _pageController = PageController();
  bool _pageReady = false; // 首帧建好后才能 jumpToPage
  bool _loadingDone = false; // 本地课表读取完成（用于区分"加载中"与"确实没有课表"）
  Appearance _appearance = const Appearance(); // 外观（背景图/透明度等）
  final AppearanceStore _appearanceStore = AppearanceStore();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 切到第 [week] 周（可带动画），并同步分页控制器
  void _goToWeek(int week, {bool animate = true}) {
    final tt = _timetable;
    if (tt == null) return;
    final target = week.clamp(1, tt.totalWeeks);
    setState(() {
      _week = target;
      _followToday = target == tt.currentWeek();
    });
    if (!_pageReady || !_pageController.hasClients) return;
    final page = (target - 1).toDouble();
    if (animate) {
      _pageController.animateToPage(
        target - 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else if ((_pageController.page ?? page) != page) {
      _pageController.jumpToPage(target - 1);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 冲突课程的显示偏好（按「时段槽位」记忆，跨周次同步）
    try {
      _slotPrefs = await SlotPrefs.load();
    } catch (_) {
      _slotPrefs = SlotPrefs.empty();
    }

    // 外观配置（背景图/透明度/圆角/格子高度）
    try {
      final a = await _appearanceStore.load();
      if (mounted) setState(() => _appearance = a);
    } catch (e) {
      debugPrint('读取外观配置失败: $e');
    }

    try {
      // 只加载用户自己导入的课表。
      // ⚠️ 刻意**不再内置任何课表数据**：内置数据会带上真实学号/姓名/班级，
      // 而 APK 的 assets 是明文可解包的。首次使用走"空课表 → 引导导入"。
      final store = TimetableStore();
      final saved = await store.loadAll();
      if (saved.isNotEmpty) {
        final tt = saved.first;
        setState(() {
          _timetable = tt;
          _week = tt.currentWeek().clamp(1, tt.totalWeeks);
        });
        _syncPageToWeek(tt);
        unawaited(_restoreReminders(tt));
        return;
      }
    } catch (e) {
      debugPrint('读取本地课表失败: $e');
    }

    // 没有任何课表 → 保持 _timetable 为 null，由界面显示导入引导
    if (mounted) {
      setState(() {
        _loadingDone = true;
      });
    }
  }

  /// 首帧渲染完成后，把分页控制器对齐到当前周
  ///
  /// 第一次打开要停在本周；从「课程」页切回来时也确保位置正确。
  void _syncPageToWeek(Timetable tt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageReady = true;
      final target = _week.clamp(1, tt.totalWeeks) - 1;
      if (_pageController.hasClients && (_pageController.page ?? 0).round() != target) {
        _pageController.jumpToPage(target);
      }
    });
  }

  /// 设置「本学期第 1 周周一」
  ///
  /// 为什么必须让用户设置：教务系统的课表**只有周次、没有日期**，
  /// 所有日期（表头显示、提醒排期、第几周判断）都从这一个基准往后推。
  /// 基准错一周，整张表头的日期就全错，提醒也会全部提前/延后一周。
  Future<void> _editSemesterStart() async {
    final tt = _timetable;
    if (tt == null) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: tt.startDate,
      firstDate: DateTime(tt.startDate.year - 1, 1, 1),
      lastDate: DateTime(tt.startDate.year + 2, 12, 31),
      helpText: '选择本学期第一周的周一',
      fieldLabelText: '日期',
    );
    if (picked == null || !mounted) return;

    final fixed = DateTime(picked.year, picked.month, picked.day);
    // 强制落在周一，避免用户选了个周三导致后面所有日期偏移
    final monday = fixed.subtract(Duration(days: fixed.weekday - 1));
    final updated = tt.copyWith(startDate: monday);

    await TimetableStore().save(updated);
    if (!mounted) return;

    setState(() {
      _timetable = updated;
      // 基准变了 → 当前周可能也变了，重新定位
      _week = updated.currentWeek().clamp(1, updated.totalWeeks);
      _followToday = true;
    });
    _syncPageToWeek(updated);
    unawaited(_restoreReminders(updated));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '学期第一天已设为 ${monday.year}/${monday.month}/${monday.day}（第 1 周周一），'
          '当前第 ${updated.currentWeek()} 周',
        ),
      ),
    );
  }

  /// 背景图层：背景图（按用户设的透明度）+ 压暗层
  ///
  /// 课程文字画在卡片之上，所以无论背景多花，文字都不会看不清。
  Widget _backgroundLayer() {
    if (!_appearance.hasBackground) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: _appearance.backgroundOpacity,
          child: Image.file(
            File(_appearance.backgroundPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        if (_appearance.backgroundDim > 0.001)
          ColoredBox(
            color: Colors.black.withValues(alpha: _appearance.backgroundDim),
          ),
      ],
    );
  }

  /// 打开外观设置（改动实时生效并持久化）
  Future<void> _openAppearance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppearancePage(
          appearance: _appearance,
          onChanged: (a) {
            setState(() => _appearance = a);
            unawaited(_appearanceStore.save(a));
          },
        ),
      ),
    );
  }

  /// 打开「关于」页
  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutPage()),
    );
  }

  /// 启动时恢复提醒计划
  ///
  /// 用户开过提醒的话，每次启动重新排一遍（成本低，且能自动跟上新课表/新学期）。
  Future<void> _restoreReminders(Timetable tt) async {
    try {
      final s = await ReminderSettings.load();
      if (!s.enabled) return;
      await _reminders.reschedule(tt, minutesBefore: s.minutesBefore);
    } catch (e) {
      debugPrint('恢复提醒失败（不影响使用）: $e');
    }
  }

  Future<void> _openReminderSettings() async {
    final tt = _timetable;
    if (tt == null) return;
    try {
      await showReminderSettings(context, timetable: tt, service: _reminders);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提醒功能异常：$e')),
      );
    }
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportPage(
          onImported: (tt) async {
            await TimetableStore().save(tt);
            if (!mounted) return;
            setState(() {
              _timetable = tt;
            });
            // 导入的是新学期的课表 → 跳到它自己的当前周
            _goToWeek(tt.currentWeek(), animate: false);
            _syncPageToWeek(tt);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已导入 ${tt.courses.length} 门课程')),
            );
          },
        ),
      ),
    );
  }

  /// 导出 ICS 到外部存储，用户可用日历 App 打开导入
  ///
  /// 上课提醒交给系统日历，不用自己写通知/保活。
  /// 注意：这里不使用 share_plus —— 它与 Flutter 3.44 的 Built-in Kotlin 冲突。
  Future<void> _exportIcs() async {
    final tt = _timetable;
    if (tt == null) return;
    try {
      final ics = IcsExport.generate(tt, alarmMinutesBefore: 20);
      // Android: getExternalStorageDirectory -> /storage/emulated/0/Android/data/<pkg>/files
      // 先试外部目录（用户能用文件管理器找到），失败退回应用文档目录
      Directory? dir;
      try {
        dir = await getExternalStorageDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final safeName = tt.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
      final file = File('${dir.path}/$safeName.ics');
      await file.writeAsString(ics, flush: true);

      final events = 'BEGIN:VEVENT'.allMatches(ics).length;
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('课表已导出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('共 $events 个上课事件（含提前 20 分钟提醒）'),
              const SizedBox(height: 12),
              const Text('文件位置：', style: TextStyle(fontSize: 12, color: Colors.grey)),
              SelectableText(file.path, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text(
                '用手机「文件管理」找到它，选择用「日历」打开即可导入。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('课表')),
        body: Center(child: Text('加载失败：$_error')),
      );
    }
    final tt = _timetable;
    if (tt == null) {
      // 读完了但确实没有课表 → 引导导入（不再内置任何个人数据）
      if (!_loadingDone) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('课表'),
          actions: [
            // 空课表时也能进外观设置（可以先把背景配好再导入）
            IconButton(
              tooltip: '外观设置',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _openAppearance,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_note_outlined,
                    size: 72, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                const SizedBox(height: 20),
                const Text('还没有课表',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(
                  '从学校教务系统导入一次即可，\n之后换学期再导入更新就行。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.6),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('从教务系统导入'),
                  onPressed: _openImport,
                ),
                const SizedBox(height: 10),
                Text(
                  '需要先在门户登录（学号 + 密码）',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        // 点标题 = 回到本周（比右上角那个小图标更直觉）
        title: InkWell(
          onTap: () => _goToWeek(tt.currentWeek()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text('${tt.name} · 第 $_week 周',
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (!_followToday) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.touch_app_outlined, size: 14),
                  ],
                ],
              ),
              Text('${tt.semesterName}${_followToday ? '' : '（点这里回本周）'}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
        actions: [
          // 只留「回到本周」；提醒/导入/导出 已挪到「课程」页顶部
          // （AppBar 上 4 个图标在窄屏上太挤，也不容易找到）
          IconButton(
            tooltip: '回到本周',
            icon: Icon(_followToday ? Icons.today : Icons.today_outlined),
            onPressed: () => _goToWeek(tt.currentWeek()),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 背景图（若有）+ 压暗层，画在最底下
          Positioned.fill(child: _backgroundLayer()),
          Positioned.fill(
            child: _tab == 0
                ? Column(
                    children: [
                      _weekBar(tt),
                      Expanded(
                        // 左右滑动切换周（像翻页一样跟手，不用去点箭头）
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: tt.totalWeeks,
                          onPageChanged: (idx) {
                            final w = idx + 1;
                            setState(() {
                              _week = w;
                              _followToday = w == tt.currentWeek();
                            });
                          },
                          itemBuilder: (context, idx) {
                            final week = idx + 1;
                            return WeekView(
                              key: ValueKey('week_$week'),
                              timetable: tt,
                              week: week,
                              sectionHeight: _appearance.sectionHeight,
                              radius: _appearance.cardRadius,
                              cardOpacity: _appearance.cardOpacity,
                              indexOfSlot: (weekday, start, end) =>
                                  _slotPrefs.indexOf(weekday, start, end),
                              onSelectConflict: _showConflictPicker,
                              onTapCourse: (course, slot) => _showCourseDetail(course, slot),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : CourseListPage(
                    timetable: tt,
                    onOpenReminder: _openReminderSettings,
                    onExportIcs: _exportIcs,
                    onImport: _openImport,
                    onEditSemesterStart: _editSemesterStart,
                    onOpenAppearance: _openAppearance,
                    onOpenAbout: _openAbout,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: '课表'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '课程'),
        ],
      ),
    );
  }

  Widget _weekBar(Timetable tt) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
            onPressed: _week > 1 ? () => _goToWeek(_week - 1) : null,
          ),
          Expanded(
            child: Slider(
              value: _week.toDouble(),
              min: 1,
              max: tt.totalWeeks.toDouble(),
              divisions: tt.totalWeeks - 1,
              label: '第 $_week 周',
              // 拖滑杆时直接跳（不要动画，否则跟手会抖）
              onChanged: (v) => _goToWeek(v.round(), animate: false),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
            onPressed: _week < tt.totalWeeks ? () => _goToWeek(_week + 1) : null,
          ),
          // 格子高度已挪到「外观设置」里（那里能精确拖，比这里盲点一下直观）
          IconButton(
            tooltip: '外观设置',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _openAppearance,
          ),
        ],
      ),
    );
  }

  /// 冲突课程选择面板
  ///
  /// 用户选中后写进 SlotPrefs（key 是「星期+节次区间」，不含周次），
  /// 因此**同一时段的其他周次会同步显示同一门课**。
  void _showConflictPicker(List<SlotItem> cluster, int weekday, int selected) {
    final tt = _timetable;
    if (tt == null || cluster.isEmpty) return;
    final start = cluster.first.slot.startSection;
    final end = cluster.first.slot.endSection;
    final safeSel = safeSlotIndex(selected, cluster.length);

    // 统计这些课分别覆盖哪些周（用于告诉用户"同步影响哪些周"）
    final allWeeks = <int>{};
    for (final it in cluster) {
      allWeeks.addAll(it.slot.weeks);
    }
    final sortedWeeks = allWeeks.toList()..sort();
    final weeksText = _weeksText(sortedWeeks.toSet());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheetState) {
          final current = safeSel;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '该时段有 ${cluster.length} 门课冲突',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '周${['', '一', '二', '三', '四', '五', '六', '日'][weekday]} '
                    '$start-$end 节 · 选择要显示的一门（当前 ${current + 1}/${cluster.length}）',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择后会同步到该时段的所有周次（$weeksText）',
                    style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(cluster.length, (i) {
                    final it = cluster[i];
                    final c = it.course;
                    final s = it.slot;
                    final isSel = i == current;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isSel
                          ? colorForCourse(c.name).withValues(alpha: 0.14)
                          : null,
                      child: ListTile(
                        leading: Container(
                          width: 10,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorForCourse(c.name, override: c.color),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        title: Text(c.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isSel ? colorForCourse(c.name) : null,
                            )),
                        subtitle: Text(
                          [
                            if (s.room.isNotEmpty) s.room,
                            if (s.teacher.isNotEmpty) s.teacher,
                            if (c.kindMark.isNotEmpty) c.kindMark,
                            _weeksText(s.weeks),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: isSel
                            ? Icon(Icons.check_circle,
                                color: colorForCourse(c.name), size: 20)
                            : const Icon(Icons.circle_outlined, size: 20),
                        onTap: () async {
                          await _slotPrefs.setChoice(weekday, start, end, i);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '已切换为「${c.name}」，该时段的其他周次同步更新',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.info_outline, size: 16),
                          label: const Text('看当前这门的详情'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showCourseDetail(cluster[current].course, cluster[current].slot);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCourseDetail(Course course, CourseSlot slot) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: colorForCourse(course.name, override: course.color),
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(course.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 14),
            _kv('时间', '周${['', '一', '二', '三', '四', '五', '六', '日'][slot.weekday]} '
                '${slot.startSection}-${slot.endSection}节'),
            if (slot.weeks.isNotEmpty)
              _kv('周次', _weeksText(slot.weeks)),
            if (slot.room.isNotEmpty) _kv('教室', '${slot.campus} ${slot.room}'),
            if (slot.teacher.isNotEmpty) _kv('教师', slot.teacher),
            if (course.classNo.isNotEmpty) _kv('教学班', course.classNo),
            if (course.credits > 0) _kv('学分', course.credits.toString()),
            if (course.assessType.isNotEmpty) _kv('考核', course.assessType),
            if (course.hourComposition.isNotEmpty) _kv('学时', course.hourComposition),
            if (course.kindMark.isNotEmpty) _kv('类型', course.kindMark),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 56, child: Text(k, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  String _weeksText(Set<int> weeks) {
    final sorted = weeks.toList()..sort();
    if (sorted.isEmpty) return '';
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
