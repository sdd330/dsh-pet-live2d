#!/usr/bin/env bash
# 把 Live2D 官方示例角色 Mao 装成 DSH 桌宠。
#
# 模型文件（*.moc3 / 贴图 / 动作）**不随本仓库分发** —— Live2D《无偿提供素材使用
# 授权协议》4.1.1 明确禁止再分发。所以这里只做两件事：
#   1. 从 Live2D 官方示例仓库拉取模型（使用者本机执行，等于自己下载）
#   2. 写入本仓库提供的宠物配置（相位映射 / 中文标签 / 表情槽 / 台词 / 语音）
#
# 用法:
#   ./install.sh                       # 从 GitHub 拉取官方模型
#   ./install.sh /path/to/Mao          # 用本地已有的 Mao 模型目录
#
# 环境变量:
#   DSH_PETS_DIR   宠物根目录，默认 ~/.dsh/pets
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pets_root="${DSH_PETS_DIR:-$HOME/.dsh/pets}"
dest="$pets_root/mao"
src="${1:-}"

if [ -z "$src" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "[1/3] 拉取 Live2D 官方示例 Mao（CubismWebSamples，只取该目录）"
  git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/Live2D/CubismWebSamples.git "$tmp/samples" >/dev/null
  ( cd "$tmp/samples" && git sparse-checkout set Samples/Resources/Mao >/dev/null )
  src="$tmp/samples/Samples/Resources/Mao"
fi

if [ ! -d "$src" ]; then
  echo "找不到 Mao 模型目录：$src" >&2
  exit 1
fi

echo "[2/3] 复制模型到 $dest"
mkdir -p "$dest"
cp -R "$src"/. "$dest"/

echo "[3/3] 写入宠物配置（相位映射 / 中文标签 / 表情槽 / 台词 / 语音）"
node "$here/setup.mjs" "$dest"
cp "$here/pet.json" "$here/catalog.json" "$dest"/
mkdir -p "$dest/locale" "$dest/voice"
cp "$here/locale/en.json" "$dest/locale"/
cp "$here"/voice/*.mp3 "$dest/voice"/

echo
echo "完成。刷新 DSH 页面，右键桌宠 → 标题栏下拉选「小舞 Mao」。"
echo "想让她说话：见 ../pet-voice/README.md"
