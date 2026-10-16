# 第三方数据与许可

WordAbove 源码本身按根目录 `LICENSE` 的 MIT 许可发布。**词库数据是第三方作品**，其许可与源码不同，随应用包一起分发，说明如下。

## ECDICT

- 用途：`Resources/dictionary.sqlite` 中的 `word` / `phonetic` / `translation` / `definition` 字段
- 上游：https://github.com/skywind3000/ECDICT
- 许可：MIT，Copyright (c) 2025 Linwei
- 许可全文：`Resources/ECDICT-LICENSE.txt`

## Princeton WordNet 3.0

- 用途：`Resources/dictionary.sqlite` 中 `example` 字段的离线例句（`example_source = 'WordNet 3.0'`，共 18,480 条）
- 上游：https://wordnet.princeton.edu/
- 许可：WordNet 3.0 License（Princeton University），全文见 `Resources/WordNet-LICENSE.txt`

## 内置例句

- 用途：少数高频词的离线例句（`example_source = '内置例句'`）
- 来源：本项目自编，随本项目 MIT 许可发布
- 生成位置：`Scripts/prepare_dictionary.py` 中的 `curated` 字典

## Free Dictionary API / Wiktionary

- 用途：**仅在运行时**为缺少音标或例句的词条联网补充（默认开启，可在应用设置关闭）
- 接口：https://api.dictionaryapi.dev/ （数据源自 Wiktionary）
- 许可：响应中的例句依 **CC BY-SA**（常见 3.0 / 4.0，以接口返回的 `license` 字段为准），应用界面会显示来源与许可名称
- 注意：本项目**不打包**该接口的任何内容，仅当用户开启联网补充时按需请求；例句只在内存缓存，退出即清除

## 应用内展示

应用菜单「词库来源与许可」打开 `Resources/Sources.html`，其中含上述来源的链接与许可摘要。

> 如需在不含词库的情况下构建（例如自备数据），可删除 `Resources/dictionary.sqlite` 后用
> `Scripts/prepare_dictionary.py` 从 ECDICT CSV 与 WordNet zip 重新生成，详见该脚本头部说明。
