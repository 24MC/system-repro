#!/usr/bin/env bash

# Systemd Service Inventory Module
# Collects enabled and manually activated services
# Identifies user-specific service customizations
# Generates declarative service configuration for reproducible state

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly INVENTORY_DIR="${SCRIPT_DIR}"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Get system-wide enabled services
get_system_services() {
    local output_file="${1}"
    
    log_info "Collecting system-wide enabled services..."
    
    # Get enabled services (both enabled-runtime and static)
    systemctl list-unit-files --state=enabled --no-legend | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer|mount|automount|swap|target|path|slice|scope)$' | \
        sort > "${output_file}"
    
    local service_count=$(wc -l < "${output_file}")
    log_success "Found ${service_count} enabled system services"
}

# Get user services (for current user)
get_user_services() {
    local output_file="${1}"
    
    log_info "Collecting user-enabled services..."
    
    # Check if systemd user instance is available
    if systemctl --user list-unit-files >/dev/null 2>&1; then
        systemctl --user list-unit-files --state=enabled --no-legend | \
            awk '{print $1}' | \
            grep -E '\.(service|socket|timer|mount|automount|swap|target|path|slice|scope)$' | \
            sort > "${output_file}"
        
        local service_count=$(wc -l < "${output_file}")
        log_success "Found ${service_count} enabled user services"
    else
        log_info "No user systemd instance found (this is normal)"
        touch "${output_file}"
    fi
}

# Get masked services (important for restore - we don't want to unmask by default)
get_masked_services() {
    local output_file="${1}"
    
    log_info "Collecting masked services..."
    
    systemctl list-unit-files --state=masked --no-legend | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer|mount|automount|swap|target|path|slice|scope)$' | \
        sort > "${output_file}"
    
    local masked_count=$(wc -l < "${output_file}")
    if [[ ${masked_count} -gt 0 ]]; then
        log_info "Found ${masked_count} masked services (will be preserved)"
    fi
}

# Get failed services (for diagnostic purposes)
get_failed_services() {
    local output_file="${1}"
    
    log_info "Checking for failed services..."
    
    systemctl list-units --state=failed --no-legend | \
        awk '{print $1}' | \
        grep -E '\.(service|socket|timer|mount|automount|swap|target|path|slice|scope)$' | \
        sort > "${output_file}"
    
    local failed_count=$(wc -l < "${output_file}")
    if [[ ${failed_count} -gt 0 ]]; then
        log_warn "Found ${failed_count} failed services - review system health"
    else
        log_success "No failed services detected"
    fi
}

# Get service status details
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
        
        local status
        local active_state
        local sub_state
        
        # Get service status in a safe way
        if systemctl is-active "${service}" >/dev/null 2>&1; then
            status="active"
        else
            status="inactive"
        fi
        
        active_state=$(systemctl show "${service}" --property=ActiveState --value 2>/dev/null || echo "unknown")
        sub_state=$(systemctl show "${service}" --property=SubState --value 2>/dev/null || echo "unknown")
        
        echo "service.${service}.status=${status}" >> "${status_file}"
        echo "service.${service}.active_state=${active_state}" >> "${status_file}"
        echo "service.${service}.sub_state=${sub_state}" >> "${status_file}"
        
    done < "${system_services}"
    
    log_success "Service status collected"
}

# Detect service customizations (overrides, drop-ins)
get_service_customizations() {
    local output_dir="${1}"
    
    log_info "Detecting service customizations..."
    
    # Create output directory
    mkdir -p "${output_dir}"
    
    # Check for systemd override files
    local override_dirs=(
        "/etc/systemd/system"
        "/run/systemd/system"
        "/usr/lib/systemd/system"
    )
    
    local user_override_dirs=(
        "${HOME}/.config/systemd/user"
    )
    
    # System-wide overrides
    for dir in "${override_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            find "${dir}" -name "*.d" -type d | while read -r override_dir; do
                if [[ -d "${override_dir}" ]]; then
                    local service_name
                    service_name=$(basename "${override_dir}" .d)
                    
                    find "${override_dir}" -name "*.conf" -type f | while read -r conf_file; do
                        local dest_file="${output_dir}/system_${service_name}_$(basename "${conf_file}").override"
                        cp "${conf_file}" "${dest_file}"
                        log_info "Found override: ${service_name} -> $(basename "${conf_file}")"
                    done
                fi
            done
        fi
    done
    
    # User overrides
    for dir in "${user_override_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            find "${dir}" -name "*.d" -type d | while read -r override_dir; do
                if [[ -d "${override_dir}" ]]; then
                    local service_name
                    service_name=$(basename "${override_dir}" .d)
                    
                    find "${override_dir}" -name "*.conf" -type f | while read -r conf_file; do
                        local dest_file="${output_dir}/user_${service_name}_$(basename "${conf_file}").override"
                        cp "${conf_file}" "${dest_file}"
                        log_info "Found user override: ${service_name} -> $(basename "${conf_file}")"
                    done
                fi
            done
        fi
    done
    
    local override_count=$(find "${output_dir}" -name "*.override" 2>/dev/null | wc -l)
    if [[ ${override_count} -gt 0 ]]; then
        log_success "Found ${override_count} service customizations"
    else
        log_info "No service customizations found"
    fi
}

# Generate declarative service configuration
generate_declarative_config() {
    local system_services="${1}"
    local user_services="${2}"
    local masked_services="${3}"
    local declarative_file="${4}"
    
    log_info "Generating declarative service configuration..."
    
    cat > "${declarative_file}" << EOF
# Declarative Systemd Service Configuration
# Generated on: $(date)
# This file defines what services SHOULD be enabled
# Edit this file to declare desired state, not current state

# System-wide services (managed by root)
# These will be enabled at boot time
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.system.${service}=enabled"
done < "${system_services}")

# User services (managed by user)
# These will be enabled for the current user
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.user.${service}=enabled"
done < "${user_services}")

# Masked services (explicitly disabled)
# These will remain masked during restore
$(while IFS= read -r service; do
    [[ -n "${service}" ]] && echo "service.masked.${service}=preserved"
done < "${masked_services}")

# Service policy configuration
# Define how services should be handled during restore

# Critical services (start immediately after restore)
# service.critical.network-manager=true
# service.critical.ssh=true

# Optional services (install but don't auto-start)
# service.optional.print-applet=installed-only

# Service dependencies (ensure these are started before)
# service.before.docker.service=network-online.target

EOF
    
    log_success "Declarative service configuration generated"
}

# Generate service restore script
generate_restore_script() {
    local system_services="${1}"
    local user_services="${2}"
    local restore_script="${3}"
    
    log_info "Generating service restore script..."
    
    cat > "${restore_script}" << 'EOF'
#!/usr/bin/env bash
# Systemd Service Restore Script
# Auto-generated by infra-backup

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Check if running as root for system services
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "System service operations require root privileges"
        exit 1
    fi
}

