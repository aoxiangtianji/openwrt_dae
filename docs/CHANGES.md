# 详细修改列表 —— dae 1.1.0 → 2.1.1 @ 10.10.100.1

> 执行时间：2026-10-10 04:02 ~ 04:03 (CST)
> 执行方式：`apk` 包管理升级（无人值守脚本 + 看门狗 + 自动回滚，全程未失联）
> 原则：**最小化修改** —— 除 dae 二进制本身外，路由器上没有任何文件被改变

---

## 一、交付物

### 1.1 安装包（主交付）

| 项目 | 值 |
| --- | --- |
| 文件名 | `dae-2.1.1-r1.apk` |
| 大小 | 11,793,147 字节（11.25 MiB） |
| SHA256 | `36405861bb3cf5188cd1411c9b5fc5ec73787beb4b13ed3663e034af98b357dc` |
| 架构 | `aarch64_cortex-a53` |
| 下载 | https://github.com/aoxiangtianji/openwrt_dae/releases/download/dae-v2.1.1-arm64/dae-2.1.1-r1.apk |
| 构建 | GitHub Actions run `37983551869`，commit `717a5bf9` |

### 1.2 其他产物（备用）

| 文件 | 大小 | 用途 |
| --- | --- | --- |
| `dae-v2.1.1-linux-arm64.tar.gz` | 16.44 MB | 独立二进制包（含 init 脚本、UCI、示例配置、geo 数据、一键部署脚本） |
| `dae-v2.1.1-linux-arm64.zip` | 16.12 MB | 同上，zip 格式 |
| `SHA256SUMS` | — | 校验值 |

### 1.3 构建工程仓库

- https://github.com/aoxiangtianji/openwrt_dae （public）
- 本地工程：`work/dae-immortalwrt/`

---

## 二、路由器上的实际修改（逐条）

### 2.1 包升级（唯一的功能性修改）

```sh
apk add --allow-untrusted /tmp/dae-2.1.1-r1.apk
```

实际执行结果：

```
(1/1) Upgrading dae (1.1.0-r1 -> 2.1.1-r1)
  Executing dae-2.1.1-r1.post-upgrade
OK: 191.4 MiB in 351 packages
```

- **变更项：1 个**（dae 包版本）
- **新增依赖：0 个**
- **移除依赖：0 个**
- **其他包被动到：0 个**

### 2.2 文件级前后对比（逐字节校验）

| 路径 | 升级前 sha256(前16) | 升级后 sha256(前16) | 大小变化 | 结论 |
| --- | --- | --- | --- | --- |
| `/usr/bin/dae` | `40c2a8f9ef36d22f` | `8fb1906feb225c17` | 26,668,712 → 32,946,305 B | **★ 唯一变化** |
| `/etc/init.d/dae` | `da6d97a7d57e3aac` | `da6d97a7d57e3aac` | 1447 B 不变 | 完全未变 |
| `/etc/config/dae` | `6f6790e38b761ede` | `6f6790e38b761ede` | 135 B 不变 | 完全未变 |
| `/etc/dae/config.dae` | `7f7854ecf2aa501b` | `7f7854ecf2aa501b` | 3069 B 不变 | 完全未变 |
| `/etc/dae/example.dae` | `bb2531e9647b2048` | `bb2531e9647b2048` | 15207 B 不变 | 完全未变 |
| `/lib/upgrade/keep.d/dae` | `ec00a2902a17c727` | `ec00a2902a17c727` | 20 B 不变 | 完全未变 |

### 2.3 权限（零漂移）

| 路径 | 升级前 | 升级后 |
| --- | --- | --- |
| `/usr/bin/dae` | 0755 | 0755 |
| `/etc/init.d/dae` | 0755 | 0755 |
| `/etc/config/dae` | 0600 | 0600 |
| `/etc/dae/config.dae` | 0600 | 0600 |
| `/etc/dae/example.dae` | 0600 | 0600 |
| `/lib/upgrade/keep.d/dae` | 0644 | 0644 |

### 2.4 服务操作

```sh
/etc/init.d/dae stop
mkdir -p /var/log/dae      # 原 init 脚本 stop 时会 rm -rf /var/log/dae，启动前必须补回
/etc/init.d/dae start
```

- 中断时长：约 1~3 秒（eBPF 卸载 → 重新加载）
- 未使用 `restart`：因为原 init 脚本的 `stop_service()` 会删除日志目录，
  分步执行可在启动前把目录建回，避免 dae 因日志目录缺失而启动失败
- 开机自启：`/etc/rc.d/S99dae` 保持存在（由 postinst 幂等重建）

### 2.5 apk 数据库

| 包名 | 升级前 | 升级后 |
| --- | --- | --- |
| `dae` | `1.1.0-r1` | **`2.1.1-r1`** |
| `dae-geoip` | `1.1.0-r1` | 不变 |
| `dae-geosite` | `1.1.0-r1` | 不变 |
| `luci-app-dae` | `26.159.10282~bf7abde` | 不变 |
| `luci-i18n-dae-zh-cn` | `26.159.10282~bf7abde` | 不变 |

