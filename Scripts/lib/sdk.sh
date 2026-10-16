#!/bin/bash
# WordAbove — 共享的 SDK 选择逻辑。用 source 引入，不要直接执行。
#
#    source "$ROOT/Scripts/lib/sdk.sh"
#    select_sdk            # 设置并导出 SDK_PATH
#
# 为什么需要它：
#   `xcrun --show-sdk-path` 返回的不一定是当前 swiftc 能用的 SDK。SDK 是用某个具体
#   Swift 版本构建的，编译器版本不匹配会直接报
#     "this SDK is not supported by the compiler"
#   （实测：本机默认 SDK 27.0 由 Swift 6.4 构建，而 swiftc 是 6.3.3 → 编译失败）。
#   硬编码版本同样不行：换台机器 SDK 版本就变了。
#
# 做法：按「编译器自身的目标系统版本」排序候选 SDK，逐个用最小样例实测，取第一个能编译的。
# 可用环境变量 SDK_PATH 或 SDK 跳过自动探测。
#
# 依赖调用方已定义（都有默认值也可）：MACOS_TARGET、SWIFT_VERSION

select_sdk() {
  local readonly PROBE_SRC='import Foundation; print("ok")'

  if [ -n "${SDK_PATH:-}" ]; then
    [ -d "$SDK_PATH" ] || { echo "错误：指定的 SDK_PATH 不存在 -> $SDK_PATH" >&2; return 1; }
    export SDK_PATH
    return 0
  fi
  if [ -n "${SDK:-}" ]; then
    [ -d "$SDK" ] || { echo "错误：指定的 SDK 不存在 -> $SDK" >&2; return 1; }
    SDK_PATH="$SDK"; export SDK_PATH
    return 0
  fi

  local target="${MACOS_TARGET:-14.0}"
  local swver="${SWIFT_VERSION:-5}"
  local compiler_target preferred
  compiler_target="$(xcrun swiftc --version 2>/dev/null \
    | sed -n 's/^Target: [a-z0-9_]*-apple-macosx\([0-9.]*\)$/\1/p' | head -1)"
  preferred="/Library/Developer/CommandLineTools/SDKs/MacOSX${compiler_target}.sdk"

  local candidates=() saw d
  for d in "$preferred" \
           "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" \
           "$(xcrun --show-sdk-path 2>/dev/null || true)" \
           /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk \
           /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk; do
    [ -d "$d" ] || continue
    local dup=0
    for saw in ${candidates[@]+"${candidates[@]}"}; do [ "$saw" = "$d" ] && dup=1; done
    [ "$dup" = "1" ] || candidates+=("$d")
  done

  local probe_dir probe_cache
  probe_dir="$(mktemp -d)"; probe_cache="$probe_dir/cache"
  printf '%s\n' "$PROBE_SRC" > "$probe_dir/ap.swift"

  local chosen=""
  for d in ${candidates[@]+"${candidates[@]}"}; do
    if xcrun swiftc -sdk "$d" -target "arm64-apple-macosx${target}" -swift-version "$swver" \
         -module-cache-path "$probe_cache" "$probe_dir/ap.swift" -o "$probe_dir/ap.out" >/dev/null 2>&1; then
      chosen="$d"; break
    fi
  done
  rm -rf "$probe_dir"

  [ -n "$chosen" ] || { echo "错误：找不到可用 SDK。请设置 SDK_PATH 指向可编译的 MacOSX*.sdk" >&2; return 1; }
  SDK_PATH="$chosen"; export SDK_PATH
  return 0
}
