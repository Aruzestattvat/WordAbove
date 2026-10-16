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

# 与 build.sh 共用同一份 SDK 选择逻辑；这里不能盲取 `xcrun --show-sdk-path`
# shellcheck source=lib/sdk.sh
source "$ROOT/Scripts/lib/sdk.sh"
select_sdk || exit 1

echo "==> SDK: $SDK_PATH"
echo "==> 输出: $OUT"

# Support.swift 提供 cardFrame / normalizedWord / Entry / DictionaryStore / RoundedMaterialView
xcrun swiftc -sdk "$SDK_PATH" -target "arm64-apple-macosx${MACOS_TARGET}" -swift-version "$SWIFT_VERSION" \
  "$ROOT/Tests/Support.swift" "$ROOT/Tests/MaskCheck.swift" \
  -framework AppKit -framework SwiftUI -lsqlite3 \
  -o "$OUT/mask-check"

echo "==> 运行 mask-check"
"$OUT/mask-check"

xcrun swiftc -sdk "$SDK_PATH" -target "arm64-apple-macosx${MACOS_TARGET}" -swift-version "$SWIFT_VERSION" \
  "$ROOT/Tests/Support.swift" "$ROOT/Tests/NetworkCheck.swift" \
  -framework AppKit -framework SwiftUI -lsqlite3 \
  -o "$OUT/network-check"

echo "==> 运行 network-check（需要联网；词库：${DICTIONARY}）"
WORDABOVE_DICTIONARY="$DICTIONARY" "$OUT/network-check"

echo "==> 全部检查通过"
