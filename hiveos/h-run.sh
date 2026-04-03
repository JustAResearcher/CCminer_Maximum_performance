#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
[[ -f "$SCRIPT_DIR/h-manifest.conf" ]] && source "$SCRIPT_DIR/h-manifest.conf"

POOL="${CUSTOM_URL:-${CUSTOM_POOL:-stratum+tcp://pool.luckypepe.org:3333}}"
USER="${CUSTOM_TEMPLATE:-${CUSTOM_WALLET:-lpep1qk6yql0t9sp3mfjkx0spmh0g39xkjkrfn7305pv.$(hostname)}}"
PASS="${CUSTOM_PASS:-x}"
ALGO="${CUSTOM_ALGO:-yescryptR32}"

MINER_ARGS="-a $ALGO -o $POOL -u $USER -p $PASS -b 0.0.0.0:${CUSTOM_API_PORT:-4068} --no-color"
[[ -n "$CUSTOM_USER_CONFIG" ]] && MINER_ARGS="$MINER_ARGS $CUSTOM_USER_CONFIG"

echo "Starting ccminer-yescrypt..."
echo "  Algo: $ALGO"
echo "  Pool: $POOL"
echo "  User: $USER"
echo "  Args: $MINER_ARGS"
echo ""
exec "$SCRIPT_DIR/ccminer" $MINER_ARGS
