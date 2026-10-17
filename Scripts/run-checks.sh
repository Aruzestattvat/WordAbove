#!/bin/bash
# WordAbove — 编译并运行 Tests/ 下的验证程序。
#
# 各检查项需要什么：
#   mask-check    脱离辅助功能的纯 UI 校验（材质遮罩、四角透明、子层裁切）。随处可跑。
#   network-check 需要联网，会真的访问 api.dictionaryapi.dev，因此不进 CI。
#
# 说明：
#   两个检查都各自带 @main，而 Sources/App.swift 也有 @main，所以不能和 Sources/ 一起编。
#   这里把每个检查单独编译，同时把 Tests/Support.swift 作为被测代码的副本（原样搬运，
#   仅去掉 App.swift 的 @main 与依赖 ApplicationServices 的 SpotlightObserver）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/dist/checks}"
mkdir -p "$OUT"

MACOS_TARGET="${MACOS_TARGET:-14.0}"
SWIFT_VERSION="${SWIFT_VERSION:-5}"
DICTIONARY="${DICTIONARY:-$ROOT/Resources/dictionary.sqlite}"
# Tests/Support.swift 只覆盖离线词库与卡片定位，不需要 Translation.framework；
# 翻译相关回归由应用内建的 --self-test 覆盖（见 build.sh）。
APP_FRAMEWORKS=(-framework AppKit -framework SwiftUI -lsqlite3)

# 与 build.sh 共用同一份 SDK 选择逻辑；这里不能盲取 `xcrun --show-sdk-path`
# shellcheck source=lib/sdk.sh
source "$ROOT/Scripts/lib/sdk.sh"
select_sdk || exit 1

echo "==> SDK: $SDK_PATH"
echo "==> 输出: $OUT"

# Support.swift 提供 cardFrame / normalizedWord / Entry / DictionaryStore / RoundedMaterialView
xcrun swiftc -sdk "$SDK_PATH" -target "arm64-apple-macosx${MACOS_TARGET}" -swift-version "$SWIFT_VERSION" \
  "$ROOT/Tests/Support.swift" "$ROOT/Tests/MaskCheck.swift" \
  "${APP_FRAMEWORKS[@]}" -o "$OUT/mask-check"

echo "==> 运行 mask-check"
"$OUT/mask-check"

xcrun swiftc -sdk "$SDK_PATH" -target "arm64-apple-macosx${MACOS_TARGET}" -swift-version "$SWIFT_VERSION" \
  "$ROOT/Tests/Support.swift" "$ROOT/Tests/NetworkCheck.swift" \
  "${APP_FRAMEWORKS[@]}" -o "$OUT/network-check"

echo "==> 运行 network-check（需要联网；词库：${DICTIONARY}）"
WORDABOVE_DICTIONARY="$DICTIONARY" "$OUT/network-check"

# 翻译路由与准备队列的回归在应用内建自检里，这里一并跑（需要能构建应用）
if [ "${SKIP_APP_SELFTEST:-0}" != "1" ]; then
  echo "==> 构建应用并运行内建自检（翻译路由 / 准备队列 / 词典与布局回归）"
  bash "$ROOT/Scripts/build.sh" --out "$OUT/app" --self-test
fi

echo "==> 全部检查通过"
