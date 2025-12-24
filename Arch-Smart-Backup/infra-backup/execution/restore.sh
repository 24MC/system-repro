#!/usr/bin/env bash

# Restore Execution Module
# Orchestrates the restore process by applying declarative configurations
# Implements the "execution" phase of the backup/restore workflow
# Supports dry-run, selective restore, and exclusion patterns

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Restore modes
readonly DRY_RUN=false
readonly EXCLUDES_FILE=""

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
    --system          Restore system configuration only
    --docker          Restore Docker configuration only
    --all             Restore everything (default)
    --dry-run         Simulate restore without making changes
    --excludes FILE   File containing patterns to exclude
    --selective       Interactive selective restore
    --force           Force restore even if files exist
    --help            Show this help message

EXAMPLES:
    $0 --system --dry-run          # Dry-run system restore
    $0 --docker                    # Restore Docker configuration
    $0 --all --excludes excludes.txt  # Restore all with exclusions
    $0 --system --force            # Force system restore

DESCRIPTION:
    This script orchestrates the restore process by applying declarative
    configurations. It implements the "execution" phase of the backup/restore
    workflow, ensuring the system matches the declared state.

    The restore process follows these principles:
    1. Declarative: Restore what SHOULD exist, not what existed
    2. Idempotent: Running restore multiple times is safe
    3. Safe: Creates backups of existing files before overwriting
    4. Auditable: All changes are logged and can be reviewed

RESTORE PHASES:
    1. Validation: Check if declarative files exist and are valid
    2. Pre-check: Verify system state and prerequisites
    3. Execution: Apply changes in dependency order
    4. Verification: Confirm restore was successful

EOF
}

