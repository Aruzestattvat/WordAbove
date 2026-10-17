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

  # 取 SDK 版本号（如 26.5 / 15.4），失败输出空
  _sdk_version() {
    /usr/libexec/PlistBuddy -c 'Print :Version' "$1/SDKSettings.plist" 2>/dev/null \
      || xcrun --sdk "$1" --show-sdk-version 2>/dev/null
  }

  # 版本比较：$1 >= $2 返回 0
  _version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -n -t. -k1,1 -k2,2 | head -1)" = "$2" ]
  }

  # 校验某个 SDK 是否满足要求；返回不满足的原因（空 = 通过）
  _sdk_problem() {
    local sdk="$1" problem=""
    if [ -n "${REQUIRED_SDK_VERSION:-}" ]; then
      local v; v="$(_sdk_version "$sdk")"
      if [ -z "$v" ] || ! _version_ge "$v" "$REQUIRED_SDK_VERSION"; then
        problem="${problem} 版本 ${v:-未知}<${REQUIRED_SDK_VERSION}"
      fi
    fi
    if [ -n "${REQUIRED_FRAMEWORKS:-}" ]; then
      local fw
      for fw in $REQUIRED_FRAMEWORKS; do
        [ -d "$sdk/System/Library/Frameworks/${fw}.framework" ] || problem="${problem} 缺框架 ${fw}"
      done
    fi
    printf '%s' "$problem"
  }

  if [ -n "${SDK_PATH:-}" ]; then
    [ -d "$SDK_PATH" ] || { echo "错误：指定的 SDK_PATH 不存在 -> $SDK_PATH" >&2; return 1; }
    local p; p="$(_sdk_problem "$SDK_PATH")"
    [ -z "$p" ] || { echo "错误：SDK_PATH 不满足要求：${p}" >&2; return 1; }
    export SDK_PATH
    return 0
  fi
  if [ -n "${SDK:-}" ]; then
    [ -d "$SDK" ] || { echo "错误：指定的 SDK 不存在 -> $SDK" >&2; return 1; }
    local p2; p2="$(_sdk_problem "$SDK")"
    [ -z "$p2" ] || { echo "错误：指定的 SDK 不满足要求：${p2}" >&2; return 1; }
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

  local chosen="" skipped=()
  for d in ${candidates[@]+"${candidates[@]}"}; do
    # 先按版本/框架要求过滤。只验证「能编译 hello world」不够：
    #   · macOS 14.4 的 SDK 能编译普通 Swift，却连 Translation.framework 都没有
    #   · 本机 macOS 15.4 的 SDK 有框架，但版本低于新 API 要求
    # 两种情况都会让真实源码在编译期才失败，所以必须提前拦。
    local problem; problem="$(_sdk_problem "$d")"
    if [ -n "$problem" ]; then
      skipped+=("$(basename "$d"):${problem}")
      continue
    fi
    if xcrun swiftc -sdk "$d" -target "arm64-apple-macosx${target}" -swift-version "$swver" \
         -module-cache-path "$probe_cache" "$probe_dir/ap.swift" -o "$probe_dir/ap.out" >/dev/null 2>&1; then
      chosen="$d"; break
    fi
    skipped+=("$(basename "$d"): 探针编译失败（编译器与 SDK 不匹配）")
  done
  rm -rf "$probe_dir"

  if [ -z "$chosen" ]; then
    echo "错误：找不到满足要求的 macOS SDK。" >&2
    echo "  要求：版本 >= ${REQUIRED_SDK_VERSION:-任意}，框架：${REQUIRED_FRAMEWORKS:-无}" >&2
    if [ "${#skipped[@]}" -gt 0 ] 2>/dev/null; then
      echo "  已排除：" >&2
      printf '    %s\n' "${skipped[@]}" >&2
    fi
    echo "  请安装 macOS 26+ / Xcode 26+，或用 SDK_PATH 指定可用 SDK。" >&2
    return 1
  fi
  SDK_PATH="$chosen"; export SDK_PATH
  return 0
}
