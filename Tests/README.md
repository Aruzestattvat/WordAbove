# Tests

开发期用的验证程序**源码**。编译产物（`mask-check`、`network-check`）不入库——在 Codex 的工作区里它们是
二进制文件，属于「测试可执行文件」，已按约定排除。要运行请自己编译：

```bash
bash Scripts/run-checks.sh
```

## 文件

| 文件 | 说明 | 需要什么 |
|---|---|---|
| `Support.swift` | 被测代码的测试副本（见下） | — |
| `MaskCheck.swift` | 卡片材质遮罩：`capInsets == 28`、`resizingMode == .stretch`、四个角透明、中心不透明、子层裁切 | 无网络、无权限；需能起 `NSApplication` |
| `NetworkCheck.swift` | 联网补充：HTTPS 请求、JSON 解析、来源 URL、许可字段 | **联网**（`api.dictionaryapi.dev`）+ 可读词库 |
| `Fixtures/dictionaryapi-serendipity.json` | `serendipity` 的真实接口响应，留档用 | — |
| `Fixtures/dictionaryapi-test.json` | `test` 的真实接口响应，留档用 | — |

## 关于 Support.swift

`Sources/App.swift` 带 `@main`，而两个检查也各自带 `@main`，一起编译会冲突；把 `Sources/*.swift`
整体编成库再链接，又会因为符号是 `internal` 而无法从测试模块访问。所以这里**原样搬运**被测符号，
只做两处删减（不修改实现正文）：

- 去掉 `App.swift` 的 `@main` 入口与 `AppDelegate`（检查不涉及）
- 去掉 `SpotlightObserver`（依赖 `ApplicationServices` 与真实 Spotlight，检查不涉及）

`Sources/` 中的实现改动后，请同步更新本文件。

## 词库路径

`NetworkCheck` 按以下顺序确定 `dictionary.sqlite`：

1. 环境变量 `WORDABOVE_DICTIONARY`
2. 第一个命令行参数
3. `/Applications/词在上.app/Contents/Resources/dictionary.sqlite`

（原版硬编码了第 3 项，换台机器或没装到 `/Applications` 就跑不起来，所以改成可覆盖。）

## 哪些进 CI

`.github/workflows/build.yml` 只**编译**这两个检查，不运行：`network-check` 需要外网，
`mask-check` 需要一个可用的图形会话。两个都需要 macOS runner。
