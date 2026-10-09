# dae 部署与运维指引（ImmortalWrt · MediaTek Filogic · aarch64）

本文档面向已经在路由器上跑 ImmortalWrt 25.12.x 的用户，覆盖从部署前检查到
升级回滚的完整流程。

---

## 1. 部署前检查

在路由器上执行：

```sh
# ① 架构必须是 aarch64
uname -m                              # 期望：aarch64

# ② 内核版本与 eBPF 基础能力
uname -r                              # 例如 6.12.91

# ③ 最关键的检查：内核 BTF（dae 的 CO-RE eBPF 依赖它）
ls -l /sys/kernel/btf/vmlinux
#   存在 → 可以正常使用（ImmortalWrt 官方 filogic 固件默认存在）

# ④ bpffs 是否已挂载（未挂载也没关系，服务脚本会自动挂载）
grep bpf /proc/mounts

# ⑤ 可用磁盘空间（dae 二进制 + geo 数据约需 15~30MB）
df -h /overlay /tmp

# ⑥ 是否已有旧版本在运行
/etc/init.d/dae status 2>/dev/null
dae --version 2>/dev/null
```

> **如果 `/sys/kernel/btf/vmlinux` 不存在**，dae 会在加载 eBPF 时报错。
> 请刷入 ImmortalWrt 官方 filogic 固件（其 `config.buildinfo` 中
> `CONFIG_KERNEL_DEBUG_INFO_BTF=y`），或自行编译固件时保持该选项开启。

---

## 2. 部署方式

### 2.1 独立二进制包 + 一键脚本（推荐）

```sh
# 电脑上
scp dae-v2.1.1-linux-arm64.tar.gz root@10.10.10.1:/tmp/

# 路由器上（root）
cd /tmp
tar xzf dae-v2.1.1-linux-arm64.tar.gz
cd dae-v2.1.1-linux-arm64
sh install.sh
```

`install.sh` 的行为：

1. 校验架构（非 aarch64 直接退出）与 BTF 存在性，缺失时给出警告；
2. 停止正在运行的 dae；
3. 备份旧二进制与旧配置到 `/root/dae-backup/`（带时间戳）；
4. **原子替换** `/usr/bin/dae`（先写 `.new` 再 `mv`，避免 `ETXTBSY`）；
5. 更新 `/etc/init.d/dae`；UCI 配置仅在不存在时安装（不覆盖你的设置）；
6. 安装 `geoip.dat` / `geosite.dat` 到 `/usr/share/dae/`；
7. 把 `/etc/dae/config.dae` 权限设为 **0600**；
8. 用 `dae validate` 校验配置，通过后启动服务。

可用参数：`--force-config`（用示例覆盖现有配置，会先备份）、
`--no-start`（只放文件不启动）、`--no-init`（不更新 init 脚本）。

### 2.2 apk 安装包

```sh
scp dae-2.1.1-r1.apk root@10.10.10.1:/tmp/
ssh root@10.10.10.1
apk add --allow-untrusted /tmp/dae-2.1.1-r1.apk
```

包内安装内容：

| 路径 | 权限 | 说明 |
| --- | --- | --- |
| `/usr/bin/dae` | 0755 | 静态二进制（eBPF 字节码已内嵌） |
| `/etc/init.d/dae` | 0755 | procd 服务脚本 |
| `/etc/config/dae` | 0644 | UCI 配置（conffile） |
| `/etc/dae/config.dae` | **0600** | dae 配置示例（conffile） |
| `/usr/share/dae/geoip.dat` | 0644 | 可选，取决于构建参数 |

安装后 `postinst` 会自动 `enable` 开机自启并打印启用步骤。

### 2.3 只替换二进制

见 README 的「方式 C」。要点是用 `mv` 原子替换，然后 `restart`。

---

## 3. 配置与启用

```sh
# 1) 编辑 dae 配置，重点是 subscription 里的订阅链接
vi /etc/dae/config.dae

# 2) 校验语法（务必先校验）
dae validate -c /etc/dae/config.dae

# 3) 打开总开关
uci set dae.dae.enabled=1
uci commit dae

# 4) 启动并设为开机自启
/etc/init.d/dae enable
/etc/init.d/dae start
```

模板里的关键项（`/etc/dae/config.dae`）：

- `lan_interface: br-lan`：把局域网流量纳入代理（网关模式必填）；
- `wan_interface: auto`：自动探测出口接口；
- `optimistic_cache: true` + `optimistic_cache_ttl: 60`：RFC 8767 乐观缓存，
  过期记录在 stale 窗口内直接返回并后台刷新，明显降低首次访问等待；
- `max_cache_size: 4096`：限制 DNS 缓存条目，控制内存；
- `bpf_conn_state_map_size: 65536`：限制 eBPF 连接跟踪表规模，省内核内存。

UCI 侧可调项（`/etc/config/dae`）：

```sh
uci set dae.dae.gomemlimit='128MiB'      # 内存紧张时下调
uci set dae.dae.log_file='/tmp/dae.log'  # 需要落盘日志时（默认走 logd）
uci set dae.dae.extra_args='--disable-pidfile'   # 追加自定义参数
uci commit dae
/etc/init.d/dae reload                   # 零中断热重载
```

---

## 4. 服务管理

