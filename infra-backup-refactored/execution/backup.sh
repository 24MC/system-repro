#!/usr/bin/env bash

# Backup Execution Module
# Orchestrates the backup process by calling individual inventory modules
# Implements the "inventory" phase of the backup/restore workflow

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --system          Backup system configuration (packages, services, configs)
    --docker          Backup Docker configuration
    --all             Backup everything (default)
    --output-dir DIR  Specify output directory for backup files
    --include-logs    Include log files in backup (not recommended)
    --compress        Compress backup files
    --help            Show this help message

EXAMPLES:
    $0 --system                    # Backup system configuration only
    $0 --docker                    # Backup Docker configuration only
    $0 --all --compress            # Backup everything with compression
    $0 --system --output-dir /tmp  # Backup to specific directory

DESCRIPTION:
    This script orchestrates the backup process by calling individual
    inventory modules. It implements the "inventory" phase of the
    backup/restore workflow, collecting current state information
    and generating declarative configurations.

    The backup process follows these principles:
    1. Inventory: Collect what currently exists
    2. Declarative: Define what should exist
    3. Idempotent: Running backup multiple times is safe
    4. Transparent: All operations are logged and auditable

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're on Arch Linux
    if [[ ! -f /etc/arch-release ]]; then
        log_warn "This tool is designed for Arch Linux - proceed with caution"
    fi
    
    # Check required directories
    local required_dirs=(
        "${PROJECT_ROOT}/inventory/packages"
        "${PROJECT_ROOT}/inventory/services"
        "${PROJECT_ROOT}/inventory/docker"
        "${PROJECT_ROOT}/inventory/config"
        "${PROJECT_ROOT}/declarative"
        "${PROJECT_ROOT}/docker/compose"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            log_info "Creating directory: ${dir}"
            mkdir -p "${dir}" || {
                log_error "Failed to create directory: ${dir}"
                return 1
            }
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Backup system configuration
backup_system() {
    log_info "Starting system configuration backup..."
    
    local success=true
    
    # Backup packages
    log_info "=== Package Inventory ==="
    if ! "${PROJECT_ROOT}/inventory/packages/inventory.sh"; then
        log_error "Package inventory failed"
        success=false
    fi
    
    # Backup services
    log_info "=== Service Inventory ==="
    if ! "${PROJECT_ROOT}/inventory/services/inventory.sh"; then
        log_error "Service inventory failed"
        success=false
    fi
    
    # Backup configuration files
    log_info "=== Configuration Inventory ==="
    if ! "${PROJECT_ROOT}/inventory/config/inventory.sh"; then
        log_error "Configuration inventory failed"
        success=false
    fi
    
    if [[ "${success}" == "true" ]]; then
        log_success "System backup completed successfully"
        return 0
    else
        log_error "System backup completed with errors"
        return 1
    fi
}

# Backup Docker configuration
backup_docker() {
    log_info "Starting Docker configuration backup..."
    
    if ! "${PROJECT_ROOT}/inventory/docker/inventory.sh"; then
        log_error "Docker backup failed"
        return 1
    fi
    
    log_success "Docker backup completed successfully"
    return 0
}

# Create backup summary
create_backup_summary() {
    local backup_dir="${1}"
    local summary_file="${backup_dir}/backup_summary.txt"
    
    log_info "Creating backup summary..."
    
    cat > "${summary_file}" << EOF
# Backup Summary
# Generated on: $(date)
# Host: $(hostname)
# User: $(whoami)

## Backup Information
- Backup type: ${BACKUP_TYPE:-full}
- Timestamp: $(date +%Y%m%d_%H%M%S)
- Tool version: 0.1.0-prototype

## System Information
- OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"' || echo "Unknown")
- Kernel: $(uname -r)
- Architecture: $(uname -m)
- Uptime: $(uptime -p)

## Backup Contents

### System Configuration
$(find "${PROJECT_ROOT}/inventory" -name "*.inventory" -type f | while read -r inv; do
    echo "- $(basename "${inv}"): $(stat -c%s "${inv}" 2>/dev/null || echo 0) bytes"
done)

### Declarative Configuration Files
$(find "${PROJECT_ROOT}/declarative" -name "*.conf" -type f | while read -r conf; do
    echo "- $(basename "${conf}"): $(stat -c%s "${conf}" 2>/dev/null || echo 0) bytes"
done)

### Docker Configuration
$(if [[ -d "${PROJECT_ROOT}/docker/compose" ]]; then
    echo "- Compose projects: $(find "${PROJECT_ROOT}/docker/compose" -name "docker-compose*.yml" | wc -l)"
    echo "- Volume metadata: $(if [[ -f "${PROJECT_ROOT}/docker/volumes.meta" ]]; then echo "present"; else echo "missing"; fi)"
fi)

### Configuration Files
$(if [[ -d "${PROJECT_ROOT}/inventory/config/files" ]]; then
    echo "- Config files: $(find "${PROJECT_ROOT}/inventory/config/files" -type f | wc -l)"
    echo "- Total size: $(( $(find "${PROJECT_ROOT}/inventory/config/files" -type f -exec stat -c%s {} + 2>/dev/null | awk '{s+=$1} END {print s}' || echo 0) / 1024 )) KB"
fi)

## Next Steps
1. Review declarative configuration files in ${PROJECT_ROOT}/declarative/
2. Edit them to reflect desired state (remove unwanted items)
3. Use restore scripts to apply configuration to new system
4. Test thoroughly before production use

## Notes
- This is a prototype - test thoroughly before relying on it
- Sensitive files (.env, private keys) are excluded from version control
- Always review declarative files before applying to production systems

EOF
    
    log_success "Backup summary created: ${summary_file}"
}

# Main backup function
main() {
    local backup_type="all"
    local output_dir="${PROJECT_ROOT}"
    local compress=false
    local include_logs=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                backup_type="system"
                shift
                ;;
            --docker)
                backup_type="docker"
                shift
                ;;
            --all)
                backup_type="all"
                shift
                ;;
            --output-dir)
                output_dir="${2}"
                shift 2
                ;;
            --include-logs)
                include_logs=true
                shift
                ;;
            --compress)
                compress=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Export for use in functions
    export BACKUP_TYPE="${backup_type}"
    
    log_info "Starting backup process..."
    log_info "Backup type: ${backup_type}"
    log_info "Output directory: ${output_dir}"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Perform backup based on type
    local success=true
    
    case "${backup_type}" in
        system)
            if ! backup_system; then
                success=false
            fi
            ;;
        docker)
            if ! backup_docker; then
                success=false
            fi
            ;;
        all)
            if ! backup_system; then
                success=false
            fi
            if ! backup_docker; then
                success=false
            fi
            ;;
        *)
            log_error "Invalid backup type: ${backup_type}"
            exit 1
            ;;
    esac
    
    # Create backup summary
    create_backup_summary "${output_dir}"
    
    # Compress if requested
    if [[ "${compress}" == "true" ]]; then
        log_info "Compressing backup files..."
        
        local archive_name="infra-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        local archive_path="${output_dir}/${archive_name}"
        
        tar -czf "${archive_path}" -C "${PROJECT_ROOT}" \
            inventory/ \
            declarative/ \
            docker/ \
            || {
            log_error "Compression failed"
            success=false
        }
        
        if [[ "${success}" == "true" ]]; then
            log_success "Backup compressed to: ${archive_path}"
        fi
    fi
    
    # Final status
    if [[ "${success}" == "true" ]]; then
        log_success "Backup completed successfully!"
        log_info "Review the generated files in:"
        log_info "  - Inventory: ${PROJECT_ROOT}/inventory/"
        log_info "  - Declarative: ${PROJECT_ROOT}/declarative/"
        log_info "  - Docker: ${PROJECT_ROOT}/docker/"
        exit 0
    else
        log_error "Backup completed with errors!"
        exit 1
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi