#!/usr/bin/env bash
# =============================================================================
# 用 ImmortalWrt 官方 SDK 把已构建好的 dae 二进制打包成 .apk（OpenWrt 25.x / apk）
#
# 采用 “预编译二进制打包” 方式：SDK 内不编译 Go 代码，只负责打包，
# 因此无需在 SDK 里下载 Go 工具链，构建速度快、结果可控。
#
# 环境变量：
#   DAE_VERSION   版本号（默认 2.1.1，不带 v）
#   DAE_BINARY    已构建好的 aarch64 二进制路径（必填）
#   IW_VERSION    ImmortalWrt 版本目录，如 25.12.0；填 snapshots 用快照 SDK
#   IW_TARGET     target，如 mediatek/filogic
#   APK_OUT       产物输出目录（默认 <repo>/apk）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DAE_VERSION="${DAE_VERSION:-2.1.1}"
DAE_VERSION="${DAE_VERSION#v}"
IW_VERSION="${IW_VERSION:-25.12.0}"
IW_TARGET="${IW_TARGET:-mediatek/filogic}"
DAE_BINARY="${DAE_BINARY:-$ROOT_DIR/build/out/dae}"
APK_OUT="${APK_OUT:-$ROOT_DIR/apk}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/build/sdk}"

log() { printf '\033[1;36m[apk-build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[apk-build][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$DAE_BINARY" ] || die "找不到二进制：$DAE_BINARY（请先运行 scripts/build-dae.sh）"
mkdir -p "$WORK_DIR" "$APK_OUT"

target_flat="$(echo "$IW_TARGET" | tr '/' '-')"

# --- 1. 定位 SDK 下载地址 ---------------------------------------------------
case "$IW_VERSION" in
  snapshot|snapshots|SNAPSHOT|SNAPSHOTS)
    bases="
      https://dl.wrt.moe/snapshots/targets/$IW_TARGET/
      https://mirrors.ustc.edu.cn/immortalwrt/snapshots/targets/$IW_TARGET/
    "
    ;;
  *)
    bases="
      https://mirrors.ustc.edu.cn/immortalwrt/releases/$IW_VERSION/targets/$IW_TARGET/
      https://downloads.immortalwrt.org/releases/$IW_VERSION/targets/$IW_TARGET/
      https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/$IW_VERSION/targets/$IW_TARGET/
    "
    ;;
esac

SDK_URL=""
for base in $bases; do
  log "探测 SDK 目录：$base"
  sdk_name="$(curl -fsSL --retry 2 --connect-timeout 20 "$base" 2>/dev/null \
    | grep -oE 'immortalwrt-sdk-[^"<>]*\.tar\.zst' | head -n 1 || true)"
  if [ -n "$sdk_name" ]; then
    SDK_URL="${base}${sdk_name}"
    log "找到 SDK：$sdk_name"
    break
  fi
done
[ -n "$SDK_URL" ] || die "未能在任何镜像找到 ImmortalWrt SDK（版本=$IW_VERSION, target=$IW_TARGET）"

# --- 2. 下载并解压 SDK -----------------------------------------------------
sdk_archive="$WORK_DIR/$(basename "$SDK_URL")"
if [ ! -f "$sdk_archive" ]; then
  log "下载 SDK（约 100~400MB，仅首次需要）..."
  curl -fL --retry 3 --connect-timeout 30 -o "$sdk_archive.part" "$SDK_URL"
  mv "$sdk_archive.part" "$sdk_archive"
fi

SDK_DIR="$WORK_DIR/$target_flat"
if [ ! -d "$SDK_DIR" ]; then
  log "解压 SDK ..."
  mkdir -p "$SDK_DIR"
  if tar --zstd -tf "$sdk_archive" >/dev/null 2>&1; then
    tar --zstd -xf "$sdk_archive" -C "$SDK_DIR" --strip-components=1
  else
    zstd -dc "$sdk_archive" | tar -xf - -C "$SDK_DIR" --strip-components=1
  fi
fi
log "SDK 就绪：$SDK_DIR"

# --- 3. 放入软件包与预编译产物 ---------------------------------------------
PKG_DIR="$SDK_DIR/package/dae"
rm -rf "$PKG_DIR"
cp -r "$ROOT_DIR/openwrt/package/dae" "$PKG_DIR"
mkdir -p "$PKG_DIR/prebuilt"
cp "$DAE_BINARY" "$PKG_DIR/prebuilt/dae"
chmod 0755 "$PKG_DIR/prebuilt/dae"

# 注意：不把 geoip.dat / geosite.dat 塞进 dae 包 —— 它们由独立的
# dae-geoip / dae-geosite 包提供，重复提供会导致 apk 文件冲突。

# --- 4. 编译软件包 ---------------------------------------------------------
[ -f "$SDK_DIR/.config" ] || ( cd "$SDK_DIR" && make defconfig )

log "开始打包（make package/dae/compile）..."
( cd "$SDK_DIR" && make package/dae/compile V=s DAE_VERSION="$DAE_VERSION" )

# --- 5. 收集产物 -----------------------------------------------------------
found=0
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  cp "$pkg" "$APK_OUT/"
  log "产物：$APK_OUT/$(basename "$pkg")"
  found=1
done < <(find "$SDK_DIR/bin/packages" -type f \( -name 'dae_*.apk' -o -name 'dae-*.apk' \
                                        -o -name 'dae_*.ipk' -o -name 'dae-*.ipk' \) 2>/dev/null)

[ "$found" = "1" ] || die "打包结束但未在 $SDK_DIR/bin/packages 下找到 dae 包"

( cd "$APK_OUT" && sha256sum ./*.apk ./*.ipk > SHA256SUMS 2>/dev/null || true )
log "APK 打包完成，产物目录：$APK_OUT"
ls -lh "$APK_OUT"
