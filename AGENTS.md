# lzit_schedule（课表 App）项目约定

自用的安卓课表 App —— 因为原软件 WakeUp 被商业化加广告而重做。
**只针对柳州工学院**（正方教务系统 V9），不做通用化（用户 2026-10 明确选了方案 A）。

## 环境

| 项 | 路径 |
| --- | --- |
| Flutter 3.44 / Dart 3.12 | `D:\Environment\flutter` |
| Java 21 | `D:\Environment\Java-21` |
| Android SDK 36 | `D:\Environment\Android\Sdk` |
| 项目根 | `D:\Shiraha\Projects\AI\lzit_schedule` |
| 交付物 | `dist\课表-vX.Y-release.apk` |

## 构建

```powershell
$env:JAVA_HOME='D:\Environment\Java-21'
$env:ANDROID_HOME='D:\Environment\Android\Sdk'
flutter build apk --release
```

- ⚠️ **不要在 `android/gradle.properties` 里写死代理**。写了之后梯子一关，
  所有 Gradle 下载都走死代理 → `Connection refused` → 完全不能构建。
  默认靠阿里云镜像（`android/settings.gradle.kts`）；只有**首次**下 Flutter 引擎库才需要梯子。
- `kotlin.incremental=false`：pub 缓存在 C 盘、项目在 D 盘，否则 Kotlin 增量编译报
  "different roots"。
- 构建约 1.5~2 分钟；模拟器（`-no-window` 模式）比有窗口模式稳定得多。

## 踩过的坑（改代码前先看这里）

### 1. WebView 抓取：不能用 `runJavaScriptReturningResult` 取 async 函数的返回值

```dart
// ❌ 错：async IIFE 返回 Promise，该方法不会 await，拿到的是 {} / null，
//    结果里所有字段都读成 null，界面只显示「调试信息：null」
final raw = await controller.runJavaScriptReturningResult(kFetchScript);

// ✅ 对：脚本写全局变量，Dart 侧轮询读取
await controller.runJavaScript(kFetchScript);            // 脚本内 window.__x = result
final probe = await controller.runJavaScriptReturningResult(
    'window.__x ? JSON.stringify(window.__x) : ""');
```

脚本开头必须 `window.__x = null` 重置，否则会读到上一次的残留。

### 2. 正方页面的 jQuery 扩展会污染 `Array.prototype`

`zftal-ui-*/assets/js/zftal/jquery.extends.contact-min.js` 覆盖了
`filter` / `map` / `forEach`，导致 `Array.from(...).filter(...)` 返回**自相矛盾**的结果
（连 `<meta>` 都能匹配）。**在正方页面里注入 JS 时一律用 `for` 循环**。

### 3. `innerText` 在后台标签页返回空

CDP 操作页面时，标签页不在前台 → `innerText` 全为空字符串。
改用 `textContent`（不依赖渲染），或先 `Page.bringToFront`。

### 4. `dsh-browser-tool` 的"连接已有浏览器"模式在本机不可用

`headless:false` 恒报 `Target ... did not expose a page`，
加 `--remote-allow-origins=*` 也无效（3 次判死）。
**替代**：自己用 CDP 直连（`websocket-client` + `http://127.0.0.1:9222/json/list`），
见 `D:\Shiraha\Projects\AI\DSH\_probe\cdp.py`。

### 5. 测试陷阱

- `Container(color: x)` 的颜色**不走 `decoration`**，想按颜色统计节点必然漏 → 用 `Key` 定位。
- 表头加了日期文本（如 `10/5`）后，用 `find.textContaining('/')` 判断"无冲突角标"会**假失败**
  （日期也含斜杠）→ 用严格正则 `^\d/\d$`。
- 测试画布默认 800x600，整张课表放不下会刷一堆溢出错误 → 用
  `tester.view.physicalSize` 放大。

### 6. 手动添加课程/事件：两个字段类型最容易写错

- **`Course.id` 是必填字段**（没有默认值）。手工新建的课要自己生成 id，
  例如 `'manual-${DateTime.now().microsecondsSinceEpoch}'`；漏了直接编译不过。
- **`CourseSlot.weeks` 是 `Set<int>`**，不是 `List<int>`。凑周次用 `{...}` / `.toSet()`。
- **`TimetableEvent` 绑"具体日期"，`Course` 绑"周次 + 星期"**。两者都用**节次**
  表示时段才画得进同一张网格；事件靠 `timetable.weekOf(date)` 换算成
  「第几周 + 星期几」，只画在正在看的那一周。

### 7. 滑块区间会退化：`min == max`

