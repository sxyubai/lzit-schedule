# 抓取脚本的离线测试

WebView 注入的抓取脚本是纯 JS，可以脱离模拟器/真机验证。

## 为什么需要它

`runJavaScriptReturningResult` **不会 await Promise** —— 脚本若写成
`(async () => {...})()`，拿到的是 `{}` / `null`，界面只会显示
「抓取失败：未知原因 / 调试信息：null」（真实踩过）。
所以脚本改成「写 `window.__lzitFetchResult` + Dart 侧轮询」，
这个测试就是验证那条链路。

## 用法

```bash
cd tools/js_test
python extract_js.py      # 从 lib/pages/import_page.dart 提取最新脚本
node test_fetch_script.js  # 跑测试（16 项断言）
```

⚠️ 改了 `kFetchScript` 之后必须重新 `extract_js.py`，否则测的还是旧脚本。

## 覆盖场景

1. 页面停在 SSO 登录页 → 应明确报「不在教务系统」并带上实际域名
2. 页面在教务系统且接口有数据 → 应拿到 `kbList` / `sjkList` / `xsxx`
3. 页面在教务系统但接口空、DOM 也空 → `debug` 必须是对象而非 null
