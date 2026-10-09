# 真机部署 Runbook —— dae 1.1.0 → 2.1.1 @ ImmortalWrt 10.10.100.1

> 本文档记录一次真实升级的**完整风险评估、执行步骤与回滚方案**。
> 核心约束：**这台路由器同时是唯一的运维通道**，任何操作都必须保证可自愈。

---

## 一、环境事实（升级前实测）

| 项目 | 实测值 |
| --- | --- |
| 设备 | ImmortalWrt 25.12-SNAPSHOT `r37876-e04af5bf78` |
| 平台 | `mediatek/filogic`，`aarch64_cortex-a53` |
| 内核 | `6.12.91` |
| 包管理器 | `apk-tools 3.0.5`（无 `mkpkg`，本地不能打 apk，必须用 SDK 构建） |
| 内核 BTF | `/sys/kernel/btf/vmlinux` 存在（CO-RE 可用） |
| bpffs | `bpffs /sys/fs/bpf bpf rw,...` 已挂载 |
| 现有 dae | `dae-1.1.0-r1`（来自 ImmortalWrt packages feed） |
| 相关包 | `dae-geoip-1.1.0-r1`、`dae-geosite-1.1.0-r1`、`luci-app-dae`、`luci-i18n-dae-zh-cn` |
| 冻结文件 | `/usr/bin/dae` 0755 `40c2a8f9…`；`/etc/init.d/dae` 0755 `da6d97a7…`；`/etc/config/dae` **0600** `6f6790e3…`；`/etc/dae/config.dae` **0600** `7f7854ec…`；`/etc/dae/example.dae` 0600 `bb2531e9…`；`/lib/upgrade/keep.d/dae` 0644 |
| 服务状态 | running，开机自启（`/etc/rc.d/S99dae`） |
| 配置校验 | `dae validate` 退出码 0 |

---

## 二、运维通道（关键安全网）

容器位于 `10.10.100.165`（`br-lan.10`），与路由器同网段二层直连。
而 dae 的 `lan_interface` 正是 **`br-lan.10`** —— 也就是说**运维流量走的正是 dae 处理的那个 VLAN**。

实测**五条可免密登录的通道**：

| 通道 | 地址 | 是否经过 dae 的 lan_interface |
| --- | --- | --- |
| 主通道 | `10.10.100.1` (br-lan.10) | ⚠️ 是（唯一有风险的一条） |
| 备用 1 | `10.10.10.1` (br-lan.1 / VLAN1) | 否 |
| 备用 2 | `10.10.5.1` (br-lan.5 / VLAN5) | 否 |
| 备用 3 | `10.1.2.20` (Wireguard) | 否 |
| 备用 4 | `192.168.66.2` (usb0) | 否 |

结论：即使 `br-lan.10` 因 dae 异常而不可用，仍有 4 条独立通道可用于抢救。

---

## 三、风险清单与处置

| # | 风险 | 后果 | 处置 |
| --- | --- | --- | --- |
| 1 | 新版本 eBPF 加载失败 | dae 无法启动 | 启动前 `dae validate`；健康检查失败自动回滚 |
| 2 | 旧 eBPF pin 残留冲突 | 加载报错 | 通过 init 脚本 `stop` 先行清理，再 `start` |
| 3 | apk 升级删除文件 | 服务脚本消失 | **包的文件集合与官方包严格一致**（含 init.d、UCI、example.dae、keep.d） |
| 4 | geo 数据文件冲突 | apk 报文件冲突 | **本包不含 geoip/geosite**，由 `dae-geoip`/`dae-geosite` 单独提供 |
| 5 | 依赖漂移 | apk 试图安装/卸载依赖包 | 包 DEPENDS 与原包**完全一致** |
| 6 | 配置不兼容（跨大版本） | 启动失败 | 已实测：v2.1.1 `validate` 现有 config.dae **退出码 0**，无需改配置 |
| 7 | `luci-app-dae` 依赖被破坏 | LuCI 报错 | 已实测：其依赖为无版本约束的 `dae`，升级不影响 |
| 8 | stop 时 `rm -rf /var/log/dae` | 重启后日志目录缺失导致启动失败 | 升级脚本在 start 前 `mkdir -p /var/log/dae` |
| 9 | 手工替换二进制触发 `ETXTBSY` | 替换失败 | 全程用 `apk add`，不做手工替换 |
| 10 | 升级过程 SSH 断开 | 运维中断 | 用 `setsid` 脱离会话执行；**五条通道**兜底 |
| 11 | 脚本自身异常中断 | 网络留在坏状态 | **看门狗**：超时未写入 SUCCESS 即自动回滚 |
| 12 | apk 未签名 | 安装被拒 | `apk add --allow-untrusted` |

---

## 四、执行步骤

```sh
# 1) 取包（GitHub Release，公开可见）
#    产物：dae-2.1.1-r1.apk / dae-v2.1.1-linux-arm64.tar.gz / SHA256SUMS

# 2) 校验（对比 Release 里的 SHA256SUMS）
sha256sum dae-2.1.1-r1.apk

# 3) 上传到路由器（走备用通道亦可）
cat dae-2.1.1-r1.apk | ssh root@10.10.10.1 'cat > /tmp/dae-2.1.1-r1.apk'

# 4) 模拟安装预检（不产生任何改动）
ssh root@10.10.10.1 'apk add --simulate --allow-untrusted /tmp/dae-2.1.1-r1.apk'

# 5) 无人值守升级（setsid 脱离会话，含自动回滚 + 看门狗）
ssh root@10.10.10.1 'setsid sh /root/upgrade-on-router.sh /tmp/dae-2.1.1-r1.apk 2.1.1 >/dev/null 2>&1 &'

# 6) 观察（任选一条通道）
ssh root@10.10.10.1 'sh /root/upgrade-on-router.sh --status'
ssh root@10.10.10.1 'tail -f /root/dae-rollback/upgrade.log'
```

---

## 五、三层回滚

1. **第一层：脚本内自动回滚** —— 健康检查（服务/进程/版本/bpf pin/日志）任一不通过，立即恢复备份二进制并重启。
2. **第二层：看门狗** —— 主流程若异常中断，300 秒后仍未写入 `SUCCESS` 即自动回滚。
3. **第三层：人工回滚** —— 备份与命令：

```sh
# 路由器本地备份目录
ls -l /root/dae-rollback/
# 恢复旧版（1.1.0）
/etc/init.d/dae stop
cp /root/dae-rollback/dae.rollback.bin /usr/bin/dae && chmod 0755 /usr/bin/dae
cp /root/dae-rollback/config.dae.rollback /etc/dae/config.dae
cp /root/dae-rollback/uci-dae.rollback /etc/config/dae
cp /root/dae-rollback/init.d-dae.rollback /etc/init.d/dae && chmod 0755 /etc/init.d/dae
mkdir -p /var/log/dae
/etc/init.d/dae start
```

容器内另存有一份完全相同的旧二进制（sha256 `40c2a8f9…`），可作为最终兜底。

---

## 六、升级后验收清单

```sh
dae --version                      # 应为 v2.1.1
/etc/init.d/dae status             # running
pgrep -f "/usr/bin/dae run"        # 进程存在
ls -d /sys/fs/bpf/dae              # eBPF pin 已建立
ls -l /proc/$(pgrep -f "/usr/bin/dae run" | head -1)/fd | grep bpf   # 持有 bpf map/prog
tail -20 /var/log/dae/dae.log      # 无 panic/fatal，代理日志正常
apk list -I | grep dae             # 包版本为 2.1.1-r1
ls -l /etc/dae/config.dae          # 权限仍为 0600，内容未被改动
```
