#!/usr/bin/env python3
"""把 DSH 桌宠的相位台词用 MiniMax 生成的语音播出来。

为什么是"旁挂"而不是改插件：
  - 插件在 ~/.dsh/profiles/desktop/node_modules/ 下，升级会被覆盖；
  - 插件已经把相位通过 SSE 推出来了（/api/live2d-pet/events），
    消费这条流就能说话，不需要动它一行代码。

音频来源：~/.dsh/pets/<宠物>/voice/*.mp3（用 pet-voice-gen.py 生成）。
没有对应音频就**保持安静** —— 不用 macOS say，那个音色不能听。

用法:
    PET_NAME=mao python3 ~/.dsh/pet-voice.py

环境变量:
    PET_NAME    读哪个宠物（~/.dsh/pets/<名字>/），默认 mao
    PET_GAP     两句之间最短间隔秒数，默认 2.5
    PET_PHASES  要念的相位，逗号分隔；默认 done,failed
                （要更多就显式列出来，例如 PET_PHASES=waiting,asking,done,failed）
    PET_DEBUG   设为 1 把事件打到 stderr
"""

from __future__ import annotations

import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.request

PETS_DIR = os.path.expanduser("~/.dsh/pets")
PET = os.environ.get("PET_NAME", "mao")
MIN_GAP = float(os.environ.get("PET_GAP", "2.5"))
DEBUG = os.environ.get("PET_DEBUG") == "1"

# 默认只播**这一轮的结果**：完成、出错。其余一律静音。
#
# 收窄过两轮：先是 thinking（一轮里每次工具调用之间都会 thinking↔tool 反复，于是每
# 两三秒一句"让我想想…"），再是 waiting/asking（审批与提问能连续触发）。留下来的
# 这两个是真正"你不用盯着也知道结果"的事件，各配一个专属动作（react-1 / react-2）。
DEFAULT_SPEAK_PHASES = {"done", "failed"}
QUIET_PHASES = {"tool", "idle"}

SPEAK_PHASES = {
    phase.strip()
    for phase in os.environ.get("PET_PHASES", "").split(",")
    if phase.strip()
} or DEFAULT_SPEAK_PHASES


def log(message: str) -> None:
    if DEBUG:
        print(message, file=sys.stderr, flush=True)


def voice_dir() -> str:
    return os.path.join(PETS_DIR, PET, "voice")


def clip(name: str) -> str | None:
    path = os.path.join(voice_dir(), f"{name}.mp3")
    return path if os.path.isfile(path) else None


def random_clip(prefix: str) -> str | None:
    """greet-1..N 里随机挑一条；没有就返回 None。"""
    folder = voice_dir()
    if not os.path.isdir(folder):
        return None
    pattern = re.compile(rf"^{re.escape(prefix)}-\d+\.mp3$")
    matches = sorted(f for f in os.listdir(folder) if pattern.match(f))
    return os.path.join(folder, random.choice(matches)) if matches else None


def find_port() -> int | None:
    """端口每次重启都会变：从 lsof 里找 DeepSeek 的监听端口，再挨个探测插件接口。"""
    try:
        out = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    ports = set()
    for line in out.splitlines():
        if "DeepSeek" not in line:
            continue
        match = re.search(r":(\d+)\s", line)
        if match:
            ports.add(int(match.group(1)))
    for port in sorted(ports):
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/api/live2d-pet/catalog", timeout=2
            ) as response:
                if response.status == 200:
                    return port
        except (OSError, ValueError):
            continue
    return None


def play(path: str) -> subprocess.Popen | None:
    try:
        return subprocess.Popen(
            ["afplay", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError as error:
        log(f"afplay failed: {error}")
        return None


def main() -> int:
    if not os.path.isdir(voice_dir()):
        print(f"[pet-voice] {voice_dir()} 不存在，先跑 pet-voice-gen.py", file=sys.stderr)
        return 1

    port = find_port()
    if port is None:
        print("[pet-voice] 没找到 DSH 的端口（App 没开？）", file=sys.stderr)
        return 1

    player: subprocess.Popen | None = None
    last_played = 0.0
    last_phase = None
    greeted = False

    def play_clip(path: str) -> None:
        nonlocal player, last_played
        if player is not None and player.poll() is None:
            player.terminate()  # 新的一句优先，不排队
        player = play(path)
        last_played = time.time()
        log(f"play: {os.path.basename(path)}")

    while True:
        url = f"http://127.0.0.1:{port}/api/live2d-pet/events"
        try:
            with urllib.request.urlopen(url, timeout=None) as stream:
                log(f"connected: {url}")
                if not greeted:
                    opening = random_clip("greet")
                    if opening:
                        play_clip(opening)
                        greeted = True
                for raw in stream:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    try:
                        event = json.loads(line[5:].strip())
                    except ValueError:
                        continue
                    if event.get("type") == "sound":
                        continue  # 每次工具调用都会发，念出来太吵
                    phase = event.get("phase")
                    if phase == last_phase:
                        continue
                    last_phase = phase
                    if phase in QUIET_PHASES or phase not in SPEAK_PHASES:
                        continue
                    if time.time() - last_played < MIN_GAP:
                        continue
                    path = clip(f"phase-{phase}")
                    if path:
                        play_clip(path)
        except Exception as error:  # 端口变了 / App 重启了
            log(f"stream dropped: {error}")
            time.sleep(2)
            port = find_port()
            if port is None:
                time.sleep(3)
        except KeyboardInterrupt:
            return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
