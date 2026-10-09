#!/usr/bin/env bash
# =============================================================================
# 在 x86_64 主机上用 Docker 交叉编译 aarch64 版 dae（Docker 交付方式）
#
# 用法：
#   ./scripts/build-with-docker.sh                 # 构建 v2.1.1
#   DAE_REF=v2.0.0 ./scripts/build-with-docker.sh  # 指定其它版本
#
# 产物：build/out/dae（aarch64 静态二进制，eBPF 字节码已内嵌）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE="${IMAGE:-dae-builder:1.26}"
DAE_REF="${DAE_REF:-v2.1.1}"
GOARCH="${GOARCH:-arm64}"
BPF_TARGET="${BPF_TARGET:-bpfel}"

command -v docker >/dev/null 2>&1 || {
  echo "缺少 docker。请先安装 Docker 后重试。" >&2
  exit 1
}

echo "[docker-build] 构建镜像 $IMAGE ..."
docker build -t "$IMAGE" -f "$ROOT_DIR/docker/Dockerfile.build" "$ROOT_DIR"

mkdir -p "$ROOT_DIR/build/out"

echo "[docker-build] 开始交叉编译：DAE_REF=$DAE_REF GOARCH=$GOARCH BPF_TARGET=$BPF_TARGET"
docker run --rm \
  -v "$ROOT_DIR":/work \
  -w /work \
  -e DAE_REF="$DAE_REF" \
  -e GOARCH="$GOARCH" \
  -e BPF_TARGET="$BPF_TARGET" \
  -v dae-go-mod-cache:/root/go/pkg/mod \
  -v dae-go-build-cache:/root/.cache/go-build \
  "$IMAGE" bash scripts/build-dae.sh

echo "[docker-build] 完成：$ROOT_DIR/build/out/dae"
ls -lh "$ROOT_DIR/build/out/dae"
file "$ROOT_DIR/build/out/dae" 2>/dev/null || true
