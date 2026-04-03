#!/bin/bash
#
# Package ccminer-yescrypt for HiveOS custom miner installation
#
# Usage:
#   1. Build the Linux ccminer binary first (see build-linux.sh)
#   2. Place the 'ccminer' binary in this directory
#   3. Run: ./package.sh
#   4. Upload ccminer-yescrypt.tar.gz to HiveOS
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_NAME="ccminer-yescrypt"

echo "=== Packaging $PACKAGE_NAME for HiveOS ==="

# Check binary exists
if [[ ! -f "$SCRIPT_DIR/ccminer" ]]; then
    echo "ERROR: No 'ccminer' binary found in $SCRIPT_DIR"
    echo "Build it first with build-linux.sh, then copy it here."
    exit 1
fi

# Verify it's a Linux binary
file_type=$(file "$SCRIPT_DIR/ccminer" 2>/dev/null || echo "unknown")
echo "Binary: $file_type"

# Create tarball with the correct structure
# HiveOS expects files directly in the tar root (no subdirectory)
cd "$SCRIPT_DIR"
tar -czf "${PACKAGE_NAME}.tar.gz" \
    ccminer \
    h-manifest.conf \
    h-config.sh \
    h-run.sh \
    h-stats.sh

echo ""
echo "=== Package created: ${PACKAGE_NAME}.tar.gz ==="
echo ""
echo "=== HiveOS Installation ==="
echo ""
echo "Option A: Flight Sheet (recommended)"
echo "  1. Upload ${PACKAGE_NAME}.tar.gz to a web server or GitHub release"
echo "  2. In HiveOS → Flight Sheets → Add New"
echo "  3. Miner: Custom"
echo "  4. Setup Miner Config:"
echo "     - Miner name: ccminer-yescrypt"
echo "     - Installation URL: https://your-server/${PACKAGE_NAME}.tar.gz"
echo "     - Hash algorithm: yescryptR32"
echo "     - Wallet and worker template: %WAL%.%WORKER_NAME%"
echo "     - Pool URL: stratum+tcp://lpepe.suprnova.cc:3635"
echo "     - Pass: x"
echo "     - Extra config arguments: -i 14.66"
echo "       (adjust intensity: RTX 5090=14.66, RTX 4090=14.3, RTX 4070TiS=13.9)"
echo ""
echo "Option B: Manual SCP"
echo "  scp ${PACKAGE_NAME}.tar.gz root@<RIG_IP>:/tmp/"
echo "  ssh root@<RIG_IP>"
echo "  mkdir -p /hive/miners/custom/${PACKAGE_NAME}"
echo "  tar -xzf /tmp/${PACKAGE_NAME}.tar.gz -C /hive/miners/custom/${PACKAGE_NAME}/"
echo "  chmod +x /hive/miners/custom/${PACKAGE_NAME}/ccminer"
echo "  chmod +x /hive/miners/custom/${PACKAGE_NAME}/h-*.sh"
