#!/usr/bin/env bash
# h-config.sh — Configure ccminer-yescrypt for HiveOS
# This is sourced by HiveOS agent before h-run.sh
# HiveOS sets: CUSTOM_URL, CUSTOM_TEMPLATE, CUSTOM_PASS, CUSTOM_USER_CONFIG, CUSTOM_ALGO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nothing to configure — all params passed via command line in h-run.sh
