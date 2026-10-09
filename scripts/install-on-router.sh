#!/bin/sh
# =============================================================================
# dae 一键安装 / 升级脚本（在路由器上以 root 执行）
#
# 适用于：ImmortalWrt / OpenWrt 25.x（apk 或 opkg）、aarch64（MediaTek Filogic）
# 用法：
#   sh install.sh                 安装或升级，并重启服务
#   sh install.sh --keep-config   保留现有 /etc/dae/config.dae（默认就保留）
#   sh install.sh --force-config  用包内示例覆盖现有 config.dae（会先备份）
#   sh install.sh --no-start      只替换文件，不启动服务
#   sh install.sh --no-init       不更新 /etc/init.d/dae
#
# 设计要点：
#   * 二进制采用 “写临时文件 + mv 原子替换”，避免 ETXTBSY（文件忙）问题
#   * 配置文件权限强制 0600，防止订阅链接 / 节点密码泄露
#   * 升级二进制必须重启进程才生效；仅改配置可用 /etc/init.d/dae reload 零中断
# =============================================================================
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DAE_BIN_SRC="$SRC_DIR/dae"
DAE_BIN_DST="/usr/bin/dae"
INIT_DST="/etc/init.d/dae"
UCI_DST="/etc/config/dae"
CONF_DIR="/etc/dae"
CONF_DST="$CONF_DIR/config.dae"
GEO_DIR="/usr/share/dae"
BACKUP_DIR="/root/dae-backup"
STAMP="$(date +%Y%m%d-%H%M%S)"

KEEP_CONFIG=1
START_SERVICE=1
UPDATE_INIT=1

for arg in "$@"; do
  case "$arg" in
    --keep-config)  KEEP_CONFIG=1 ;;
    --force-config) KEEP_CONFIG=0 ;;
    --no-start)     START_SERVICE=0 ;;
    --no-init)      UPDATE_INIT=0 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数：$arg（-h 查看帮助）" >&2; exit 1 ;;
  esac
done

log()  { echo "[dae-install] $*"; }
warn() { echo "[dae-install][警告] $*" >&2; }
die()  { echo "[dae-install][错误] $*" >&2; exit 1; }

log "路由架构：$(uname -m)"

# --- 0. 前置检查 ------------------------------------------------------------
[ -f "$DAE_BIN_SRC" ] || die "当前目录缺少 dae 二进制（请在解压后的目录内运行本脚本）"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "本包仅适用于 aarch64，当前为 $(uname -m)" ;;
esac

if [ ! -e /sys/kernel/btf/vmlinux ]; then
  warn "未发现 /sys/kernel/btf/vmlinux —— 当前内核未开启 CONFIG_DEBUG_INFO_BTF，"
  warn "dae 的 eBPF 程序将无法加载。请刷入带 BTF 的 ImmortalWrt 固件后再试。"
fi

mkdir -p "$BACKUP_DIR"

# --- 1. 停止服务 ------------------------------------------------------------
if [ -x "$INIT_DST" ]; then
  if "$INIT_DST" status >/dev/null 2>&1; then
    log "停止原有 dae 服务 ..."
    "$INIT_DST" stop || warn "停止服务失败，继续尝试替换二进制"
    sleep 1
  fi
fi

# --- 2. 备份 ----------------------------------------------------------------
if [ -f "$DAE_BIN_DST" ]; then
  log "备份旧二进制 → $BACKUP_DIR/dae.$STAMP"
  cp "$DAE_BIN_DST" "$BACKUP_DIR/dae.$STAMP"
fi
if [ -f "$CONF_DST" ]; then
  log "备份旧配置   → $BACKUP_DIR/config.dae.$STAMP"
  cp "$CONF_DST" "$BACKUP_DIR/config.dae.$STAMP"
fi

