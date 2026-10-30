#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 ECDICT CSV + WordNet zip 重新生成 Resources/dictionary.sqlite。

仓库内已包含生成好的词库，**通常不需要跑这个脚本**。
只有在你想自备数据、或想清空 40 MB 词库改成自己构建时才需要它。

数据准备：
  ecdict.csv    https://github.com/skywind3000/ECDICT   （约 66 MB，MIT）
  wordnet.zip   https://wordnet.princeton.edu/          （WordNet 3.0，含 wordnet/LICENSE）

用法（数据放在仓库上一级目录时可直接跑）：
  python3 Scripts/prepare_dictionary.py
  python3 Scripts/prepare_dictionary.py --ecdict /path/ecdict.csv --wordnet /path/wordnet.zip

参数：
  --ecdict   ECDICT CSV 路径（默认：向上逐级查找 ecdict.csv）
  --wordnet  WordNet zip 路径（默认：向上逐级查找 wordnet.zip）
  --resources  Resources/ 目录（默认：仓库根/Resources）
  --out      生成的 sqlite 路径（默认：<resources>/dictionary.sqlite）

输出字段：word, phonetic, translation, definition, example, example_source
  · definition 来自 ECDICT 的英文释义
  · example 优先取内置例句（example_source='内置例句'），否则取 WordNet 3.0（'WordNet 3.0'）
  · 仅收录纯英文词（含连字符与撇号），长度 <= 48，且有中文释义
"""
from __future__ import annotations

import argparse
import csv
import json
import pathlib
import re
import sqlite3
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_RESOURCES = HERE.parent / "Resources"


def find_upwards(name: str, start: pathlib.Path) -> pathlib.Path:
    """从 start 向上逐级查找文件，便于数据放在仓库外任一层。"""
    for base in [start, *start.parents]:
        candidate = base / name
        if candidate.exists():
            return candidate
    return start / name


# 内置例句：为高频词/自检词条提供稳定例句，随本项目 MIT 许可发布
CURATED = {
    'app': 'I opened the app to check the weather forecast.',
    'serendipity': 'Finding this quiet café by chance was a moment of serendipity.',
    'hello': 'She smiled and said hello to her new neighbor.',
    'focus': 'I need a quiet room so I can focus on my work.',
    'example': 'This sentence is a simple example of how to use the word.',
    'beautiful': 'We watched a beautiful sunset over the sea.',
    'computer': 'I use my computer to study and write every day.',
    'learn': 'You can learn a new word every day.',
    'learning': 'Learning a language takes time and practice.',
    'clarity': 'She explained the idea with remarkable clarity.',
    'curious': 'The curious child asked how the stars were formed.',
    'ephemeral': 'The beauty of a rainbow is ephemeral.',
    'resilience': 'She showed great resilience after the setback.',
    'world': 'People around the world speak many different languages.',
    'apple': 'She packed an apple in her lunch bag.',
    'dictionary': 'I looked up the word in a dictionary.',
    'word': 'Write the new word in your notebook.',
    'plugin': 'This plugin adds a dictionary to the search experience.',
}

# ECDICT leaves this common abbreviation without a transcription.
# IPA checked against Cambridge Dictionary: https://dictionary.cambridge.org/pronunciation/english/app
PHONETIC_OVERRIDES = {'app': 'æp'}


def build_examples(wordnet_zip: pathlib.Path) -> dict[str, tuple[str, str]]:
    """从 WordNet 3.0 的 data.* 索引里提取例句，键为小写单词。"""
    z = zipfile.ZipFile(wordnet_zip)
    examples: dict[str, tuple[str, str]] = {}
    for name in ['noun', 'verb', 'adj', 'adv']:
        for line in z.read('wordnet/data.' + name).decode().splitlines():
            if not line or not line[0].isdigit() or ' | ' not in line:
                continue
            head, gloss = line.split(' | ', 1)
            fields = head.split()
            count = int(fields[3], 16)
            sentences = re.findall(r'"([^"\n]+)"', gloss)
            for word in fields[4:4 + count * 2:2]:
                word = re.sub(r'\(.*?\)$', '', word).replace('_', ' ').lower()
                if word in examples:
                    continue
                good = [s for s in sentences if re.search(r'\b' + re.escape(word) + r'\b', s, re.I)]
                if good:
                    examples[word] = (min(good, key=lambda s: abs(len(s) - 75)), 'WordNet 3.0')
    return examples


def main() -> None:
    parser = argparse.ArgumentParser(description='从 ECDICT + WordNet 生成 dictionary.sqlite')
    parser.add_argument('--ecdict', type=pathlib.Path, default=None)
    parser.add_argument('--wordnet', type=pathlib.Path, default=None)
    parser.add_argument('--resources', type=pathlib.Path, default=DEFAULT_RESOURCES)
    parser.add_argument('--out', type=pathlib.Path, default=None)
    args = parser.parse_args()

    ecdict = args.ecdict or find_upwards('ecdict.csv', HERE)
    wordnet = args.wordnet or find_upwards('wordnet.zip', HERE)
    out = args.out or (args.resources / 'dictionary.sqlite')

    for label, path in (('ECDICT CSV', ecdict), ('WordNet zip', wordnet)):
        if not path.exists():
            raise SystemExit(f'找不到{label}：{path}\n用 --ecdict/--wordnet 指定路径。')

    examples = build_examples(wordnet)
    for word, sentence in CURATED.items():
        examples[word] = (sentence, '内置例句')

    # 随词库一起刷新 WordNet 许可全文，保证分发时许可不缺失
    with zipfile.ZipFile(wordnet) as z:
        try:
            (args.resources / 'WordNet-LICENSE.txt').write_bytes(z.read('wordnet/LICENSE'))
        except KeyError:
            print('提示：wordnet.zip 内未找到 wordnet/LICENSE，未刷新 WordNet 许可文件')

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.execute('CREATE TABLE words(word TEXT PRIMARY KEY COLLATE NOCASE, phonetic TEXT, '
               'translation TEXT, definition TEXT, example TEXT, example_source TEXT) WITHOUT ROWID')
    rows = []
    with ecdict.open(newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            w = (r.get('word') or '').lower()
            if not re.fullmatch(r"[a-z]+(?:[-'][a-z]+)*", w) or len(w) > 48:
                continue
            if not r.get('translation'):
                continue
            ex, source = examples.get(w, ('', ''))
            rows.append((w, PHONETIC_OVERRIDES.get(w, r.get('phonetic', '')), r['translation'].replace('\\n', '\n'),
                         (r.get('definition') or '').replace('\\n', '\n'), ex, source))
    db.executemany('INSERT OR IGNORE INTO words VALUES(?,?,?,?,?,?)', rows)
    db.commit()
    db.execute('VACUUM')

    stats = {
        'words': db.execute('SELECT count(*) FROM words').fetchone()[0],
        'examples': db.execute("SELECT count(*) FROM words WHERE example != ''").fetchone()[0],
        'size_MB': round(out.stat().st_size / 1e6, 1),
    }
    print(json.dumps(stats, ensure_ascii=False))
    for w in ['hello', 'serendipity', 'focus', 'apple', 'resilience']:
        print(db.execute('SELECT word,phonetic,translation,example FROM words WHERE word=?', (w,)).fetchone())
    db.close()
    print(f'已生成：{out}')


if __name__ == '__main__':
    main()
