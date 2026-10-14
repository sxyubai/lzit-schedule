"""从 lib/pages/import_page.dart 提取 kFetchScript 到 fetch_script.js。

路径以**脚本自身位置**为基准，不依赖当前工作目录。
"""
import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "lib", "pages", "import_page.dart"))
OUT = os.path.join(HERE, "fetch_script.js")

if not os.path.exists(SRC):
    raise SystemExit("找不到源文件: " + SRC)

src = io.open(SRC, encoding="utf-8").read()

m = re.search(r"const String kFetchScript = r'''(.*?)''';", src, re.S)
if not m:
    raise SystemExit("在源文件里没找到 kFetchScript")

js = m.group(1)
io.open(OUT, "w", encoding="utf-8", newline="\n").write(js)

print("源文件 :", SRC)
print("输出   :", OUT)
print("长度   :", len(js))
print("全局写入:", js.count("window.__lzitFetchResult"), "次")
print("返回可序列化值:", js.rstrip().endswith("'started';"))
