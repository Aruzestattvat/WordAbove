## WordAbove · 词在上 1.0.1

macOS 菜单栏词典：打开 Spotlight（⌘ 空格）输入英文单词，搜索框**上方**浮出一张卡片显示中文释义、音标与例句；关闭 Spotlight 后自动收起。跟随系统深浅色模式，卡片不抢键盘焦点。

### 下载与安装

1. 下载下面的 `WordAbove-1.0.1-macos-arm64.zip`，解压
2. 把 `词在上.app` 拖进 `/Applications`
3. 打开应用 → 点「打开辅助功能设置」→ 在**系统设置 → 隐私与安全性 → 辅助功能**里打开「词在上」
4. 回到 Spotlight 输入 `hello` / `focus` / `serendipity`，无需回车

> 首次打开若被拦下：**系统设置 → 隐私与安全性 → 仍要打开**。本包为本机临时签名，未经 Apple 公证。

### 本版内容

- **399,213** 条离线词条（ECDICT），其中 **18,480** 条含离线例句（Princeton WordNet 3.0 + 内置例句）
- 卡片与 Spotlight 等宽、左右对齐；用 `NSVisualEffectView.maskImage` 裁切毛玻璃，圆角外不再漏出矩形背景
- 可选联网补充：仅当已识别词条缺少音标或例句时请求 Free Dictionary API，默认开启、可关闭
- 完全离线可用；不记录键盘、不读取其他应用文本、不保存搜索历史

### 系统要求

- macOS **14.0** 及以上
- **Apple Silicon（arm64）**，本 Release 不提供 Intel 版本

### 从源码构建

```bash
git clone https://github.com/Aruzestattvat/WordAbove.git
cd WordAbove
bash Scripts/build.sh --self-test
```

词库已随仓库提供（`Resources/dictionary.sqlite`，40 MB），**不需要**额外下载数据。

### 已知问题

- 更新本地临时签名的版本后，可能需要重新授权辅助功能。若开关已开仍无卡片：
  `tccutil reset Accessibility local.wordabove.SpotlightDictionary`，然后从应用程序目录重新打开并授权。
  **不要**替其他应用重置权限。
- 卡片联动依赖辅助功能接口与窗口元数据，macOS 后续更新可能影响兼容性。

### 校验下载

```bash
shasum -a 256 -c WordAbove-1.0.1-macos-arm64.zip.sha256
```

### 许可

源码 MIT © 2026 Aruzestattvat。词库数据为第三方作品：ECDICT（MIT）、Princeton WordNet 3.0，
详见仓库内 [THIRD-PARTY-NOTICES.md](https://github.com/Aruzestattvat/WordAbove/blob/main/THIRD-PARTY-NOTICES.md)。
