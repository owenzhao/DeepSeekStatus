#!/bin/bash
# 命令行构建脚本。
#
#   ./Tools/build.sh            # Debug
#   ./Tools/build.sh release    # Release
#   ./Tools/build.sh run        # Debug + 启动
#
# 说明：把 TMPDIR 与模块缓存放进工程内的 Build/，避免依赖系统临时目录
# （某些沙盒环境下 /var/folders 不可写，xcodebuild 会直接失败）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="Debug"
RUN=0
case "${1:-debug}" in
  release|Release) CONFIG="Release" ;;
  run) RUN=1 ;;
  debug|Debug) ;;
  *) echo "用法: $0 [debug|release|run]"; exit 1 ;;
esac

mkdir -p Build/tmp Build/modulecache
export TMPDIR="$ROOT/Build/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/Build/modulecache"
export SWIFT_MODULE_CACHE_PATH="$ROOT/Build/modulecache"

xcodebuild \
  -project DeepSeekStatus.xcodeproj \
  -scheme DeepSeekStatus \
  -configuration "$CONFIG" \
  -derivedDataPath Build/DerivedData \
  build

APP="$ROOT/Build/DerivedData/Build/Products/$CONFIG/DeepSeekStatus.app"
echo "✅ 构建完成: $APP"

if [ "$RUN" = "1" ]; then
  # 先退出已有实例，避免菜单栏出现两只鲸鱼。
  pkill -f "DeepSeekStatus.app/Contents/MacOS/DeepSeekStatus" 2>/dev/null || true
  sleep 0.5
  open "$APP"
  echo "🐳 已启动，请查看菜单栏右上角。"
fi