| 命令 | 作用 |
| --- | --- |
| `/etc/init.d/dae start` | 校验配置 → 挂载 bpffs → 启动 |
| `/etc/init.d/dae stop` | 停止（进程自行清理 eBPF 挂载与 pin） |
| `/etc/init.d/dae restart` | 重启（更换二进制后必须执行） |
| `/etc/init.d/dae reload` | **热重载配置，不断开既有连接**（失败自动回退 restart） |
| `/etc/init.d/dae status` | 查看运行状态 |
| `/etc/init.d/dae validate` | 仅校验配置语法 |
| `/etc/init.d/dae version` | 显示当前二进制版本 |
| `/etc/init.d/dae enable` / `disable` | 开机自启开关 |

`reload` 的两道保护：

1. 先 `dae validate`，新配置非法 → 拒绝重载，保持当前运行状态；
2. 热重载失败（进程未运行、pid 文件缺失）→ 自动回退为 `restart`。

---

## 5. 日志

默认（UCI `log_file` 为空）由 procd 把 stdout/stderr 转交 `logd`：

```sh
logread -e dae | tail -n 50          # 实时查看
logread -f -e dae                    # 持续跟随
```

如需落盘并自动轮转：

```sh
uci set dae.dae.log_file='/tmp/dae.log'     # /tmp 在内存，推荐
uci set dae.dae.log_maxsize='30'            # 单文件 30MB
uci set dae.dae.log_maxbackups='3'
uci commit dae && /etc/init.d/dae reload
```

> 不建议把日志写到 flash（如 `/etc/dae/dae.log`），长期运行会磨损存储。

调整日志级别：修改 `/etc/dae/config.dae` 中 `global.log_level`
（`error` / `warn` / `info` / `debug` / `trace`），然后 `reload`。

---

## 6. 升级与回滚

### 升级

```sh
sh install.sh            # 会保留现有 /etc/dae/config.dae
/etc/init.d/dae status
dae --version
```

### 回滚到上一版本

`install.sh` 已把旧二进制备份到 `/root/dae-backup/`：

```sh
ls -l /root/dae-backup/
/etc/init.d/dae stop
cp /root/dae-backup/dae.<时间戳> /usr/bin/dae
chmod 0755 /usr/bin/dae
/etc/init.d/dae start
```

### 卸载

```sh
# apk 安装的
apk del dae

# 手动安装的
/etc/init.d/dae stop
/etc/init.d/dae disable
rm -f /usr/bin/dae /etc/init.d/dae /etc/config/dae
rm -rf /etc/dae /usr/share/dae
rm -f /var/run/dae.pid /var/run/dae.progress /var/run/dae.abort
```

---

## 7. 排障

### 7.1 服务启动失败

```sh
/etc/init.d/dae validate          # 看配置问题
logread -e dae | tail -n 30       # 看启动日志
dae run --disable-timestamp -c /etc/dae/config.dae    # 前台跑，看完整报错（Ctrl+C 退出）
```

### 7.2 eBPF 加载失败

| 报错关键字 | 处理 |
| --- | --- |
| `BTF` / `no BTF found` | 内核未开 `CONFIG_DEBUG_INFO_BTF`，换官方固件 |
| `permission denied` / `EPERM` | 未以 root 运行，或 bpffs 未挂载（`mount -t bpf bpf /sys/fs/bpf`） |
| `bad CO-RE relocation` | 内核与编译时头文件差异过大；用与固件同源的内核头文件或升级固件 |

### 7.3 设备上网正常但不走代理

1. 确认 `config.dae` 里 `lan_interface` 与真实 LAN 口一致（`ip link` 查看，
   家宽多为 `br-lan`，部分设备是 `br-lan` 之外的 bridge 名）；
2. 确认客户端网关/DNS 指向路由器；
3. `dae trace` 可查看某条流量的分流决策：

```sh
dae trace --help
```

### 7.4 内存占用高

```sh
uci set dae.dae.gomemlimit='128MiB'; uci commit dae; /etc/init.d/dae reload
# 同时可在 config.dae 下调低：
#   bpf_conn_state_map_size: 32768
#   max_cache_size: 2048
```

### 7.5 校园网 / 高延迟线路

模板中 `sniffing_timeout` 已放宽到 100ms。若首包仍偶发被直连放行，
可继续加大到 `300ms`（代价是首包延迟略增）。

---

## 8. 手工验收清单

部署完成后逐条确认：

```sh
# 1) 版本正确（不能是 unknown）
dae --version

# 2) 配置校验通过
dae validate -c /etc/dae/config.dae && echo OK

# 3) 权限符合规范：应为 -rw------- (600)
ls -l /etc/dae/config.dae

# 4) 服务在运行且被 procd 监管
/etc/init.d/dae status
ps w | grep -c "[d]ae run"

# 5) bpffs 已挂载，eBPF 对象已 pin
mount | grep bpf
ls -l /sys/fs/bpf/

# 6) 内核流量劫持生效（应能看到 tc/ebpf 相关条目）
tc filter show dev br-lan 2>/dev/null | head
tc filter show dev eth1 2>/dev/null | head

# 7) 日志无持续报错
logread -e dae | tail -n 20

# 8) 终端设备实测：国内站点直连、境外站点走代理
#    可在客户端执行：curl -s https://ipinfo.io/ip
```

以上全部通过即部署成功。更换二进制记得 `restart`，只改配置用 `reload`。
