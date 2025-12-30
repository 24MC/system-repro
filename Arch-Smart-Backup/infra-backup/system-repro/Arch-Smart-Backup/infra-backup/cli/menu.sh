#!/usr/bin/env bash

# infra-backup CLI Menu
# Senior DevOps Engineer Prototype
# Arch Linux / EndeavourOS Infrastructure Backup & Restore

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VERSION="0.1.0-prototype"

# Color output
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly NC=$'\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Check if running on Arch Linux
check_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        log_error "This tool is designed for Arch Linux / EndeavourOS only"
        exit 1
    fi
}

# Check if running as root for system operations
check_root() {
    if [[ $EUID -ne 0 && "${1:-}" != "--user" ]]; then
        log_warn "Some operations may require root privileges"
        log_warn "Consider running with sudo for system-wide operations"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Show banner
show_banner() {
    cat << EOF

${BLUE}
╔═══════════════════════════════════════════════════════════════╗
║         🚀 INFRA-BACKUP v${VERSION} - DevOps Edition           ║
║     Local Infrastructure Backup & Restore for Arch Linux      ║
╚═══════════════════════════════════════════════════════════════╝
${NC}

EOF
}

# Show main menu
show_menu() {
    cat << EOF
${YELLOW}=== MAIN MENU ===${NC}

${GREEN}System Operations:${NC}
  1) Backup System          - Inventory packages, services, configs
  2) Restore System         - Restore from declarative state
  3) Validate System State  - Check current vs declared state

${GREEN}Docker Operations:${NC}
  4) Backup Docker          - Inventory Docker configuration
  5) Restore Docker         - Restore Docker stack and volumes
  6) Validate Docker State  - Check Docker configuration

${GREEN}Advanced Operations:${NC}
  7) Dry-Run Restore        - Simulate restore without changes
  8) Restore with Excludes  - Selective restore excluding items
  9) Generate Report        - Create system state report

${YELLOW}Utility:${NC}
  0) Exit

EOF
}

# Backup system function
backup_system() {
    log_info "Starting system backup..."
    
    check_root --user
    
    # Create inventory directory if it doesn't exist
    mkdir -p "${PROJECT_ROOT}/inventory"/{packages,services,docker}
    
    # Run inventory scripts
    log_info "Collecting package inventory..."
    if ! "${PROJECT_ROOT}/inventory/packages/inventory.sh"; then
        log_error "Package inventory failed"
        return 1
    fi
    
    log_info "Collecting systemd service inventory..."
    if ! "${PROJECT_ROOT}/inventory/services/inventory.sh"; then
        log_error "Service inventory failed"
        return 1
    fi
    
    log_info "Collecting configuration files..."
    if ! "${PROJECT_ROOT}/inventory/config/inventory.sh"; then
        log_error "Configuration inventory failed"
        return 1
    fi
    
    log_success "System backup completed successfully"
    log_info "Inventory saved to: ${PROJECT_ROOT}/inventory/"
    log_info "Review and update declarative files in: ${PROJECT_ROOT}/declarative/"
}

