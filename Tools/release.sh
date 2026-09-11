#!/bin/bash
# 打发布包并用 Sparkle 生成签名好的更新源（appcast.xml）。
#
#   ./Tools/release.sh            # 构建 Release，产出 Build/release/{archives/*.zip, appcast.xml}
#   ./Tools/release.sh --upload   # 再创建 GitHub Release 并上传 zip + appcast.xml（需要 gh）
#
# 两个地址要配合：
#   - App 内的 SUFeedURL 指向 releases/latest/download/appcast.xml（见 Config/Info.plist）
#   - appcast 里的下载地址指向 releases/download/v<版本>/DeepSeekStatus-<版本>.zip
# 所以**每个 Release 都要把 appcast.xml 作为资源传上去**，否则 App 拉不到更新源。
#
# 版本与构建号（MARKETING_VERSION / CURRENT_PROJECT_VERSION）必须比上一版大，
# Sparkle 靠 CFBundleVersion 判断新旧。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UPLOAD=0
[[ "${1:-}" == "--upload" ]] && UPLOAD=1

REPO_URL="https://github.com/owenzhao/DeepSeekStatus"
OUT="$ROOT/Build/release"
ARCHIVES="$OUT/archives"
GENERATE_APPCAST="$ROOT/Build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"

# 1. 构建 Release
./Tools/build.sh release

APP="$ROOT/Build/DerivedData/Build/Products/Release/DeepSeekStatus.app"
INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
ZIP_NAME="DeepSeekStatus-$VERSION.zip"
TAG="v$VERSION"

[[ -x "$GENERATE_APPCAST" ]] || { echo "❌ 找不到 generate_appcast：$GENERATE_APPCAST"; exit 1; }

# 2. 打包。用 ditto 保住符号链接与可执行权限，App 里嵌的 Sparkle.framework 才能被加载。
mkdir -p "$ARCHIVES"
rm -f "$ARCHIVES/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVES/$ZIP_NAME"

# 3. 生成 appcast。签名用的 EdDSA 私钥从登录钥匙串读取（generate_keys 生成的那把）。
"$GENERATE_APPCAST" \
  --download-url-prefix "$REPO_URL/releases/download/$TAG/" \
  --link "$REPO_URL" \
  -o "$ARCHIVES/appcast.xml" \
  "$ARCHIVES"

echo
echo "✅ DeepSeek Status $VERSION (build $BUILD)"
echo "   归档  : $ARCHIVES/$ZIP_NAME"
echo "   更新源: $ARCHIVES/appcast.xml"

# 4. 可选：发布到 GitHub
if [[ "$UPLOAD" == "1" ]]; then
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "DeepSeek Status $VERSION" --generate-notes
  fi
  gh release upload "$TAG" "$ARCHIVES/$ZIP_NAME" "$ARCHIVES/appcast.xml" --clobber
  echo "🐳 已上传到 $TAG（appcast.xml 必须在最新的 Release 里）"
else
  echo
  echo "下一步（手动发布）："
  echo "  gh release create $TAG --title 'DeepSeek Status $VERSION' --generate-notes"
  echo "  gh release upload $TAG '$ARCHIVES/$ZIP_NAME' '$ARCHIVES/appcast.xml'"
fi
