#!/usr/bin/env bash

# Package Inventory Module
# Collects explicitly installed packages (pacman + AUR)
# Separates official packages from AUR packages
# Generates declarative package lists for reproducible installations

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

get_pacman_packages() {
    local output_file="${1}"
    log_info "Collecting explicitly installed pacman packages..."
    pacman -Qqe | grep -v '^$' | sort > "${output_file}"
    local package_count=$(wc -l < "${output_file}")
    log_success "Found ${package_count} explicitly installed packages"
}

separate_aur_packages() {
    local all_packages="$1"
    local aur_packages="$2"
    local official_packages="$3"

    log_info "Separating AUR packages using pacman -Qm (repo-agnostic)"

    pacman -Qm | awk '{print $1}' | sort > "${aur_packages}" 2>/dev/null || touch "${aur_packages}"

    if [[ -s "${aur_packages}" ]]; then
        grep -vxF -f "${aur_packages}" "${all_packages}" > "${official_packages}" || touch "${official_packages}"
    else
        cp "${all_packages}" "${official_packages}"
    fi

    local official_count aur_count
    official_count=$(wc -l < "${official_packages}" 2>/dev/null || echo 0)
    aur_count=$(wc -l < "${aur_packages}" 2>/dev/null || echo 0)

    log_success "Separated: ${official_count} official, ${aur_count} AUR packages"
}

generate_declarative_config() {
    local official_packages="${1}"
    local aur_packages="${2}"
    local declarative_file="${3}"

    log_info "Generating declarative package configuration..."

    cat > "${declarative_file}" << EOF
# Declarative Package Configuration
# Generated on: $(date)

# Official packages (from Arch repositories)
$(while IFS= read -r package; do
    [[ -n "${package}" ]] && echo "package.official.${package}=required"
done < "${official_packages}")

# AUR packages (from Arch User Repository)
$(while IFS= read -r package; do
    [[ -n "${package}" ]] && echo "package.aur.${package}=required"
done < "${aur_packages}")
EOF

    log_success "Declarative configuration generated: ${declarative_file}"
}

generate_install_script() {
    local official_packages="${1}"
    local aur_packages="${2}"
    local install_script="${3}"

    log_info "Generating package installation script..."

    cat > "${install_script}" << 'INSTALLEOF'
#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

detect_aur_helper() {
    for helper in yay paru aura; do
        if command -v "${helper}" >/dev/null 2>&1; then
            echo "${helper}"
            return 0
        fi
    done
    return 1
}

install_official_packages() {
    local package_list=(
INSTALLEOF

    while IFS= read -r package; do
        [[ -n "${package}" ]] && echo "        ${package}" >> "${install_script}"
    done < "${official_packages}"

    cat >> "${install_script}" << 'INSTALLEOF2'
    )

    log_info "Installing official packages..."

    if [[ ${#package_list[@]} -gt 0 ]]; then
        pacman -Syu --needed --noconfirm "${package_list[@]}"
        log_success "Official packages installed"
    fi
}

install_aur_packages() {
    local package_list=(
INSTALLEOF2

    while IFS= read -r package; do
        [[ -n "${package}" ]] && echo "        ${package}" >> "${install_script}"
    done < "${aur_packages}"

    cat >> "${install_script}" << 'INSTALLEOF3'
    )

    if [[ ${#package_list[@]} -gt 0 ]]; then
        local aur_helper
        if ! aur_helper=$(detect_aur_helper); then
            log_error "No AUR helper found. Install yay or paru first"
            return 1
        fi

        log_info "Installing AUR packages using ${aur_helper}..."
        "${aur_helper}" -S --needed --noconfirm "${package_list[@]}"
        log_success "AUR packages installed"
    fi
}

main() {
    check_root
    log_info "Starting package installation..."
    pacman -Sy
    install_official_packages
    install_aur_packages
    log_success "Package installation completed!"
}

main "$@"
INSTALLEOF3

    chmod +x "${install_script}"
    log_success "Installation script generated: ${install_script}"
}

main() {
    local temp_all="${INVENTORY_DIR}/all_packages_${TIMESTAMP}.tmp"
    local temp_aur="${INVENTORY_DIR}/aur_packages_${TIMESTAMP}.tmp"
    local temp_official="${INVENTORY_DIR}/official_packages_${TIMESTAMP}.tmp"

    local inventory_file="${INVENTORY_DIR}/packages_${TIMESTAMP}.inventory"
    local declarative_file="${PROJECT_ROOT}/declarative/system.conf"
    local install_script="${INVENTORY_DIR}/install_packages.sh"

    get_pacman_packages "${temp_all}"
    separate_aur_packages "${temp_all}" "${temp_aur}" "${temp_official}"

    cat > "${inventory_file}" << EOF
# Package Inventory
# Generated on: $(date)
# Host: $(hostname)

## Total Packages: $(wc -l < "${temp_all}")
## Official: $(wc -l < "${temp_official}")
## AUR: $(wc -l < "${temp_aur}")

### Official Packages
$(cat "${temp_official}")

### AUR Packages
$(cat "${temp_aur}")
EOF

    log_success "Inventory saved: ${inventory_file}"

    generate_declarative_config "${temp_official}" "${temp_aur}" "${declarative_file}"
    generate_install_script "${temp_official}" "${temp_aur}" "${install_script}"

    rm -f "${temp_all}" "${temp_aur}" "${temp_official}"

    log_info "Package inventory completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
