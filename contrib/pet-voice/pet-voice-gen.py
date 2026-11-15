#!/usr/bin/env python3
"""用 MiniMax（mmx）把宠物的台词生成为音频文件。

产物落在 <宠物目录>/voice/ 下，命名规则是 pet-voice.py 认得的：
    greet-1.mp3        greet-2.mp3        ...
    phase-thinking.mp3 phase-done.mp3     ...
    click-1.mp3        pat-1.mp3          ...
重复执行是幂等的：已有的文件会跳过（想重生成就加 --force）。

用法:
    python3 ~/.dsh/pet-voice-gen.py --pet mao --voice female-shaonv
    python3 ~/.dsh/pet-voice-gen.py --pet mao --voice "Chinese (Mandarin)_Crisp_Girl" --force

可用音色: mmx speech voices
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import pathlib
import re
import subprocess
import sys
import time

PETS_DIR = pathlib.Path.home() / ".dsh" / "pets"
# 这些键的台词是数组（随机挑一句），逐个生成；phase 是单句，按键生成。
MULTI_KEYS = ("greet", "click", "pat", "tail", "spin", "reset", "loadFailed")


def load_manifest(pet: str) -> dict:
    for name in ("pet.json", "pet.json.hidden"):
        path = PETS_DIR / pet / name
        if path.exists():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except ValueError:
                continue
    raise SystemExit(f"找不到 {pet}/pet.json")


def slug(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "", text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pet", default="mao")
    parser.add_argument("--voice", default="female-shaonv")
    parser.add_argument("--force", action="store_true")
    # MiniMax 有 RPM 限制，连续打会返回 "rate limit exceeded(RPM)"。
    parser.add_argument("--delay", type=float, default=1.5, help="每条之间的间隔秒数")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # 语音一律由 MiniMax 生成。macOS 自带的 say 音色不行，明确不做兜底。
    if shutil.which("mmx") is None:
        raise SystemExit("找不到 mmx。语音必须用 MiniMax 生成：npm i -g mmx-cli && mmx auth login")

    manifest = load_manifest(args.pet)
    lines = (manifest.get("live2d") or {}).get("lines") or {}
    if not lines:
        raise SystemExit(f"{args.pet} 没有 lines，先生成台词")

    out_dir = PETS_DIR / args.pet / "voice"
    out_dir.mkdir(parents=True, exist_ok=True)

    jobs: list[tuple[str, str]] = []
    for key in MULTI_KEYS:
        values = lines.get(key)
        if not isinstance(values, list):
            continue
        for index, text in enumerate(values, 1):
            if isinstance(text, str) and text.strip():
                jobs.append((f"{slug(key)}-{index}", text.strip()))
    phase = lines.get("phase") or {}
    for key, text in phase.items():
        if isinstance(text, str) and text.strip():
            jobs.append((f"phase-{slug(key)}", text.strip()))

    made = skipped = failed = 0
    for name, text in jobs:
        target = out_dir / f"{name}.mp3"
        if target.exists() and not args.force:
            skipped += 1
            continue
        if args.dry_run:
            print(f"  would: {name} <- {text}")
            continue
        result = None
        for attempt in range(args.retries):
            result = subprocess.run(
                ["mmx", "speech", "synthesize",
                 "--text", text, "--voice", args.voice,
                 "--out", str(target), "--quiet"],
                capture_output=True, text=True,
            )
            if target.exists() and target.stat().st_size > 0:
                break
            # 典型的失败是 RPM 限流；退避重试比整批重跑便宜。
            time.sleep(2 ** (attempt + 1))
        time.sleep(args.delay)
        if target.exists() and target.stat().st_size > 0:
            made += 1
            print(f"  ✓ {name:18} {target.stat().st_size:>7} B  {text}")
        else:
            failed += 1
            print(f"  ✗ {name}: {(result.stderr or result.stdout).strip()[:120]}", file=sys.stderr)

    print(f"\n生成 {made} 条，跳过 {skipped} 条，失败 {failed} 条 -> {out_dir}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