「结束节次」的 `min` 是「开始节次」，「结束周」的 `min` 是「起始周」。
一旦开始值顶到上限（一天只有 1 节、总周数只有 1 周），区间就成了 `min == max`，
滑块拖不动、看着像坏了。统一在 `_SectionSlider` 内部兜住：
`max <= min` 时把上界撑成 `min + 1`，并把 `value` clamp 进区间。

### 8. 空白格点击层必须垫在课程卡片下面

`WeekView` 用一整层 `HitTestBehavior.opaque` 的透明 `GestureDetector` 铺满网格。
它必须声明在课程卡片**之前**（Stack 里 z 序在下）：点空白处命中它，点卡片仍走卡片。
顺序反过来会把卡片的点击全吃掉。
测试用 `Key('empty_<星期>_<节次>')` 定位格子，**不要去算像素坐标**（列宽受表头宽度影响）。

## 隐私（重要）

- **不打包任何个人数据**。`assets/` 里只有字体；`pubspec.yaml` 刻意不声明 `assets/data/`。
  APK 可被解包，明文 JSON 会泄露学号姓名。
- 测试样本放 `tools/samples/`（含真实学号/姓名，**已加入 .gitignore**，不进 APK）。
- 首次启动走"空课表 → 引导导入"，不预置任何课表。

## 应用图标

源图放 `tools/icon/source.png`，然后：

```bash
cd tools/icon
python make_icons.py      # 生成全套资源到 android/app/src/main/res/
python fix_preview.py     # 真实裁切预览
python validate_icons.py  # 校验
```

⚠️ **自适应图标不是"整图缩放到各尺寸"**：画布 108dp，系统**只保留中心 72dp（2/3）**，
前景内容要占 2/3 左右（我第一次按 72% 做会被裁掉一圈）。背景单独一层（纯白）。
详见 `tools/icon/README.md`。

## 测试

```powershell
flutter test          # 全量 Dart 测试（当前 132 个用例，全绿）
dart analyze lib test # 静态检查（必须 No issues found）
```

样本通过 `test/test_data.dart` 从 `tools/samples/` 读（验证真实 JSON 格式）。

### 抓取脚本的离线测试（不用真机/模拟器）

WebView 注入的抓取脚本是纯 JS，可以脱离安卓验证：

```bash
cd tools/js_test
python extract_js.py        # 从 lib/pages/import_page.dart 提取最新脚本
node test_fetch_script.js   # 16 项断言
```

覆盖：停在 SSO 页应明确报错、教务系统页应拿到 kbList/sjkList/xsxx、
接口空时 `debug` 必须是对象而非 null。
⚠️ **改了 `kFetchScript` 后必须重新跑 `extract_js.py`**，否则测的还是旧脚本。

> 为什么要这个测试：模拟器没有教务系统的登录凭据，走不到课表页；
> 而真机验证一轮成本很高。脚本本身是纯逻辑，mock 掉
> `window/location/document/fetch` 就能完整覆盖。

## 教务系统实测事实（2026-10 核对）

| 项 | 值 |
| --- | --- |
| 门户 | `https://ywtb.lzhit.edu.cn/portal/home`（OAuth2，client_id `X35zbo84PxbkKdquXshT`） |
| 统一认证 | `https://sso.lzhit.edu.cn/sso/login` |
| 教务系统 | `https://jwglxt.lzhit.edu.cn`（SSO 入口 `/sso/ksiotlogin` 走 CAS 换票） |
| 课表接口 | `POST /jwglxt/kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508&su=<学号>`，body `xnm=&xqm=&kzlx=ck`（空参=当前学期） |
| 课表字段 | `kcmc/jc/jcs/xqj/xqjmc/zcd/cdmc/jxbmc/jxbzc/cxbjmc(重修)/xslxbj(○理论▲上机■实验●实践)/xf` |
| **开课单位来源** | 信息查询 → **重修课程查询**（`N255720`，`/cxkccx/cxkccx_cxCxkccxIndex.html`）<br>字段 `kkbmmc`=开课学院、`kclbmc`=课程类别、`kch`=课程代码 |
| 其它菜单 | 个人课表查询 `N253508` · 按周次 `N2154` · 学生选课情况确认 `N2158` · 全校课表查询 `N219933` |

> 正方页面的数据表格是 **jqGrid**，爬 DOM 不可靠；用
> `jQuery('#tabGrid').jqGrid('getRowData')` 直接读数据模型。

## 免听申请表（相关工具）

