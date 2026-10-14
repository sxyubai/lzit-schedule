# 柳工课表 · lzit-schedule

一个干净的自用安卓课表 App —— 从学校教务系统导入课表，**无广告、无推送、不收集信息**。

> 仓库地址：<https://github.com/sxyubai/lzit-schedule>

> 起因很简单：原来用的课表软件被商业化接手后广告变多，而学校教务系统又换了统一身份认证入口，
> 旧软件导入不进去。索性自己写一个。

## 功能

### 课表
- **从教务系统直接导入**：内置浏览器 → 自己登录统一身份认证 → 进入教务系统 → 一键抓取课表
  （登录过程完全交给页面，App 不接触账号密码）
- **多套课表**：大一/大二/大三/大四各存一份，可切换、重命名、删除；导入时可选「覆盖当前」或「新增一份」
- **左右滑动切周**，打开自动定位到当前周；点标题即可跳回本周
- **今天高亮**：整列着色 + 表头胶囊（写「今天」而不是日期）
- **表头显示日期**（10/5、10/6…），学期第一天可自定义
- **冲突课程**：同一时段多门课时显示 `1/2` 角标，点击切换，且**跨周次同步记忆**
- **无固定时段的课程**（实践课/实习/网课）折叠面板单独列出
- **手动添加**：点课表空白格可以加「每周重复的课程」或「一次性事件」（事件是紫色卡片、
  带图钉，点它可以删除）；也可以直接手动填一份课表，不用教务系统

### 自定义外观
- **背景图**：从相册选图 → 双指缩放 + 拖动选区裁剪
- **透明度分层可调**：背景图透明度 / 背景压暗 / 课程卡片不透明度
- 卡片圆角、单节高度可调，改动实时预览

### 上课提醒
- 上课前 N 分钟提醒（5/10/15/20/30 可选）
- **响铃 + 震动 + 最高优先级**，以顶部横幅弹出（类似 QQ/微信）
- 锁屏可见；重启手机后自动恢复排期
- 内置小米等国产系统的权限设置指引

## 截图

> 待补充。

## 构建

需要 **Flutter 3.44+** 与 **Android SDK 36**。

```bash
flutter pub get
flutter test                 # 跑单元测试
flutter build apk --release  # 产物在 build/app/outputs/flutter-apk/
```

### 国内环境注意

- 项目已在 `android/settings.gradle.kts` 配了**阿里云镜像**，一般不需要代理。
  只有**首次**构建需要下载 Flutter 引擎的 Android 库时才要临时开代理（下完就有缓存）。
- ⚠️ **不要**在 `android/gradle.properties` 里写死代理地址：
  一旦写了，梯子一关就会导致**所有** Gradle 下载都走死代理而完全无法构建。
- 已设 `kotlin.incremental=false`：pub 缓存在 C 盘、项目在 D 盘时，
  Kotlin 增量编译会报 "different roots" 而构建失败。
- Windows 上带插件的 Flutter 项目需要开启**开发者模式**（插件要创建符号链接）。

## 技术笔记

写这个项目踩过的一些坑，记录一下：

- **WebView 抓取不能靠 `runJavaScriptReturningResult` 取 async 函数的返回值** ——
  它不会 await Promise，只会拿到 `{}` 或 `null`（表现为界面报「调试信息：null」）。
  正确做法：脚本把结果写进 `window.__xxx`，Dart 侧轮询读取。
- **正方教务系统页面里的 jQuery 扩展会污染 `Array.prototype`** ——
  注入 JS 时用 `map`/`filter` 会得到自相矛盾的结果，一律改用 `for` 循环。
- **Android 的通知渠道一旦创建，配置就不可修改** ——
  想调整声音/震动/优先级，只能换一个新的 `channelId`。
- **自适应图标（Android 8+）的画布是 108dp，但系统只保留中心 72dp（2/3）** ——
  前景内容超出这个范围会被裁掉。本项目用脚本生成全套图标（`tools/icon/`）。
- **课表接口只给周次，不给日期** —— 所有日期都由「学期第一天」推算，
  所以这个参数必须让用户能改（错一周，整张表全错）。
- **「课程」和「事件」是两种东西**：课程按「周次 + 星期几」重复，事件绑在具体日期上。
  两者都用**节次**表示时段，才能画进同一张网格；事件靠 `weekOf(date)` 换算成
  「第几周 + 星期几」，只画在正在看的那一周。
- **空白格点击层要垫在卡片下面**：用一整层 `HitTestBehavior.opaque` 的透明
  `GestureDetector` 铺满网格，声明在课程卡片**之前**（z 序在下），这样点空白处能命中、
  点卡片仍然走卡片自己的手势。

