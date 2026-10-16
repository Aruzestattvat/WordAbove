# WordAbove · 词在上

A macOS menu-bar dictionary that renders a card **above the Spotlight search field**. Type an English word in Spotlight (⌘ Space) and a card with the Chinese definition, IPA, and an example sentence appears above the search box; it dismisses itself when Spotlight closes. Follows the system light/dark appearance and never steals keyboard focus.

> 词在上是一个 macOS 菜单栏词典应用：打开 Spotlight 输入英文单词，搜索框上方会浮出一张
> 卡片显示中文释义、音标与例句；关闭 Spotlight 后自动收起。中文完整说明见下方
> [中文说明](#中文说明)。

- **Version**: 1.0.1
- **Platform**: macOS 14.0+ · Apple Silicon (arm64)
- **Dictionary**: 399,213 offline entries, 18,480 with example sentences (ECDICT + WordNet 3.0)
- **License**: MIT for the source · third-party data under its own terms — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)

## Install

1. Download `WordAbove-1.0.1-macos-arm64.zip` from the [Releases](../../releases) page and unzip it.
2. Drag `词在上.app` into `/Applications`.
3. Open it, then in the app's setup window click **打开辅助功能设置** and enable **词在上** under
   *System Settings → Privacy & Security → Accessibility*.
4. Press ⌘ Space and type a word such as `hello`, `focus`, or `serendipity` — no need to hit Enter.

The build is ad-hoc signed (not notarized), so the first launch may require
*System Settings → Privacy & Security → Open Anyway*.

## Build from source

Requirements: Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no external
package manager — the app is four Swift files compiled directly with `swiftc`.

```bash
git clone https://github.com/Aruzestattvat/WordAbove.git
cd WordAbove
bash Scripts/build.sh --self-test          # 产物：dist/词在上.app
```

`Scripts/build.sh` reads the SDK from `xcrun --show-sdk-path`; override anything via environment
variables instead of editing the script:

| Variable | Default | Meaning |
|---|---|---|
| `SDK_PATH` | `xcrun --show-sdk-path` | SDK to compile against |
| `ARCHS` | `arm64` | Space-separated; set `"arm64 x86_64"` to attempt a universal binary |
| `MACOS_TARGET` | `14.0` | `LSMinimumSystemVersion` |
| `SWIFT_VERSION` | `5` | Swift language mode |
| `CODESIGN` | `1` | `0` skips the ad-hoc signature step |
| `APP_NAME` | `词在上` | Output `.app` name |

```bash
# 指定输出目录并跑自检
bash Scripts/build.sh --out dist --self-test

# 跳过签名（CI 或无 codesign 的环境）
CODESIGN=0 bash Scripts/build.sh --out dist

# 用非默认 SDK
SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash Scripts/build.sh
```

The build ends by running `WordAbove --self-test`, which verifies offline lookups, IPA, Chinese
meanings, examples, input filtering, and card placement.

## Repository layout

```
WordAbove/
├── Sources/                 Swift 源码（App / Dictionary / RoundedMaterialView / SpotlightObserver）
├── Resources/               运行时资源：词库、图标、第三方许可全文
│   ├── dictionary.sqlite    40 MB 离线词库（399,213 词条），clone 后即可构建
│   ├── AppIcon.icns
│   ├── ECDICT-LICENSE.txt   ECDICT（MIT）
│   ├── WordNet-LICENSE.txt  Princeton WordNet 3.0
│   └── Sources.html         应用内「词库来源与许可」页面
├── Scripts/
│   ├── build.sh             构建（读 SDK、可配架构/部署目标）
│   ├── run-checks.sh        编译并运行 Tests/ 下的验证程序
│   ├── package-release.sh   打 Release 用的 zip（ditto，保留签名与权限）
│   ├── make_icon.swift      重新生成 WordAbove.iconset/
│   └── prepare_dictionary.py 从 ECDICT+WordNet 重建 dictionary.sqlite
├── Tests/                   验证程序源码（见 Tests/README.md）
└── .github/workflows/build.yml
```

## Tests

`Tests/` holds the verification programs used while developing; the compiled binaries are **not**
tracked. See [Tests/README.md](Tests/README.md).

```bash
bash Scripts/run-checks.sh     # mask-check 本地、network-check 需联网
```

## Compatibility notes

- The shipped binary is **Apple Silicon only** (`arm64`). Intel Macs can build for `x86_64`
  themselves by setting `ARCHS=x86_64` — this repository does not ship an Intel build.
- The card's Spotlight coupling relies on the Accessibility API and window metadata; a future
  macOS update could change that behaviour.
