#!/bin/bash
# 把 App 里的 SwiftUI 视图离屏渲染成 PNG，方便在没有窗口的情况下检查动画效果。
#
#   ./Tools/render-preview.sh            # 渲染 Preview/*.png
#   ./Tools/render-preview.sh icons      # 渲染 Preview/AppIcon/*.png（App 图标源图）
#
# 说明：xcodebuild / swiftc 需要可写的模块缓存目录，这里统一放在项目内的 Build/ 下，
# 避免依赖系统临时目录（在某些沙盒环境下系统临时目录不可写）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p Build/tmp Build/modulecache Build/snapshot
export TMPDIR="$ROOT/Build/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/Build/modulecache"

MODE="${1:-preview}"
OUT="${2:-Preview}"

# 除 App 入口（含 @main）之外的全部源码，加上快照工具的入口。
SOURCES=$(find DeepSeekStatus -name '*.swift' ! -name 'DeepSeekStatusApp.swift' | sort)

# shellcheck disable=SC2086
swiftc \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -module-cache-path "$ROOT/Build/modulecache" \
  -o Build/snapshot/DeepSeekSnapshot \
  Tools/Snapshot/main.swift \
  $SOURCES

./Build/snapshot/DeepSeekSnapshot "$MODE" --out "$OUT"
