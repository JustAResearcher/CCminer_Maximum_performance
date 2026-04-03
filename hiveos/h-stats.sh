#!/usr/bin/env bash
#
# h-stats.sh — Report ccminer-yescrypt stats to HiveOS dashboard
#
# HiveOS agent sources this script then reads $khs and $stats.
# ccminer uses a text-based API (not JSON), format:
#   summary → NAME=...;VER=...;ALGO=...;KHS=12.34;ACC=100;REJ=0;UPTIME=3600;...
#   threads → GPU=0;KHS=12.34;...
#

# Source manifest for API port
[[ -z "$CUSTOM_API_PORT" ]] && CUSTOM_API_PORT=4068
[[ -f /hive/miners/custom/ccminer-yescrypt/h-manifest.conf ]] &&
  . /hive/miners/custom/ccminer-yescrypt/h-manifest.conf

local_api="127.0.0.1:${CUSTOM_API_PORT}"

# Query ccminer API (text protocol: send command, receive pipe-delimited response)
get_api() {
    local cmd="$1"
    echo "$cmd" | timeout 5 nc "$local_api" ${CUSTOM_API_PORT} 2>/dev/null | tr -d '\0' | head -1
}

# Alternative: use /dev/tcp if nc not available
get_api_tcp() {
    local cmd="$1"
    exec 3<>/dev/tcp/127.0.0.1/${CUSTOM_API_PORT} 2>/dev/null
    if [[ $? -ne 0 ]]; then echo ""; return; fi
    echo "$cmd" >&3
    timeout 5 cat <&3 2>/dev/null | tr -d '\0' | head -1
    exec 3>&-
}

# Try nc first, fall back to /dev/tcp
summary_raw=$(get_api "summary")
[[ -z "$summary_raw" ]] && summary_raw=$(get_api_tcp "summary")

if [[ -z "$summary_raw" ]]; then
    khs=0
    stats='{"hs":[],"hs_units":"khs","temp":[],"fan":[],"uptime":0,"ver":"unknown","ar":[0,0],"algo":""}'
    return 0 2>/dev/null
    exit 0
fi

# Parse ccminer summary response
# Format: NAME=ccminer;VER=1.0;ALGO=yescryptr32;GPUS=1;KHS=13.42;ACC=100;REJ=0;DIFF=0.08;UPTIME=3600;TS=...
parse_val() {
    echo "$summary_raw" | tr ';' '\n' | grep "^$1=" | cut -d= -f2
}

local_khs=$(parse_val "KHS")
local_acc=$(parse_val "ACC")
local_rej=$(parse_val "REJ")
local_algo=$(parse_val "ALGO")
local_ver=$(parse_val "VER")
local_uptime=$(parse_val "UPTIME")
local_gpus=$(parse_val "GPUS")

# Defaults
[[ -z "$local_khs" ]] && local_khs=0
[[ -z "$local_acc" ]] && local_acc=0
[[ -z "$local_rej" ]] && local_rej=0
[[ -z "$local_algo" ]] && local_algo="yescryptr32"
[[ -z "$local_ver" ]] && local_ver="1.0.0"
[[ -z "$local_uptime" ]] && local_uptime=0
[[ -z "$local_gpus" ]] && local_gpus=1

# Query per-GPU stats
threads_raw=$(get_api "threads")
[[ -z "$threads_raw" ]] && threads_raw=$(get_api_tcp "threads")

# Parse per-GPU hashrates (kH/s)
# threads response: GPU=0;BUS=1;CARD=...;TEMP=45;FAN=0;...;KHS=13.42;...|GPU=1;...
gpu_khs_arr="[]"
gpu_temp_arr="[]"
gpu_fan_arr="[]"

if [[ -n "$threads_raw" ]]; then
    # Split by | for multiple GPUs
    IFS='|' read -ra gpu_entries <<< "$threads_raw"
    khs_list=""
    temp_list=""
    fan_list=""
    for entry in "${gpu_entries[@]}"; do
        [[ -z "$entry" ]] && continue
        g_khs=$(echo "$entry" | tr ';' '\n' | grep "^KHS=" | cut -d= -f2)
        g_temp=$(echo "$entry" | tr ';' '\n' | grep "^TEMP=" | cut -d= -f2)
        g_fan=$(echo "$entry" | tr ';' '\n' | grep "^FAN=" | cut -d= -f2)
        [[ -n "$g_khs" ]] && khs_list="${khs_list:+$khs_list,}$g_khs"
        [[ -n "$g_temp" ]] && temp_list="${temp_list:+$temp_list,}$g_temp"
        [[ -n "$g_fan" ]] && fan_list="${fan_list:+$fan_list,}${g_fan:-0}"
    done
    [[ -n "$khs_list" ]] && gpu_khs_arr="[$khs_list]"
    [[ -n "$temp_list" ]] && gpu_temp_arr="[$temp_list]"
    [[ -n "$fan_list" ]] && gpu_fan_arr="[$fan_list]"
fi

# If no per-GPU data, use summary total
[[ "$gpu_khs_arr" == "[]" ]] && gpu_khs_arr="[$local_khs]"

# khs — total hashrate in kH/s (HiveOS reads this)
khs="$local_khs"

# stats — JSON payload (HiveOS reads this)
stats=$(cat <<EOF
{"hs":$gpu_khs_arr,"hs_units":"khs","temp":$gpu_temp_arr,"fan":$gpu_fan_arr,"uptime":$local_uptime,"ver":"$local_ver","ar":[$local_acc,$local_rej],"algo":"$local_algo"}
EOF
)

# Also set stats_raw for compatibility
stats_raw="$stats"