# --- 3. 原子替换二进制 ------------------------------------------------------
# 先落到同分区临时文件再 mv，避免“文本文件忙”以及替换瞬间出现半截文件
log "安装二进制 → $DAE_BIN_DST"
cp "$DAE_BIN_SRC" "$DAE_BIN_DST.new"
chmod 0755 "$DAE_BIN_DST.new"
mv -f "$DAE_BIN_DST.new" "$DAE_BIN_DST"

# --- 4. 安装 procd 启动脚本 -------------------------------------------------
if [ "$UPDATE_INIT" = "1" ] && [ -f "$SRC_DIR/dae.init" ]; then
  log "安装启动脚本 → $INIT_DST"
  cp "$SRC_DIR/dae.init" "$INIT_DST"
  chmod 0755 "$INIT_DST"
fi

# --- 5. UCI 配置（不覆盖已有配置）------------------------------------------
if [ -f "$SRC_DIR/dae.uci" ] && [ ! -f "$UCI_DST" ]; then
  log "安装 UCI 配置 → $UCI_DST（默认 disabled，配置好后再启用）"
  cp "$SRC_DIR/dae.uci" "$UCI_DST"
  chmod 0644 "$UCI_DST"
fi

# --- 6. dae 配置文件（权限 0600）-------------------------------------------
mkdir -p "$CONF_DIR"
if [ -f "$SRC_DIR/config.dae.example" ]; then
  if [ -f "$CONF_DST" ] && [ "$KEEP_CONFIG" = "1" ]; then
    log "保留已有配置：$CONF_DST"
  else
    log "安装示例配置 → $CONF_DST"
    cp "$SRC_DIR/config.dae.example" "$CONF_DST"
  fi
fi
[ -f "$CONF_DST" ] && chmod 0600 "$CONF_DST" && log "配置权限已设为 0600"

# --- 7. geo 数据 ------------------------------------------------------------
if [ -f "$SRC_DIR/geoip.dat" ] || [ -f "$SRC_DIR/geosite.dat" ]; then
  mkdir -p "$GEO_DIR"
  [ -f "$SRC_DIR/geoip.dat" ]  && cp "$SRC_DIR/geoip.dat"  "$GEO_DIR/geoip.dat"  && log "安装 geoip.dat"
  [ -f "$SRC_DIR/geosite.dat" ] && cp "$SRC_DIR/geosite.dat" "$GEO_DIR/geosite.dat" && log "安装 geosite.dat"
  chmod 0644 "$GEO_DIR"/*.dat 2>/dev/null || true
fi

# --- 8. 校验与启动 ----------------------------------------------------------
log "二进制版本：$("$DAE_BIN_DST" --version 2>&1 | head -n 1)"

if [ "$START_SERVICE" = "1" ] && [ -x "$INIT_DST" ]; then
  if [ -f "$CONF_DST" ]; then
    if "$DAE_BIN_DST" validate -c "$CONF_DST" >/dev/null 2>&1; then
      log "配置校验通过：$CONF_DST"
      "$INIT_DST" enable 2>/dev/null || true
      # 注意：UCI 中 enabled=0 时启动脚本会拒绝启动，这里给出明确提示
      if grep -qE "^\s*option\s+enabled\s+'0'" "$UCI_DST" 2>/dev/null; then
        warn "UCI 配置中 enabled=0，服务不会自动启动。"
        warn "编辑 /etc/dae/config.dae 填好订阅后执行："
        warn "  uci set dae.dae.enabled=1 && uci commit dae && /etc/init.d/dae start"
      else
        log "启动服务 ..."
        "$INIT_DST" restart || die "服务启动失败，请查看 logread -e dae"
      fi
    else
      warn "配置校验未通过，未启动服务。请检查 $CONF_DST 后执行 /etc/init.d/dae start"
    fi
  fi
fi

log "完成。备份目录：$BACKUP_DIR"
log "回滚方式：cp $BACKUP_DIR/dae.$STAMP $DAE_BIN_DST && /etc/init.d/dae restart"
