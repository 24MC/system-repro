#!/usr/bin/env bash

# Docker Inventory Module
# Collects Docker configuration, compose files, and volume metadata
# Does NOT backup container images (they should be reproducible from compose)
# Focuses on declarative state: what should exist, not what currently exists

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Get Docker system information
get_docker_info() {
    local output_file="${1}"
    
    log_info "Collecting Docker system information..."
    
    cat > "${output_file}" << EOF
# Docker System Information
# Generated on: $(date)
# Host: $(hostname)

## Docker Version
$(docker version --format 'Client: {{.Client.Version}}' 2>/dev/null || echo "Client: unknown")
$(docker version --format 'Server: {{.Server.Version}}' 2>/dev/null || echo "Server: unknown")

## Docker Info
$(docker info 2>/dev/null | head -20 || echo "Docker info unavailable")

## Storage Driver
$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")

## Root Directory
$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "unknown")

EOF
    
    log_success "Docker system information collected"
}

# Find docker-compose files
find_compose_files() {
    local output_file="${1}"
    local search_paths=(
        "${HOME}"
        "${HOME}/docker"
        "${HOME}/containers"
        "${HOME}/compose"
        "/opt/docker"
        "/srv/docker"
        "${PROJECT_ROOT}/docker/compose"
    )
    
    log_info "Searching for docker-compose files..."
    
    # Common compose file names
    local compose_names=(
        "docker-compose.yml"
        "docker-compose.yaml"
        "compose.yml"
        "compose.yaml"
    )
    
    > "${output_file}"
    
    for search_path in "${search_paths[@]}"; do
        if [[ -d "${search_path}" ]]; then
            for compose_name in "${compose_names[@]}"; do
                find "${search_path}" -name "${compose_name}" -type f 2>/dev/null | while read -r compose_file; do
                    echo "${compose_file}" >> "${output_file}"
                    log_info "Found compose file: ${compose_file}"
                done
            done
        fi
    done
    
    local compose_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    log_success "Found ${compose_count} docker-compose files"
}

