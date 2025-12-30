#!/usr/bin/env bash
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

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

get_docker_info() {
    local output_file="${1}"
    log_info "Collecting Docker system information..."

    cat > "${output_file}" << EOF
# Docker System Information
# Generated on: $(date)

## Docker Version
$(docker version --format 'Client: {{.Client.Version}}' 2>/dev/null || echo "unknown")
$(docker version --format 'Server: {{.Server.Version}}' 2>/dev/null || echo "unknown")

## Storage Driver
$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
EOF

    log_success "Docker system information collected"
}

find_compose_files() {
    local output_file="${1}"
    local search_paths=(
        "${HOME}"
        "/opt/docker"
        "/srv/docker"
    )

    log_info "Searching for docker-compose files..."

    > "${output_file}"

    # Exclude destination to prevent circular copies
    local exclude_path="${PROJECT_ROOT}/docker/compose"

    for search_path in "${search_paths[@]}"; do
        if [[ -d "${search_path}" ]]; then
            find "${search_path}" -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null | while read -r compose_file; do
                # Skip if in destination directory
                if [[ ! "${compose_file}" =~ ^${exclude_path} ]]; then
                    echo "${compose_file}" >> "${output_file}"
                    log_info "Found compose file: ${compose_file}"
                fi
            done || true
        fi
    done

    local compose_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    log_success "Found ${compose_count} docker-compose files"
}

copy_compose_files() {
    local compose_list="${1}"
    local dest_dir="${2}"

    log_info "Copying compose files to inventory..."
    mkdir -p "${dest_dir}"

    local compose_index=1
    local copied=0
    local skipped=0

    while IFS= read -r compose_file; do
        [[ -z "${compose_file}" ]] && continue

        local compose_dir
        compose_dir=$(dirname "${compose_file}")
        local project_name
        project_name=$(basename "${compose_dir}")

        # Generează nume unic pentru proiect
        if [[ "${project_name}" == "." ]] || [[ -z "${project_name}" ]]; then
            project_name="project_${compose_index}"
        fi

        local target_dir="${dest_dir}/${project_name}"
        local target_file="${target_dir}/$(basename "${compose_file}")"

        # Verifică dacă sursa și destinația sunt identice
        if [[ -f "${target_file}" ]] && [[ "$(realpath "${compose_file}" 2>/dev/null)" == "$(realpath "${target_file}" 2>/dev/null)" ]]; then
            log_info "Skipped (already in place): ${project_name}"
            ((skipped++))
        else
            mkdir -p "${target_dir}"
            if cp "${compose_file}" "${target_file}" 2>/dev/null; then
                log_info "Copied: ${project_name}/$(basename "${compose_file}")"
                ((copied++))
            else
                log_warn "Failed to copy: ${compose_file}"
            fi
        fi

        # Look for .env files
        if [[ -d "${compose_dir}" ]]; then
            local env_count=0
            while IFS= read -r env_file; do
                ((env_count++))
            done < <(find "${compose_dir}" -maxdepth 1 \( -name ".env" -o -name ".env.*" \) 2>/dev/null || true)

            if [[ ${env_count} -gt 0 ]]; then
                log_warn "Project ${project_name} has ${env_count} .env file(s) - create templates manually"

                cat > "${target_dir}/.env.template" << 'ENVEOF'
# Environment file template
# Copy to .env and configure
ENVEOF
            fi
        fi

        ((compose_index++))

    done < "${compose_list}"

    log_success "Copied ${copied} files, skipped ${skipped} existing"
}

get_volumes_info() {
    local output_file="${1}"
    log_info "Collecting Docker volumes information..."

    cat > "${output_file}" << EOF
# Docker Volumes
# Generated on: $(date)

## Named Volumes
$(docker volume ls --format '{{.Name}}' 2>/dev/null || echo "none")
EOF

    local volume_count
    volume_count=$(docker volume ls --quiet 2>/dev/null | wc -l || echo 0)
    log_success "Found ${volume_count} Docker volumes"
}

get_networks_info() {
    local output_file="${1}"
    log_info "Collecting Docker networks information..."

    cat > "${output_file}" << EOF
# Docker Networks
# Generated on: $(date)

## Custom Networks
$(docker network ls --filter "type=custom" --format '{{.Name}}' 2>/dev/null || echo "none")
EOF

    local network_count
    network_count=$(docker network ls --filter "type=custom" --quiet 2>/dev/null | wc -l || echo 0)
    log_success "Found ${network_count} custom Docker networks"
}

get_containers_info() {
    local output_file="${1}"
    log_info "Collecting running containers information..."

    cat > "${output_file}" << EOF
# Docker Containers
# Generated on: $(date)

## Running Containers
$(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null || echo "none")
EOF

    local container_count
    container_count=$(docker ps --quiet 2>/dev/null | wc -l || echo 0)
    log_info "Found ${container_count} running containers"
}