### 2.6 新增的文件（非破坏性，可随时删除）

| 路径 | 说明 | 是否建议保留 |
| --- | --- | --- |
| `/root/dae-rollback/dae.rollback.bin` | 旧版 1.1.0 二进制备份（26,668,712 B） | 建议保留一段时间 |
| `/root/dae-rollback/config.dae.rollback` | 升级前 dae 配置备份 | 建议保留 |
| `/root/dae-rollback/uci-dae.rollback` | 升级前 UCI 配置备份 | 建议保留 |
| `/root/dae-rollback/init.d-dae.rollback` | 升级前 init 脚本备份 | 建议保留 |
| `/root/dae-rollback/upgrade.log` | 升级全过程日志 | 可保留查阅 |
| `/root/dae-rollback/status` | 升级结果标记（`SUCCESS:...`） | 可删除 |
| `/root/upgrade-on-router.sh` | 无人值守升级 + 自动回滚脚本 | 建议保留，后续升级可复用 |
| `/var/cache/apk/APKINDEX.*.tar.gz` | apk 源索引缓存（升级时生成） | apk 自行管理 |

### 2.7 已清理的临时文件

- `/tmp/dae-2.1.1-r1.apk`（上传的安装包，11.8 MB）
- `/tmp/dae-v211-test`（用于配置兼容性验证的官方二进制，33 MB）
- `/tmp/dae-pkg-check`、`/tmp/dae-pkg-check2`、`/tmp/pk3`（包内容解包校验目录）

---

## 三、明确的「未修改」清单（最小化修改的证据）

以下内容**完全未被触碰**：

- ✅ `/etc/dae/config.dae` —— 你的 dae 配置（订阅、节点、分流规则）逐字节未变
- ✅ `/etc/config/dae` —— UCI 配置逐字节未变
- ✅ `/etc/init.d/dae` —— 服务脚本逐字节未变（官方脚本已支持 validate / GOMEMLIMIT / hot_reload，无需替换）
- ✅ `/etc/dae/example.dae`、`/lib/upgrade/keep.d/dae` —— 逐字节未变
- ✅ `dae-geoip` / `dae-geosite` —— geo 数据包未动（新包刻意不含 geo 文件，避免与它们冲突）
- ✅ `luci-app-dae` / `luci-i18n-dae-zh-cn` —— LuCI 界面未动（其依赖 `dae` 无版本约束，升级不受影响）
- ✅ 网络配置 —— `/etc/config/network`、`firewall`、Nikki、SmartDNS 等全部未动
- ✅ 内核、固件、其他全部软件包 —— 未动
- ✅ 未安装任何新软件、未新增任何内核模块

---

## 四、验证证据

### 4.1 版本与服务

```
dae version v2.1.1
go runtime go1.26.8-X:newinliner,simd linux/arm64
Copyright (c) 2022-2026 @daeuniverse
/etc/init.d/dae status → running
dae run 进程 PID 17189
```

### 4.2 eBPF

```
/sys/fs/bpf/ 下存在 dae pin 目录
dae 进程持有 45 个 bpf 句柄（bpf-map / bpf-prog）
日志：Successfully created Netkit device pair dae0 <-> dae0peer
      Loading routing rules into kernel space (BPF)...
      Routing match set len: 20/1024
      Bind to LAN: br-lan.10
      Control plane built in 4.75s / Total startup time: 4.83s
```

> 说明：v2.1.1 改用 **Netkit device pair** 机制（v1.1.0 为 tc/eBPF 方案），
> 因此路由器上未安装的 `tc` 命令不再需要，日志格式也从 `level=info msg=...`
> 变为 ` INFO ...`，属正常变化。

### 4.3 日志健康度

- `ERROR` 行数：**0**
- `WARN` 行数：**0**

### 4.4 真实网络验证（从容器发起，流量正是经 dae 分流）

| 目标 | 结果 |
| --- | --- |
| `https://api.github.com/` | HTTP **200** |
| `https://www.google.com/generate_204` | HTTP **204** |

Google 可达即证明代理链路（dae → 出口）工作正常。

### 4.5 升级前配置兼容性预验证（零风险）

升级前曾用官方 v2.1.1 二进制在 `/tmp` 对现有配置做校验：

```
/tmp/dae-v211-test validate -c /etc/dae/config.dae   →  退出码 0
```

即跨大版本（1.1.0 → 2.1.1）配置**完全兼容**，无需任何改动。

---

## 五、回滚方式（三层）

### 第一层：脚本自动回滚（本次未触发）

健康检查（服务/进程/版本/bpf pin/日志）任一不通过即自动恢复旧二进制并重启。

### 第二层：看门狗（本次未触发）

主流程若异常中断，300 秒后仍未写入 `SUCCESS` 标记则自动回滚。

### 第三层：人工回滚

