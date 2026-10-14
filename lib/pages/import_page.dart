/// 教务系统导入页
///
/// 交互设计（参考 WakeUp 课程表）：
///   1) 内置 WebView 打开正方教务系统登录页，用户自己输入学号/密码/验证码登录
///   2) 用户自己点进"信息查询 → 学生课表查询"
///   3) 页面右下角悬浮"导入"按钮出现，点击后从页面上下文抓课表数据
///   4) 弹出预览确认，写入本地课表
///
/// 抓取策略（双层兜底）：
///   A. 页面内 fetch 调正方课表接口（xskbcx_cxXsKb.html），session 自动带上 —— 返回 JSON，最稳
///   B. 若接口变更/失败：读取课表页 DOM 表格（含 iframe 递归），解析 HTML
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/timetable.dart';
import '../services/timetable_parser.dart';

/// 教务系统入口（2026-10 实测修正）
///
/// ⚠️ 学校已改为一网通办门户，**不能**再直接开正方登录页
/// （`jwglxt/xtgl/login_slogin.html` 直连打不开，必须由门户换票）。
///
/// 实测可用路径：
///   ① 打开门户 https://ywtb.lzhit.edu.cn/portal/home
///   ② 未登录会跳 SSO，登录后回到门户（门户自身走 OAuth2 + id_token）
///   ③ 门户里有「教务系统」链接 → https://jwglxt.lzhit.edu.cn/sso/ksiotlogin
///      点它走 CAS 换票：
///        sso/ksiotlogin → cas/login?service=... → ksiotlogin?ticket=ST-...
///        → jwglxt/ticketlogin?uid=xxx&timestamp=xxx&verify=xxx → 主页面
///   ④ 进入正方主页面后即可调课表接口
const String kPortalHome = 'https://ywtb.lzhit.edu.cn/portal/home';
const String kJwglxtSsoEntry = 'https://jwglxt.lzhit.edu.cn/sso/ksiotlogin';
const String kJwglxtBase = 'https://jwglxt.lzhit.edu.cn/jwglxt';
const String kJwglxtLoginUrl = '$kJwglxtBase/xtgl/login_slogin.html';

/// 课表查询功能码（从正方主页面菜单实测抓取，非猜测）
///   个人课表查询            N253508  /kbcx/xskbcx_cxXskbcxIndex.html
///   学生课表查询（按周次）   N2154    /kbcx/xskbcxZccx_cxXskbcxIndex.html
const String kMenuCodePersonalKb = 'N253508';
const String kMenuCodePersonalKbByWeek = 'N2154';

