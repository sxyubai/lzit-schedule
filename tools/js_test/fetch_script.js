
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
