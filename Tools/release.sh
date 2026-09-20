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
# 公证凭据在钥匙串里的名字，可用环境变量覆盖：NOTARY_PROFILE=xxx ./Tools/release.sh
NOTARY_PROFILE="${NOTARY_PROFILE:-DeepSeekStatus-notary}"

# 1. 构建 Release
./Tools/build.sh release

APP="$ROOT/Build/DerivedData/Build/Products/Release/DeepSeekStatus.app"
INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
ZIP_NAME="DeepSeekStatus-$VERSION.zip"
TAG="v$VERSION"

[[ -x "$GENERATE_APPCAST" ]] || { echo "❌ 找不到 generate_appcast：$GENERATE_APPCAST"; exit 1; }

# 1.5 用 Developer ID 深度重签，再由内到外签回本体。
#
# 两个坑，都会让公证直接判 Invalid：
#   a) SPM 分发的 Sparkle 二进制框架里，Updater.app / Installer.xpc / Downloader.xpc 是 ad-hoc 签名，
#      而 xcodebuild 只签框架本身、不深入嵌套组件 →「not signed with a valid Developer ID certificate」
#      且「does not include a secure timestamp」。
#   b) Xcode 会给 App 本体注入调试用的 get-task-allow，公证明确拒绝。
#      这里不带 --preserve-metadata 重签本体，正好把它去掉（本项目不需要任何 entitlement）。
SIGN_IDENTITY=$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)$/\1/p' | head -1)
[[ -n "$SIGN_IDENTITY" ]] || { echo "❌ 没找到 Developer ID Application 签名，请检查 CODE_SIGN_IDENTITY"; exit 1; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  # 按 Sparkle 官方顺序从内到外签名。Downloader 自带的 entitlement
  # 必须保留；Autoupdate 是独立可执行文件，不能遗漏。
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
    --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE"
fi
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Sparkle 的安全原子替换要求 Autoupdate 与新 App 属于同一 Team ID。
# 不在发布前硬性检查，签名看似成功也可能在升级时才暴露。
APP_TEAM=$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
AUTOUPDATE="$SPARKLE/Versions/B/Autoupdate"
AUTOUPDATE_TEAM=$(codesign -dv --verbose=4 "$AUTOUPDATE" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[[ -n "$APP_TEAM" && "$APP_TEAM" == "$AUTOUPDATE_TEAM" ]] || {
  echo "❌ App Team ID ($APP_TEAM) 与 Autoupdate Team ID ($AUTOUPDATE_TEAM) 不一致"
  exit 1
}
echo "✅ 已重签：${SIGN_IDENTITY}"

# 2. 打包。用 ditto 保住符号链接与可执行权限，App 里嵌的 Sparkle.framework 才能被加载。
#
# 每次都清空归档目录：appcast 的下载地址前缀是按 tag 区分的（releases/download/v<版本>/…），
# 如果留着旧版本的 zip，generate_appcast 会把旧条目的地址也指到新 tag 上，产生 404 的失效条目。
rm -rf "$ARCHIVES"
mkdir -p "$ARCHIVES"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVES/$ZIP_NAME"

# 3. 公证（notarize）并装订（staple）。
#
# 凭据放在钥匙串里的 notarytool 配置中，先自己存一次：
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#     --apple-id <你的 Apple ID> --team-id 96NM39SGJ5
# （也可以用 App Store Connect API Key：--key/--key-id/--issuer）
echo "⏳ 提交公证，profile = ${NOTARY_PROFILE} …"
xcrun notarytool submit "$ARCHIVES/$ZIP_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 装订后重新打包：Sparkle 下载到的必须是这个版本，离线也能过 Gatekeeper。
rm -f "$ARCHIVES/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVES/$ZIP_NAME"

# 4. 生成 appcast。签名用的 EdDSA 私钥从登录钥匙串读取（generate_keys 生成的那把）。
"$GENERATE_APPCAST" \
  --download-url-prefix "$REPO_URL/releases/download/$TAG/" \
  --link "$REPO_URL" \
  -o "$ARCHIVES/appcast.xml" \
  "$ARCHIVES"

echo
echo "✅ DeepSeek Status $VERSION (build $BUILD)"
echo "   归档  : $ARCHIVES/$ZIP_NAME"
echo "   更新源: $ARCHIVES/appcast.xml"

# 5. 可选：发布到 GitHub
if [[ "$UPLOAD" == "1" ]]; then
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "DeepSeek Status $VERSION" --generate-notes
  fi
  gh release upload "$TAG" "$ARCHIVES/$ZIP_NAME" "$ARCHIVES/appcast.xml" --clobber
  echo "🐳 已上传到 ${TAG}，appcast.xml 必须在最新的 Release 里"
else
  echo
  echo "下一步（手动发布）："
  echo "  gh release create $TAG --title 'DeepSeek Status $VERSION' --generate-notes"
  echo "  gh release upload $TAG '$ARCHIVES/$ZIP_NAME' '$ARCHIVES/appcast.xml'"
fi
