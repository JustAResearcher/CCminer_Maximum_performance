#!/bin/bash
#
# Build optimized ccminer-yescrypt on Linux for HiveOS
#
# Prerequisites (on Ubuntu/Debian):
#   sudo apt-get install build-essential automake autoconf libcurl4-openssl-dev \
#     libjansson-dev libssl-dev cuda-toolkit
#
# Run this from the ccmineryescrypt source directory:
#   chmod +x build-linux.sh
#   ./build-linux.sh
#

set -e

echo "=== Building optimized ccminer-yescrypt for HiveOS ==="

# Check CUDA
command -v nvcc >/dev/null 2>&1 || { echo "ERROR: nvcc not found. Install CUDA Toolkit."; exit 1; }
NVCC_VER=$(nvcc --version | grep release | sed 's/.*release //' | sed 's/,.*//')
echo "CUDA: $NVCC_VER"

# Detect GPU for architecture targeting
CUDA_ARCH=""
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
    if [[ -n "$GPU_CC" ]]; then
        CUDA_ARCH="--with-cuda=/usr/local/cuda"
        echo "GPU detected: SM $GPU_CC"
    fi
fi

# Run autotools
if [[ ! -f configure ]]; then
    echo "Running autogen.sh..."
    ./autogen.sh
fi

# Configure with optimizations
echo "Configuring..."
./configure \
    CFLAGS="-O3 -march=native" \
    CXXFLAGS="-O3 -march=native" \
    --with-cuda=/usr/local/cuda \
    --with-nvml=libnvidia-ml

# Build
echo "Building (this may take 10+ minutes)..."
make -j$(nproc)

# Strip debug symbols
strip ccminer

echo ""
echo "=== Build complete ==="
ls -la ccminer
echo ""
echo "Copy ./ccminer to your HiveOS package directory."