```sh
/etc/init.d/dae stop
cp /root/dae-rollback/dae.rollback.bin /usr/bin/dae && chmod 0755 /usr/bin/dae
cp /root/dae-rollback/config.dae.rollback /etc/dae/config.dae
cp /root/dae-rollback/uci-dae.rollback /etc/config/dae
cp /root/dae-rollback/init.d-dae.rollback /etc/init.d/dae && chmod 0755 /etc/init.d/dae
mkdir -p /var/log/dae
/etc/init.d/dae start
dae --version      # 应显示 dae version 1.1.0
```

容器内另存一份完全相同的旧二进制（sha256 `40c2a8f9…`），作为最终兜底。

---

## 六、工程仓库侧的变更（GitHub）

### 6.1 新建仓库

`aoxiangtianji/openwrt_dae`（原为空仓库，本次初始化）

### 6.2 提交历史

| commit | 内容 |
| --- | --- |
| `5254c73` | 初始工程：workflow、OpenWrt 包、构建脚本、部署脚本、文档 |
| `942f841` | fix(ci)：push 触发时 `inputs.*` 为空导致构建失败 |
| `bf27637` | fix(ci)：boolean 输入的 `null == false` 类型陷阱导致 apk/Release 被跳过；新增升级脚本与 runbook |
| `5379a7c` | fix(pkg)：`files/` → `rootfs/`；`example.dae` 权限对齐 0600 |
| `717a5bf` | fix(pkg)：不再手写 `keep.d/dae`，交由构建系统生成（消除重复行） |

### 6.3 工程文件清单

```
.github/workflows/build-dae.yml     GitHub Actions（workflow_dispatch + push 自动构建）
openwrt/package/dae/Makefile        OpenWrt 包定义（预编译二进制打包）
openwrt/package/dae/rootfs/         包内文件（与官方包布局严格一致）
  ├── etc/init.d/dae                procd 服务脚本（原版，未改动）
  ├── etc/config/dae                UCI 配置（原版）
  └── etc/dae/example.dae           示例配置（原版）
openwrt/optional/                   可选增强件（不参与打包）
  ├── init.d-dae-enhanced           强化版 procd 脚本（支持可调 GOMEMLIMIT/日志轮转/热重载）
  └── config.dae.example            路由器适配版配置模板
scripts/
  ├── build-dae.sh                  构建 aarch64 静态二进制（含 eBPF）
  ├── build-apk.sh                  用 ImmortalWrt SDK 打 .apk
  ├── build-with-docker.sh          Docker 交叉编译
  ├── upgrade-on-router.sh          无人值守升级 + 自动回滚 + 看门狗
  ├── install-on-router.sh          路由器一键安装
  └── deploy-from-host.sh           主机侧 SSH 部署
docker/Dockerfile.build             交叉编译容器（Go 1.26 + clang-15/llvm-15）
docs/DEPLOY.md                      部署与运维指引
docs/DEPLOY-RUNBOOK.md              本次真机部署 runbook（风险/步骤/回滚）
docs/CHANGES.md                     本文件
```

---

## 七、过程中的关键发现（供后续参考）

1. **apk-tools 3.0.5 没有 `mkpkg`** —— 路由器本地无法生成 apk，必须用 ImmortalWrt SDK（x86_64）构建。
2. **包的"文件集合"必须与官方包一致** —— apk 升级时会删除"属于旧包但新包未提供"的文件；若新包不含 `/etc/init.d/dae` 等，升级后服务脚本会消失。
3. **不能重复提供 geo 文件** —— geoip/geosite 由 `dae-geoip`/`dae-geosite` 包提供，dae 包再提供会造成文件冲突。
4. **`keep.d/dae` 不要手写** —— OpenWrt 构建系统会自动把"不在默认保留路径下的 conffile"（如 `/etc/dae/config.dae`）写入 keep.d；手工再提供一份会导致内容重复两行。
5. **GitHub 表达式陷阱** —— push 触发时 `inputs.*` 为 `null`，而 `null == false` 会被判为 `true`，导致 boolean 开关失效；改用 `choice`（字符串）类型即可。
6. **原 init 脚本 stop 会删日志目录** —— `stop_service() { rm -rf "$LOG_DIR"; }`，升级重启前需 `mkdir -p /var/log/dae`。
7. **本机 go 版本低于 dae 要求** —— dae v2.x 要求 Go 1.26（`go.mod` 为 `go 1.26.0`），本地容器为 go1.24.4 且无 clang，故一律走 GitHub Actions 构建。
8. **运维通道冗余** —— 这台路由器同时是唯一运维通道；实测 5 条可免密登录的入口
   （`10.10.100.1` / `10.10.10.1` / `10.10.5.1` / `10.1.2.20` / `192.168.66.2`），
   其中仅 `10.10.100.1` 属于 dae 绑定的 `br-lan.10`，其余 4 条不受 dae 故障影响。
9. **GitHub 直连不稳** —— `ssh.github.com:443` 与直连 22 端口均会间歇性被切断；
   本次通过路由器上的 SOCKS5 代理（`10.10.100.1:7891`）+ Python 隧道作为备用推送通道，
   并采用多通道轮换重试，最终推送全部成功。