`D:\Shiraha\Projects\AI\DSH\_probe\` 下有一批脚本（生成/校验 `.doc`）：

- `gen_forms.py` —— 基于已填好的模板复制并填 R4 单元格（Word COM）
- `fix_date.py` —— 修日期。**Word 的 `Find.Execute(Replace=2)` 在 pywin32 下不生效**，
  要用"Find 定位 + `Range.Text = 新值`"的写法
- `verify_forms.py` —— 回读校验（课程信息/勾选项/日期）

模板路径：`D:\Shiraha\Files\College\4.1\课程冲突免听申请\`


## 教务系统接口情报（**不要提交到公开仓库**）

原 README 里的这部分内容，公开仓库上不合适，挪到这里。

| 项 | 值 |
| --- | --- |
| 教务系统 | 正方 V-9.0，`https://jwglxt.lzhit.edu.cn/jwglxt` |
| 登录页 | `/jwglxt/xtgl/login_slogin.html`（表单 POST，字段 `yhm` 学号 / `mm` 密码） |
| 学校代码 | `xxdm=13639` |
| 密码加密 | `mmsfjm=1` → 取 `/xtgl/login_getPublicKey.html` 的 `modulus`/`exponent`，用页面内 RSA 加密后填 `#hidMm` |
| 验证码 | `dlsfbxyzm=0`，但**失败 3 次后服务端强制要求**；锁定 3 分钟 |
| 统一认证 | 正方端**没有**统一登录按钮，两条路各自独立登录 |
| 课表接口 | `POST /jwglxt/kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508&su=<学号>`，body `xnm=&xqm=&kzlx=ck`（空参=当前学期） |
| 门户 | `https://ywtb.lzhit.edu.cn/portal/home`（OAuth2，client_id `X35zbo84PxbkKdquXshT`） |
| 统一认证 | `https://sso.lzhit.edu.cn/sso/login` |
| 教务 SSO | `/sso/ksiotlogin` → CAS 换票 → `jwglxt/ticketlogin` → `index_initMenu.html` |

### 响应结构

```jsonc
{
  "xsxx":    { "XH": "学号", "XM": "姓名", "BJMC": "班级", "ZYMC": "专业", "XNMC": "2026-2027" },
  "kbList":  [ /* 有固定时段的课 */ ],
  "sjkList": [ /* 实践课/其它课，只有 qsjsz 周次范围，无节次 */ ],
  "xqjmcMap": { "1": "星期一", "...": "..." }
}
```

`kbList` 关键字段：

| 字段 | 含义 | 示例 |
| --- | --- | --- |
| `kcmc` | 课程名 | `Python程序设计B` |
| `xqj` / `xqjmc` | 星期几 | `1` / `星期一` |
| `jcs` / `jc` | 节次 | `1-2` / `1-2节` |
| `zcd` | 周次段 | `3-4周,7-9周`、`2-6周(双)`、`第7周` |
| `cdmc` | 教室 | `1教408` |
| `xm` | 教师（**kbList 用 `xm`，sjkList 用 `jsxm`**） | `陈稳中` |
| `jxbmc` | 教学班编号（**含课程代码**，如 `(2026-2027-1)-DJ0100701-12`） | — |
| `cxbj` / `cxbjmc` | 重修标记 | `1` / `重修` |
| `xslxbj` | 课程性质符号 | ○理论 ▲上机 ■实验 ●实践 ★实验上机 |
| `xf` | 学分 | `2` |

> ⚠️ **纯文本复制会丢失星期列**：课表页的"星期"由表格**列位置**表达，
> Ctrl+A 复制的文本里 7 个格子被压成一维，无法还原星期几。
> 必须走接口（`xqj`）或从 DOM 按列位置提取。

### 其它菜单功能码（实测抓取）

| 菜单 | gnmkdm | 路径 |
| --- | --- | --- |
| 个人课表查询 | `N253508` | `/kbcx/xskbcx_cxXskbcxIndex.html` |
| 学生课表查询（按周次） | `N2154` | `/kbcx/xskbcxZccx_cxXskbcxIndex.html` |
| 学生选课情况确认 | `N2158` | `/kbcx/xskkbqr_cxXskbqrIndex.html` |
| **重修课程查询** | `N255720` | `/cxkccx/cxkccx_cxCxkccxIndex.html` |
| 全校课表查询 | `N219933` | `/design/viewFunc_cxDesignFuncPageIndex.html` |

> **「重修课程查询」是查"开课单位/课程性质"的关键页面**（表格列
> `kkbmmc`=开课学院、`kclbmc`=课程类别、`kch`=课程代码）。
> 它是 jqGrid，爬 DOM 不可靠 —— 用
> `jQuery('#tabGrid').jqGrid('getRowData')` 直接读数据模型。
> 注意查询有**串页**问题：提交后要等结果内容真的变了再读。
