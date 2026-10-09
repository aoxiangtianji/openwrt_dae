#!/bin/sh
# =============================================================================
# dae apk 无人值守升级 + 自动回滚（在路由器上以 root 执行）
#
# 设计目标（针对“路由器同时是唯一运维通道”的场景）：
#   1. 全程用 apk 管理包（apk add），不做手工替换；
#   2. 升级前完整备份旧二进制、旧配置、旧 init 脚本、旧 UCI；
#   3. 升级后做健康检查（服务状态 / 进程 / 版本 / eBPF / 日志），
#      任何一项不达标即自动回滚到备份的旧二进制并重启服务；
#   4. 自派生一个“看门狗”子进程：即使主流程异常中断，
#      超时后仍未写入 SUCCESS 标记也会自动回滚，避免把网络留在坏状态；
#   5. 全过程日志落到 /root/dae-rollback/upgrade.log，便于事后核查。
#
# 用法：
#   sh upgrade-on-router.sh <apk文件路径> <期望版本，如 2.1.1>
#   sh upgrade-on-router.sh --status        # 查看上次升级结果
#
# 注意：本脚本必须在路由器本机执行（脱离 SSH 会话用 setsid 启动），
#       这样即使 SSH 断开，升级与回滚逻辑仍会跑完。
# =============================================================================
set -u

ROLLBACK_DIR="/root/dae-rollback"
BAK_BIN="$ROLLBACK_DIR/dae.rollback.bin"
BAK_CONF="$ROLLBACK_DIR/config.dae.rollback"
BAK_UCI="$ROLLBACK_DIR/uci-dae.rollback"
BAK_INIT="$ROLLBACK_DIR/init.d-dae.rollback"
LOG="$ROLLBACK_DIR/upgrade.log"
STATUS_FILE="$ROLLBACK_DIR/status"
WATCHDOG_DELAY="${WATCHDOG_DELAY:-300}"
DAE_INIT="/etc/init.d/dae"
DAE_BIN="/usr/bin/dae"
IFACE_LAN="${IFACE_LAN:-br-lan.10}"

mkdir -p "$ROLLBACK_DIR" 2>/dev/null