抓取脚本是纯 JS，可以脱离真机验证：

```bash
cd tools/js_test
python extract_js.py        # 从 lib/pages/import_page.dart 提取最新脚本
node test_fetch_script.js   # 跑断言
```

## 教务系统接口情报

> 这些是开发时实测到的接口细节，写出来供想改这个项目的同学参考。
> 都是页面上 F12 就能看到的东西，不涉及任何账号或隐私。

| 项 | 值 |
| --- | --- |
| 教务系统 | 正方 V-9.0，`https://jwglxt.lzhit.edu.cn/jwglxt` |
| 统一认证 | `https://sso.lzhit.edu.cn/sso/login` |
| 门户 | `https://ywtb.lzhit.edu.cn/portal/home` |
| 教务 SSO 入口 | `/sso/ksiotlogin` → CAS 换票 → `ticketlogin` → `index_initMenu.html` |
| 学校代码 | `xxdm=13639` |
| 课表接口 | `POST /jwglxt/kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508&su=<学号>`，body `xnm=&xqm=&kzlx=ck`（空参 = 当前学期） |

### 课表接口响应结构

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
| `xm` | 教师（注意：`kbList` 用 `xm`，`sjkList` 用 `jsxm`） | `陈稳中` |
| `jxbmc` | 教学班编号（含课程代码，如 `(2026-2027-1)-DJ0100701-12`） | — |
| `cxbj` / `cxbjmc` | 重修标记 | `1` / `重修` |
| `xslxbj` | 课程性质符号 | ○理论 ▲上机 ■实验 ●实践 ★实验上机 |
| `xf` | 学分 | `2` |

> ⚠️ **纯文本复制会丢失星期列**：课表页的"星期"由表格**列位置**表达，
> Ctrl+A 复制的文本里 7 个格子被压成一维，无法还原星期几。
> 必须走接口（`xqj`）或从 DOM 按列位置提取。

### 其它菜单的功能码

| 菜单 | gnmkdm | 路径 |
| --- | --- | --- |
| 个人课表查询 | `N253508` | `/kbcx/xskbcx_cxXskbcxIndex.html` |
| 学生课表查询（按周次） | `N2154` | `/kbcx/xskbcxZccx_cxXskbcxIndex.html` |
| 学生选课情况确认 | `N2158` | `/kbcx/xskbqr_cxXskbqrIndex.html` |
| 重修课程查询 | `N255720` | `/cxkccx/cxkccx_cxCxkccxIndex.html` |
| 全校课表查询 | `N219933` | `/design/viewFunc_cxDesignFuncPageIndex.html` |

> 「重修课程查询」是查**开课单位 / 课程性质**的关键页面
> （表格列 `kkbmmc`=开课学院、`kclbmc`=课程类别、`kch`=课程代码）。
> 它是 jqGrid，爬 DOM 不可靠 —— 用
> `jQuery('#tabGrid').jqGrid('getRowData')` 直接读数据模型。
> 另外它查询有**串页**问题：提交后要等结果内容真的变了再读。

## 项目结构

```
lib/
  main.dart                   主页（周视图 + 课程列表 + 状态管理）
  models/
    timetable.dart            课表 / 课程 / 时段 / 学生信息
    section_presets.dart       作息时间（柳州工学院南校区，10 节）
    appearance.dart            外观配置（背景图/透明度）+ 持久化
  pages/
    import_page.dart           内置浏览器导入（含注入的抓取脚本）
    course_list_page.dart      课程列表 + 各设置入口
    appearance_page.dart       外观设置（选图/裁剪/滑块）
    reminder_settings.dart     提醒设置
    about_page.dart            关于
  services/
    timetable_parser.dart      教务系统响应解析
    timetable_store.dart       课表本地存储（支持多份）
    slot_prefs.dart            冲突课程的显示偏好（跨周次记忆）
    slot_cluster.dart          同一时段课程聚类
    reminder_service.dart      上课提醒（排期 + 通知）
    ics_export.dart            导出到日历
  widgets/
    week_view.dart             周视图网格
    unscheduled_panel.dart     无固定时段课程面板

tools/
  icon/                        应用图标生成（含 2/3 裁切规范的说明）
  js_test/                     抓取脚本的离线测试
```

## 免责声明

- 本项目**仅供个人学习与自用**，与学校官方无关。
- 课表数据由使用者本人从教务系统获取，App **不收集、不上报任何个人信息**。
- 教务系统若改版，导入功能可能失效。

## 联系

- 作者：**生鲜鱼白**
- 交流群（QQ）：**1126356335**