# Restore system function
restore_system() {

    log_info "Starting system restore..."
    
    [[ $EUID -eq 0 ]] || { log_error "System restore requires root privileges"; exit 1; }
    
    # Validate declarative configuration exists
    if [[ ! -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_error "Declarative configuration not found: declarative/system.conf"
        return 1
    fi
    
    # Run restore script
    if ! "${PROJECT_ROOT}/execution/restore.sh" --system; then
        log_error "System restore failed"
        return 1
    fi
    
    log_success "System restore completed"
}

# Backup Docker function
backup_docker() {
    log_info "Starting Docker backup..."
    
    check_root --user
    
    # Run Docker inventory
    if ! "${PROJECT_ROOT}/inventory/docker/inventory.sh"; then
        log_error "Docker inventory failed"
        return 1
    fi
    
    log_success "Docker backup completed"
    log_info "Docker configuration saved to: ${PROJECT_ROOT}/inventory/docker/"
}

# Restore Docker function
restore_docker() {
    log_info "Starting Docker restore..."
    
    check_root --user
    
    # Validate Docker declarative configuration
    if [[ ! -f "${PROJECT_ROOT}/declarative/docker.conf" ]]; then
        log_error "Docker declarative configuration not found: declarative/docker.conf"
        return 1
    fi
    
    # Run Docker restore
    if ! "${PROJECT_ROOT}/execution/restore.sh" --docker; then
        log_error "Docker restore failed"
        return 1
    fi
    
    log_success "Docker restore completed"
}

# Validate system state
validate_system() {
    log_info "Validating system state..."
    
    if ! "${PROJECT_ROOT}/execution/validate.sh" --system; then
        log_error "System validation failed"
        return 1
    fi
    
    log_success "System validation completed"
}

# Validate Docker state
validate_docker() {
    log_info "Validating Docker state..."
    
    if ! "${PROJECT_ROOT}/execution/validate.sh" --docker; then
        log_error "Docker validation failed"
        return 1
    fi
    
    log_success "Docker validation completed"
}

# Dry-run restore
dry_run() {
    log_warn "Dry-run depends on restore.sh implementation. No changes should be made."

    log_info "Performing dry-run restore simulation..."
    
    log_warn "This is a simulation - no changes will be made"
    
    if ! "${PROJECT_ROOT}/execution/restore.sh" --dry-run; then
        log_error "Dry-run encountered issues"
        return 1
    fi
    
    log_success "Dry-run completed successfully"
}

# Restore with excludes
restore_with_excludes() {
    log_info "Restore with excludes..."
    
    # Create temporary exclude file if it doesn't exist
    local exclude_file="/tmp/infra-backup-excludes.$$"
    touch "${exclude_file}"
    
    # Show current declarative state
    if [[ -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_info "Available items in system declarative configuration:"
        grep -E '^(package|service|config)\.' "${PROJECT_ROOT}/declarative/system.conf" | nl
    fi
    
    echo
    log_info "Enter items to exclude (one per line, empty line to finish):"
    while read -r exclude_item; do
        [[ -z "${exclude_item}" ]] && break
        echo "${exclude_item}" >> "${exclude_file}"
        log_info "Added '${exclude_item}' to exclude list"
    done
    
    if [[ -s "${exclude_file}" ]]; then
        log_info "Starting restore with excludes..."
        if ! "${PROJECT_ROOT}/execution/restore.sh" --excludes "${exclude_file}"; then
            log_error "Restore with excludes failed"
            rm -f "${exclude_file}"
            return 1
        fi
        log_success "Restore with excludes completed"
    else
        log_info "No excludes specified, aborting"
    fi
    
    rm -f "${exclude_file}"
}

# Generate report
generate_report() {
    log_info "Generating system report..."
    
    local report_file="/tmp/infra-backup-report.$$"
    
    cat > "${report_file}" << EOF
# INFRA-BACKUP System Report
Generated on: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
Arch: $(uname -m)

## System Information
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')
- Uptime: $(uptime -p)
- Shell: ${SHELL}

## Declarative Configuration Status
EOF

    if [[ -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        echo "- System config: ✓ Present" >> "${report_file}"
        echo "- Packages defined: $(grep -c '^package\.' "${PROJECT_ROOT}/declarative/system.conf" 2>/dev/null || echo 0)" >> "${report_file}"
        echo "- Services defined: $(grep -c '^service\.' "${PROJECT_ROOT}/declarative/system.conf" 2>/dev/null || echo 0)" >> "${report_file}"
    else
        echo "- System config: ✗ Missing" >> "${report_file}"
    fi
    
    if [[ -f "${PROJECT_ROOT}/declarative/docker.conf" ]]; then
        echo "- Docker config: ✓ Present" >> "${report_file}"
    else
        echo "- Docker config: ✗ Missing" >> "${report_file}"
    fi
    
    echo "" >> "${report_file}"
    echo "## Recent Backup History" >> "${report_file}"
    if [[ -d "${PROJECT_ROOT}/inventory" ]]; then
        find "${PROJECT_ROOT}/inventory" -name "*.inventory" -exec ls -lt {} + | head -5 | while read -r line; do
            echo "- ${line}" >> "${report_file}"
        done
    else
        echo "- No inventory data found" >> "${report_file}"
    fi
    
    echo "" >> "${report_file}"
    echo "## Recommendations" >> "${report_file}"
    echo "- Run 'backup system' to update inventory" >> "${report_file}"
    echo "- Review declarative files before restore" >> "${report_file}"
    echo "- Use dry-run before actual restore" >> "${report_file}"
    
    log_success "Report generated: ${report_file}"
    echo
    cat "${report_file}"
}

# Main function
main() {
    check_arch
    
    while true; do
        show_banner
        show_menu
        
        read -p "Select option [0-9]: " choice
        
        case ${choice} in
            1)
                backup_system
                ;;
            2)
                restore_system
                ;;
            3)
                validate_system
                ;;
            4)
                backup_docker
                ;;
            5)
                restore_docker
                ;;
            6)
                validate_docker
                ;;
            7)
                dry_run
                ;;
            8)
                restore_with_excludes
                ;;
            9)
                generate_report
                ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option: ${choice}"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        clear
    done
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi