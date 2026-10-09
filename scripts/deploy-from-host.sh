#!/usr/bin/env bash
# =============================================================================
# 在电脑上执行：把 dae 安装包上传到路由器并平滑升级（SSH 部署）
#
# 用法：
#   ./scripts/deploy-from-host.sh root@10.10.10.1                 # 自动下载最新 Release
#   ./scripts/deploy-from-host.sh root@10.10.10.1 ./dae-xxx.tar.gz # 使用本地包
#   ./scripts/deploy-from-host.sh root@10.10.10.1 <某个 Release 的 tar.gz URL>
#
# 环境变量：
#   GH_REPO    Release 所在仓库（默认 aoxiangtianji/openwrt_dae）
#   SSH_OPTS   额外 ssh/scp 参数（默认 -o StrictHostKeyChecking=accept-new）
# =============================================================================
set -euo pipefail

GH_REPO="${GH_REPO:-aoxiangtianji/openwrt_dae}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=accept-new}"

TARGET="${1:-}"
PKG_ARG="${2:-}"

if [ -z "$TARGET" ]; then
  cat >&2 <<EOF
用法: $0 <user@router-ip> [本地 tar.gz 路径 | 下载 URL]

示例:
  $0 root@10.10.10.1
  $0 root@10.10.10.1 ./dae-v2.1.1-linux-arm64.tar.gz
EOF
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- 1. 准备安装包 ----------------------------------------------------------
if [ -z "$PKG_ARG" ]; then
  echo "[deploy] 未指定安装包，尝试从 GitHub Release 自动获取 ..."
  API="https://api.github.com/repos/${GH_REPO}/releases"
  URL="$(curl -fsSL --retry 3 "$API" \
    | grep -o '"browser_download_url": *"[^"]*linux-arm64\.tar\.gz"' \
    | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$URL" ] || { echo "[deploy] 未能从 $GH_REPO 找到 Release 产物" >&2; exit 1; }
  echo "[deploy] 下载: $URL"
  curl -fL --retry 3 -o "$WORK_DIR/pkg.tar.gz" "$URL"
elif echo "$PKG_ARG" | grep -qE '^https?://'; then
  echo "[deploy] 下载: $PKG_ARG"
  curl -fL --retry 3 -o "$WORK_DIR/pkg.tar.gz" "$PKG_ARG"
else
  [ -f "$PKG_ARG" ] || { echo "[deploy] 找不到本地文件：$PKG_ARG" >&2; exit 1; }
  cp "$PKG_ARG" "$WORK_DIR/pkg.tar.gz"
fi

# --- 2. 校验与解包 ----------------------------------------------------------
echo "[deploy] 解包 ..."
tar -xzf "$WORK_DIR/pkg.tar.gz" -C "$WORK_DIR"
PKG_DIR="$(find "$WORK_DIR" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
[ -n "$PKG_DIR" ] || { echo "[deploy] 压缩包结构异常" >&2; exit 1; }
[ -f "$PKG_DIR/dae" ] || { echo "[deploy] 包内缺少 dae 二进制" >&2; exit 1; }

echo "[deploy] 二进制信息：$(file "$PKG_DIR/dae" 2>/dev/null || echo '(file 命令不可用)')"

# --- 3. 上传 ----------------------------------------------------------------
REMOTE_DIR="/tmp/dae-deploy.$$"
echo "[deploy] 上传到 $TARGET:$REMOTE_DIR ..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$TARGET" "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"
# shellcheck disable=SC2086
scp $SSH_OPTS -r "$PKG_DIR"/. "$TARGET:$REMOTE_DIR/"

# --- 4. 在路由器上安装并 restart -------------------------------------------
echo "[deploy] 在路由器上执行安装脚本 ..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "$TARGET" "cd '$REMOTE_DIR' && sh install.sh; rc=\$?; rm -rf '$REMOTE_DIR'; exit \$rc"

echo "[deploy] 完成。"
echo "[deploy] 提示：更换二进制后需 restart 才生效（本脚本已自动处理）；"
echo "[deploy]       仅修改 /etc/dae/config.dae 时可用 /etc/init.d/dae reload 做到零中断热重载。"