# Copy compose files to inventory
copy_compose_files() {
    local compose_list="${1}"
    local dest_dir="${2}"
    
    log_info "Copying compose files to inventory..."
    
    mkdir -p "${dest_dir}"
    
    local compose_index=1
    while IFS= read -r compose_file; do
        [[ -z "${compose_file}" ]] && continue
        
        local compose_name
        compose_name=$(basename "${compose_file}")
        local compose_dir
        compose_dir=$(dirname "${compose_file}")
        
        # Create a unique name for this compose project
        local project_name
        project_name=$(basename "${compose_dir}")
        if [[ "${project_name}" == "${compose_name}" ]] || [[ "${project_name}" == "." ]]; then
            project_name="project_${compose_index}"
            ((compose_index++))
        fi
        
        local target_dir="${dest_dir}/${project_name}"
        mkdir -p "${target_dir}"
        
        # Copy the main compose file
        cp "${compose_file}" "${target_dir}/"
        log_info "Copied: ${compose_file} -> ${target_dir}/"
        
        # Look for additional compose files (overrides, etc.)
        local compose_base
        compose_base="${compose_file%.*}"
        
        # Common override patterns
        local override_patterns=(
            "${compose_base}.override.yml"
            "${compose_base}.override.yaml"
            "${compose_base}.prod.yml"
            "${compose_base}.prod.yaml"
            "${compose_base}.dev.yml"
            "${compose_base}.dev.yaml"
            "${compose_base}.local.yml"
            "${compose_base}.local.yaml"
        )
        
        for override_file in "${override_patterns[@]}"; do
            if [[ -f "${override_file}" ]]; then
                cp "${override_file}" "${target_dir}/"
                log_info "Copied override: ${override_file}"
            fi
        done
        
        # Look for .env files (but don't copy them - they're sensitive)
        local env_files=()
        while IFS= read -r env_file; do
            env_files+=("${env_file}")
        done < <(find "${compose_dir}" -maxdepth 1 -name ".env*" -o -name "*.env" 2>/dev/null)
        
        if [[ ${#env_files[@]} -gt 0 ]]; then
            log_warn "Found .env files (NOT copied for security):"
            printf '  - %s\n' "${env_files[@]}"
            
            # Create a template .env file
            cat > "${target_dir}/.env.template" << EOF
# Environment Variables Template
# Copy this to .env and fill in your values
# DO NOT commit actual .env files to version control

# Example variables (replace with actual ones from your .env files):
# DATABASE_PASSWORD=your_password_here
# API_KEY=your_api_key_here
# DOMAIN_NAME=your_domain.com

EOF
            
            # Try to extract variable names without values
            for env_file in "${env_files[@]}"; do
                if [[ -r "${env_file}" ]]; then
                    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${env_file}" 2>/dev/null | \
                        sed 's/=.*/=/' | \
                        sed 's/^/# /' >> "${target_dir}/.env.template"
                fi
            done
        fi
        
        # Check for additional configuration files
        local config_files=()
        while IFS= read -r config_file; do
            config_files+=("${config_file}")
        done < <(find "${compose_dir}" -name "*.conf" -o -name "*.config" -o -name "config" -type f 2>/dev/null)
        
        if [[ ${#config_files[@]} -gt 0 ]]; then
            local config_dir="${target_dir}/config"
            mkdir -p "${config_dir}"
            
            for config_file in "${config_files[@]}"; do
                cp "${config_file}" "${config_dir}/"
                log_info "Copied config: ${config_file}"
            done
        fi
        
    done < "${compose_list}"
}

# Get Docker volumes information
get_volumes_info() {
    local output_file="${1}"
    
    log_info "Collecting Docker volumes information..."
    
    cat > "${output_file}" << EOF
# Docker Volumes Information
# Generated on: $(date)
# Host: $(hostname)

## Named Volumes
$(docker volume ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null || echo "No volumes found")

## Volume Details
$(docker volume ls --quiet 2>/dev/null | while read -r volume; do
    echo "=== Volume: ${volume} ==="
    docker volume inspect "${volume}" 2>/dev/null || echo "Inspect failed"
    echo ""
done || echo "No volume details available")

## Anonymous Volumes
$(docker volume ls --filter "dangling=true" --format 'table {{.Name}}\t{{.Driver}}' 2>/dev/null || echo "No anonymous volumes")

EOF
    
    local volume_count
    volume_count=$(docker volume ls --quiet 2>/dev/null | wc -l || echo 0)
    log_success "Found ${volume_count} Docker volumes"
}

# Get Docker networks information
get_networks_info() {
    local output_file="${1}"
    
    log_info "Collecting Docker networks information..."
    
    cat > "${output_file}" << EOF
# Docker Networks Information
# Generated on: $(date)
# Host: $(hostname)

## Custom Networks
$(docker network ls --filter "type=custom" --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null || echo "No custom networks")

## Network Details
$(docker network ls --filter "type=custom" --quiet 2>/dev/null | while read -r network; do
    echo "=== Network: ${network} ==="
    docker network inspect "${network}" 2>/dev/null | jq '.[] | {Name: .Name, Driver: .Driver, Subnet: .IPAM.Config[0].Subnet}' || echo "Inspect failed"
    echo ""
done || echo "No network details available")

## Default Networks
$(docker network ls --filter "type=builtin" --format 'table {{.Name}}\t{{.Driver}}' 2>/dev/null)

EOF
    
    local network_count
    network_count=$(docker network ls --filter "type=custom" --quiet 2>/dev/null | wc -l || echo 0)
    log_success "Found ${network_count} custom Docker networks"
}

# Get running containers information (for reference only)
get_containers_info() {
    local output_file="${1}"
    
    log_info "Collecting running containers information..."
    
    cat > "${output_file}" << EOF
# Docker Containers Information
# Generated on: $(date)
# Host: $(hostname)

## Running Containers
$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "No running containers")

## Container Details (for reference only)
# This is NOT used for restore - compose files are the source of truth
$(docker ps --quiet 2>/dev/null | while read -r container; do
    echo "=== Container: $(docker inspect "${container}" --format '{{.Name}}' 2>/dev/null || echo "unknown") ==="
    echo "Image: $(docker inspect "${container}" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")"
    echo "Created: $(docker inspect "${container}" --format '{{.Created}}' 2>/dev/null || echo "unknown")"
    echo "Volumes: $(docker inspect "${container}" --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' 2>/dev/null || echo "none")"
    echo ""
done || echo "No container details available")

## Exited Containers
$(docker ps -a --filter "status=exited" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo "No exited containers")

EOF
    
    local container_count
    container_count=$(docker ps --quiet 2>/dev/null | wc -l || echo 0)
    log_info "Found ${container_count} running containers (for reference only)"
}

# Generate volume metadata for backup/restore
generate_volume_metadata() {
    local output_file="${1}"
    
    log_info "Generating volume metadata for backup/restore..."
    
    cat > "${output_file}" << 'EOF'
# Docker Volume Backup/Restore Metadata
# This file defines how volumes should be handled during backup/restore

# Volume Backup Policy
# Format: volume.<name>.backup=<policy>
# Policies:
#   - all: Backup all data in this volume
#   - metadata: Only backup metadata (structure, not content)
#   - none: Skip this volume during backup
#   - custom: Use custom backup script

# Volume Restore Policy
# Format: volume.<name>.restore=<policy>
# Policies:
#   - auto: Restore automatically if volume doesn't exist
#   - prompt: Ask before restoring
#   - skip: Never restore this volume
#   - init-only: Only create empty volume (for databases that initialize themselves)

# Default policies
volume.default.backup=all
volume.default.restore=auto

# Example configurations (customize for your volumes):

# Database volumes - backup all data, restore automatically
# volume.postgres_data.backup=all
# volume.postgres_data.restore=auto
# volume.mysql_data.backup=all
# volume.mysql_data.restore=auto

# Cache volumes - backup metadata only (they can be rebuilt)
# volume.redis_cache.backup=metadata
# volume.redis_cache.restore=init-only

# Temporary volumes - skip backup entirely
# volume.temp_data.backup=none
# volume.temp_data.restore=skip

# Sensitive volumes - prompt before restore
# volume.app_secrets.backup=all
# volume.app_secrets.restore=prompt

EOF
    
    # Try to auto-detect some common volumes and suggest policies
    docker volume ls --quiet 2>/dev/null | while read -r volume; do
        [[ -z "${volume}" ]] && continue
        
        # Skip anonymous volumes
        [[ "${volume}" =~ ^[a-f0-9]{64}$ ]] && continue
        
        # Guess volume type based on name
        local policy="all"
        local restore_policy="auto"
        
        if [[ "${volume}" =~ (cache|temp|tmp|session) ]]; then
            policy="metadata"
            restore_policy="init-only"
        elif [[ "${volume}" =~ (secret|key|cert|password) ]]; then
            policy="all"
            restore_policy="prompt"
        elif [[ "${volume}" =~ (db|database|postgres|mysql|mongo) ]]; then
            policy="all"
            restore_policy="auto"
        fi
        
        echo "volume.${volume}.backup=${policy}" >> "${output_file}"
        echo "volume.${volume}.restore=${restore_policy}" >> "${output_file}"
        
    done 2>/dev/null || true
    
    log_success "Volume metadata generated: ${output_file}"
}

# Generate declarative Docker configuration
generate_declarative_config() {
    local compose_files="${1}"
    local volumes_info="${2}"
    local networks_info="${3}"
    local declarative_file="${4}"
    
    log_info "Generating declarative Docker configuration..."
    
    cat > "${declarative_file}" << EOF
# Declarative Docker Configuration
# Generated on: $(date)
# This file defines what Docker resources SHOULD exist
# Edit this file to declare desired state, not current state

# Docker Compose Projects
# These define your application stacks
$(while IFS= read -r compose_file; do
    [[ -z "${compose_file}" ]] && continue
    local project_name
    project_name=$(basename "$(dirname "${compose_file}")")
    echo "docker.compose.${project_name}.file=inventory/docker/compose/${project_name}/$(basename "${compose_file}")"
    echo "docker.compose.${project_name}.state=present"
done < "${compose_files}")

# Docker Volumes
# These volumes will be created if they don't exist
$(docker volume ls --quiet 2>/dev/null | while read -r volume; do
    [[ -z "${volume}" ]] && continue
    # Skip anonymous volumes (64-char hex)
    [[ "${volume}" =~ ^[a-f0-9]{64}$ ]] && continue
    echo "docker.volume.${volume}.state=present"
    echo "docker.volume.${volume}.driver=local"
done 2>/dev/null || echo "# No named volumes found")

# Docker Networks
# These networks will be created if they don't exist
$(docker network ls --filter "type=custom" --quiet 2>/dev/null | while read -r network; do
    [[ -z "${network}" ]] && continue
    local network_name
    network_name=$(docker network inspect "${network}" --format '{{.Name}}' 2>/dev/null || echo "${network}")
    echo "docker.network.${network_name}.state=present"
    echo "docker.network.${network_name}.driver=bridge"
done 2>/dev/null || echo "# No custom networks found")

# Docker Configuration Policy
# Define how Docker should be managed

# Auto-start policy for compose projects
# docker.policy.autostart=true

# Backup policy for volumes
# docker.policy.backup=true

# Prune policy (remove unused resources)
# docker.policy.prune.dangling=true
# docker.policy.prune.volumes=false
# docker.policy.prune.networks=true

# Registry configuration
# docker.registry.default=docker.io
# docker.registry.mirror=https://mirror.gcr.io

# Resource limits
# docker.resource.default.memory=2g
# docker.resource.default.cpus=1.0

EOF
    
    log_success "Declarative Docker configuration generated: ${declarative_file}"
}

# Generate Docker restore script
generate_restore_script() {
    local restore_script="${1}"
    
    log_info "Generating Docker restore script..."
    
    cat > "${restore_script}" << 'EOF'
#!/usr/bin/env bash
# Docker Restore Script
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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        log_info "Install Docker: pacman -S docker"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        log_info "Start Docker: systemctl start docker"
        exit 1
    fi
}

# Check if docker-compose is available
check_compose() {
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        log_info "Install docker-compose: pacman -S docker-compose"
        exit 1
    fi
}

# Restore Docker volumes
restore_volumes() {
    local volumes_meta="${SCRIPT_DIR}/../volumes.meta"
    
    if [[ ! -f "${volumes_meta}" ]]; then
        log_warn "No volume metadata found, skipping volume restore"
        return 0
    fi
    
    log_info "Restoring Docker volumes..."
    
    # This is a placeholder - actual volume data restore happens separately
    # after the services are initialized
    
    log_info "Volume metadata processed (data restore happens after service initialization)"
}

# Restore Docker networks
restore_networks() {
    log_info "Restoring Docker networks..."
    
    # Get custom networks from declarative configuration
    local declarative_file="${PROJECT_ROOT}/declarative/docker.conf"
    
    if [[ -f "${declarative_file}" ]]; then
        grep '^docker.network\.' "${declarative_file}" | while read -r line; do
            if [[ "${line}" =~ docker\.network\.([^.]+)\.state=present ]]; then
                local network_name="${BASH_REMATCH[1]}"
                
                if ! docker network ls --filter "name=${network_name}" --quiet | grep -q .; then
                    log_info "Creating network: ${network_name}"
                    docker network create "${network_name}" || log_warn "Failed to create network: ${network_name}"
                else
                    log_info "Network already exists: ${network_name}"
                fi
            fi
        done
    fi
    
    log_success "Docker networks restored"
}

# Restore Docker Compose projects
restore_compose_projects() {
    local compose_dir="${SCRIPT_DIR}/../compose"
    
    if [[ ! -d "${compose_dir}" ]]; then
        log_warn "No compose projects found in inventory"
        return 0
    fi
    
    log_info "Restoring Docker Compose projects..."
    
    find "${compose_dir}" -name "docker-compose*.yml" -o -name "compose*.yml" | while read -r compose_file; do
        local project_dir
        project_dir=$(dirname "${compose_file}")
        local project_name
        project_name=$(basename "${project_dir}")
        
        log_info "Processing project: ${project_name}"
        
        # Check if .env file exists (template)
        if [[ -f "${project_dir}/.env.template" ]]; then
            if [[ ! -f "${project_dir}/.env" ]]; then
                log_warn "Missing .env file for project ${project_name}"
                log_info "Copy .env.template to .env and configure it"
                continue
            fi
        fi
        
        # Pull images first
        log_info "Pulling images for ${project_name}..."
        cd "${project_dir}"
        
        if docker-compose pull 2>/dev/null; then
            log_success "Images pulled for ${project_name}"
        elif docker compose pull 2>/dev/null; then
            log_success "Images pulled for ${project_name} (using docker compose)"
        else
            log_warn "Failed to pull some images for ${project_name}"
        fi
        
        # Create and start containers (don't restore volumes yet)
        log_info "Creating containers for ${project_name}..."
        
        if docker-compose up --no-start 2>/dev/null; then
            log_success "Containers created for ${project_name}"
        elif docker compose up --no-start 2>/dev/null; then
            log_success "Containers created for ${project_name} (using docker compose)"
        else
            log_error "Failed to create containers for ${project_name}"
            continue
        fi
        
        cd - >/dev/null
        
    done
    
    log_success "Docker Compose projects restored (containers created)"
}

# Main restore function
main() {
    local mode="${1:-all}"
    
    check_docker
    check_compose
    
    case "${mode}" in
        volumes)
            restore_volumes
            ;;
        networks)
            restore_networks
            ;;
        compose)
            restore_compose_projects
            ;;
        all)
            restore_networks
            restore_compose_projects
            restore_volumes
            ;;
        *)
            log_error "Invalid mode: ${mode}"
            log_info "Usage: $0 [volumes|networks|compose|all]"
            exit 1
            ;;
    esac
    
    log_success "Docker restore completed!"
    log_info "Next: Restore volume data using volume restore procedures"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

