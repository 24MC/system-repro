#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

restore_networks() {
    log_info "Restoring Docker networks..."

    local declarative_file="${PROJECT_ROOT:-$(dirname "$0")/../..}/declarative/docker.conf"

    if [[ -f "${declarative_file}" ]]; then
        grep '^docker.network\.' "${declarative_file}" 2>/dev/null | while read -r line; do
            if [[ "${line}" =~ docker\.network\.([^.]+)\.state=present ]]; then
                local network_name="${BASH_REMATCH[1]}"

                if ! docker network ls --filter "name=${network_name}" --quiet | grep -q .; then
                    log_info "Creating network: ${network_name}"
                    docker network create "${network_name}" 2>/dev/null || true
                else
                    log_info "Network exists: ${network_name}"
                fi
            fi
        done
    fi

    log_success "Docker networks restored"
}

main() {
    check_docker
    restore_networks
    log_success "Docker restore completed!"
}

main "$@"
