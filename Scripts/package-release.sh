#!/bin/bash
# 打包可分发 zip（用于 GitHub Release 附件）。
#
#   bash Scripts/package-release.sh [--build] [--out DIR]
#
# 关键点：
#   · 必须用 ditto -c -k --sequesterRsrc，才能保留 .app 内的符号链接、权限位与扩展属性
#   · 不能用 `zip -r`：会混入 ._* AppleDouble 文件，下载后应用无法正常签名/启动
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.1.10}"
OUT="$ROOT/dist"
DO_BUILD=0
APP_NAME="${APP_NAME:-词在上}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build) DO_BUILD=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

[ "$DO_BUILD" = "1" ] && bash "$ROOT/Scripts/build.sh" --out "$OUT"

APP="$OUT/$APP_NAME.app"
[ -d "$APP" ] || { echo "错误：找不到 ${APP}，先运行 bash Scripts/build.sh" >&2; exit 1; }

# 分发包必须是签过名的，否则用户首次打开会被 Gatekeeper 拦下
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "错误：$APP 签名校验失败，先重新构建" >&2; exit 1; }

ZIP="$OUT/WordAbove-${VERSION}-macos-arm64.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> 已打包：$ZIP"
echo "==> 大小：$(du -h "$ZIP" | cut -f1)"
echo "==> 内容抽样："
unzip -l "$ZIP" | sed -n '1,6p'
echo "==> 校验包内无 AppleDouble 垃圾："
if unzip -l "$ZIP" | grep -q '/\._'; then echo "  ⚠️ 发现 ._ 文件"; else echo "  干净"; fi
# 只写裸文件名（不写构建机绝对路径），下载者才能直接 `shasum -a 256 -c`
( cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256" )
cat "$ZIP.sha256"
