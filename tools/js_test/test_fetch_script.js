/**
 * 用 Node 的 vm 模块跑 WebView 注入脚本，验证「写全局变量 + 可被读取」这条链路。
 *
 * 为什么不在模拟器里测：模拟器没有教务系统登录凭据，走不到课表页；
 * 而脚本本身是纯 JS，mock 掉 window/location/document/fetch 就能完整验证。
 */
const vm = require('fs');
const fs = require('fs');
const vmMod = require('vm');

const code = fs.readFileSync(__dirname + '/fetch_script.js', 'utf8');

function runWith({ hostname, href, sessionStorage = {}, fetchImpl, elements = {} }) {
  const sandbox = {
    location: { href, hostname },
    sessionStorage,
    localStorage: {},
    document: {
      querySelector: () => null,
      querySelectorAll: () => [],
      // 课表查询页上有两个下拉框，id 就叫 xnm / xqm —— 接口靠它们才知道查哪个学期
      getElementById: (id) => elements[id] || null,
      cookie: '',
    },
    fetch: fetchImpl || (async () => ({ text: async () => '' })),
    console,
  };
  sandbox.window = sandbox;
  const ctx = vmMod.createContext(sandbox);
  const ret = vmMod.runInContext(code, ctx, { timeout: 5000 });
  return { ret, sandbox };
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

(async () => {
  let pass = 0;
  let fail = 0;
  const check = (name, cond, extra) => {
    if (cond) {
      console.log(`  ✓ ${name}`);
      pass++;
    } else {
      console.log(`  ✗ ${name}${extra ? '  → ' + extra : ''}`);
      fail++;
    }
  };

  console.log('=== 场景 1：页面停在 SSO 登录页（不该尝试抓取）===');
  {
    const { ret, sandbox } = runWith({
      hostname: 'sso.lzhit.edu.cn',
      href: 'https://sso.lzhit.edu.cn/sso/login?x=1',
    });
    check('脚本立刻返回 "started"（可被 runJavaScript 正常执行）', ret === 'started', `实际=${JSON.stringify(ret)}`);
    await sleep(300);
    const r = sandbox.__lzitFetchResult;
    check('全局变量已被写入', r !== null && r !== undefined, `实际=${JSON.stringify(r)}`);
    check('ok === false', r && r.ok === false);
    check('错误信息说明了当前不在教务系统', r && /不在教务系统/.test(r.error), r && r.error);
    check('错误信息里带上了实际域名', r && /sso\.lzhit\.edu\.cn/.test(r.error), r && r.error);
    check('debug.host 被记录（便于诊断）', r && r.debug && r.debug.host === 'sso.lzhit.edu.cn');
  }

  console.log('\n=== 场景 2：页面在教务系统，接口返回课表 JSON ===');
  {
    const kb = {
      xsxx: { xh: '20222441', xm: '黄之程' },
      kbList: [
        { kcmc: '概率论与数理统计', xqj: '2', jc: '1-2节', zcd: '1-9周', cdmc: '1教305', xm: '韦新星', xf: '3' },
      ],
      sjkList: [{ kcmc: '离散数学', qsjsz: '1-12周', jsxm: '周磊' }],
    };
    const { ret, sandbox } = runWith({
      hostname: 'jwglxt.lzhit.edu.cn',
      href: 'https://jwglxt.lzhit.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html',
      sessionStorage: { xnm: '2026', xqm: '1' },
      fetchImpl: async () => ({ text: async () => JSON.stringify(kb) }),
    });
    check('脚本返回 "started"', ret === 'started', `实际=${JSON.stringify(ret)}`);
    await sleep(500);
    const r = sandbox.__lzitFetchResult;
    check('全局变量已写入', !!r, `实际=${JSON.stringify(r)}`);
    check('ok === true', r && r.ok === true, r && JSON.stringify(r.error));
    check("mode === 'api'", r && r.mode === 'api', r && r.mode);
    check('data.kbList 有 1 条', r && r.data && r.data.kbList && r.data.kbList.length === 1);
    check('data.sjkList 也带上了（实践课不能丢）', r && r.data && r.data.sjkList && r.data.sjkList.length === 1);
    check('data.xsxx 带上了（学号/姓名）', r && r.data && r.data.xsxx && r.data.xsxx.xh === '20222441');
  }

  console.log('\n=== 场景 3：教务系统页面但接口空、DOM 也没数据（应给出明确错误）===');
  {
    const { sandbox } = runWith({
      hostname: 'jwglxt.lzhit.edu.cn',
      href: 'https://jwglxt.lzhit.edu.cn/jwglxt/xtgl/index_initMenu.html',
      fetchImpl: async () => ({ text: async () => '' }),
    });
    await sleep(400);
    const r = sandbox.__lzitFetchResult;
    check('ok === false', r && r.ok === false);
    check('error 非空（不会显示成空白）', r && typeof r.error === 'string' && r.error.trim().length > 0, JSON.stringify(r && r.error));
    check('debug 是对象而非 null（这才是关键修复点）', r && r.debug && typeof r.debug === 'object', `debug=${JSON.stringify(r && r.debug)}`);
  }

  console.log('\n=== 场景 4：学年学期来自页面下拉框（「实践课面板空了」的真凶）===');
  {
    // 实测：课表查询页的 sessionStorage 里**没有** xnm/xqm（只有一个 _path），
    // 而接口少了这两个参数会返回字面量 "null"（HTTP 200，4 字节）——
    // 于是静默回退到 DOM 解析，sjkList（实践课）全丢。修复后从 #xnm/#xqm 取。
    let seenBody = '';
    let hitCorrect = false;
    const { sandbox } = runWith({
      hostname: 'jwglxt.lzhit.edu.cn',
      href: 'https://jwglxt.lzhit.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N253508',
      sessionStorage: {}, // 故意为空，模拟真实情况
      elements: { xnm: { value: '2026' }, xqm: { value: '3' } },
      fetchImpl: async (url, opt) => {
        seenBody = (opt && opt.body) || '';
        if (/xnm=2026&xqm=3/.test(seenBody)) {
          hitCorrect = true;
          return {
            status: 200,
            text: async () =>
              JSON.stringify({
                kbList: [{ kcmc: '高等数学', xqj: '1', jcs: '1-2', zcd: '1-5周', cdmc: '1教408' }],
                sjkList: [{ kcmc: '毕业实习', qsjsz: '11-14周', jsxm: '王老师', sjkcgs: '毕业实习●' }],
                xsxx: { XH: '20222441', XM: '测试同学', XNMC: '2026-2027', XQM: '3' },
              }),
          };
        }
        return { status: 200, text: async () => 'null' }; // 参数不对时正方的真实表现
      },
    });
    await sleep(900);
    const r = sandbox.__lzitFetchResult;
    check('走到接口（mode === api）', r && r.mode === 'api', `mode=${r && r.mode}`);
    check('学年学期取自页面下拉框', r && r.debug.xnm === '2026' && r.debug.xqm === '3',
        `xnm=${r && r.debug.xnm} xqm=${r && r.debug.xqm}`);
    check('debug 标明来源是下拉框', r && r.debug.xnmSrc === '页面下拉框', `${r && r.debug.xnmSrc}`);
    check('请求体真的带上了 xnm/xqm', hitCorrect && /xnm=2026&xqm=3/.test(seenBody), `body=${seenBody}`);
    check('实践课条数被记录（sjkCount=1）', r && r.debug.sjkCount === 1, `sjkCount=${r && r.debug.sjkCount}`);
    check('空参失败被记进 tried（诊断可回溯）',
        r && Array.isArray(r.debug.tried) && r.debug.tried.some((s) => /null/.test(s)),
        JSON.stringify(r && r.debug.tried));
  }

  console.log(`\n结果：${pass} 通过 / ${fail} 失败`);
  process.exit(fail === 0 ? 0 : 1);
})();
