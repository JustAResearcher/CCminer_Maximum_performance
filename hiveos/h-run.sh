#!/usr/bin/env bash
# h-run.sh — Launch ccminer-yescrypt on HiveOS
#
# HiveOS provides these variables from the Flight Sheet:
#   CUSTOM_URL          — pool stratum URL (e.g., stratum+tcp://pool:port)
#   CUSTOM_TEMPLATE     — wallet.worker template (e.g., %WAL%.%WORKER_NAME%)
#   CUSTOM_PASS         — pool password (e.g., x)
#   CUSTOM_USER_CONFIG  — extra args from "Extra config arguments" field
#   CUSTOM_ALGO         — algorithm name from flight sheet
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source manifest for CUSTOM_API_PORT
[[ -f "$SCRIPT_DIR/h-manifest.conf" ]] && source "$SCRIPT_DIR/h-manifest.conf"

# Default algorithm
ALGO="${CUSTOM_ALGO:-yescryptR32}"

# Default intensity (auto-detected per GPU, but can be overridden in CUSTOM_USER_CONFIG)
# RTX 5090: -i 14.66, RTX 4090: -i 14.3, RTX 4070TiS: -i 13.9

# Build command line
MINER_ARGS=""
MINER_ARGS="$MINER_ARGS -a $ALGO"
MINER_ARGS="$MINER_ARGS -o $CUSTOM_URL"
MINER_ARGS="$MINER_ARGS -u $CUSTOM_TEMPLATE"
MINER_ARGS="$MINER_ARGS -p ${CUSTOM_PASS:-x}"
MINER_ARGS="$MINER_ARGS -b 0.0.0.0:${CUSTOM_API_PORT:-4068}"
MINER_ARGS="$MINER_ARGS --no-color"

# Append any extra config from the flight sheet
[[ -n "$CUSTOM_USER_CONFIG" ]] && MINER_ARGS="$MINER_ARGS $CUSTOM_USER_CONFIG"

echo "Starting ccminer-yescrypt..."
echo "  Algo: $ALGO"
echo "  Pool: $CUSTOM_URL"
echo "  User: $CUSTOM_TEMPLATE"
echo "  API:  0.0.0.0:${CUSTOM_API_PORT:-4068}"
echo "  Args: $MINER_ARGS"
echo ""

exec "$SCRIPT_DIR/ccminer" $MINER_ARGS