/// 在页面上下文里执行的抓取脚本。
///
/// 先探测正方课表接口（返回 JSON），失败则回退抓 DOM 里的课表表格文本。
const String kFetchScript = r'''
// 注意：不能用 `runJavaScriptReturningResult` 直接取 async 函数的返回值——
// 它不会 await Promise，只会拿到 {} 或 null（曾因此出现「调试信息：null」）。
// 正确做法：把结果写进全局变量，Dart 侧轮询读取。
window.__lzitFetchResult = null;
(async () => {
  const result = { ok: false, mode: 'none', data: null, error: '', debug: {} };

  // ---------- 前置检查：必须真的在教务系统域名下 ----------
  // 下面的接口和 DOM 都用**相对路径**（/jwglxt/...），只有页面本身在 jwglxt
  // 域名下才有效。如果用户还停在门户/登录页就点「导入课表」，
  // 请求会打到错误域名、失败信息又含糊（只看到 null），所以这里显式判断。
  result.debug.url = location.href;
  result.debug.host = location.hostname;
  if (!/jwglxt\./i.test(location.hostname)) {
    result.error = '当前页面不在教务系统（现在在：' + location.hostname + '）。'
                 + '请先在下面进入教务系统，打开「信息查询 → 个人课表查询」，再点「导入课表」。';
    window.__lzitFetchResult = result;
    return;
  }

  // ---------- 准备参数：正方把学年学期存在 sessionStorage ----------
  const want = ['xnm', 'xqm', 'xqj', 'kbjcms', 'gnmkdm', 'kbtable'];
  const params = {};
  try {
    Object.keys(sessionStorage).forEach(k => {
      const lk = k.toLowerCase();
      want.forEach(w => { if (lk.includes(w)) params[k] = sessionStorage.getItem(k); });
    });
  } catch (e) { result.debug.storErr = String(e); }

  const pick = (k) => {
    const hit = Object.keys(params).find(x => x.toLowerCase() === k || x.toLowerCase().endsWith(k));
    return hit ? params[hit] : '';
  };
  const xnm = pick('xnm') || '', xqm = pick('xqm') || '';
  result.debug.xnm = xnm; result.debug.xqm = xqm;

  // 学号：从页面里的用户信息猜（正方通常放在顶部）
  let su = '';
  const suEl = document.querySelector('.media-heading, .user-name, #yh_id, .navbar-text');
  if (suEl) { const m = (suEl.innerText || '').match(/\d{6,}/); if (m) su = m[0]; }

  // ---------- A. 接口抓取 ----------
  const endpoints = [
    '/jwglxt/kbcx/xskbcx_cxXsKb.html',
    '/jwglxt/kbcx/xskbcx_cxXskbList.html'
  ];
  for (const ep of endpoints) {
    // 优先用空参：正方会返回**当前学期**，跨学期不用改代码
    for (const body of [
      'xnm=&xqm=&kzlx=ck',
      `xnm=${encodeURIComponent(xnm)}&xqm=${encodeURIComponent(xqm)}&kzlx=ck`
    ]) {
      try {
        const r = await fetch(ep + '?gnmkdm=N253508&su=' + encodeURIComponent(su), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest'
          },
          credentials: 'include',
          body
        });
        const t = await r.text();
        if (!t) continue;
        let j = null;
        try { j = JSON.parse(t); } catch (e) { /* 非 JSON */ }

        // 完整响应对象（含 xsxx 学生信息 / kbList 课表 / sjkList 实践课）
        // 必须整份返回：只回 kbList 会丢掉实践课和学号
        if (j && typeof j === 'object' && Array.isArray(j.kbList) && j.kbList.length) {
          result.ok = true; result.mode = 'api'; result.data = j;
          result.debug.endpoint = ep; result.debug.body = body;
          result.debug.kbCount = j.kbList.length;
          result.debug.sjkCount = Array.isArray(j.sjkList) ? j.sjkList.length : 0;
          window.__lzitFetchResult = result;
          return;
        }
        // 少数接口直接返回数组
        if (j && Array.isArray(j) && j.length) {
          result.ok = true; result.mode = 'api'; result.data = { kbList: j };
          result.debug.endpoint = ep; result.debug.body = body;
          window.__lzitFetchResult = result;
          return;
        }
        if (t.length > 50 && !result.debug.lastText) {
          result.debug.lastText = t.slice(0, 400);
        }
      } catch (e) { result.debug['err_' + ep] = String(e).slice(0, 120); }
    }
  }

  // ---------- B. DOM 回退：抓课表表格文本 ----------
  function tableText(doc) {
    let out = '';
    try {
      doc.querySelectorAll('table').forEach(tb => {
        const rows = [...tb.querySelectorAll('tr')];
        if (rows.length < 2) return;
        out += rows.map(tr => [...tr.querySelectorAll('td,th')]
          .map(td => (td.innerText || '').replace(/\s+/g, ' ').trim())
          .join('\t')).join('\n') + '\n';
      });
    } catch (e) { /* 跨域 */ }
    return out;
  }

  let html = tableText(document);
  const frames = [];
  try { for (const f of document.querySelectorAll('iframe')) frames.push(f); } catch (e) {}
  try {
    for (let i = 0; i < window.frames.length; i++) {
      try { html += tableText(window.frames[i].document); } catch (e) {}
    }
  } catch (e) {}

  if (html.trim().length > 50) {
    result.ok = true; result.mode = 'dom'; result.data = html;
    result.debug.htmlLen = html.length;
    window.__lzitFetchResult = result;
    return;
  }

  result.error = '未能从页面取到课表数据（接口与表格都为空）';
  window.__lzitFetchResult = result;
  return;
})();
// 立即返回，告诉 Dart 侧脚本已启动（真正的结果由轮询 window.__lzitFetchResult 获取）
'started';
''';

class ImportPage extends StatefulWidget {
  final void Function(Timetable) onImported;

  /// 当前已存在的课表 id（null = 还没有课表）。
  /// 用来在导入时问用户「覆盖它」还是「另外新增一份」。
  final String? existingId;

  /// 当前课表名（显示在「覆盖」选项里，让用户知道要覆盖谁）
  final String? existingName;