generate_volume_metadata() {
    local output_file="${1}"
    log_info "Generating volume metadata..."

    cat > "${output_file}" << 'VOLEOF'
# Docker Volume Metadata
# Generated on: $(date)

volume.default.backup=all
volume.default.restore=auto
VOLEOF

    log_success "Volume metadata generated"
}

generate_declarative_config() {
    local compose_files="${1}"
    local declarative_file="${2}"

    log_info "Generating declarative Docker configuration..."

    cat > "${declarative_file}" << EOF
# Declarative Docker Configuration
# Generated on: $(date)

# Docker Compose Projects
$(while IFS= read -r compose_file; do
    [[ -z "${compose_file}" ]] && continue
    local project_name
    project_name=$(basename "$(dirname "${compose_file}")")
    echo "docker.compose.${project_name}.state=present"
done < "${compose_files}")

# Docker Volumes
$(docker volume ls --quiet 2>/dev/null | while read -r volume; do
    [[ -z "${volume}" ]] && continue
    [[ "${volume}" =~ ^[a-f0-9]{64}$ ]] && continue
    echo "docker.volume.${volume}.state=present"
done || echo "# No named volumes")

# Docker Networks
$(docker network ls --filter "type=custom" --quiet 2>/dev/null | while read -r network; do
    [[ -z "${network}" ]] && continue
    local name
    name=$(docker network inspect "${network}" --format '{{.Name}}' 2>/dev/null || echo "${network}")
    echo "docker.network.${name}.state=present"
done || echo "# No custom networks")
EOF

    log_success "Declarative configuration generated"
}

generate_restore_script() {
    local restore_script="${1}"
    log_info "Generating Docker restore script..."

    cat > "${restore_script}" << 'RESTOREEOF'
#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }

main() {
    log_info "Docker restore functionality"
    log_info "Use docker-compose up -d in each project directory"
    log_success "Restore script generated"
}

main "$@"
RESTOREEOF

    chmod +x "${restore_script}"
    log_success "Restore script generated"
}

main() {
    if ! check_docker; then
        log_error "Docker inventory cannot proceed"
        exit 1
    fi

    local temp_info="${INVENTORY_DIR}/docker_info_${TIMESTAMP}.tmp"
    local temp_compose="${INVENTORY_DIR}/compose_files_${TIMESTAMP}.tmp"
    local temp_volumes="${INVENTORY_DIR}/volumes_${TIMESTAMP}.tmp"
    local temp_networks="${INVENTORY_DIR}/networks_${TIMESTAMP}.tmp"
    local temp_containers="${INVENTORY_DIR}/containers_${TIMESTAMP}.tmp"

    local inventory_file="${INVENTORY_DIR}/docker_${TIMESTAMP}.inventory"
    local declarative_file="${PROJECT_ROOT}/declarative/docker.conf"
    local volumes_meta="${PROJECT_ROOT}/docker/volumes.meta"
    local restore_script="${INVENTORY_DIR}/restore_docker.sh"
    local compose_dest_dir="${PROJECT_ROOT}/docker/compose"

    # Colectează informații
    get_docker_info "${temp_info}" || { log_error "Failed to get Docker info"; exit 1; }
    find_compose_files "${temp_compose}" || { log_error "Failed to find compose files"; exit 1; }
    get_volumes_info "${temp_volumes}" || { log_error "Failed to get volumes"; exit 1; }
    get_networks_info "${temp_networks}" || { log_error "Failed to get networks"; exit 1; }
    get_containers_info "${temp_containers}" || { log_error "Failed to get containers"; exit 1; }

    # Copiază fișiere
    copy_compose_files "${temp_compose}" "${compose_dest_dir}" || { log_error "Failed to copy compose files"; exit 1; }

    # Generează inventory
    cat > "${inventory_file}" << EOF
# Docker Infrastructure Inventory
# Generated on: $(date)

## Summary
- Compose projects: $(wc -l < "${temp_compose}" 2>/dev/null || echo 0)
- Volumes: $(docker volume ls -q 2>/dev/null | wc -l || echo 0)
- Networks: $(docker network ls --filter type=custom -q 2>/dev/null | wc -l || echo 0)
- Containers: $(docker ps -q 2>/dev/null | wc -l || echo 0)

$(cat "${temp_info}" 2>/dev/null || echo "# No info")
$(cat "${temp_volumes}" 2>/dev/null || echo "# No volumes")
$(cat "${temp_networks}" 2>/dev/null || echo "# No networks")
$(cat "${temp_containers}" 2>/dev/null || echo "# No containers")
EOF

    log_success "Docker inventory saved: ${inventory_file}"

    # Generează configurații
    generate_volume_metadata "${volumes_meta}" || log_warn "Volume metadata generation failed"
    generate_declarative_config "${temp_compose}" "${declarative_file}" || log_warn "Declarative config generation failed"
    generate_restore_script "${restore_script}" || log_warn "Restore script generation failed"

    # Cleanup
    rm -f "${temp_info}" "${temp_compose}" "${temp_volumes}" "${temp_networks}" "${temp_containers}" 2>/dev/null || true

    log_success "Docker inventory completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
