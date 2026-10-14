/// 冲突课程的显示偏好（用户的"切换"选择）
///
/// 场景：同一星期 + 同一节次区间可能有多门课（选课冲突，或正方给出多条记录）。
/// 本模块让用户**指定该时段默认显示哪一门**，并记住这个选择。
///
/// 关键设计 —— **按「时段槽位」记忆，而非按「周次」**：
///   key = "weekday-startSection-endSection"（如 "1-7-8" = 周一 7-8 节）
/// 因此周一 7-8 节的切换会**同步影响所有在该时段有课的周次**（第 2、4、7 周一起变），
/// 这正是需求里要的"其他周重叠的也同步"。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 槽位 key：同一星期 + 同一节次区间的所有周次共享
String slotKey(int weekday, int startSection, int endSection) =>
    '$weekday-$startSection-$endSection';

class SlotPrefs {
  static const _prefsKey = 'conflict_slot_choice_v1';

  /// slotKey -> 该时段当前显示第几门课（0-based 下标）
  final Map<String, int> _choice;

  SlotPrefs._(this._choice);

  static SlotPrefs empty() => SlotPrefs._({});

  /// 从本地读取
  static Future<SlotPrefs> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return SlotPrefs.empty();
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return SlotPrefs._(map.map((k, v) => MapEntry(k, (v as num).toInt())));
    } catch (_) {
      // 数据损坏不该让 App 起不来
      return SlotPrefs.empty();
    }
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(_choice));
    } catch (_) {
      // 存不下也不影响本次会话使用
    }
  }

  /// 取某时段选中的下标（越界时按 0 处理，避免课程增删后崩溃）
  int indexOf(int weekday, int startSection, int endSection) {
    final v = _choice[slotKey(weekday, startSection, endSection)];
    return v == null || v < 0 ? 0 : v;
  }

  /// 设置某时段显示第几门课
  Future<void> setChoice(int weekday, int startSection, int endSection, int index) async {
    _choice[slotKey(weekday, startSection, endSection)] = index;
    await save();
  }

  /// 清空所有选择
  Future<void> clear() async {
    _choice.clear();
    await save();
  }

  /// 给上层展示用：当前记住了多少条
  int get count => _choice.length;
}
