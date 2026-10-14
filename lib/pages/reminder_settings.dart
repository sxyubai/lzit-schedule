/// 上课提醒设置面板
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable.dart';
import '../services/reminder_service.dart';

const String kReminderEnabledKey = 'reminder_enabled_v1';
const String kReminderMinutesKey = 'reminder_minutes_v1';

class ReminderSettings {
  final bool enabled;
  final int minutesBefore;

  const ReminderSettings({this.enabled = false, this.minutesBefore = 15});

  static Future<ReminderSettings> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return ReminderSettings(
        enabled: sp.getBool(kReminderEnabledKey) ?? false,
        minutesBefore: sp.getInt(kReminderMinutesKey) ?? 15,
      );
    } catch (_) {
      return const ReminderSettings();
    }
  }

  static Future<void> save({required bool enabled, required int minutesBefore}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kReminderEnabledKey, enabled);
      await sp.setInt(kReminderMinutesKey, minutesBefore);
    } catch (_) {}
  }
}

/// 打开提醒设置面板（底部 sheet）
Future<void> showReminderSettings(
  BuildContext context, {
  required Timetable timetable,
  required ReminderService service,
}) async {
  var settings = await ReminderSettings.load();
  var minutes = settings.minutesBefore;
  var enabled = settings.enabled;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setSheet) {
        Future<void> apply({bool? newEnabled, int? newMinutes}) async {
          enabled = newEnabled ?? enabled;
          minutes = newMinutes ?? minutes;
          setSheet(() {});
          await ReminderSettings.save(enabled: enabled, minutesBefore: minutes);

          final svc = service;
          if (enabled) {
            final granted = await svc.requestPermission();
            if (!granted) {
              if (!ctx2.mounted) return;
              ScaffoldMessenger.of(ctx2).showSnackBar(
                const SnackBar(content: Text('通知权限被拒绝，请到系统设置里允许通知')),
              );
            }
            final n = await svc.reschedule(timetable, minutesBefore: minutes);
            if (!ctx2.mounted) return;
            ScaffoldMessenger.of(ctx2).showSnackBar(
              SnackBar(content: Text('已排定 $n 条提醒（未来 4 周）')),
            );
          } else {
            await svc.cancelAll();
            if (!ctx2.mounted) return;
            ScaffoldMessenger.of(ctx2).showSnackBar(
              const SnackBar(content: Text('已关闭上课提醒')),
            );
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('上课提醒',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Switch(
                      value: enabled,
                      onChanged: (v) => apply(newEnabled: v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? '已开启：每节课开始前会提醒你' : '未开启',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                ),
                const SizedBox(height: 14),
                const Text('提前多久提醒', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [5, 10, 15, 20, 30])
                      ChoiceChip(
                        label: Text('$m 分钟'),
                        selected: minutes == m,
                        onSelected: enabled ? (_) => apply(newMinutes: m) : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_none, size: 18),
                  label: const Text('发一条测试通知'),
                  onPressed: () async {
                    await service.requestPermission();
                    await service.showTestNotification();
                    if (!ctx2.mounted) return;
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      const SnackBar(content: Text('已发送，看看通知栏有没有')),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.phone_android, size: 15, color: Colors.orange[800]),
                          const SizedBox(width: 5),
                          Text('小米 / 国产手机必看',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[900])),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '系统省电策略会杀掉后台提醒，需要手动开权限：\n'
                        '① 设置 → 应用管理 → 课表 → 通知：允许\n'
                        '② 设置 → 应用管理 → 课表 → 省电策略：无限制\n'
                        '③ 设置 → 应用管理 → 课表 → 权限 → 自启动：允许\n'
                        '否则重启手机后提醒会全部失效。',
                        style: TextStyle(fontSize: 11, color: Colors.grey[800], height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
