#!/bin/bash
# Run on HiveOS rig to benchmark different ccminer variants
# Usage: bash bench_variants.sh

MINER_DIR="/hive/miners/custom/ccminer-yescrypt"
POOL="stratum+tcp://pool.luckypepe.org:3333"
WALLET="lpep1qk6yql0t9sp3mfjkx0spmh0g39xkjkrfn7305pv.bench"

echo "=== CCminer Variant Benchmark ==="
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
echo ""

for variant in A B C D; do
    FILE="$MINER_DIR/ccminer_${variant}"
    if [ ! -f "$FILE" ]; then
        echo "Variant $variant: binary not found, skipping"
        continue
    fi
    
    echo -n "Variant $variant: "
    # Run for 30 seconds, capture hashrate
    timeout 35 "$FILE" -a yescryptR32 -o "$POOL" -u "$WALLET" -p x --no-color -d 0 2>&1 | \
        grep "GPU #0:" | tail -1 | sed 's/.*GPU #0: .*, //' 
done

echo ""
echo "=== Done ==="
