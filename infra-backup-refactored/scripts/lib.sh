#!/usr/bin/env bash
# Common helper functions for infra-backup refactor
set -euo pipefail

log_info() { printf "[INFO] %s\n" "$*"; }
log_warn() { printf "[WARN] %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*" >&2; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root."
        return 1
    fi
}

detect_aur_helper() {
    # simple detection for paru/yay
    if command -v paru >/dev/null 2>&1; then
        printf "paru"
    elif command -v yay >/dev/null 2>&1; then
        printf "yay"
    else
        printf ""
    fi
}
