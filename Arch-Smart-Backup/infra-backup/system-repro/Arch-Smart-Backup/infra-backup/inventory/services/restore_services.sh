#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "System service operations require root"
        exit 1
    fi
}

enable_system_services() {
    log_info "Enabling system services..."

    local services=(
        avahi-daemon.service
        avahi-daemon.socket
        coolercontrold.service
        docker.service
        firewalld.service
        fstrim.timer
        getty@.service
        libvirtd-admin.socket
        libvirtd-ro.socket
        libvirtd.service
        libvirtd.socket
        lm_sensors.service
        NetworkManager-dispatcher.service
        NetworkManager.service
        NetworkManager-wait-online.service
        ollama.service
        paccache.timer
        power-profiles-daemon.service
        sddm.service
        SO5_LabApp.service
        systemd-timesyncd.service
        systemd-userdbd.socket
        virtlockd-admin.socket
        virtlockd.socket
        virtlogd-admin.socket
        virtlogd.socket
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}" >/dev/null 2>&1; then
            log_info "Enabling ${service}..."
            systemctl enable "${service}" 2>/dev/null || log_error "Failed: ${service}"
        fi
    done

    systemctl daemon-reload
    log_success "System services enabled"
}

enable_user_services() {
    log_info "Enabling user services..."

    local services=(
        appimagelauncherd.service
        p11-kit-server.socket
        pipewire-pulse.socket
        pipewire.socket
        SO5_LabApp.service
        wireplumber.service
        xdg-user-dirs.service
    )

    if systemctl --user list-unit-files >/dev/null 2>&1; then
        for service in "${services[@]}"; do
            if systemctl --user list-unit-files "${service}" >/dev/null 2>&1; then
                log_info "Enabling ${service}..."
                systemctl --user enable "${service}" 2>/dev/null || log_error "Failed: ${service}"
            fi
        done
        systemctl --user daemon-reload
        log_success "User services enabled"
    fi
}

main() {
    local mode="${1:-all}"

    case "${mode}" in
        system|all)
            check_root
            enable_system_services
            ;;
        user)
            enable_user_services
            ;;
        *)
            log_error "Usage: $0 [system|user|all]"
            exit 1
            ;;
    esac

    log_success "Service restore completed!"
}

main "$@"