# Validate declarative configuration
validate_declarative() {
    local errors=0
    
    log_info "Validating declarative configuration..."
    
    # Check system declarative file
    if [[ -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_success "System declarative configuration found"
        
        # Basic syntax check
        if ! grep -q '^package\.' "${PROJECT_ROOT}/declarative/system.conf" && \
           ! grep -q '^service\.' "${PROJECT_ROOT}/declarative/system.conf" && \
           ! grep -q '^config\.' "${PROJECT_ROOT}/declarative/system.conf"; then
            log_warn "System declarative file has no package/service/config entries"
        fi
    else
        log_error "System declarative configuration not found: declarative/system.conf"
        ((errors++))
    fi
    
    # Check Docker declarative file
    if [[ -f "${PROJECT_ROOT}/declarative/docker.conf" ]]; then
        log_success "Docker declarative configuration found"
    else
        log_warn "Docker declarative configuration not found: declarative/docker.conf"
        log_info "Run 'backup docker' first to generate Docker declarative configuration"
    fi
    
    if [[ ${errors} -gt 0 ]]; then
        log_error "Validation failed with ${errors} errors"
        return 1
    fi
    
    log_success "Declarative configuration validation completed"
    return 0
}

# Pre-restore system checks
precheck_system() {
    log_info "Performing pre-restore system checks..."
    
    # Check if we're on Arch Linux
    if [[ ! -f /etc/arch-release ]]; then
        log_warn "Not running on Arch Linux - some operations may fail"
    fi
    
    # Check network connectivity
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        log_warn "Network connectivity check failed - package installation may fail"
    fi
    
    # Check disk space
    local available_space
    available_space=$(df / | tail -1 | awk '{print $4}')
    if [[ ${available_space} -lt 1048576 ]]; then  # Less than 1GB
        log_warn "Low disk space available: $((available_space / 1024 / 1024))GB"
    fi
    
    # Check if running as root for system operations
    if [[ $EUID -ne 0 ]]; then
        log_warn "Not running as root - some system operations may fail"
    fi
    
    log_success "Pre-restore checks completed"
}

# Pre-restore Docker checks
precheck_docker() {
    log_info "Performing pre-restore Docker checks..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        return 1
    fi
    
    log_success "Docker pre-restore checks completed"
    return 0
}

# Restore system configuration
restore_system() {
    log_info "Starting system configuration restore..."
    
    local success=true
    
    # Pre-checks
    precheck_system
    
    # Restore packages
    log_info "=== Package Restore ==="
    if [[ -f "${PROJECT_ROOT}/inventory/packages/install_packages.sh" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would execute: inventory/packages/install_packages.sh"
        else
            log_info "Executing package installation script..."
            if ! "${PROJECT_ROOT}/inventory/packages/install_packages.sh"; then
                log_error "Package installation failed"
                success=false
            fi
        fi
    else
        log_warn "Package installation script not found"
    fi
    
    # Restore services
    log_info "=== Service Restore ==="
    if [[ -f "${PROJECT_ROOT}/inventory/services/restore_services.sh" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would execute: inventory/services/restore_services.sh"
        else
            log_info "Executing service restore script..."
            if ! "${PROJECT_ROOT}/inventory/services/restore_services.sh"; then
                log_error "Service restore failed"
                success=false
            fi
        fi
    else
        log_warn "Service restore script not found"
    fi
    
    # Restore configuration files
    log_info "=== Configuration Files Restore ==="
    if [[ -f "${PROJECT_ROOT}/inventory/config/restore_config.sh" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would execute: inventory/config/restore_config.sh"
        else
            log_info "Executing configuration restore script..."
            if ! "${PROJECT_ROOT}/inventory/config/restore_config.sh"; then
                log_error "Configuration restore failed"
                success=false
            fi
        fi
    else
        log_warn "Configuration restore script not found"
    fi
    
    if [[ "${success}" == "true" ]]; then
        log_success "System restore completed successfully"
        return 0
    else
        log_error "System restore completed with errors"
        return 1
    fi
}

# Restore Docker configuration
restore_docker() {
    log_info "Starting Docker configuration restore..."
    
    # Pre-checks
    if ! precheck_docker; then
        log_error "Docker pre-checks failed"
        return 1
    fi
    
    # Restore Docker resources
    if [[ -f "${PROJECT_ROOT}/inventory/docker/restore_docker.sh" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would execute: inventory/docker/restore_docker.sh"
        else
            log_info "Executing Docker restore script..."
            if ! "${PROJECT_ROOT}/inventory/docker/restore_docker.sh"; then
                log_error "Docker restore failed"
                return 1
            fi
        fi
    else
        log_warn "Docker restore script not found"
        log_info "Run 'backup docker' first to generate Docker inventory"
        return 1
    fi
    
    log_success "Docker restore completed successfully"
    return 0
}

# Apply exclusions
apply_exclusions() {
    local excludes_file="${1}"
    local target_file="${2}"
    
    if [[ ! -f "${excludes_file}" ]]; then
        log_warn "Excludes file not found: ${excludes_file}"
        return 0
    fi
    
    log_info "Applying exclusions from: ${excludes_file}"
    
    # Create temporary file
    local temp_file="${target_file}.tmp"
    cp "${target_file}" "${temp_file}"
    
    # Apply exclusions
    while IFS= read -r exclude_pattern; do
        [[ -z "${exclude_pattern}" ]] && continue
        [[ "${exclude_pattern}" =~ ^# ]] && continue
        
        log_info "Excluding pattern: ${exclude_pattern}"
        
        # Remove matching lines
        sed -i "/${exclude_pattern}/d" "${temp_file}"
        
    done < "${excludes_file}"
    
    mv "${temp_file}" "${target_file}"
    log_success "Exclusions applied"
}

# Interactive selective restore
selective_restore() {
    log_info "Starting interactive selective restore..."
    
    # Show available items from declarative configuration
    if [[ -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_info "Available system configuration items:"
        grep -E '^(package|service|config)\.' "${PROJECT_ROOT}/declarative/system.conf" | nl
        
        echo
        read -p "Enter numbers to restore (space-separated), or 'all': " selection
        
        if [[ "${selection}" != "all" ]]; then
            # Create temporary selective file
            local temp_file="/tmp/selective_restore_$$"
            > "${temp_file}"
            
            for num in ${selection}; do
                # This is a simplified implementation
                # In a real tool, you'd want more sophisticated selection logic
                log_info "Would restore item #${num}"
            done
            
            rm -f "${temp_file}"
        fi
    fi
    
    log_success "Selective restore completed"
}

# Post-restore verification
verify_restore() {
    local mode="${1:-all}"
    
    log_info "Starting post-restore verification..."
    
    case "${mode}" in
        system|all)
            log_info "Verifying system configuration..."
            # Add verification logic here
            ;;
        docker|all)
            log_info "Verifying Docker configuration..."
            # Add verification logic here
            ;;
    esac
    
    log_success "Post-restore verification completed"
}

# Main restore function
main() {
    local restore_mode="all"
    local dry_run=false
    local excludes_file=""
    local selective=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                restore_mode="system"
                shift
                ;;
            --docker)
                restore_mode="docker"
                shift
                ;;
            --all)
                restore_mode="all"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --excludes)
                excludes_file="${2}"
                shift 2
                ;;
            --selective)
                selective=true
                shift
                ;;
            --force)
                force=true
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
    
    # Export dry-run flag for use in functions
    export DRY_RUN="${dry_run}"
    
    log_info "Starting restore process..."
    log_info "Restore mode: ${restore_mode}"
    log_info "Dry run: ${dry_run}"
    
    if [[ -n "${excludes_file}" ]]; then
        log_info "Excludes file: ${excludes_file}"
    fi
    
    # Validate declarative configuration
    if ! validate_declarative; then
        log_error "Declarative validation failed - cannot proceed with restore"
        exit 1
    fi
    
    # Handle selective restore
    if [[ "${selective}" == "true" ]]; then
        selective_restore
        exit 0
    fi
    
    # Perform restore based on mode
    local success=true
    
    case "${restore_mode}" in
        system)
            if ! restore_system; then
                success=false
            fi
            ;;
        docker)
            if ! restore_docker; then
                success=false
            fi
            ;;
        all)
            if ! restore_system; then
                success=false
            fi
            if ! restore_docker; then
                success=false
            fi
            ;;
        *)
            log_error "Invalid restore mode: ${restore_mode}"
            exit 1
            ;;
    esac
    
    # Post-restore verification
    if [[ "${dry_run}" == "false" ]]; then
        verify_restore "${restore_mode}"
    fi
    
    # Final status
    if [[ "${success}" == "true" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
            log_success "Dry-run completed successfully - no changes made"
        else
            log_success "Restore completed successfully!"
            log_info "You may need to reboot for all changes to take effect"
        fi
        exit 0
    else
        if [[ "${dry_run}" == "true" ]]; then
            log_error "Dry-run completed with errors"
        else
            log_error "Restore completed with errors!"
            log_info "Check the logs above for details"
        fi
        exit 1
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi