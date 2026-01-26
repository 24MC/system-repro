#!/usr/bin/env bash

# Systemd Service Inventory Module
# Collects enabled and manually activated services
# Generates declarative service configuration for reproducible state

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly INVENTORY_DIR="${SCRIPT_DIR}"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

get_system_services() {
    local output_file="${1}"
    log_info "Collecting system-wide enabled services..."

    systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer)$' | \
        sort > "${output_file}" || touch "${output_file}"

    local service_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    log_success "Found ${service_count} enabled system services"
}

get_user_services() {
    local output_file="${1}"
    log_info "Collecting user-enabled services..."

    if systemctl --user list-unit-files >/dev/null 2>&1; then
        systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | \
            awk '{print $1}' | \
            grep -E '\.(service|socket|timer)$' | \
            sort > "${output_file}" || touch "${output_file}"

        local service_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
        log_success "Found ${service_count} enabled user services"
    else
        log_info "No user systemd instance found"
        touch "${output_file}"
    fi
}

get_masked_services() {
    local output_file="${1}"
    log_info "Collecting masked services..."

    systemctl list-unit-files --state=masked --no-legend 2>/dev/null | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer)$' | \
        sort > "${output_file}" || touch "${output_file}"

    local masked_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    log_info "Found ${masked_count} masked services"
}

get_failed_services() {
    local output_file="${1}"
    log_info "Checking for failed services..."

    systemctl list-units --state=failed --no-legend 2>/dev/null | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer)$' | \
        sort > "${output_file}" || touch "${output_file}"

    local failed_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    if [[ ${failed_count} -gt 0 ]]; then
        log_warn "Found ${failed_count} failed services"
    else
        log_info "No failed services detected"
    fi
}

get_service_status() {
    local system_services="${1}"
    local status_file="${2}"

    log_info "Collecting service status details..."

    cat > "${status_file}" << EOF
# Service Status Report
# Generated on: $(date)
# Host: $(hostname)

## System Services Status
EOF

    while IFS= read -r service; do
        [[ -z "${service}" ]] && continue

        local status="unknown"
        if systemctl is-active "${service}" >/dev/null 2>&1; then
            status="active"
        elif systemctl is-enabled "${service}" >/dev/null 2>&1; then
            status="enabled"
        else
            status="inactive"
        fi

        echo "service.${service}.status=${status}" >> "${status_file}"

    done < "${system_services}"

    log_success "Service status collected"
}

get_service_customizations() {
    local output_dir="${1}"
    log_info "Detecting service customizations..."

    mkdir -p "${output_dir}"

    local override_dirs=(
        "/etc/systemd/system"
        "${HOME}/.config/systemd/user"
    )

    local found=0
    for dir in "${override_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            while IFS= read -r override_dir; do
                if [[ -d "${override_dir}" ]]; then
                    local service_name
                    service_name=$(basename "${override_dir}" .d)

                    while IFS= read -r conf_file; do
                        local dest_file="${output_dir}/$(basename "${dir}")_${service_name}_$(basename "${conf_file}").override"
                        cp "${conf_file}" "${dest_file}" 2>/dev/null && ((found++)) || true
                    done < <(find "${override_dir}" -name "*.conf" -type f 2>/dev/null || true)
                fi
            done < <(find "${dir}" -name "*.d" -type d 2>/dev/null || true)
        fi
    done

    log_info "Found ${found} service customizations"
}

generate_declarative_config() {
    local system_services="${1}"
    local user_services="${2}"
    local masked_services="${3}"
    local declarative_file="${4}"

    log_info "Generating declarative service configuration..."

    # Check if system.conf exists
    if [[ -f "${declarative_file}" ]]; then
        # Append to existing file
        cat >> "${declarative_file}" << EOF

# === SERVICE CONFIGURATION (added $(date)) ===

EOF
    else
        # Create new file
        cat > "${declarative_file}" << EOF
# Declarative Service Configuration
# Generated on: $(date)

EOF
    fi

    cat >> "${declarative_file}" << EOF
# System-wide services
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.system.${service}=enabled"
done < "${system_services}")

# User services
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.user.${service}=enabled"
done < "${user_services}")

# Masked services
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.masked.${service}=preserved"
done < "${masked_services}")
EOF

    log_success "Declarative service configuration generated"
}

generate_restore_script() {
    local system_services="${1}"
    local user_services="${2}"
    local restore_script="${3}"

    log_info "Generating service restore script..."

    cat > "${restore_script}" << 'RESTOREEOF'
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
RESTOREEOF

    while IFS= read -r service; do
        [[ -n "${service}" ]] && echo "        ${service}" >> "${restore_script}"
    done < "${system_services}"

    cat >> "${restore_script}" << 'RESTOREEOF2'
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
RESTOREEOF2

    while IFS= read -r service; do
        [[ -n "${service}" ]] && echo "        ${service}" >> "${restore_script}"
    done < "${user_services}"

    cat >> "${restore_script}" << 'RESTOREEOF3'
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
RESTOREEOF3

    chmod +x "${restore_script}"
    log_success "Service restore script generated"
}

main() {
    local temp_system="${INVENTORY_DIR}/system_services_${TIMESTAMP}.tmp"
    local temp_user="${INVENTORY_DIR}/user_services_${TIMESTAMP}.tmp"
    local temp_masked="${INVENTORY_DIR}/masked_services_${TIMESTAMP}.tmp"
    local temp_failed="${INVENTORY_DIR}/failed_services_${TIMESTAMP}.tmp"
    local temp_status="${INVENTORY_DIR}/service_status_${TIMESTAMP}.tmp"

    local inventory_file="${INVENTORY_DIR}/services_${TIMESTAMP}.inventory"
    local declarative_file="${PROJECT_ROOT}/declarative/system.conf"
    local restore_script="${INVENTORY_DIR}/restore_services.sh"
    local customizations_dir="${INVENTORY_DIR}/customizations"

    get_system_services "${temp_system}"
    get_user_services "${temp_user}"
    get_masked_services "${temp_masked}"
    get_failed_services "${temp_failed}"
    get_service_status "${temp_system}" "${temp_status}"
    get_service_customizations "${customizations_dir}"

    cat > "${inventory_file}" << EOF
# Systemd Service Inventory
# Generated on: $(date)
# Host: $(hostname)

## Summary
- System services: $(wc -l < "${temp_system}" 2>/dev/null || echo 0)
- User services: $(wc -l < "${temp_user}" 2>/dev/null || echo 0)
- Masked services: $(wc -l < "${temp_masked}" 2>/dev/null || echo 0)
- Failed services: $(wc -l < "${temp_failed}" 2>/dev/null || echo 0)

## System Services
$(cat "${temp_system}")

## User Services
$(cat "${temp_user}")

## Masked Services
$(cat "${temp_masked}")

## Failed Services
$(cat "${temp_failed}")

## Service Status
$(cat "${temp_status}")
EOF

    log_success "Service inventory saved: ${inventory_file}"

    generate_declarative_config "${temp_system}" "${temp_user}" "${temp_masked}" "${declarative_file}"
    generate_restore_script "${temp_system}" "${temp_user}" "${restore_script}"

    rm -f "${temp_system}" "${temp_user}" "${temp_masked}" "${temp_failed}" "${temp_status}"

    log_success "Service inventory completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
