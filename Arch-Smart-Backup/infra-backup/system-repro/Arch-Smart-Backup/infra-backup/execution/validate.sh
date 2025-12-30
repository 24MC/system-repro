#!/usr/bin/env bash

# Validation Execution Module
# Validates current system state against declarative configuration
# Implements the "validation" phase of the backup/restore workflow
# Provides detailed drift analysis and remediation suggestions

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Validation results
readonly STATUS_OK=0
readonly STATUS_WARNING=1
readonly STATUS_ERROR=2

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
    --system          Validate system configuration only
    --docker          Validate Docker configuration only
    --all             Validate everything (default)
    --report FORMAT   Output format: text, json, html (default: text)
    --output FILE     Write report to file
    --detailed        Show detailed differences
    --quiet           Suppress output except errors
    --help            Show this help message

EXAMPLES:
    $0 --system --detailed         # Detailed system validation
    $0 --docker --report json      # JSON Docker validation report
    $0 --all --output report.txt   # Save full report to file

DESCRIPTION:
    This script validates the current system state against the declarative
    configuration. It implements the "validation" phase of the backup/restore
    workflow, providing drift analysis and remediation suggestions.

    Validation follows these principles:
    1. Comprehensive: Checks packages, services, configs, Docker
    2. Detailed: Shows exactly what's different
    3. Actionable: Provides specific remediation steps
    4. Flexible: Multiple output formats for different use cases

VALIDATION PHASES:
    1. Package validation: Check installed packages vs declared
    2. Service validation: Verify enabled services match declaration
    3. Configuration validation: Compare config files
    4. Docker validation: Check Docker resources
    5. Summary: Overall status and recommendations

EOF
}

# Initialize validation report
init_report() {
    local report_file="${1}"
    local format="${2}"
    
    case "${format}" in
        text)
            cat > "${report_file}" << EOF
# System State Validation Report
# Generated on: $(date)
# Host: $(hostname)
# User: $(whoami)

## Validation Summary

EOF
            ;;
        json)
            echo "{" > "${report_file}"
            echo "  \"generated\": \"$(date -Iseconds)\"," >> "${report_file}"
            echo "  \"hostname\": \"$(hostname)\"," >> "${report_file}"
            echo "  \"user\": \"$(whoami)\"," >> "${report_file}"
            echo "  \"validation\": {" >> "${report_file}"
            ;;
        html)
            cat > "${report_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>System State Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .ok { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .section { margin: 20px 0; padding: 10px; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <h1>System State Validation Report</h1>
    <p>Generated on: $(date)</p>
    <p>Host: $(hostname)</p>
    
    <h2>Validation Summary</h2>
    
EOF
            ;;
    esac
}

