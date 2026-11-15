#!/bin/bash
# 桌宠配音控制（MiniMax 音频版，不用 macOS say）
#
# 把本目录的 pet-voice.py / pet-voice-gen.py / pet-voice-ctl.sh 放到 ~/.dsh/ 之后：
#
#   ~/.dsh/pet-voice-ctl.sh --on                启动（plist 不存在会自动创建）
#   ~/.dsh/pet-voice-ctl.sh --off               停止
#   ~/.dsh/pet-voice-ctl.sh --list              列出可用的 MiniMax 中文音色
#   ~/.dsh/pet-voice-ctl.sh --voice female-shaonv   换音色并全部重新生成
#   ~/.dsh/pet-voice-ctl.sh --pet natori        换台词来源宠物
#   ~/.dsh/pet-voice-ctl.sh --regen             按当前音色重新生成
set -euo pipefail

LABEL=com.dsh.pet-voice
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"
HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
GEN="$HOME_DIR/pet-voice-gen.py"
RUN="$HOME_DIR/pet-voice.py"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# PlistBuddy 在文件不存在时把错误信息打到 **stdout**，直接 $(...) 会把它当成值。
# 所以这里只接受看起来像宠物名的输出（[A-Za-z0-9._-]），其余一律当作"没有"。
env_of() {
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$1" "$PLIST" 2>/dev/null || true)"
  case "$value" in
    "" | *[!A-Za-z0-9._-]*) return 0 ;;
  esac
  printf '%s' "$value"
}
set_env() {
  /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:$1 $2" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$1 string $2" "$PLIST"
}

# 没有 plist 就自己写一份，--on 才算真的"开箱即用"。
ensure_plist() {
  if [ -f "$PLIST" ]; then return; fi
  if [ ! -f "$RUN" ]; then
    echo "找不到 $RUN —— 先把 contrib/pet-voice/ 里的文件复制到 $HOME_DIR/" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(command -v python3)</string>
    <string>$RUN</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PET_NAME</key><string>${1:-mao}</string>
    <key>PET_GAP</key><string>2.5</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/pet-voice.log</string>
  <key>StandardErrorPath</key><string>/tmp/pet-voice.log</string>
</dict>
</plist>
EOF
  echo "[ok] 已创建 $PLIST"
}

reload() {
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$PLIST"
  echo "[ok] relaunched"
}

PET_NOW="$(env_of PET_NAME)"; PET_NOW="${PET_NOW:-mao}"

case "${1:-}" in
  ""|-h|--help) usage 0 ;;
  --list) mmx speech voices 2>/dev/null | grep -i "mandarin" | tr -d ' ",' | sed 's/^/  /' ;;
  --off)  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true; echo "[ok] voice off" ;;
  --on)   ensure_plist "$PET_NOW"; reload; echo "[ok] voice on" ;;
  --pet)
    [ -n "${2:-}" ] || usage 1
    ensure_plist "$2"; set_env PET_NAME "$2"; reload; echo "[ok] pet: $2" ;;
  --voice)
    [ -n "${2:-}" ] || usage 1
    ensure_plist "$PET_NOW"
    python3 "$GEN" --pet "$PET_NOW" --voice "$2" --force
    reload; echo "[ok] voice: $2" ;;
  --regen)
    ensure_plist "$PET_NOW"
    python3 "$GEN" --pet "$PET_NOW" --voice "${2:-female-shaonv}" --force
    echo "[ok] regenerated" ;;
  *) usage 1 ;;
esac