  const ImportPage({
    super.key,
    required this.onImported,
    this.existingId,
    this.existingName,
  });

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _fetching = false;
  bool _loggedInLikely = false;
  bool _onPortal = false;
  bool _onSso = false;
  bool _autoJumped = false; // 门户 → 教务系统 只自动跳一次，避免循环
  String _status = '正在打开一网通办门户…';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _status = '加载中…';
            });
          },
          onPageFinished: (url) {
            final onPortal = url.contains('ywtb.lzhit.edu.cn');
            final onJw = url.contains('jwglxt.lzhit.edu.cn');
            final isJwLogin = url.contains('login_slogin');
            final onSso = url.contains('sso.lzhit.edu.cn') || url.contains('cas/login');
            setState(() {
              _loading = false;
              _onPortal = onPortal;
              _onSso = onSso;
              // 正方主页面（已换票成功）才算就绪；登录页不算
              _loggedInLikely = onJw && !isJwLogin;
              _status = _buildStatus(onPortal: onPortal, onSso: onSso, onJw: onJw, isJwLogin: isJwLogin);
            });

            // 登录后停在门户 → 自动跳到教务系统（用户少点一次）
            if (onPortal && !_autoJumped && !_loading) {
              _autoJumped = true;
              Future<void>.delayed(const Duration(milliseconds: 900), () {
                if (!mounted) return;
                _gotoJwglxt();
              });
            }
          },
          onWebResourceError: (e) {
            // 注意：Android 原生侧在拿不到错误描述时会把它 toString()，
            // 于是 Dart 这边收到的是**字符串 "null"**（不是 null 值）——
            // 用户看到的「加载失败：null」就是这么来的，等于没有任何信息。
            // 真正能定位问题的是 errorCode / errorType，务必显示出来。
            final d = e.description;
            final desc = (d.isEmpty || d == 'null') ? '(系统未提供描述)' : d;
            final t = e.errorType;
            final typeText = (t == null) ? '' : ' · $t';
            setState(() => _status =
                '加载失败：$desc\n错误码 ${e.errorCode}$typeText\n'
                '（错误码含义：-2 域名解析失败 · -6 连接失败 · -8 超时 · -11 SSL 握手失败）');
          },
        ),
      )
      // 从门户进（学校已改为门户 → 教务系统，直连正方登录页已失效）
      ..loadRequest(Uri.parse(kPortalHome));
  }

  String _buildStatus({
    required bool onPortal,
    required bool onSso,
    required bool onJw,
    required bool isJwLogin,
  }) {
    if (onSso) return '请在下面登录统一身份认证（学号 + 密码）';
    if (onPortal) return '已登录门户。点右下角「进入教务系统」，\n进去后停在课表页，再点「导入课表」';
    if (onJw && !isJwLogin) return '已进入教务系统 — 请点开「信息查询 → 个人课表查询」';
    if (onJw && isJwLogin) return '正方登录页（正常情况下应该会被 SSO 自动放行，若停在这里请点右下角按钮）';
    return '加载中…';
  }

  /// 从门户跳到教务系统（走 CAS 换票，不需要在正方再登录）
  ///
  /// 实测直接用这个 URL 导航，效果与在门户里点「教务系统」链接**完全一致**
  /// （门户那链接的 href 就是这个地址），所以不必去 DOM 里找按钮点击。
  Future<void> _gotoJwglxt() async {
    setState(() => _status = '正在通过门户进入教务系统…');
    await _controller.loadRequest(Uri.parse(kJwglxtSsoEntry));
  }

  Future<void> _doFetch() async {
    setState(() {
      _fetching = true;
      _status = '正在抓取课表…';
    });
    try {
      // 关键：抓取脚本是 async 的，`runJavaScriptReturningResult` 不会 await Promise，
      // 直接读返回值只会拿到 {} / null（曾因此报「调试信息：null」）。
      // 所以改成：脚本把结果写进 window.__lzitFetchResult，这里轮询读取。
      await _controller.runJavaScript(kFetchScript);

      dynamic decoded;
      const stepMs = 300;
      const maxWaitMs = 15000;
      var waited = 0;
      while (waited < maxWaitMs) {
        await Future<void>.delayed(const Duration(milliseconds: stepMs));
        waited += stepMs;
        final probe = await _controller.runJavaScriptReturningResult(
            "window.__lzitFetchResult ? JSON.stringify(window.__lzitFetchResult) : ''");
        final d = _decodeJsResult(probe);
        if (d is Map && d.isNotEmpty) {
          decoded = d;
          break;
        }
        if (waited % 3000 == 0 && mounted) {
          setState(() => _status = '正在抓取课表…（已等待 ${waited ~/ 1000} 秒）');
        }
      }

      if (decoded == null) {
        setState(() => _status = '抓取超时：脚本 15 秒内没有返回结果。\n'
            '请确认页面已经打开「信息查询 → 个人课表查询」，并且课表内容已显示出来。');
        return;
      }
      final ok = decoded['ok'] == true;
      final mode = decoded['mode']?.toString() ?? 'none';
      if (!ok) {
        // error 可能是空串（?? 只对 null 生效），空串会显示成一行空白，
        // 所以这里显式判断 trim 后的长度
        final rawErr = decoded['error'];
        final errText = (rawErr is String && rawErr.trim().isNotEmpty)
            ? rawErr
            : '未知原因（脚本没有给出错误说明）';
        setState(() => _status = '抓取失败：$errText\n\n调试信息：${decoded['debug']}');
        return;
      }

      final data = decoded['data'];
      List<Course> courses = [];
      ZfTimetableResponse? parsed;
      if (mode == 'api') {
        // 接口可能返回完整响应对象（含 xsxx/kbList/sjkList），也可能只返回 kbList 数组
        final Map<String, dynamic> full;
        if (data is Map) {
          full = data.cast<String, dynamic>();
        } else if (data is List) {
          full = {'kbList': data};
        } else {
          full = const {};
        }
        parsed = parseZfResponse(full);
        courses = parsed.courses;
      } else if (mode == 'dom' && data is String) {
        courses = parseGrid(data);
      }

      if (courses.isEmpty) {
        setState(() => _status = '抓到了数据但没解析出课程（模式：$mode），需要调整解析器');
        return;
      }
      _showPreview(courses, mode, parsed);
    } catch (e, st) {
      // 异常对象本身可能是 null（例如平台通道返回 null 被 throw），
      // 那样 '异常：$e' 会渲染成 "异常：null"，什么都查不出来。
      final msg = e.toString();
      debugPrint('课表抓取异常: $e\n$st');
      setState(() => _status = '异常：$msg\n${st.toString().split('\n').take(2).join('\n')}');
    } finally {
      setState(() => _fetching = false);
    }
  }

  /// WebView 的 runJavaScriptReturningResult 返回值在 Android 上是 JSON 字符串（可能被引号包裹）
  dynamic _decodeJsResult(dynamic raw) {
    if (raw is Map || raw is List) return raw;
    var s = raw.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = jsonDecode(s) as String;
    }
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  void _showPreview(List<Course> courses, String mode, ZfTimetableResponse? parsed) {
    final totalSlots = courses.fold<int>(0, (a, c) => a + c.slots.length);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx2, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('识别到 ${courses.length} 门课 / $totalSlots 个时段',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('数据来源：${mode == 'api' ? '课表接口(JSON)' : '页面表格(DOM)'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  if (parsed != null && parsed.xm.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('${parsed.xm} · ${parsed.className} · ${parsed.semesterName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                  if (parsed != null && parsed.unscheduled.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('另有 ${parsed.unscheduled.length} 门无固定时段的实践/其它课程',
                        style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: courses.length,
                itemBuilder: (c, i) {
                  final course = courses[i];
                  return ListTile(
                    dense: true,
                    title: Text(course.name),
                    subtitle: Text(course.slots
                        .map((s) => '周${s.weekday} ${s.startSection}-${s.endSection}节 ${s.room}')
                        .join(' | ')),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openImportOptions(courses, parsed);
                        },
                        child: const Text('下一步'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导入设置对话框：课表名 / 学期第一天 / 覆盖或新增
  ///
  /// 为什么必须有这一步：
  ///   · 课表接口**只给周次不给日期**，起始日猜错一周，整张表头的日期全错
  ///   · 一个学期可能同时存好几套课表（大一/大二…），得让用户决定放哪
  Future<void> _openImportOptions(List<Course> courses, ZfTimetableResponse? parsed) async {
    final guessed = defaultSemesterStart();
    final nameCtl = TextEditingController(text: defaultTimetableName(guessed));
    var startDate = guessed;
    var replace = widget.existingId != null;
    var nameEdited = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('导入设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtl,
                  onChanged: (_) => nameEdited = true,
                  decoration: const InputDecoration(
                    labelText: '课表名称',
                    helperText: '例如「2026课表」「大四上」',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: startDate,
                      firstDate: DateTime(startDate.year - 1, 1, 1),
                      lastDate: DateTime(startDate.year + 2, 12, 31),
                      helpText: '选择第 1 周的周一',
                    );
                    if (picked == null) return;
                    // 统一落到那一周的周一，避免整张表日期偏移
                    final mon = picked.subtract(Duration(days: picked.weekday - 1));
                    setDlg(() {
                      startDate = DateTime(mon.year, mon.month, mon.day);
                      if (!nameEdited) {
                        nameCtl.text = defaultTimetableName(startDate);
                      }
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '学期第一天（第 1 周周一）',
                      helperText: '课表只给周次，日期全靠这个基准推算',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Text('${startDate.year}/${startDate.month}/${startDate.day}'),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                if (widget.existingId != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: replace,
                    onChanged: (v) => setDlg(() => replace = v),
                    title: const Text('覆盖现有课表', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      replace
                          ? '将替换「${widget.existingName ?? widget.existingId}」'
                          : '保留它，另外新增一份',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    nameCtl.dispose();

    final name = nameCtl.text.trim().isEmpty
        ? defaultTimetableName(startDate)
        : nameCtl.text.trim();
    widget.onImported(_buildTimetable(
      courses,
      parsed,
      name: name,
      startDate: startDate,
      // 覆盖 → 沿用旧 id（替换它）；新增 → 给一个唯一 id（否则会撞车）
      id: replace ? widget.existingId : 'jwglxt-${DateTime.now().millisecondsSinceEpoch}',
    ));
  }

  Timetable _buildTimetable(
    List<Course> courses,
    ZfTimetableResponse? parsed, {
    required String name,
    required DateTime startDate,
    String? id,
  }) {
    final now = DateTime.now();
    final semester = (parsed?.semesterName.isNotEmpty ?? false)
        ? parsed!.semesterName
        : '${now.year}';

    return Timetable(
      id: id ?? 'jwglxt-${parsed?.xnm ?? now.year}-${parsed?.xqm ?? ''}',
      name: name,
      semesterName: semester,
      xnm: parsed?.xnm ?? '',
      xqm: parsed?.xqm ?? '',
      startDate: startDate,
      totalWeeks: 20,
      sectionsPerDay: 10,
      courses: courses,
      // 实践课/实习/网课：没有固定节次，但必须带过去，否则界面上看不到
      unscheduled: (parsed?.unscheduled ?? const [])
          .map((u) => UnscheduledCourse(
                name: u.name,
                weeks: u.weeks,
                teacher: u.teacher,
                credits: u.credits,
              ))
          .toList(),
      student: StudentInfo(
        xh: parsed?.xh ?? '',
        xm: parsed?.xm ?? '',
        className: parsed?.className ?? '',
        major: parsed?.major ?? '',
        grade: parsed?.grade ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('从教务系统导入'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
          // 顶部状态条
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_status,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 3),
            ),
          ),
          // 悬浮按钮：三种状态**互斥**，只显示一个。
          //
          // ⚠️ 曾写成 `if / else if` 再加一个**独立 if**，于是进入 SSO 页时
          //    「导入课表」与「重新进入教务系统」会同时渲染、位置完全重叠，
          //    后画的那个盖在上面 —— 用户点「导入课表」实际点到的是另一个按钮。
          if (_onSso)
            Positioned(
              right: 18,
              bottom: 28,
              child: FloatingActionButton.extended(
                onPressed: _gotoJwglxt,
                icon: const Icon(Icons.refresh),
                label: const Text('重新进入教务系统'),
              ),
            )
          else if (_onPortal)
            Positioned(
              right: 18,
              bottom: 28,
              child: FloatingActionButton.extended(
                onPressed: _gotoJwglxt,
                icon: const Icon(Icons.login),
                label: const Text('进入教务系统'),
              ),
            )
          else if (_loggedInLikely)
            Positioned(
              right: 18,
              bottom: 28,
              child: FloatingActionButton.extended(
                onPressed: _fetching ? null : _doFetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_fetching ? '抓取中' : '导入课表'),
              ),
            ),
        ],
      ),
    );
  }
}