# Enable system services
enable_system_services() {
    log_info "Enabling system services..."
    
    local services=(
EOF

    # Add system services to the script
    while IFS= read -r service; do
        [[ -n "${service}" ]] && echo "        ${service}" >> "${restore_script}"
    done < "${system_services}"
    
    cat >> "${restore_script}" << 'EOF'
    )
    
    if [[ ${#services[@]} -gt 0 ]]; then
        for service in "${services[@]}"; do
            if systemctl list-unit-files | grep -q "^${service}"; then
                log_info "Enabling ${service}..."
                systemctl enable "${service}"
            else
                log_warn "Service not found: ${service} (skipping)"
            fi
        done
        
        # Reload systemd
        systemctl daemon-reload
        log_success "System services enabled"
    else
        log_info "No system services to enable"
    fi
}

# Enable user services
enable_user_services() {
    log_info "Enabling user services..."
    
    local services=(
EOF

    # Add user services to the script
    while IFS= read -r service; do
        [[ -n "${service}" ]] && echo "        ${service}" >> "${restore_script}"
    done < "${user_services}"
    
    cat >> "${restore_script}" << 'EOF'
    )
    
    if [[ ${#services[@]} -gt 0 ]]; then
        # Check if user systemd is available
        if systemctl --user list-unit-files >/dev/null 2>&1; then
            for service in "${services[@]}"; do
                if systemctl --user list-unit-files | grep -q "^${service}"; then
                    log_info "Enabling user service: ${service}..."
                    systemctl --user enable "${service}"
                else
                    log_warn "User service not found: ${service} (skipping)"
                fi
            done
            
            # Reload user systemd
            systemctl --user daemon-reload
            log_success "User services enabled"
        else
            log_warn "User systemd instance not available, skipping user services"
        fi
    else
        log_info "No user services to enable"
    fi
}

# Restore service customizations
restore_customizations() {
    local customizations_dir="${SCRIPT_DIR}/customizations"
    
    if [[ -d "${customizations_dir}" ]]; then
        log_info "Restoring service customizations..."
        
        find "${customizations_dir}" -name "*.override" | while read -r override_file; do
            local filename
            filename=$(basename "${override_file}" .override)
            
            # Parse filename to determine target location
            if [[ "${filename}" =~ ^system_(.*)_(.*)$ ]]; then
                local service="${BASH_REMATCH[1]}"
                local conf_file="${BASH_REMATCH[2]}"
                local target_dir="/etc/systemd/system/${service}.d"
                
                log_info "Restoring system override: ${service}/${conf_file}"
                
                mkdir -p "${target_dir}"
                cp "${override_file}" "${target_dir}/${conf_file}"
                
            elif [[ "${filename}" =~ ^user_(.*)_(.*)$ ]]; then
                local service="${BASH_REMATCH[1]}"
                local conf_file="${BASH_REMATCH[2]}"
                local target_dir="${HOME}/.config/systemd/user/${service}.d"
                
                log_info "Restoring user override: ${service}/${conf_file}"
                
                mkdir -p "${target_dir}"
                cp "${override_file}" "${target_dir}/${conf_file}"
            fi
        done
        
        log_success "Service customizations restored"
    fi
}

# Main restore function
main() {
    local mode="${1:-all}"
    
    case "${mode}" in
        system|all)
            check_root
            enable_system_services
            restore_customizations
            ;;
        user)
            enable_user_services
            ;;
        *)
            log_error "Invalid mode: ${mode}"
            log_info "Usage: $0 [system|user|all]"
            exit 1
            ;;
    esac
    
    log_success "Service restore completed!"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

EOF
    
    chmod +x "${restore_script}"
    log_success "Service restore script generated"
}

# Main inventory function
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
    
    # Step 1: Collect all service information
    get_system_services "${temp_system}"
    get_user_services "${temp_user}"
    get_masked_services "${temp_masked}"
    get_failed_services "${temp_failed}"
    get_service_status "${temp_system}" "${temp_status}"
    get_service_customizations "${customizations_dir}"
    
    # Step 2: Create comprehensive inventory
    cat > "${inventory_file}" << EOF
# Systemd Service Inventory
# Generated on: $(date)
# Host: $(hostname)

## Summary
- System services enabled: $(wc -l < "${temp_system}")
- User services enabled: $(wc -l < "${temp_user}")
- Masked services: $(wc -l < "${temp_masked}")
- Failed services: $(wc -l < "${temp_failed}")

## System Services
$(cat "${temp_system}")

## User Services
$(cat "${temp_user}")

## Masked Services
$(cat "${temp_masked}")

## Failed Services
$(cat "${temp_failed}")

## Detailed Status
$(cat "${temp_status}")

## Customizations
$(if [[ -d "${customizations_dir}" ]]; then
    echo "Service customizations found in: ${customizations_dir}/"
    find "${customizations_dir}" -name "*.override" | wc -l | xargs echo "Override files:"
else
    echo "No service customizations found"
fi)

EOF
    
    log_success "Service inventory saved: ${inventory_file}"
    
    # Step 3: Generate declarative configuration (append to system.conf)
    if [[ ! -f "${declarative_file}" ]]; then
        # Create new file if it doesn't exist
        generate_declarative_config "${temp_system}" "${temp_user}" "${temp_masked}" "${declarative_file}"
    else
        # Append service configuration to existing file
        log_info "Appending service configuration to existing declarative file..."
        
        cat >> "${declarative_file}" << EOF

# === SERVICE CONFIGURATION (added $(date)) ===

EOF
        
        generate_declarative_config "${temp_system}" "${temp_user}" "${temp_masked}" "${declarative_file}.tmp"
        cat "${declarative_file}.tmp" >> "${declarative_file}"
        rm -f "${declarative_file}.tmp"
    fi
    
    # Step 4: Generate restore script
    generate_restore_script "${temp_system}" "${temp_user}" "${restore_script}"
    
    # Cleanup temporary files
    rm -f "${temp_system}" "${temp_user}" "${temp_masked}" "${temp_failed}" "${temp_status}"
    
    log_info "Service inventory completed successfully"
    log_info "Next steps:"
    log_info "  1. Review ${declarative_file}"
    log_info "  2. Edit to declare desired service state"
    log_info "  3. Use ${restore_script} to reproduce service configuration"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi