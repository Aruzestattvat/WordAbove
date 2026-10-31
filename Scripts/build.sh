#!/bin/bash
# WordAbove · 词在上 — 可移植构建脚本
#
# 相对原始版本的三处修正：
#   1. SDK 不再硬编码 MacOSX26.5.sdk，默认用 `xcrun --show-sdk-path`（可用 SDK_PATH 覆盖）
#   2. 部署目标与架构可配置（MACOS_TARGET / ARCHS），默认沿用 arm64 + macOS 14.0
#   3. 支持签名开关（CODESIGN）与自检开关（--self-test）
#
# 用法：
#   bash Scripts/build.sh [--out DIR] [--self-test]
#
# 环境变量：
#   SDK_PATH       指定 SDK（默认 `xcrun --show-sdk-path`）
#   ARCHS          架构，空格分隔。默认 "arm64"；设成 "arm64 x86_64" 会尝试 universal
#   MACOS_TARGET   最低系统版本，默认 14.0
#   SWIFT_VERSION  Swift 语言版本，默认 5
#   CODESIGN       1=ad-hoc 签名（默认），0=跳过
#   APP_NAME       .app 名称，默认 词在上
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ARCHS="${ARCHS:-arm64}"
MACOS_TARGET="${MACOS_TARGET:-14.0}"
SWIFT_VERSION="${SWIFT_VERSION:-5}"
CODESIGN="${CODESIGN:-1}"
APP_NAME="${APP_NAME:-词在上}"
BUNDLE_ID="local.wordabove.SpotlightDictionary"
EXECUTABLE="WordAbove"
VERSION="1.1.18"
BUILD_NUMBER="21"

OUT="$ROOT/dist"
RUN_SELF_TEST=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --self-test) RUN_SELF_TEST=1; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# 选择 SDK（逻辑见 Scripts/lib/sdk.sh，与 run-checks.sh / CI 共用一份）
# ---------------------------------------------------------------------------
# shellcheck source=lib/sdk.sh
# 应用用到 Translation.framework，探测 SDK 时必须要求该框架存在
REQUIRED_SDK_VERSION="26.0"
REQUIRED_FRAMEWORKS="Translation"
source "$ROOT/Scripts/lib/sdk.sh"
select_sdk || exit 1

echo "==> 编译器   : $(xcrun swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1)"
echo "==> 默认 SDK : $(xcrun --show-sdk-path)"

APP="$OUT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> SDK      : $SDK_PATH"
echo "==> 架构     : $ARCHS"
echo "==> 最低系统 : macOS $MACOS_TARGET"
echo "==> 输出     : $APP"

FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework ApplicationServices
            -framework ServiceManagement -framework Translation -lsqlite3)

# 编译所有 Sources/*.swift，把 @main 与 cardFrame/normalizedWord 编进产物；
# 自检（--self-test）走 App.swift 里的 WordAboveMain.selfTest()。
# 注意：不要和 Tests/ 一起编译，两处都有 @main。
if [ "$(echo "$ARCHS" | wc -w | tr -d ' ')" -gt 1 ]; then
  SLICES=()
  for arch in $ARCHS; do
    slice="$OUT/.slice-$arch-$EXECUTABLE"
    xcrun swiftc -sdk "$SDK_PATH" -target "${arch}-apple-macosx${MACOS_TARGET}" \
      -swift-version "$SWIFT_VERSION" -O "${FRAMEWORKS[@]}" \
      "$ROOT/Sources"/*.swift -o "$slice"
    SLICES+=("$slice")
  done
  xcrun lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$EXECUTABLE"
  rm -f "${SLICES[@]}"
else
  xcrun swiftc -sdk "$SDK_PATH" -target "${ARCHS}-apple-macosx${MACOS_TARGET}" \
    -swift-version "$SWIFT_VERSION" -O "${FRAMEWORKS[@]}" \
    "$ROOT/Sources"/*.swift -o "$APP/Contents/MacOS/$EXECUTABLE"
fi

# 词库与第三方许可必须随包分发：Resources/ 下的 dictionary.sqlite 是运行时依赖
cp "$ROOT/Resources"/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>$MACOS_TARGET</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>WordAbove · ECDICT / WordNet acknowledgements included.</string>
</dict></plist>
PLIST

if [ "$CODESIGN" = "1" ]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
  echo "==> CODESIGN=0，跳过签名"
fi

echo "==> 构建完成：$APP"
if [ "$RUN_SELF_TEST" = "1" ]; then
  echo "==> 运行 --self-test"
  "$APP/Contents/MacOS/$EXECUTABLE" --self-test
fi
