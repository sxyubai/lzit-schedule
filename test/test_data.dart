/// 测试样本读取工具
///
/// 为什么不放在 `assets/data/`：
/// 这些样本含**真实个人信息**（学号/姓名/班级），打进 APK 后任何人解包都能读到。
/// 但解析器又必须有真实数据才能验证（字段名、周次格式、单双周写法都来自实测）。
///
/// 折中：样本放 `tools/samples/`（**不打包进 APK**），测试通过文件系统直接读。
/// 附带好处：读的是**真实 JSON 文件**，能顺带验证格式本身没问题。
library;

import 'dart:convert';
import 'dart:io';

/// 读取并解析一个样本 JSON
Map<String, dynamic> loadSampleJson(String name) {
  final file = _sampleFile(name);
  final raw = file.readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// 读取样本原始文本（需要自己解析时用）
String loadSampleText(String name) => _sampleFile(name).readAsStringSync();

File _sampleFile(String name) {
  // flutter test 的工作目录是包根目录
  final candidates = [
    File('tools/samples/$name'),
    File('../tools/samples/$name'),
  ];
  for (final f in candidates) {
    if (f.existsSync()) return f;
  }
  throw StateError(
    '找不到测试样本 $name（尝试过：${candidates.map((f) => f.path).join(', ')}）。'
    '当前工作目录：${Directory.current.path}',
  );
}
