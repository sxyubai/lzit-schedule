/// 上课提醒通知
///
/// 设计要点：
///   1) **提前量可配**（默认 15 分钟），用户可改
///   2) 只给"未来 N 周内会实际发生"的课排提醒（用课表的 startDate + 周次算真实日期）
///      否则会给第 16 周才上的课在第 1 周就排一堆无用通知
///   3) 每条通知带课程名 / 教室 / 节次，点开能直接看课表
///   4) 重排前先取消旧的，避免重复提醒
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/timetable.dart';

/// 未来的提醒计划（纯数据，便于测试）
class PlannedNotification {
  final int id;
  final DateTime when;
  final String title;
  final String body;

  const PlannedNotification({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  @override
  String toString() => '[$id] ${when.toIso8601String()} $title | $body';
}

/// 计算需要排定的提醒（纯函数，不碰插件，方便单元测试）
///
/// [now] 当前时间；[weeksAhead] 向前规划多少周；
/// [minutesBefore] 提前几分钟。
List<PlannedNotification> planNotifications(
  Timetable tt, {
  required DateTime now,
  int weeksAhead = 4,
  int minutesBefore = 15,
}) {
  final out = <PlannedNotification>[];
  final bySection = {for (final s in tt.sectionTimes) s.section: s};

  // 从"当周"开始往后数 weeksAhead 周
  final currentWeek = tt.weekOf(now);
  final firstWeek = currentWeek < 1 ? 1 : currentWeek;

  // 用于生成稳定 id（同一门课同一时段每周不同 id，避免互相覆盖）
  var seq = 0;

  for (var w = firstWeek; w < firstWeek + weeksAhead; w++) {
    final weekMonday = tt.startDate.add(Duration(days: (w - 1) * 7));
    for (final course in tt.courses) {
      for (final slot in course.slots) {
        if (!slot.weeks.contains(w)) continue; // 这周不上这门课
        final st = bySection[slot.startSection];
        if (st == null) continue;
        final hm = _parseHm(st.start);
        if (hm == null) continue;

        final day = weekMonday.add(Duration(days: slot.weekday - 1));
        final startAt = DateTime(day.year, day.month, day.day, hm.h, hm.m);
        final alertAt = startAt.subtract(Duration(minutes: minutesBefore));
        if (!alertAt.isAfter(now)) continue; // 过去了就跳过

        final where = [slot.campus, slot.room].where((e) => e.isNotEmpty).join(' ');
        out.add(PlannedNotification(
          id: 10000 + (seq++),
          when: alertAt,
          title: '$minutesBefore分钟后上课：${course.name}',
          body: [
            '第 ${slot.startSection}-${slot.endSection} 节',
            if (where.isNotEmpty) where,
            if (slot.teacher.isNotEmpty) slot.teacher,
          ].join(' · '),
        ));
      }
    }
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

({int h, int m})? _parseHm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return (h: int.parse(m.group(1)!), m: int.parse(m.group(2)!));
}

/// 通知服务（真正跟插件打交道的部分）
class ReminderService {
  // ⚠️ channel id 带版本后缀：Android 的通知渠道**一旦创建，配置就不可更改**。
  // 想调整声音/震动/优先级，只能换一个新 id（旧的会被系统忽略）。
  // v2 = 响铃 + 震动 + 最高优先级（会以顶部横幅弹出，类似 QQ/微信）。
  static const String channelId = 'class_reminder_v2';
  static const String channelName = '上课提醒';
  static const String channelDesc = '每节课开始前提醒（响铃 + 震动）';

  /// 震动节奏：[等待, 震动, 暂停, 震动]（毫秒）
  static final Int64List vibrationPattern =
      Int64List.fromList(<int>[0, 600, 250, 600]);

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;

    // 时区（zonedSchedule 必需，否则时间会偏）
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('时区获取失败，回退 Asia/Shanghai: $e');
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('通知被点击: ${resp.payload}');
      },
    );

    // 通知渠道（Android 8+ 必须）
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      enableLights: true,
      showBadge: true,
    ));

    _inited = true;
  }

  /// 请求通知权限（Android 13+ 需要；用户拒绝就返回 false）
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    // Android 12+ 精确闹钟权限
    try {
      await android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('精确闹钟权限请求失败（可忽略）: $e');
    }
    return granted ?? true;
  }

  /// 是否已获得通知权限
  Future<bool> hasPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// 取消所有已排定的提醒
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// 按课表重排提醒；返回实际排定的条数
  Future<int> reschedule(
    Timetable tt, {
    int weeksAhead = 4,
    int minutesBefore = 15,
  }) async {
    await init();
    await _plugin.cancelAll();

    final plans = planNotifications(
      tt,
      now: DateTime.now(),
      weeksAhead: weeksAhead,
      minutesBefore: minutesBefore,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibrationPattern,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        enableLights: true,
        ticker: '上课提醒',
      ),
    );

    for (final p in plans) {
      final when = tz.TZDateTime.from(p.when, tz.local);
      try {
        await _plugin.zonedSchedule(
          p.id,
          p.title,
          p.body,
          when,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('排定提醒失败(${p.title}): $e');
      }
    }
    return plans.length;
  }

  /// 立刻发一条测试通知（让用户马上看到效果，不用等到上课）
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      9999,
      '测试提醒',
      '看到这条说明通知是通的。真正上课前 15 分钟会像这样提醒你。',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: vibrationPattern,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }
}