- Accessibility permission may need to be re-granted after updating a locally signed build:
  `tccutil reset Accessibility local.wordabove.SpotlightDictionary` — reset only this app, never others.

## Privacy

Accessibility access is used to read Spotlight's search field and window position. The app does not
log keystrokes, does not read other apps' text, and does not store search history. Online
supplement is **opt-in** (on by default, switchable off) and sends only the current English word to
`api.dictionaryapi.dev`; examples are cached in memory and cleared on quit.

## License

MIT for the source, © 2026 Aruzestattvat — see [LICENSE](LICENSE).
The bundled dictionary data is third-party: ECDICT (MIT) and Princeton WordNet 3.0 — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## 中文说明

独立的 macOS 菜单栏词典辅助应用。打开 Spotlight（⌘ 空格）并输入英文单词后，在搜索框上方显示中文释义、音标与例句；关闭 Spotlight 后自动收起。界面跟随系统深浅色模式，卡片不获取键盘焦点。

### 首次使用

1. 把 `词在上.app` 拖进 `/Applications`。
2. 打开应用，在设置窗口点「打开辅助功能设置」。
3. 在「系统设置 → 隐私与安全性 → 辅助功能」中打开「词在上」的开关。若列表没有该应用，点 `+` 添加 `/Applications/词在上.app`。
4. 回到 Spotlight，输入 `hello`、`focus`、`serendipity` 等单词。无需按回车。

状态栏的词典图标提供设置、暂停、预览和退出。可在应用设置中开启「登录时启动」。应用不会改变 Spotlight 的快捷键或系统词典设置。

### 位置和内容

- 卡片置于 Spotlight 窗口顶部上方，间距 12 pt，宽度随 Spotlight 窗口同步、左右边缘对齐，最大高度 206 pt。只有窗口超出屏幕安全边界时才限制宽度。
- 上方空间有限时自动缩小；不足 100 pt 时隐藏，以免遮住搜索框。此时把 Spotlight 窗口稍微向下拖动。
- 只匹配单个英文词，也支持连字符与撇号。句子、邮箱、中文、未知词不显示卡片。
- 399,213 个离线词条，18,480 个词条含离线例句/用法片段。部分专业词、屈折形式可能缺少音标或例句；长释义和例句会截短显示。
- 例句可能体现某一个词义，不一定对应中文释义列表的第一项。
- 可选联网补充仅在已识别词条缺少音标或例句时访问 Free Dictionary API。网络超时或源数据缺失时保留离线释义，并明确显示暂无例句。

### 权限与隐私

辅助功能用于读取 Spotlight 的搜索栏和窗口位置。程序不记录键盘、不读取其他应用文本、不保存搜索历史。使用窗口元数据定位，不录屏、不需要屏幕录制权限。

联网补充默认开启，仅把当前英文单词发给 `api.dictionaryapi.dev`；服务也会收到正常网络请求所含的 IP 等连接信息。可在设置中关闭。例句仅在内存缓存，退出清除。

### 兼容性与验证

本版本为 Apple Silicon 原生应用，面向 macOS 14 及以上，采用本机临时签名，未经 Apple 公证。其 Spotlight 联动依赖辅助功能界面，macOS 后续更新可能影响兼容性。

已验证编译、离线查询、音标/释义/例句数据、无效输入、未知词、上方定位、屏幕边界、多显示器坐标和原生卡片预览。用户已确认首次版本能随 Spotlight 显示卡片。1.0.1 修复两侧对齐与毛玻璃圆角外漏；已验证不同窗口宽度下的左右边缘对齐，以及圆角遮罩四角透明。

### 从源码构建

```bash
bash Scripts/build.sh --out dist --self-test
```

构建脚本不再硬编码 SDK 版本，默认取 `xcrun --show-sdk-path`；架构与最低系统版本可用
`ARCHS`、`MACOS_TARGET` 覆盖。词库已随仓库提供，**不需要**额外下载数据即可构建。

### 卸载

在状态栏菜单退出词在上；如果启用了登录启动，先在设置中关闭；将应用移至废纸篓，并可在系统辅助功能列表移除它。

### 1.0.1 更新

- 卡片与 Spotlight 等宽，两侧对齐。
- 使用 `NSVisualEffectView.maskImage` 裁切毛玻璃材质，清除圆角外露出的矩形背景；内容层与窗口阴影同步采用圆角。
- 本地临时签名的程序更新后可能需要重新授权辅助功能。若开关打开仍无卡片，可针对本应用执行 `tccutil reset Accessibility local.wordabove.SpotlightDictionary` 后，从应用程序目录重新打开词在上并授权。不要替其他应用重置权限。
