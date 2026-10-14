/// 课表本地存储
///
/// 数据量很小（一张课表几十 KB），直接用 JSON 文件持久化，不引入 sqflite。
/// 目录：`<应用文档目录>/timetables/<id>.json`
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/timetable.dart';

class TimetableStore {
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/timetables');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Timetable>> loadAll() async {
    final dir = await _dir();
    final out = <Timetable>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final raw = await e.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        out.add(Timetable.fromJson(json));
      } catch (_) {
        // 单张课表损坏不影响其它课表
        continue;
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<void> save(Timetable t) async {
    final dir = await _dir();
    final f = File('${dir.path}/${t.id}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(t.toJson()));
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final f = File('${dir.path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}