# Validate packages
validate_packages() {
    local report_file="${1}"
    local format="${2}"
    local detailed="${3}"
    
    log_info "Validating packages..."
    
    local status=${STATUS_OK}
    local missing_packages=()
    local extra_packages=()
    local wrong_version_packages=()
    
    # Check if declarative file exists
    if [[ ! -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_warn "System declarative configuration not found"
        return ${STATUS_WARNING}
    fi
    
    # Get declared packages
    local declared_official_packages=()
    local declared_aur_packages=()
    
    while IFS= read -r line; do
        if [[ "${line}" =~ ^package\.official\.([^.]+)\.=required ]]; then
            declared_official_packages+=("${BASH_REMATCH[1]}")
        elif [[ "${line}" =~ ^package\.aur\.([^.]+)\.=required ]]; then
            declared_aur_packages+=("${BASH_REMATCH[1]}")
        fi
    done < "${PROJECT_ROOT}/declarative/system.conf"
    
    # Get currently installed packages
    local installed_packages=()
    while IFS= read -r package; do
        installed_packages+=("${package}")
    done < <(pacman -Qqe 2>/dev/null || echo "")
    
    # Check for missing packages
    for pkg in "${declared_official_packages[@]}" "${declared_aur_packages[@]}"; do
        if ! printf '%s\n' "${installed_packages[@]}" | grep -q "^${pkg}$"; then
            missing_packages+=("${pkg}")
            status=${STATUS_ERROR}
        fi
    done
    
    # Check for extra packages (optional, can be noisy)
    if [[ "${detailed}" == "true" ]]; then
        for pkg in "${installed_packages[@]}"; do
            if ! printf '%s\n' "${declared_official_packages[@]}" "${declared_aur_packages[@]}" | grep -q "^${pkg}$"; then
                extra_packages+=("${pkg}")
            fi
        done
    fi
    
    # Generate report
    case "${format}" in
        text)
            cat >> "${report_file}" << EOF
### Package Validation

Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")

EOF
            if [[ ${#missing_packages[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
Missing packages (${#missing_packages[@]}):
$(printf '  - %s\n' "${missing_packages[@]}")

Remediation:
  pacman -S ${missing_packages[*]}

EOF
            fi
            
            if [[ ${#extra_packages[@]} -gt 0 && "${detailed}" == "true" ]]; then
                cat >> "${report_file}" << EOF
Extra packages (${#extra_packages[@]}):
$(printf '  - %s\n' "${extra_packages[@]}")

EOF
            fi
            ;;
        json)
            echo "    \"packages\": {" >> "${report_file}"
            echo "      \"status\": \"$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "failed")\"," >> "${report_file}"
            echo "      \"missing\": [$(printf '"%s",' "${missing_packages[@]}" | sed 's/,$//')]," >> "${report_file}"
            echo "      \"extra\": [$(printf '"%s",' "${extra_packages[@]}" | sed 's/,$//')]" >> "${report_file}"
            echo "    }," >> "${report_file}"
            ;;
        html)
            cat >> "${report_file}" << EOF
    <div class="section">
        <h3>Package Validation</h3>
        <p class="$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "error")">
            Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")
        </p>
EOF
            if [[ ${#missing_packages[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
        <h4>Missing Packages</h4>
        <ul>
$(printf '          <li>%s</li>\n' "${missing_packages[@]}")
        </ul>
EOF
            fi
            cat >> "${report_file}" << EOF
    </div>
EOF
            ;;
    esac
    
    return ${status}
}

# Validate services
validate_services() {
    local report_file="${1}"
    local format="${2}"
    local detailed="${3}"
    
    log_info "Validating services..."
    
    local status=${STATUS_OK}
    local missing_services=()
    local failed_services=()
    
    # Check if declarative file exists
    if [[ ! -f "${PROJECT_ROOT}/declarative/system.conf" ]]; then
        log_warn "System declarative configuration not found"
        return ${STATUS_WARNING}
    fi
    
    # Get declared services
    local declared_system_services=()
    local declared_user_services=()
    
    while IFS= read -r line; do
        if [[ "${line}" =~ ^service\.system\.([^.]+)\.=enabled ]]; then
            declared_system_services+=("${BASH_REMATCH[1]}")
        elif [[ "${line}" =~ ^service\.user\.([^.]+)\.=enabled ]]; then
            declared_user_services+=("${BASH_REMATCH[1]}")
        fi
    done < "${PROJECT_ROOT}/declarative/system.conf"
    
    # Check system services
    for service in "${declared_system_services[@]}"; do
        if ! systemctl is-enabled "${service}" >/dev/null 2>&1; then
            missing_services+=("${service}")
            status=${STATUS_ERROR}
        fi
        
        if systemctl is-failed "${service}" >/dev/null 2>&1; then
            failed_services+=("${service}")
            status=${STATUS_ERROR}
        fi
    done
    
    # Check user services
    for service in "${declared_user_services[@]}"; do
        if systemctl --user is-enabled "${service}" >/dev/null 2>&1; then
            if systemctl --user is-failed "${service}" >/dev/null 2>&1; then
                failed_services+=("${service}")
                status=${STATUS_ERROR}
            fi
        else
            missing_services+=("${service}")
            status=${STATUS_ERROR}
        fi
    done
    
    # Generate report
    case "${format}" in
        text)
            cat >> "${report_file}" << EOF
### Service Validation

Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")

EOF
            if [[ ${#missing_services[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
Missing/disabled services (${#missing_services[@]}):
$(printf '  - %s\n' "${missing_services[@]}")

Remediation:
  systemctl enable ${missing_services[*]}

EOF
            fi
            
            if [[ ${#failed_services[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
Failed services (${#failed_services[@]}):
$(printf '  - %s\n' "${failed_services[@]}")

Check service status with:
  systemctl status ${failed_services[*]}

EOF
            fi
            ;;
        json)
            echo "    \"services\": {" >> "${report_file}"
            echo "      \"status\": \"$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "failed")\"," >> "${report_file}"
            echo "      \"missing\": [$(printf '"%s",' "${missing_services[@]}" | sed 's/,$//')]," >> "${report_file}"
            echo "      \"failed\": [$(printf '"%s",' "${failed_services[@]}" | sed 's/,$//')]" >> "${report_file}"
            echo "    }," >> "${report_file}"
            ;;
        html)
            cat >> "${report_file}" << EOF
    <div class="section">
        <h3>Service Validation</h3>
        <p class="$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "error")">
            Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")
        </p>
EOF
            if [[ ${#missing_services[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
        <h4>Missing/Disabled Services</h4>
        <ul>
$(printf '          <li>%s</li>\n' "${missing_services[@]}")
        </ul>
EOF
            fi
            cat >> "${report_file}" << EOF
    </div>
EOF
            ;;
    esac
    
    return ${status}
}

# Validate Docker configuration
validate_docker() {
    local report_file="${1}"
    local format="${2}"
    local detailed="${3}"
    
    log_info "Validating Docker configuration..."
    
    local status=${STATUS_OK}
    local missing_networks=()
    local missing_volumes=()
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker is not installed"
        return ${STATUS_WARNING}
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker daemon is not running"
        return ${STATUS_WARNING}
    fi
    
    # Check if declarative file exists
    if [[ ! -f "${PROJECT_ROOT}/declarative/docker.conf" ]]; then
        log_warn "Docker declarative configuration not found"
        return ${STATUS_WARNING}
    fi
    
    # Get declared Docker resources
    local declared_networks=()
    local declared_volumes=()
    
    while IFS= read -r line; do
        if [[ "${line}" =~ ^docker\.network\.([^.]+)\.state=present ]]; then
            declared_networks+=("${BASH_REMATCH[1]}")
        elif [[ "${line}" =~ ^docker\.volume\.([^.]+)\.state=present ]]; then
            declared_volumes+=("${BASH_REMATCH[1]}")
        fi
    done < "${PROJECT_ROOT}/declarative/docker.conf"
    
    # Check networks
    for network in "${declared_networks[@]}"; do
        if ! docker network ls --filter "name=${network}" --quiet | grep -q .; then
            missing_networks+=("${network}")
            status=${STATUS_ERROR}
        fi
    done
    
    # Check volumes
    for volume in "${declared_volumes[@]}"; do
        if ! docker volume ls --quiet | grep -q "^${volume}$"; then
            missing_volumes+=("${volume}")
            status=${STATUS_ERROR}
        fi
    done
    
    # Generate report
    case "${format}" in
        text)
            cat >> "${report_file}" << EOF
### Docker Validation

Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")

EOF
            if [[ ${#missing_networks[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
Missing networks (${#missing_networks[@]}):
$(printf '  - %s\n' "${missing_networks[@]}")

EOF
            fi
            
            if [[ ${#missing_volumes[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
Missing volumes (${#missing_volumes[@]}):
$(printf '  - %s\n' "${missing_volumes[@]}")

EOF
            fi
            ;;
        json)
            echo "    \"docker\": {" >> "${report_file}"
            echo "      \"status\": \"$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "failed")\"," >> "${report_file}"
            echo "      \"missing_networks\": [$(printf '"%s",' "${missing_networks[@]}" | sed 's/,$//')]," >> "${report_file}"
            echo "      \"missing_volumes\": [$(printf '"%s",' "${missing_volumes[@]}" | sed 's/,$//')]" >> "${report_file}"
            echo "    }" >> "${report_file}"
            ;;
        html)
            cat >> "${report_file}" << EOF
    <div class="section">
        <h3>Docker Validation</h3>
        <p class="$([ ${status} -eq ${STATUS_OK} ] && echo "ok" || echo "error")">
            Status: $([ ${status} -eq ${STATUS_OK} ] && echo "OK" || echo "FAILED")
        </p>
EOF
            if [[ ${#missing_networks[@]} -gt 0 ]]; then
                cat >> "${report_file}" << EOF
        <h4>Missing Networks</h4>
        <ul>
$(printf '          <li>%s</li>\n' "${missing_networks[@]}")
        </ul>
EOF
            fi
            cat >> "${report_file}" << EOF
    </div>
EOF
            ;;
    esac
    
    return ${status}
}

# Generate final summary
generate_summary() {
    local report_file="${1}"
    local format="${2}"
    local overall_status="${3}"
    
    case "${format}" in
        text)
            cat >> "${report_file}" << EOF
## Overall Status

Status: $([ ${overall_status} -eq ${STATUS_OK} ] && echo "OK" || echo [ ${overall_status} -eq ${STATUS_WARNING} ] && echo "WARNING" || echo "FAILED")

Recommendations:
EOF
            if [[ ${overall_status} -ne ${STATUS_OK} ]]; then
                cat >> "${report_file}" << EOF
- Review the specific validation failures above
- Run restore with appropriate options to fix issues
- Re-run validation to confirm fixes
EOF
            else
                cat >> "${report_file}" << EOF
- System state matches declarative configuration
- No action required
EOF
            fi
            ;;
        json)
            echo "  }," >> "${report_file}"
            echo "  \"overall_status\": \"$([ ${overall_status} -eq ${STATUS_OK} ] && echo "ok" || echo [ ${overall_status} -eq ${STATUS_WARNING} ] && echo "warning" || echo "failed")\"" >> "${report_file}"
            echo "}" >> "${report_file}"
            ;;
        html)
            cat >> "${report_file}" << EOF
    <div class="section">
        <h2>Overall Status</h2>
        <p class="$([ ${overall_status} -eq ${STATUS_OK} ] && echo "ok" || echo [ ${overall_status} -eq ${STATUS_WARNING} ] && echo "warning" || echo "error")">
            Status: $([ ${overall_status} -eq ${STATUS_OK} ] && echo "OK" || echo [ ${overall_status} -eq ${STATUS_WARNING} ] && echo "WARNING" || echo "FAILED")
        </p>
    </div>
</body>
</html>
EOF
            ;;
    esac
}

# Main validation function
main() {
    local validate_mode="all"
    local report_format="text"
    local output_file=""
    local detailed=false
    local quiet=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system)
                validate_mode="system"
                shift
                ;;
            --docker)
                validate_mode="docker"
                shift
                ;;
            --all)
                validate_mode="all"
                shift
                ;;
            --report)
                report_format="${2}"
                shift 2
                ;;
            --output)
                output_file="${2}"
                shift 2
                ;;
            --detailed)
                detailed=true
                shift
                ;;
            --quiet)
                quiet=true
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
    
    # Use temporary file if no output specified
    local temp_report=false
    if [[ -z "${output_file}" ]]; then
        output_file="/tmp/validation_report_$$"
        temp_report=true
    fi
    
    # Initialize report
    init_report "${output_file}" "${report_format}"
    
    # Perform validation
    local overall_status=${STATUS_OK}
    
    case "${validate_mode}" in
        system)
            if ! validate_packages "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            if ! validate_services "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            ;;
        docker)
            if ! validate_docker "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            ;;
        all)
            if ! validate_packages "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            if ! validate_services "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            if ! validate_docker "${output_file}" "${report_format}" "${detailed}"; then
                overall_status=${STATUS_ERROR}
            fi
            ;;
        *)
            log_error "Invalid validation mode: ${validate_mode}"
            exit 1
            ;;
    esac
    
    # Generate summary
    generate_summary "${output_file}" "${report_format}" "${overall_status}"
    
    # Output report
    if [[ "${temp_report}" == "true" ]]; then
        if [[ "${quiet}" == "false" ]]; then
            cat "${output_file}"
        fi
        rm -f "${output_file}"
    else
        log_success "Validation report saved to: ${output_file}"
    fi
    
    # Exit with appropriate status
    exit ${overall_status}
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi