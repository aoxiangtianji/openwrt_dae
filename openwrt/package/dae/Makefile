#
# dae - 基于 eBPF 的高性能透明代理，OpenWrt / ImmortalWrt 软件包
#
# 打包方式：预编译二进制打包（prebuilt）
#   二进制由 GitHub Actions 用 dae 官方工具链（Go 1.26 + clang-15/llvm-15）
#   交叉编译为 aarch64 静态可执行文件，eBPF 字节码已内嵌，因此本包不在
#   OpenWrt 构建系统内编译 Go，只负责打包。
#
# 【重要】本包的文件集合与 ImmortalWrt 官方 dae 包（dae-1.1.0-r1）严格一致：
#   usr/bin/dae、etc/init.d/dae、etc/config/dae、etc/dae/example.dae、
#   lib/upgrade/keep.d/dae
#   原因：apk 升级时“属于旧包但新包未提供的文件”会被删除。若新包缺少
#   /etc/init.d/dae 等文件，升级后服务脚本会消失。因此这里的文件集合必须完整。
#
# 同时本包“不”包含 geoip.dat / geosite.dat：那两份数据由独立的
# dae-geoip / dae-geosite 包提供，若本包重复提供会造成文件冲突。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=dae
# 版本号由构建命令传入（make package/dae/compile DAE_VERSION=2.1.1）
PKG_VERSION:=$(if $(DAE_VERSION),$(DAE_VERSION),2.1.1)
PKG_RELEASE:=1

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=aoxiangtianji <https://github.com/aoxiangtianji>

# 预编译模式：不走下载与源码编译流程
PKG_SOURCE:=
PKG_SOURCE_PROTO:=
PKG_SOURCE_URL:=

include $(INCLUDE_DIR)/package.mk

define Package/dae
  SECTION:=net
  CATEGORY:=Network
  TITLE:=eBPF-based high-performance transparent proxy (dae)
  URL:=https://github.com/daeuniverse/dae
  # 与原包（dae-1.1.0-r1）保持完全一致的依赖，避免升级时依赖关系发生漂移
  DEPENDS:=ca-bundle kmod-sched-bpf kmod-sched-core kmod-veth kmod-xdp-sockets-diag libc
endef

define Package/dae/description
 dae（goose）是基于 eBPF 的高性能透明代理：直连流量在内核直接转发，不经过
 用户态，因此直连方向几乎无性能损耗与额外资源占用。

 本包为 MediaTek Filogic（aarch64_cortex-a53）预编译版本，eBPF 字节码已内嵌，
 纯静态链接（CGO_ENABLED=0），可直接在 musl 环境运行。

 运行前提：内核需开启 CONFIG_DEBUG_INFO_BTF（ImmortalWrt 25.12 filogic 固件
 默认开启，固件内含 /sys/kernel/btf/vmlinux），并已挂载 bpffs。
endef

# 与原包一致：保护用户配置在升级/卸载流程中不被覆盖
define Package/dae/conffiles
/etc/config/dae
/etc/dae/config.dae
endef

# --- 预编译产物准备 ---------------------------------------------------------
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./prebuilt/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
	@echo "dae: 二进制为预编译产物，跳过编译步骤"
endef

# --- 安装（文件集合与官方包一致）--------------------------------------------
define Package/dae/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/dae $(1)/usr/bin/dae

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/dae $(1)/etc/init.d/dae

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/dae $(1)/etc/config/dae

	$(INSTALL_DIR) $(1)/etc/dae
	$(INSTALL_DATA) ./files/etc/dae/example.dae $(1)/etc/dae/example.dae

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/dae $(1)/lib/upgrade/keep.d/dae
endef

# 安装后仅注册开机自启（幂等），不启动、不重启服务：
# 升级场景下 apk 替换文件时运行中的进程仍持有旧 inode，服务不会中断；
# 新二进制需要生效时由运维人员显式执行 /etc/init.d/dae restart。
define Package/dae/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/dae enable 2>/dev/null || true
}
exit 0
endef

# 卸载/升级前不做任何动作：避免升级流程强制停服造成不必要的断网。
# 卸载后如需彻底停止，可手动执行 /etc/init.d/dae stop。
define Package/dae/prerm
#!/bin/sh
exit 0
endef

define Package/dae/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /var/run/dae.pid /var/run/dae.progress /var/run/dae.abort 2>/dev/null || true
}
exit 0
endef

$(eval $(call BuildPackage,dae))
