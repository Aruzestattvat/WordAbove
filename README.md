# WordAbove · 词在上

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Aruzestattvat/WordAbove?label=release&color=blue)](../../releases/latest)
[![Platform: macOS 26+](https://img.shields.io/badge/Platform-macOS%2026%2B%20for%20translation-lightgrey.svg)](#requirements)
[![Arch: Apple Silicon](https://img.shields.io/badge/Arch-Apple%20Silicon-black.svg)](#compatibility-notes)
[![Dictionary: 399,213 entries](https://img.shields.io/badge/Dictionary-399%2C213%20entries-8A2BE2.svg)](#offline-dictionary)
[![Translation: EN ⇄ ZH ⇄ JA](https://img.shields.io/badge/Translation-EN%20%E2%87%84%20ZH%20%E2%87%84%20JA-4B8BBE.svg)](#automatic-translation)

A macOS menu-bar **translation & dictionary** app that renders a card **above the Spotlight search field**.
Type something in Spotlight (⌘ Space) and a card appears above the search box: Chinese/Japanese translation
via Apple's on-device `Translation.framework`, or — for English words that hit the offline dictionary —
the Chinese definition, IPA and an example sentence. It dismisses itself when Spotlight closes, follows the
system light/dark appearance, and never steals keyboard focus.

> 词在上是一个 macOS 菜单栏**翻译 + 词典**应用：打开 Spotlight 输入文字，搜索框上方浮出卡片。
> 中英日短词短句用 Apple 本机 `Translation.framework` 自动互译；英文单词命中离线词库时显示中文释义、
> 音标与例句。关闭 Spotlight 自动收起。中文完整说明见 [中文说明](#中文说明)。

- **Version**: 1.1.18 (build 21)
- **Platform**: macOS **26.0+** for automatic translation · macOS 14.0+ for offline English dictionary
- **Architecture**: Apple Silicon (arm64)
- **Languages**: 中文 ⇄ English ⇄ 日本語 (on-device, no third-party translation service)
- **Dictionary**: 399,213 offline entries, 18,480 with example sentences (ECDICT + WordNet 3.0)
- **License**: MIT for the source · third-party data under its own terms — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)

## Install

Choose a release for your system:

| System | Recommended release | Focus |
| --- | --- | --- |
| macOS 27 | [v1.1.18](../../releases/tag/v1.1.18) | Adaptive top card, one-click copy and in-app updates |
| macOS 26 | [v1.1.2](../../releases/tag/v1.1.2) | Stable on-device translation language-pack setup |

Both releases remain available. The newer app also supports macOS 26; the labels identify the system each release was optimized for.

1. Download `WordAbove-*-macos-arm64.zip` from your chosen release.
2. Unzip it (double-click in Finder) and drag `词在上.app` into `/Applications`.
3. Open it, then in the app's setup window click **打开辅助功能设置** and enable **词在上** under
   *System Settings → Privacy & Security → Accessibility*.
4. Menu bar icon → **更多** → **下载中英日语言包…** → **一键准备中英日**. The app checks and downloads any missing
   language packs, then verifies all six translation directions. **The first download is roughly 0.9 GB and can
   take 5–30 minutes**; keep the panel open and allow any macOS download prompt.
5. Once it reports **中英日已就绪 · 6/6**, press ⌘ Space and type `你好` or `Hello`.

The build is ad-hoc signed (not notarized), so the first launch may require
*System Settings → Privacy & Security → Open Anyway*.

From v1.1.18 onward, the app checks GitHub for new stable releases when it starts and every six hours while running.
It prompts once per new version; choose **一键安装** to download, verify the release SHA-256 and code signature,
replace the installed app and restart. **Older installed versions have no updater**, so they need one manual upgrade
to v1.1.18 before future in-app update prompts can work. The update check does not send Spotlight searches or
translations. Because releases are currently ad-hoc signed, macOS may ask you to renew Accessibility permission
after an update. The menu bar also has **检查更新…** for a manual check.

If no card appears for `hello`, open the menu bar's **设置…** item. It now shows whether the bundled dictionary
is readable and whether Spotlight's search box can be read. **更多 → 复制诊断信息** copies these checks without copying your
search text. The app can also print them from Terminal with
`/Applications/词在上.app/Contents/MacOS/WordAbove --diagnose`.
For macOS 27 reports, type `hello` in Spotlight before copying diagnostics. The app keeps the most recent search
status and search-window owner after Spotlight closes; it does not keep the typed word.

> ⚠️ Unzip with Finder. If you unzip with the command-line `unzip`, macOS AppleDouble `._*` files can break
> the code signature — re-extract with `ditto -x -k <zip> <dir>` or just use Finder.

## Automatic translation

Pick a language pair from the menu bar:

- 中文 ⇄ 英文 (default)
- 中文 ⇄ 日文
- English ⇄ 日本語

Direction is auto-detected by default (type either language, get the other), or can be pinned forward/reverse
from **翻译方向**. The pair and direction are stored locally and restored on launch. Short words and short
sentences up to **400 characters** are supported.

Ambiguity rule: a word written only in Han characters can't be reliably told apart. Under 中文/日文 pairs it is
treated as **Chinese** by default — to translate Japanese `学校` into Chinese, pin the direction to 日文 → 中文.
Text containing kana is treated as Japanese. English-only input does not trigger auto-translation under a
Chinese/Japanese pair; switch the pair or pin the direction.

## If the language pack download is slow or fails

The first preparation is not a small download: macOS fetches roughly **0.9 GB** of on-device models
(installed size ~1.7 GB) and it owns the transfer — the app cannot read a byte counter or a percentage.
Expect **5–30 minutes** depending on the network.

- **Keep the window open.** Since 1.1.2, closing it or quitting asks for confirmation instead of silently
  cancelling the download.
- Watch real system-level progress in **System Settings → General → Language & Region → Translation
  Languages**; the panel has a button that opens it directly.
- If it fails: check network/proxy (try without a VPN), keep **≥ 3 GB** free disk, then press
  **重试未完成部分**. Verified directions are remembered, so a retry does not redo everything.
- **复制诊断信息** copies app version, macOS version, progress, free disk and the raw error — attach it to a
  bug report.
- Each step times out after **45 minutes** instead of waiting forever.

## Offline dictionary

English → Chinese words that hit the offline dictionary keep showing the Chinese definition, IPA and example
sentence. Everything else goes through Apple's on-device translation. Translation cards show the original text,
language direction and the result; the app never invents IPA or example sentences it has not verified.
Long text may be truncated in the card.
Click the book icon on a card to copy the first dictionary meaning (without its part-of-speech label), or the
current on-device translation. A monochrome ring turns once and draws a checkmark after copying; Reduce Motion
shows the checkmark without the spin.

## Requirements

| Feature | Minimum macOS |
|---|---|
| Automatic translation (中/英/日) | **macOS 26.0** |
| Offline English dictionary, IPA, examples | macOS 14.0 |
| Build from source | macOS 26+ SDK (must include `Translation.framework`) + matching Swift compiler |

Language packs are managed by macOS (*System Settings → General → Language & Region → Translation Languages*).
Downloading them needs network access; translation itself then runs on-device. The app **ships no Apple
translation models** and does not depend on the developer's installed models — the app asks macOS to download
them, and macOS owns the confirmation prompts.

## Privacy

Accessibility access is used only to read Spotlight's search field and window position. The app does not log
keystrokes, does not read other apps' text, does not record the screen, and does not store search history.
Emails, URLs, paths, pure numbers, control characters and inputs longer than 400 characters do not trigger
translation.

Translation uses Apple's `Translation.framework` — **no third-party translation service**. Results are cached in
memory (last 100) and cleared on quit.

The English dictionary's optional *online example supplement* is separate and opt-in (on by default): it sends
only the current English word to `api.dictionaryapi.dev`, and can be turned off in settings. It does not affect
on-device translation.

## Layout

The card matches Spotlight's width, sits 12 pt above it, and is at most 206 pt tall. It shrinks when space above
is limited and hides when less than 100 pt is available (drag Spotlight slightly down). Screen edges constrain
the card size.

## Build from source

Requirements: macOS 26+ SDK with `Translation.framework`, and a matching Swift toolchain
(`xcode-select --install`). No Xcode project, no package manager — the app is compiled directly with `swiftc`.

```bash
git clone https://github.com/Aruzestattvat/WordAbove.git
cd WordAbove
bash Scripts/build.sh --out dist --self-test
```

`Scripts/build.sh` **auto-detects a usable SDK** instead of trusting `xcrun --show-sdk-path` (which may return an
SDK built by a different Swift version). Override via environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `SDK_PATH` | auto-detected | SDK to compile against (must contain `Translation.framework`) |
| `ARCHS` | `arm64` | Space-separated; `"arm64 x86_64"` attempts a universal binary |
| `MACOS_TARGET` | `14.0` | `LSMinimumSystemVersion` |
| `SWIFT_VERSION` | `5` | Swift language mode |
| `CODESIGN` | `1` | `0` skips the ad-hoc signature step |
| `APP_NAME` | `词在上` | Output `.app` name |

The offline dictionary (`Resources/dictionary.sqlite`, 40 MB) and all third-party licences are included in the
repository — a normal build needs no extra downloads.

`WordAbove --self-test` verifies: all six translation directions, language-pair isolation, Han/kana direction
override, input filtering and the 400-character limit; the six-direction preparation queue (failure, retry,
cancellation, stale callbacks, recheck); and the original dictionary + card-placement regression checks.

## Package a release

```bash
bash Scripts/package-release.sh --build
```

Uses `ditto -c -k --sequesterRsrc` (never `zip -r`, which injects `._*` AppleDouble files that break the
signature on extraction) and writes a portable `.sha256` next to the zip.

## Repository layout

```
WordAbove/
├── Sources/                 Swift 源码
│   ├── App.swift                   应用主体：状态栏、卡片、查找/翻译调度
│   ├── Dictionary.swift            离线词库读取 + 可选联网例句补充
│   ├── SpotlightObserver.swift     Spotlight 窗口/输入框读取、卡片定位
│   ├── RoundedMaterialView.swift   毛玻璃圆角遮罩
│   ├── TranslationSupport.swift    语言/语言对/方向模型 + Apple 翻译封装
│   ├── TranslationCard.swift       翻译卡片视图
│   ├── LanguageSetupView.swift     「一键准备中英日」窗口
│   ├── LanguagePreparation.swift   六方向准备队列（重试/取消/过期回调隔离）
│   └── TranslationChecks.swift     六方向路由的回归检查
├── Resources/               运行时资源：词库、图标、第三方许可全文、来源页
│   └── dictionary.sqlite    40 MB 离线词库（399,213 词条）
├── Scripts/
│   ├── build.sh             构建（SDK 自动探测、可配架构/部署目标）
│   ├── lib/sdk.sh           共享 SDK 选择逻辑
│   ├── run-checks.sh        编译并运行 Tests/ 下的验证程序
│   ├── package-release.sh   Release 打包（ditto + sha256）
│   ├── make_icon.swift      重新生成 WordAbove.iconset/
│   └── prepare_dictionary.py 从 ECDICT+WordNet 重建 dictionary.sqlite
├── Tests/                   验证程序源码（见 Tests/README.md）
└── .github/workflows/build.yml
```

## Tests

`Tests/` holds the verification programs used while developing; compiled binaries are **not** tracked. The
richest check is the app's own built-in self-test (`--self-test`), which covers translation routing, the
preparation queue, persistence/error classification, and the dictionary/placement regressions. See [Tests/README.md](Tests/README.md).

```bash
bash Scripts/run-checks.sh            # mask-check (local) + network-check (needs network)
bash Scripts/build.sh --self-test     # app-level self-test
```

## Compatibility notes

- The shipped binary is **Apple Silicon only** (`arm64`). Intel Macs can build for `x86_64` by setting
  `ARCHS=x86_64`; this repository does not ship an Intel build.
- Automatic translation needs **macOS 26+**. On macOS 14/15 the offline English dictionary still works, but the
  translation features report that a newer system is required.
- Spotlight coupling relies on the Accessibility API and window metadata; a future macOS update could change it.
- macOS 27 moved the Command-Space overlay to `com.apple.campo`. The app recognizes that host while
  excluding Campo's frontmost Siri chat window. Card placement is recalculated from the current screen and
  search-field position whenever Spotlight moves.
- After rebuilding or updating an ad-hoc signed app, re-grant Accessibility if the card stops appearing:
  `tccutil reset Accessibility local.wordabove.SpotlightDictionary` — reset only this app, never others.

## 1.1.18 changes — macOS 27 optimization

- Click the card's book icon to copy the first dictionary meaning, or the full on-device translation. The icon
  confirms the copy with layered monochrome rings rotating on different axes before drawing a checkmark, while keeping Spotlight focused.
- Keep the card aligned to the live Spotlight window across 13-, 14-, and 16-inch layouts, scaled resolutions and
  external displays. A permanent window-size change is adopted after stable readings; reopening starts from fresh geometry.
- Fit the card into as little as 64 pt above Spotlight, showing the word and first meaning when space is tight.
- Show full dictionary meanings on click within the card, without shifting the word title.
- Reject stale Spotlight frames after dismissal to prevent the card flashing alone; preserve native Esc behavior.
- Keep the menu concise and add a GitHub update check with verified, one-click installation for later releases.

## 1.1.10 changes

- Fill the available region above Spotlight on macOS 27, matching the outer search panel's left and right edges.
- Use AppKit's system Liquid Glass on macOS 26+, so the card follows the macOS 27 glass appearance slider; keep the existing material on older systems.
- Shorten the grace period after Spotlight closes while still allowing a brief window transition during typing.

## 1.1.9 changes

- Keep the macOS 27 card aligned to Spotlight's outer search panel even while Campo expands its suggestion window.
- Use the input field for the vertical anchor from the start and preserve card geometry during one search session.
- Update offline dictionary text in the visible card as typing changes, without hiding and reopening the panel.

## 1.1.8 changes

- Report the built-in display's physical size (13, 14 or 16 inches) in diagnostics. Card placement uses the live
  Spotlight field and available screen space, including external and scaled displays.
- Include the detected display class, usable screen size and chosen card size in copied diagnostics.

## 1.1.7 changes

- Center compact dictionary content vertically and use the available 80–110 point height for clearer spacing.
- Add a verified pronunciation and original example for `app`, which ECDICT leaves empty. Reject malformed
  phonetic strings from online enrichment instead of showing replacement characters.

## 1.1.6 changes

- Keep the card above the search input. Fit its height to the space between the field and menu bar, using a
  compact three-line dictionary layout when that space is short. Never move it to the side or below Spotlight.

## 1.1.5 changes

- Position the card from the actual Accessibility frame of the search input on macOS 27 when the host window
  extends to the top edge. The traditional above-window placement remains first choice.
- A temporary side/below fallback helped diagnose the macOS 27 layout; 1.1.6 replaces it with top-only placement.

## 1.1.4 changes

- Recognize the macOS 27 Command-Space search host (`com.apple.campo`) as well as classic Spotlight.
- Keep Siri's regular chat window outside the search observer and preserve the most recent search diagnostics.

## 1.1.3 changes

- Show dictionary and Spotlight connection status in settings; add a privacy-safe diagnostic copy command.
- Recognize Spotlight's focused text field even when macOS omits its older Accessibility identifier or subrole.
- On the first authorized launch, offer the language preparation window when the selected language pair is not installed.
- Report a missing bundled dictionary explicitly instead of silently falling back to system translation.

## 1.1.2 changes

- Language-pack preparation reworked: elapsed timer and current direction, a 45-minute per-step timeout, and
  failures classified as network / disk / system-service / timeout with concrete next steps.
- Closing the window or quitting no longer cancels silently — it asks first; verified directions are persisted
  and shown as “已就绪 N/6” after relaunch.
- New **打开语言设置** button jumps to macOS's Translation Languages pane to watch system-level progress.
- New **复制诊断信息** button for bug reports.
- Fixed progress text being updated off the main thread.

## License

MIT for the source, © 2026 Aruzestattvat — see [LICENSE](LICENSE).
Bundled dictionary data is third-party: ECDICT (MIT), Princeton WordNet 3.0, and optional
Free Dictionary API / Wiktionary responses (CC BY-SA) — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
Translation itself is performed by Apple's `Translation.framework`, which ships no data with this repository.

---

## 中文说明

macOS 菜单栏翻译辅助应用。打开 Spotlight（⌘ 空格）并输入文字，在搜索框上方显示独立卡片。卡片与 Spotlight 两侧对齐，采用原生半透明材质与圆角遮罩，不获取键盘焦点。

### 自动互译

点击菜单栏的词典图标，在“自动互译”中选择：

- 中文 ↔ 英文（默认）
- 中文 ↔ 日文
- 英文 ↔ 日文

默认自动判断方向，输入一种语言即译成另一种。语言对与方向会保存在本机，重启后恢复。支持短词与短句，最多 400 字符。

中日文中仅含汉字的词无法可靠区分语言：中文/日文语言对下默认按中文处理；例如想把日文“学校”译成中文，请从“翻译方向”选择“日文 → 中文”。包含假名的文字按日文处理。仅含英文的内容在中文/日文语言对下不触发自动翻译，可切换语言对或手动指定方向。

英文 → 中文的单词命中离线词库时，继续显示中文释义、音标和例句。其余内容交给 Apple 本机翻译。自动翻译卡片显示原文、语言方向和译文；不生成未经词典核实的音标或例句。长文本可能在卡片中截短。
点击卡片左侧的词典图标，可复制首条词典释义（不含词性标签）或当前系统译文；复制成功后，图标会保持单色样式转一圈并描出勾号。系统开启“减少动态效果”时直接显示勾号。

### 首次设置

1. 把 `词在上.app` 拖进 `/Applications`。
2. 打开应用，在设置中点击“打开辅助功能设置”，为当前安装版开启权限。
3. 菜单栏 → “下载中英日语言包…” → “一键准备中英日”。应用会自动检查并下载缺少的语言包，再逐个验证六个翻译方向。**首次下载约 0.9 GB（解压后约 1.7 GB），慢网可能需要 10–30 分钟**；期间请保持该窗口打开、不要退出应用。如 macOS 弹出下载确认，请点“允许”。
4. 面板会显示已用时间、当前方向和失败归因；“已验证 N/6”是**方向数**，不是下载百分比。系统不提供下载进度，可在「系统设置 → 通用 → 语言和地区 → 翻译语言」查看系统级下载状态（面板内有“打开语言设置”按钮）。失败时点“重试未完成部分”，已验证的方向会被记住，不会重来。
5. 在 Spotlight 输入“你好”或“今天的天气很好。”测试中译英，切换语言对后再尝试日文。

翻译语言包由 macOS 管理，可在“系统设置 → 通用 → 语言与地区 → 翻译语言”中查看。下载语言包需要联网；下载后使用本机翻译。**自动翻译需要 macOS 26+**，本版本为 Apple Silicon 编译。macOS 14/15 的英文离线查词保留，但新增后台翻译功能需要升级系统。

如果输入 `hello` 后完全没有上方卡片，请打开菜单栏的「设置…」查看「离线词库」和「聚焦状态」。若辅助功能未授权，点击「打开辅助功能设置」授权当前安装版；若显示无法读取搜索框，点击「复制诊断信息」提交反馈。诊断信息不包含搜索词。也可在终端运行 `/Applications/词在上.app/Contents/MacOS/WordAbove --diagnose`。
macOS 27 上请先在 Spotlight 输入 `hello`，关闭后再复制诊断信息；应用保留最近一次搜索状态与系统搜索窗口所属进程，不保留所输入的文字。
1.1.4 开始识别 macOS 27 的 `com.apple.campo` 搜索浮窗；普通 Siri 聊天窗口不会被当作 Spotlight 读取。
1.1.6 使用搜索输入框的实际位置摆放卡片，并按当前屏幕上方的可用高度缩小排版；卡片只出现在搜索框上方。
1.1.7 优化顶部紧凑卡片的垂直留白，并补齐 `app` 的音标与例句；无效音标不再显示乱码。
1.1.8 新增 13、14、16 寸内屏识别与显示器诊断；后续版本改为始终按当前 Spotlight 窗口及屏幕可用空间排版，外接屏和显示缩放也使用实际坐标。
1.1.9 修复 macOS 27 搜索结果展开时卡片先大后小、重新出现的闪烁；卡片与 Spotlight 外框左右对齐，连续输入时只更新内容。
1.1.10 让顶部卡片填充 Spotlight 上方可用空间，并使用系统 Liquid Glass，跟随 macOS 27 的玻璃效果设置；缩短关闭搜索后的收起等待。
1.1.18 加入图标一键复制首条释义／译文及单色多轴圆环确认动效、卡片内展开完整释义、跨屏幕尺寸的稳定对齐与 64 pt 紧凑排版，并修复关闭 Spotlight 后词卡短暂重现。菜单已精简；本版起内置检查更新和一键安装。旧版没有更新器，需先手动升级一次。

### 菜单

- 自动互译：选择两个语言。
- 翻译方向：自动识别，或固定正向/反向。
- 暂停/恢复自动翻译、设置、检查更新：保留在主菜单。
- 更多 → 下载中英日语言包：一键准备三种语言，验证全部六个方向；不改变当前选定的语言对。
- 更多 → 重试当前翻译、卡片预览、来源与许可、复制诊断信息。
- 退出词在上：主菜单底部。

设置中可开启登录启动。程序不会修改 Spotlight 的快捷键或其他应用的搜索开关。

### 权限与隐私

辅助功能仅用于读取 Spotlight 搜索栏和窗口位置。程序不记录键盘、不读取其他应用文本、不录屏，也不保存搜索历史。邮箱、网址、路径、纯数字、控制字符和超过 400 字符的输入不触发翻译。

自动互译使用 Apple `Translation.framework`，不调用第三方翻译服务；译文仅在进程内缓存最近 100 条，退出清除。
更新检查只向 GitHub 查询正式版本，不上传搜索词或译文。安装包下载后会校验 GitHub Release 的 SHA-256 和应用签名。

英文词典的“缺少例句时联网补充”是单独的可选功能，默认开启；仅把已识别且需要补充的英文单词发给 `api.dictionaryapi.dev`。可在设置中关闭。这一开关不影响 Apple 本机翻译。

### 布局与缺失内容

卡片跟随 Spotlight 当前外框的宽度和位置；macOS 27 的卡片最高 116 pt，上方空间紧张时最小可缩至 64 pt 并优先显示单词和释义。若连 64 pt 都放不下，卡片会隐藏。屏幕边缘会限制卡片尺寸。

离线词库包含 399,213 个英文词条，其中 18,480 个带例句或用法片段。部分词条没有音标或例句；缺失内容会明确提示，不编造。英语例句可能对应其他词义。系统翻译结果也可能有歧义。

### 构建与验证

```bash
bash Scripts/build.sh --out dist --self-test
```

需要支持 `Translation.framework` 的 macOS 26+ SDK 与匹配的 Swift 编译器，架构 arm64。构建脚本**自动探测可用 SDK**，
也可用 `SDK_PATH=/路径/MacOSX.sdk` 指定；架构与最低系统版本可用 `ARCHS`、`MACOS_TARGET` 覆盖。
源码、离线数据库、图标与许可文件均包含在仓库中，正常构建无需重新下载词库原始数据。

`WordAbove --self-test` 验证：一键准备队列的六方向覆盖、失败重试、取消、过期回调隔离和重复检查；以及六种翻译方向、语言对隔离、中日同形字的方向覆盖、输入过滤、字符上限，以及原有词库与卡片定位回归检查。

本地使用临时签名，未经 Apple 公证。重新编译或更新后 macOS 可能要求重新授权辅助功能。若开关已开但无卡片，可仅针对本应用执行 `tccutil reset Accessibility local.wordabove.SpotlightDictionary`，然后从“应用程序”重新打开并授权。

### 开源分发与语言包

源代码包含下载入口与自动准备逻辑，**不包含 Apple 翻译模型**，也不依赖开发者已安装的模型。首次使用者通过应用内按钮向 macOS 请求下载；Apple 的下载授权弹窗由用户确认，应用不能代替用户确认。模型由系统管理，无需维护下载地址或把模型上传 GitHub。

### 语言包下载很慢或失败？

- 首次是 **约 0.9 GB** 的系统级下载（解压后约 1.7 GB），应用拿不到字节进度，只有方向数。
- **不要关窗口或退出应用**：1.1.2 起关窗/退出会先弹确认，不再静默中断下载。
- 看真实进度：系统设置 → 通用 → 语言和地区 → 翻译语言（面板内有按钮直达）。
- 失败排查：网络或代理（可先关 VPN）、磁盘至少留 3 GB，再点“重试未完成部分”。
- 反馈问题时点“复制诊断信息”，把 App 版本、macOS 版本、进度、磁盘和原始错误一起发出。
- 每个方向最多等 45 分钟，不会无限挂起。

### 1.1.2 更新

- 语言包准备重做：显示已用时间与当前方向；单步 45 分钟超时；失败按“网络 / 磁盘 / 系统服务 / 超时”归因并给出可执行建议。
- 关闭窗口或退出应用不再静默取消：会先确认；已验证的方向会持久化，重开应用仍显示“已就绪 N/6”。
- 新增“打开语言设置”，直达系统「翻译语言」面板查看系统级下载进度。
- 新增“复制诊断信息”，便于反馈问题。
- 修复准备进度文字可能在非主线程更新的问题。

### 数据来源

- ECDICT：中文释义及词库音标，MIT 许可。
- Princeton WordNet 3.0：离线例句/用法片段，附原始许可；另含少量自编例句。
- Free Dictionary API / Wiktionary：可选英语例句补充，按响应的 CC BY-SA 许可。
- Apple Translation.framework：本机中英日翻译（不随仓库分发任何模型）。

详细来源及许可在应用菜单“词库来源与许可”中。卸载时先退出应用；如启用了登录启动，先关闭，再将应用移至废纸篓。