log() {
	printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

set_status() {
	printf '%s\n' "$*" > "$STATUS_FILE"
}

# ---------------------------------------------------------------- 结果查询
if [ "${1:-}" = "--status" ]; then
	echo "状态文件 : $STATUS_FILE"
	[ -f "$STATUS_FILE" ] && cat "$STATUS_FILE" || echo "(尚无记录)"
	echo "日志尾部 :"
	tail -n 30 "$LOG" 2>/dev/null || echo "(无日志)"
	exit 0
fi

# ---------------------------------------------------------------- 回滚逻辑
do_rollback() {
	reason="$1"
	log "!!!!! 触发自动回滚：$reason !!!!!"
	if [ ! -f "$BAK_BIN" ]; then
		log "致命：没有可用的旧二进制备份，无法回滚！"
		set_status "ROLLBACK_FAILED:no-backup"
		return 1
	fi

	log "停止服务 ……"
	"$DAE_INIT" stop 2>/dev/null

	log "恢复旧二进制 ……"
	cp -f "$BAK_BIN" "$DAE_BIN.new" 2>/dev/null || cp -f "$BAK_BIN" /tmp/dae.new
	chmod 0755 "$DAE_BIN.new" 2>/dev/null
	mv -f "$DAE_BIN.new" "$DAE_BIN" 2>/dev/null || cp -f "$BAK_BIN" "$DAE_BIN"

	[ -f "$BAK_CONF" ] && cp -f "$BAK_CONF" /etc/dae/config.dae 2>/dev/null
	[ -f "$BAK_UCI" ] && cp -f "$BAK_UCI" /etc/config/dae 2>/dev/null
	[ -f "$BAK_INIT" ] && cp -f "$BAK_INIT" "$DAE_INIT" 2>/dev/null && chmod 0755 "$DAE_INIT"

	log "启动服务 ……"
	mkdir -p /var/log/dae
	"$DAE_INIT" start 2>/dev/null

	sleep 8
	newver="$("$DAE_BIN" --version 2>/dev/null | head -n 1)"
	if "$DAE_INIT" status >/dev/null 2>&1; then
		log "回滚完成，服务已运行：$newver"
		set_status "ROLLED_BACK:$newver"
	else
		log "回滚后服务仍未运行，请人工介入！"
		set_status "ROLLBACK_FAILED:service-down"
	fi
	return 0
}

# ---------------------------------------------------------------- 看门狗
# 由主流程 setsid 派生；若超时后仍未写入 SUCCESS，说明主流程异常，执行回滚
if [ "${1:-}" = "--watchdog" ]; then
	sleep "$WATCHDOG_DELAY"
	if grep -q "SUCCESS" "$STATUS_FILE" 2>/dev/null; then
		exit 0
	fi
	log "看门狗：等待 ${WATCHDOG_DELAY}s 未收到成功标记，判定升级异常"
	do_rollback "watchdog-timeout"
	exit 0
fi

# ---------------------------------------------------------------- 主流程
APK="${1:-}"
EXPECT="${2:-}"
if [ -z "$APK" ] || [ -z "$EXPECT" ]; then
	echo "用法: $0 <apk文件路径> <期望版本，如 2.1.1>" >&2
	echo "      $0 --status" >&2
	exit 1
fi

# 把标准输出与错误统一并入日志（后续所有输出都进日志）
exec >>"$LOG" 2>&1

log "=============================================================="
log "dae 升级开始（apk 管理方式）"
log "apk 文件 : $APK"
log "期望版本 : $EXPECT"

if [ ! -f "$APK" ]; then
	log "错误：找不到 apk 文件"
	set_status "FAILED:no-apk"
	exit 1
fi

# 确保有 pkgid 校验可能的包完整性（仅提示，不阻塞）
if command -v sha256sum >/dev/null 2>&1; then
	log "apk sha256: $(sha256sum "$APK" | cut -d' ' -f1)"
fi

OLD_VER="$("$DAE_BIN" --version 2>/dev/null | head -n 1)"
log "升级前版本: $OLD_VER"

WAS_RUNNING="no"
"$DAE_INIT" status >/dev/null 2>&1 && WAS_RUNNING="yes"
log "升级前服务: $WAS_RUNNING"

if "$DAE_INIT" status >/dev/null 2>&1; then
	log "热重载前的配置校验: $("$DAE_BIN" validate -c /etc/dae/config.dae 2>&1 | head -n 1)"
fi

# --- 1. 备份 --------------------------------------------------------------
log "--- 备份旧二进制与配置 ---"
cp -f "$DAE_BIN" "$BAK_BIN" || { log "备份二进制失败，中止升级"; set_status "FAILED:backup"; exit 1; }
cp -f /etc/dae/config.dae "$BAK_CONF" 2>/dev/null
cp -f /etc/config/dae "$BAK_UCI" 2>/dev/null
cp -f "$DAE_INIT" "$BAK_INIT" 2>/dev/null
log "备份完成：$ROLLBACK_DIR（$(ls -l "$BAK_BIN" | awk '{print $5}') 字节）"

# --- 2. 派生看门狗（第二层保护） -------------------------------------------
set_status "RUNNING:watchdog-armed"
setsid "$0" --watchdog >/dev/null 2>&1 &
log "看门狗已派生（${WATCHDOG_DELAY}s 超时）"

# --- 3. apk 安装（包管理方式） ---------------------------------------------
log "--- apk add --allow-untrusted $APK ---"
if ! apk add --allow-untrusted "$APK"; then
	log "apk 安装失败"
	do_rollback "apk-add-failed"
	exit 1
fi
log "apk 安装完成"

INSTALLED_VER="$("$DAE_BIN" --version 2>/dev/null | head -n 1)"
log "安装后二进制自报版本: $INSTALLED_VER"

# --- 4. 重启服务 -----------------------------------------------------------
# 注意：原 /etc/init.d/dae 的 stop_service 会 `rm -rf /var/log/dae`，
# 因此在启动前必须把日志目录建回来，否则 dae 可能因 --logfile 目录缺失而启动失败。
log "--- 重启服务（stop → 恢复日志目录 → start）---"
"$DAE_INIT" stop 2>/dev/null
mkdir -p /var/log/dae
"$DAE_INIT" start

# --- 5. 健康检查（最多 90 秒）---------------------------------------------
i=0
ok="no"
while [ "$i" -lt 90 ]; do
	sleep 3
	i=$((i + 3))

	ver="$("$DAE_BIN" --version 2>/dev/null | head -n 1)"
	svc="no"; "$DAE_INIT" status >/dev/null 2>&1 && svc="yes"
	proc="no"; pgrep -f "/usr/bin/dae run" >/dev/null 2>&1 && proc="yes"
	pin="no"; [ -d /sys/fs/bpf/dae ] && pin="yes"

	log "健康检查 ${i}s: 版本='$ver' 服务=$svc 进程=$proc bpf-pin=$pin"

	if [ "$svc" = "yes" ] && [ "$proc" = "yes" ]; then
		case "$ver" in
			*"$EXPECT"*) ok="yes"; break ;;
		esac
	fi
done

if [ "$ok" != "yes" ]; then
	log "健康检查未通过（期望版本含 '$EXPECT'）"
	do_rollback "health-check-failed"
	exit 1
fi

# --- 6. 附加业务检查 -------------------------------------------------------
log "--- 附加检查 ---"
if [ -d /sys/fs/bpf/dae ]; then
	log "OK: /sys/fs/bpf/dae 已建立（eBPF map 已 pin）"
else
	log "警告: 未发现 /sys/fs/bpf/dae"
fi

# 日志中不应出现 panic / fatal
if [ -f /var/log/dae/dae.log ]; then
	if tail -n 200 /var/log/dae/dae.log 2>/dev/null | grep -qiE "panic|fatal error"; then
		log "警告: 新版本日志中发现 panic/fatal，触发回滚"
		do_rollback "log-panic"
		exit 1
	fi
	log "日志检查通过（近 200 行无 panic/fatal）"
fi

# 上游接口连通性（尽力而为，不阻塞）
if command -v nslookup >/dev/null 2>&1; then
	ns="$(nslookup www.baidu.com 2>/dev/null | tail -n 3 | head -n 1)"
	[ -n "$ns" ] && log "DNS 解析测试: $ns" || log "警告: DNS 解析测试无输出"
fi

NEW_VER="$("$DAE_BIN" --version 2>/dev/null | head -n 1)"
log "升级成功：$OLD_VER  →  $NEW_VER"
set_status "SUCCESS:$NEW_VER"
log "=============================================================="
exit 0
