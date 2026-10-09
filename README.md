# dae for ImmortalWrt · MediaTek Filogic (aarch64_cortex-a53)

为 **ImmortalWrt 25.12.x（OpenWrt 25.x 代码树，apk 包管理器）** 上的
**MediaTek Filogic（ARM64 双核）** 路由器构建并打包 [dae](https://github.com/daeuniverse/dae)。

一次 `workflow_dispatch` 即可自动产出：

| 产物 | 说明 |
| --- | --- |
| `dae-<版本>-linux-arm64.tar.gz` / `.zip` | 独立静态二进制包：`dae` + procd 启动脚本 + UCI 模板 + `config.dae` 示例 + 一键部署脚本 |
| `dae-<版本>-r1.apk` | OpenWrt / ImmortalWrt 安装包（ImmortalWrt 官方 SDK 打包，可直接 `apk add`） |
| `SHA256SUMS` | 校验值 |

默认构建的版本是 **dae v2.1.1（当前上游最新 release）**；如需 v2.0.0（含 RFC 8767
乐观缓存特性引入版本），在触发 workflow 时把 `dae_ref` 填成 `v2.0.0` 即可。

---

## 目录结构

```
.
├── .github/workflows/build-dae.yml        # GitHub Actions 自动化构建（手动触发）
├── openwrt/package/dae/                   # OpenWrt / ImmortalWrt 软件包
│   ├── Makefile                           #   预编译二进制打包（不在 SDK 内编译 Go）
│   └── files/
│       ├── etc/init.d/dae                 #   procd 服务脚本（校验/热重载/日志/GOMEMLIMIT）
│       ├── etc/config/dae                 #   UCI 配置模板
│       ├── etc/dae/config.dae             #   dae 配置示例（权限 0600）
│       └── usr/share/dae/                 #   geoip.dat / geosite.dat 安装位置
├── scripts/
│   ├── build-dae.sh                       # 构建 aarch64 静态二进制（含 eBPF 字节码）
│   ├── build-apk.sh                       # 用 ImmortalWrt SDK 打包 .apk
│   ├── build-with-docker.sh               # x86 主机上用 Docker 交叉编译
│   ├── install-on-router.sh               # 路由器上执行的一键安装/升级
│   └── deploy-from-host.sh                # 电脑上执行：SSH 上传并平滑升级
├── docker/Dockerfile.build                # 交叉编译容器（Go 1.26 + clang-15/llvm-15）
└── docs/DEPLOY.md                         # 部署与运维详细指引
```

---

## 一、一键构建（GitHub Actions）

1. 把本工程推到 GitHub 仓库（默认分支 `main`）。
2. 打开仓库的 **Actions** 页 → 左侧选择 **“Build dae for ImmortalWrt (aarch64_cortex-a53)”**。
3. 点击右上角 **Run workflow**，**保持默认值**即可，然后点绿色的 Run。
4. 约 5～15 分钟后（首次因下载 SDK 会久一些）：
   - **Artifact**：`dae-v2.1.1-aarch64`，在 workflow 页面底部下载；
   - **Release**：仓库 `Releases` 页会生成 `dae-v2.1.1-arm64` 标签，产物可直接下载。

### 可调参数（Run workflow 面板）

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `dae_ref` | `v2.1.1` | dae 源码 tag / 分支 / commit，想用 v2.0.0 就填 `v2.0.0` |
| `go_version` | `1.26.x` | dae v2.x 要求 Go 1.26，不建议改小 |
| `bpf_target` | `bpfel` | arm64 是小端，只需 bpfel（改了会增加体积） |
| `max_match_set_len` | `1024` | eBPF 规则集上限，调小可省内核内存 |
| `bundle_geodata` | `true` | 是否把 geoip/geosite 数据打进包里（`geoip:cn` 规则必需） |
| `build_apk` | `true` | 是否额外产出 `.apk` 安装包 |
| `immortalwrt_version` | `25.12.0` | 打包 apk 用的 SDK 版本；填 `snapshots` 用快照 SDK |
| `immortalwrt_target` | `mediatek/filogic` | Filogic 平台 |
| `create_release` | `true` | 是否创建/更新 GitHub Release |

---

## 二、部署到路由器（SSH）

### 方式 A：独立二进制包（推荐，最简单）

在电脑上（工程内已有脚本，会自动取最新 Release）：

```sh
./scripts/deploy-from-host.sh root@10.10.10.1
# 或指定本地/远程包
./scripts/deploy-from-host.sh root@10.10.10.1 ./dae-v2.1.1-linux-arm64.tar.gz
```

脚本做的事：下载 → 上传到 `/tmp` → 在路由器上执行 `install.sh`
（备份旧二进制与配置 → 原子替换 `/usr/bin/dae` → 更新 init 脚本 → 权限 0600 →
校验配置 → 重启服务），完成后自动清理临时目录。

手动方式等价于：

```sh
# 1) 上传
scp dae-v2.1.1-linux-arm64.tar.gz root@10.10.10.1:/tmp/

# 2) 路由器上安装 / 升级
ssh root@10.10.10.1
cd /tmp && tar xzf dae-v2.1.1-linux-arm64.tar.gz
cd dae-v2.1.1-linux-arm64 && sh install.sh

# 3) 验证
dae --version
/etc/init.d/dae status
logread -e dae | tail -n 20
```

### 方式 B：apk 安装包（ImmortalWrt 25.x）

```sh
scp dae-2.1.1-r1.apk root@10.10.10.1:/tmp/
ssh root@10.10.10.1
apk add --allow-untrusted /tmp/dae-2.1.1-r1.apk     # 本地包需 --allow-untrusted
```

装好后同样是编辑 `/etc/dae/config.dae` → 启用 → 启动：

```sh
vi /etc/dae/config.dae                 # 填入订阅链接
dae validate -c /etc/dae/config.dae    # 先校验语法
uci set dae.dae.enabled=1 && uci commit dae
/etc/init.d/dae start
```

### 方式 C：只替换二进制（最小改动）

```sh
scp dae root@10.10.10.1:/tmp/dae.new
ssh root@10.10.10.1 '
  /etc/init.d/dae stop
  chmod 0755 /tmp/dae.new
  mv /tmp/dae.new /usr/bin/dae     # mv 原子替换，避免“文本文件忙”
  dae --version
  /etc/init.d/dae start
'
```

### 平滑重启 vs 零中断热重载

| 场景 | 命令 | 影响 |
| --- | --- | --- |
| **改了 `config.dae`** | `/etc/init.d/dae reload` | **零中断**：`dae reload` 通过 SIGUSR1 原地重载，既有连接不断开 |
| 换了 `dae` 二进制 | `/etc/init.d/dae restart` | 必须重启进程才能生效，中断约 1～3 秒（eBPF 会重新加载） |
| 只想停服务 | `/etc/init.d/dae stop` | 进程退出时自行清理 eBPF 挂载与 pin |

`reload` 前会自动执行一次 `dae validate`：**新配置不合法就拒绝重载并保持当前运行状态**，
不会出现“一改配置就断网”。

---

## 三、关键实现细节

| 项目 | 本工程的实现 |
| --- | --- |
| 版本注入 | `-X github.com/daeuniverse/dae/cmd.Version=<版本>`（上游真实路径） |
| 体积裁剪 | `-trimpath -ldflags "-s -w"` + eBPF 对象经 `llvm-strip` 裁剪 |
| 静态链接 | `CGO_ENABLED=0`，产出纯静态二进制，musl 环境直接运行 |
| eBPF 编译 | `clang-15` 编译 `control/`、`trace/` 下的 C 代码，`bpf2go` 内嵌进 Go 二进制 |
| eBPF 子模块 | `control/kern/headers`、`trace/kern/headers`（`daeuniverse/dae_bpf_headers`）必须初始化 |
| 内存优化 | `GOEXPERIMENT=heapminimum512kib,randomizedheapbase64`（v2.1.1 上游默认已含 `newinliner,simd`） |
| 运行时内存 | procd 注入 `GOMEMLIMIT`（默认 256MiB，可 UCI 调整），Go 运行时软上限防 OOM |
| 内核前置条件 | 需要 `/sys/kernel/btf/vmlinux`（CO-RE）；服务脚本启动前检查并给出可读报错 |
| bpffs | 服务脚本自动 `mount -t bpf bpf /sys/fs/bpf`（dae 的 map pin 目录） |
| 配置权限 | `/etc/dae/config.dae` 强制 **0600**（安装即设，启动时再兜底一次） |
| 日志 | 默认交给 `logd`（`logread -e dae`），也可写文件并按大小/个数自动轮转 |
| 开机自启 | `START=95`（网络与防火墙之后），`/etc/init.d/dae enable` 由包脚本自动完成 |

### ⚠️ 已核实的关键事实（与常见资料不同，务必知悉）

1. **ImmortalWrt 25.12 filogic 固件默认开启 BTF**：官方 `config.buildinfo` 中
   `CONFIG_KERNEL_DEBUG_INFO_BTF=y`、`CONFIG_KERNEL_DEBUG_INFO_BTF_MODULES=y`，
   即固件内含 `/sys/kernel/btf/vmlinux`，dae 的 CO-RE eBPF 可正常加载。
   （若自行编译固件，请勿关闭该选项。）
2. **dae 的版本变量路径是 `cmd.Version`**，不是 `version.Version`；写错会导致
   `dae --version` 显示 `unknown`。
3. **dae v2.x 要求 Go 1.26**（`go.mod` 为 `go 1.26.0`，上游 Dockerfile 用
   `golang:1.26-bookworm`），不是 1.24。
4. **上游没有官方 OpenWrt 包仓库**（`daeuniverse/OpenWrt-dae` 不存在），
   因此 OpenWrt/ImmortalWrt 包必须自建 —— 这正是本工程 `openwrt/package/dae` 的作用。
5. **ImmortalWrt 25.12 确实使用 apk**（软件源为 `packages.adb`、包为 `.apk`），
   本工程用官方 SDK 生成的即为 apk 包。
6. dae 默认搜索 geo 数据的路径包含 `/usr/share/dae`，本工程将 `geoip.dat` /
   `geosite.dat` 安装到该目录，并在服务脚本中显式设置 `DAE_LOCATION_ASSET`。

---

## 四、本地 / Docker 构建

### Docker 交叉编译（x86_64 主机即可，无需 QEMU）

```sh
./scripts/build-with-docker.sh                  # 产物：build/out/dae
DAE_REF=v2.0.0 ./scripts/build-with-docker.sh   # 指定版本
```

### 直接在本机构建（需 Linux + Go 1.26 + clang-15 + llvm-15）

```sh
sudo apt install -y clang-15 llvm-15 make git   # Debian/Ubuntu
./scripts/build-dae.sh
```

### 本地打 apk（需先有二进制）

```sh
DAE_BINARY=build/out/dae IW_VERSION=25.12.0 IW_TARGET=mediatek/filogic \
  ./scripts/build-apk.sh                        # 产物：apk/*.apk
```

---

## 五、排障速查

| 现象 | 原因与处理 |
| --- | --- |
| `dae --version` 显示 `unknown` | 构建时未注入 `-X .../cmd.Version`，用本工程脚本构建即可避免 |
| 启动报 `BTF not found` / eBPF 加载失败 | 内核未开 `CONFIG_DEBUG_INFO_BTF`；换用官方 filogic 固件 |
| `/sys/fs/bpf` 为空 / 权限错误 | bpffs 未挂载；`mount -t bpf bpf /sys/fs/bpf`（脚本已自动处理） |
| `apk add` 报签名错误 | 本地包需加 `--allow-untrusted` |
| 服务起不来但配置看着没问题 | `dae validate -c /etc/dae/config.dae` 看具体报错；`logread -e dae` |
| 内存吃紧 / 被 OOM | 调小 `uci set dae.dae.gomemlimit=128MiB`，并降低 `bpf_conn_state_map_size`、`max_cache_size` |
| 想把 LAN 流量也代理 | `config.dae` 里设置 `lan_interface: br-lan`（模板已填） |

更多部署与运维细节见 [`docs/DEPLOY.md`](docs/DEPLOY.md)。

---

## 许可

本打包工程仅包含构建脚本与服务集成，dae 本体版权归
[daeuniverse](https://github.com/daeuniverse/dae) 所有，遵循 **AGPL-3.0**。
