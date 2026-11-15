#!/bin/bash
# 一眼看清桌宠 + 配音的状态：端口、可见宠物、语音覆盖、守护进程。
#
#   ~/.dsh/pet-status.sh
#
# 只读，不改任何东西。
set -uo pipefail

PY="$(command -v python3 || echo /usr/bin/python3)"
PETS="${DSH_HOME:-$HOME/.dsh}/pets"
LABEL=com.dsh.pet-voice
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# lsof 的 NAME 列是 "127.0.0.1:62455 (LISTEN)"，只取 host:port 里的端口。
PORT="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -i DeepSeek \
  | grep -oE '127\.0\.0\.1:[0-9]+' | head -1 | sed 's/.*://')"

echo "DSH"
if [ -z "$PORT" ]; then
  echo "  端口: 未运行（App 没开？）"
else
  echo "  端口: $PORT"
  # python 脚本来自 heredoc，stdin 被占用，所以响应通过环境变量传进去。
  CATALOG="$(curl -sS -m 5 "http://127.0.0.1:$PORT/api/live2d-pet/catalog" 2>/dev/null)" \
  PETS_DIR="$PETS" "$PY" <<'PYEOF'
import json, os, pathlib
pets_dir = pathlib.Path(os.environ["PETS_DIR"])
try:
    data = json.loads(os.environ.get("CATALOG") or "")
except Exception:
    print("  插件接口: 无响应")
    raise SystemExit
print(f"  可见宠物: {len(data.get('pets', []))} 只")
for pet in data.get("pets", []):
    motions = sum(m.get("count", 0) for m in (pet.get("motions") or []))
    slots = pet.get("expressionSlots") or []
    options = sum(len(s.get("options") or []) for s in slots)
    folder = pets_dir / pet["id"] / "voice"
    clips = len(list(folder.glob("*.mp3"))) if folder.is_dir() else 0
    print(f"    {pet['id']:8} 「{pet['displayName']}」 动作 {motions:>2}"
          f"  表情 {len(pet.get('expressions') or []):>2}  装扮项 {options:>2}  语音 {clips:>2}")
PYEOF
fi

echo "配音"
if ! launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "  守护: 未运行（~/.dsh/pet-voice-ctl.sh --on 启动）"
else
  state="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk -F'= ' '/state =/{print $2; exit}')"
  echo "  守护: ${state:-unknown}"
  echo "  宠物: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PET_NAME' "$PLIST" 2>/dev/null || echo mao)"
  echo "  相位: $(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PET_PHASES' "$PLIST" 2>/dev/null || echo 'done,failed（默认）')"
fi
[ -f /tmp/pet-voice.log ] && echo "  日志: $(wc -l < /tmp/pet-voice.log | tr -d ' ') 行（/tmp/pet-voice.log）"