EOF
    
    chmod +x "${restore_script}"
    log_success "Docker restore script generated: ${restore_script}"
}

# Main inventory function
main() {
    # Check if Docker is available
    if ! check_docker; then
        log_error "Docker inventory cannot proceed - Docker not available"
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
    
    # Step 1: Collect all Docker information
    get_docker_info "${temp_info}"
    find_compose_files "${temp_compose}"
    get_volumes_info "${temp_volumes}"
    get_networks_info "${temp_networks}"
    get_containers_info "${temp_containers}"
    
    # Step 2: Copy compose files to inventory
    copy_compose_files "${temp_compose}" "${compose_dest_dir}"
    
    # Step 3: Create comprehensive inventory
    cat > "${inventory_file}" << EOF
# Docker Infrastructure Inventory
# Generated on: $(date)
# Host: $(hostname)

## Summary
- Docker available: ✓
- Compose projects found: $(wc -l < "${temp_compose}")
- Named volumes: $(docker volume ls --quiet 2>/dev/null | grep -v '^[a-f0-9]\{64\}$' | wc -l || echo 0)
- Custom networks: $(docker network ls --filter "type=custom" --quiet 2>/dev/null | wc -l || echo 0)
- Running containers: $(docker ps --quiet 2>/dev/null | wc -l || echo 0)

## Docker System Information
$(cat "${temp_info}")

## Docker Compose Projects
$(cat "${temp_compose}")

## Docker Volumes
$(cat "${temp_volumes}")

## Docker Networks
$(cat "${temp_networks}")

## Running Containers (for reference)
$(cat "${temp_containers}")

## Inventory Files
- Compose files copied to: ${compose_dest_dir}/
- Volume metadata: ${volumes_meta}

EOF
    
    log_success "Docker inventory saved: ${inventory_file}"
    
    # Step 4: Generate volume metadata
    generate_volume_metadata "${volumes_meta}"
    
    # Step 5: Generate declarative configuration
    generate_declarative_config "${temp_compose}" "${temp_volumes}" "${temp_networks}" "${declarative_file}"
    
    # Step 6: Generate restore script
    generate_restore_script "${restore_script}"
    
    # Cleanup temporary files
    rm -f "${temp_info}" "${temp_compose}" "${temp_volumes}" "${temp_networks}" "${temp_containers}"
    
    log_info "Docker inventory completed successfully"
    log_info "Important notes:"
    log_info "  1. Compose files are now in ${compose_dest_dir}/"
    log_info "  2. Volume data is NOT backed up by this inventory"
    log_info "  3. Review ${volumes_meta} for volume backup/restore policies"
    log_info "  4. .env files are NOT copied - use .env.template files instead"
    log_info "  5. Container images are NOT backed up - they should be reproducible"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi