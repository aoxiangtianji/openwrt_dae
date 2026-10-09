#!/usr/bin/env bash
# =============================================================================
# 构建 dae（默认最新版 v2.1.1）的 aarch64 静态二进制，含 eBPF 字节码编译
#
# 可用于：GitHub Actions（ubuntu-22.04）/ 本地 Linux / Docker 容器
# 依赖：git、make、go 1.26+、clang-15、llvm-15（llvm-strip）
#
# 常用环境变量：
#   DAE_REF       源码 ref（默认 v2.1.1，最新版）
#   GOARCH        目标架构（默认 arm64）
#   BPF_TARGET    eBPF 字节码目标（默认 bpfel；arm64 为小端）
#   SRC_DIR       源码目录（默认 <repo>/build/src/dae）
#   OUTPUT        输出二进制路径（默认 <repo>/build/out/dae）
#   VERSION       注入的版本号（默认取 DAE_REF）
# =============================================================================
set -euo pipefail

DAE_REPO="${DAE_REPO:-https://github.com/daeuniverse/dae}"
DAE_REF="${DAE_REF:-v2.1.1}"
GOOS="${GOOS:-linux}"
GOARCH="${GOARCH:-arm64}"
CLANG="${CLANG:-clang-15}"
STRIP="${STRIP:-llvm-strip-15}"
BPF_TARGET="${BPF_TARGET:-bpfel}"
MAX_MATCH_SET_LEN="${MAX_MATCH_SET_LEN:-1024}"
GOEXPERIMENT_EXTRA="${GOEXPERIMENT_EXTRA:-newinliner,simd}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="${SRC_DIR:-$ROOT_DIR/build/src/dae}"
OUTPUT="${OUTPUT:-$ROOT_DIR/build/out/dae}"
VERSION="${VERSION:-$DAE_REF}"

log() { printf '\033[1;36m[dae-build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[dae-build][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 依赖检查 ---------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "缺少 git"
command -v go  >/dev/null 2>&1 || die "缺少 go（dae v2.x 需要 Go 1.26+）"
command -v make >/dev/null 2>&1 || die "缺少 make"
command -v "$CLANG" >/dev/null 2>&1 || die "缺少 $CLANG（编译 eBPF 用；Ubuntu: apt install clang-15）"

if command -v "$STRIP" >/dev/null 2>&1; then
  :
else
  log "警告：找不到 $STRIP，eBPF 对象不会被裁剪（最终二进制会更大）"
  STRIP=""
fi

log "Go      : $(go env GOVERSION)"
log "clang   : $("$CLANG" --version | head -n 1)"
log "目标    : $GOOS/$GOARCH，eBPF target=$BPF_TARGET，版本=$VERSION"

# --- 获取源码 ---------------------------------------------------------------
if [ -d "$SRC_DIR/.git" ]; then
  log "复用已有源码目录：$SRC_DIR"
  git -C "$SRC_DIR" fetch --tags --force origin >/dev/null 2>&1 || true
  if ! git -C "$SRC_DIR" checkout --force "$DAE_REF" >/dev/null 2>&1; then
    log "本地找不到 $DAE_REF，尝试重新克隆"
    rm -rf "$SRC_DIR"
  fi
fi

if [ ! -d "$SRC_DIR/.git" ]; then
  log "克隆 $DAE_REPO @ $DAE_REF"
  mkdir -p "$(dirname "$SRC_DIR")"
  if ! git clone --depth 1 --branch "$DAE_REF" "$DAE_REPO" "$SRC_DIR" 2>/dev/null; then
    rm -rf "$SRC_DIR"
    git clone "$DAE_REPO" "$SRC_DIR"
    git -C "$SRC_DIR" checkout "$DAE_REF"
  fi
fi

# eBPF 依赖两个子模块（daeuniverse/dae_bpf_headers），缺少会导致 bpf2go 生成失败
git -C "$SRC_DIR" submodule update --init --recursive
log "源码 commit: $(git -C "$SRC_DIR" rev-parse --short HEAD)"

# --- 构建 -------------------------------------------------------------------
# 注意：不要给 make 加 -j，上游 Makefile 的 ebpf 目标内部（ebpf-sync / clean-ebpf）
# 存在先后依赖，并行会引发竞态。
mkdir -p "$(dirname "$OUTPUT")"

log "第一步：编译 eBPF 字节码并生成 Go 绑定（bpf2go）"
log "第二步：编译 Go 主程序并注入版本信息"
make -C "$SRC_DIR" \
  OUTPUT="$OUTPUT" \
  VERSION="$VERSION" \
  CLANG="$CLANG" \
  STRIP="$STRIP" \
  TARGET="$BPF_TARGET" \
  MAX_MATCH_SET_LEN="$MAX_MATCH_SET_LEN" \
  GOOS="$GOOS" \
  GOARCH="$GOARCH" \
  CGO_ENABLED=0 \
  GOEXPERIMENT="$GOEXPERIMENT_EXTRA" \
  GOFLAGS="-buildvcs=false -modcacherw"

[ -f "$OUTPUT" ] || die "构建结束但未找到产物：$OUTPUT"
log "构建完成：$OUTPUT（$(du -h "$OUTPUT" | cut -f1)）"
log "SHA256：$(sha256sum "$OUTPUT" | cut -d' ' -f1)"
