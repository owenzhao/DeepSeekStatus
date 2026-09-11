#!/bin/bash
# 让 Xcode 重新提取源码里的字符串并同步到 String Catalog。
#
#   ./Tools/update-strings.sh
#
# 做两件事：
#   1. 构建一次 —— `SWIFT_EMIT_LOC_STRINGS = YES` 会为每个源文件产出 .stringsdata；
#   2. 用 `xcstringstool sync` 把这些键合并进 Localizable.xcstrings，
#      同时把源码里已经找不到的键标记为 stale 并删除。
#
# 约定：所有界面文案都从源码里的 `String(localized:defaultValue:)` 出（带显式 key），
# 所以可以直接跑 sync 让 catalog 与源码保持一致；纯数字/符号类的 Text 请用
# `Text(verbatim:)`，否则会被当成可本地化键提取进来。
#
# 跑完再去 Xcode 里补/改翻译即可（Xcode 打开时会自动补上 extractionState 之类的元数据）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CATALOG="DeepSeekStatus/Localizable.xcstrings"

./Tools/build.sh release

# shellcheck disable=SC2046
xcrun xcstringstool sync "$CATALOG" \
  --stringsdata $(find Build/DerivedData -name '*.stringsdata' -path '*Release*')

echo "✅ 已同步 $CATALOG"
