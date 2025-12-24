#!/usr/bin/env bash

# Configuration Files Inventory Module
# Collects user and system configuration files
# Respects include/exclude patterns
# Generates declarative configuration for reproducible setups

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

# Load include/exclude patterns
load_patterns() {
    local config_dir="${PROJECT_ROOT}/config"
    local include_file="${config_dir}/include.conf"
    local exclude_file="${config_dir}/exclude.conf"
    
    # Default include patterns (system and user configs)
    local default_includes=(
        # System configuration
        "/etc/fstab"
        "/etc/hosts"
        "/etc/hostname"
        "/etc/locale.conf"
        "/etc/vconsole.conf"
        "/etc/mkinitcpio.conf"
        "/etc/pacman.conf"
        "/etc/makepkg.conf"
        "/etc/sudoers"
        "/etc/default/grub"
        "/etc/grub.d/"
        "/etc/systemd/"
        "/etc/NetworkManager/"
        "/etc/ssh/"
        "/etc/ssl/"
        
        # User configuration (current user)
        "${HOME}/.bashrc"
        "${HOME}/.bash_profile"
        "${HOME}/.profile"
        "${HOME}/.zshrc"
        "${HOME}/.vimrc"
        "${HOME}/.gitconfig"
        "${HOME}/.ssh/config"
        "${HOME}/.config/"
        
        # Common application configs
        "${HOME}/.local/share/applications/"
    )
    
    # Default exclude patterns (sensitive or dynamic files)
    local default_excludes=(
        # Sensitive files
        "*.key"
        "*.pem"
        "*.crt"
        "*.p12"
        "*.pfx"
        ".ssh/id_*"
        ".gnupg/"
        ".ssh/known_hosts"
        ".ssh/authorized_keys"
        
        # Cache and temporary files
        "*/cache/"
        "*/Cache/"
        "*/tmp/"
        "*/temp/"
        "*.tmp"
        "*.log"
        "*/logs/"
        
        # Dynamic system files
        "/etc/resolv.conf"
        "/etc/machine-id"
        "/proc/"
        "/sys/"
        "/dev/"
        "/tmp/"
        "/run/"
        "/var/"
        
        # Binary and data files
        "*.so"
        "*.o"
        "*.pyc"
        "__pycache__/"
        ".git/objects/"
    )
    
    # Load custom patterns if files exist
    local includes=("${default_includes[@]}")
    local excludes=("${default_excludes[@]}")
    
    if [[ -f "${include_file}" ]]; then
        log_info "Loading custom include patterns..."
        while IFS= read -r pattern; do
            [[ -n "${pattern}" ]] && ! [[ "${pattern}" =~ ^# ]] && includes+=("${pattern}")
        done < "${include_file}"
    fi
    
    if [[ -f "${exclude_file}" ]]; then
        log_info "Loading custom exclude patterns..."
        while IFS= read -r pattern; do
            [[ -n "${pattern}" ]] && ! [[ "${pattern}" =~ ^# ]] && excludes+=("${pattern}")
        done < "${exclude_file}"
    fi
    
    # Return patterns as arrays
    printf '%s\n' "${includes[@]}" > "${INVENTORY_DIR}/includes.tmp"
    printf '%s\n' "${excludes[@]}" > "${INVENTORY_DIR}/excludes.tmp"
    
    log_success "Loaded ${#includes[@]} include patterns, ${#excludes[@]} exclude patterns"
}

# Find configuration files based on patterns
find_config_files() {
    local includes_file="${1}"
    local excludes_file="${2}"
    local output_file="${3}"
    
    log_info "Searching for configuration files..."
    
    > "${output_file}"
    
    # Process includes
    while IFS= read -r pattern; do
        [[ -z "${pattern}" ]] && continue
        
        # Check if pattern is a directory
        if [[ -d "${pattern}" ]]; then
            # For directories, find regular files recursively
            find "${pattern}" -type f 2>/dev/null | while read -r file; do
                echo "${file}" >> "${output_file}"
            done
        elif [[ -f "${pattern}" ]]; then
            # For files, add them directly
            echo "${pattern}" >> "${output_file}"
        elif [[ "${pattern}" == */* ]]; then
            # For patterns with path components, use find
            local dir_part
            dir_part="$(dirname "${pattern}")"
            local file_part
            file_part="$(basename "${pattern}")"
            
            if [[ -d "${dir_part}" ]]; then
                find "${dir_part}" -name "${file_part}" -type f 2>/dev/null | while read -r file; do
                    echo "${file}" >> "${output_file}"
                done
            fi
        else
            # For simple patterns, search from root and home
            find / -name "${pattern}" -type f 2>/dev/null | while read -r file; do
                echo "${file}" >> "${output_file}"
            done
            find "${HOME}" -name "${pattern}" -type f 2>/dev/null | while read -r file; do
                echo "${file}" >> "${output_file}"
            done
        fi
    done < "${includes_file}"
    
    # Remove duplicates and sort
    sort -u "${output_file}" -o "${output_file}"
    
    # Apply excludes
    local temp_filtered="${output_file}.filtered"
    cp "${output_file}" "${temp_filtered}"
    
    while IFS= read -r exclude_pattern; do
        [[ -z "${exclude_pattern}" ]] && continue
        
        # Remove excluded files
        grep -v -F "${exclude_pattern}" "${temp_filtered}" > "${temp_filtered}.tmp" && mv "${temp_filtered}.tmp" "${temp_filtered}"
        
        # Also handle wildcard patterns
        if [[ "${exclude_pattern}" == *"*"* ]]; then
            # Convert shell glob to grep pattern
            local grep_pattern
            grep_pattern="${exclude_pattern//\*/.*}"
            grep -v -E "${grep_pattern}" "${temp_filtered}" > "${temp_filtered}.tmp" && mv "${temp_filtered}.tmp" "${temp_filtered}"
        fi
    done < "${excludes_file}"
    
    mv "${temp_filtered}" "${output_file}"
    
    local config_count=$(wc -l < "${output_file}" 2>/dev/null || echo 0)
    log_success "Found ${config_count} configuration files"
}

# Analyze configuration files
analyze_configs() {
    local config_list="${1}"
    local analysis_file="${2}"
    
    log_info "Analyzing configuration files..."
    
    cat > "${analysis_file}" << EOF
# Configuration Files Analysis
# Generated on: $(date)
# Host: $(hostname)

## Analysis Summary

EOF
    
    local total_size=0
    local file_count=0
    local system_files=0
    local user_files=0
    local sensitive_files=0
    
    while IFS= read -r config_file; do
        [[ -z "${config_file}" ]] && continue
        ((file_count++))
        
        # Get file size
        if [[ -r "${config_file}" ]]; then
            local file_size
            file_size=$(stat -c%s "${config_file}" 2>/dev/null || echo 0)
            total_size=$((total_size + file_size))
        fi
        
        # Categorize file
        if [[ "${config_file}" =~ ^/etc/ ]] || [[ "${config_file}" =~ ^/usr/ ]] || [[ "${config_file}" =~ ^/opt/ ]]; then
            ((system_files++))
        else
            ((user_files++))
        fi
        
        # Check for sensitive content
        if [[ "${config_file}" =~ \.(key|pem|crt|p12|pfx)$ ]] || \
           [[ "${config_file}" =~ /\.ssh/ ]] || \
           [[ "${config_file}" =~ /\.gnupg/ ]] || \
           [[ "${config_file}" =~ /authorized_keys$ ]] || \
           [[ "${config_file}" =~ /known_hosts$ ]]; then
            ((sensitive_files++))
        fi
        
    done < "${config_list}"
    
    cat >> "${analysis_file}" << EOF
- Total files: ${file_count}
- Total size: $((total_size / 1024)) KB
- System configuration files: ${system_files}
- User configuration files: ${user_files}
- Potentially sensitive files: ${sensitive_files}

## File Categories

### System Configuration (/etc, /usr, /opt)
$(grep '^/etc/\|^/usr/\|^/opt/' "${config_list}" | head -20)

### User Configuration (~/.*, ~/.config/)
$(grep "^${HOME}/" "${config_list}" | head -20)

### Security-related Files
$(grep -E '\.(key|pem|crt|p12|pfx)$|/\.ssh/|/\.gnupg/|authorized_keys$|known_hosts$' "${config_list}" || echo "None found")

### Network Configuration
$(grep -E 'network|Network' "${config_list}" || echo "None found")

### Service Configuration
$(grep -E 'systemd|service|daemon' "${config_list}" || echo "None found")

EOF
    
    log_success "Configuration analysis completed"
}

# Copy configuration files to inventory
copy_config_files() {
    local config_list="${1}"
    local dest_dir="${2}"
    
    log_info "Copying configuration files to inventory..."
    
    mkdir -p "${dest_dir}"
    
    local copied_count=0
    local skipped_count=0
    
    while IFS= read -r config_file; do
        [[ -z "${config_file}" ]] && continue
        
        # Create relative path for destination
        local rel_path
        rel_path="${config_file#/}"  # Remove leading /
        rel_path="${rel_path//\//_}"  # Replace / with _
        
        # Handle home directory specially
        if [[ "${config_file}" =~ ^${HOME}/ ]]; then
            rel_path="home_${USER}_${config_file#${HOME}/}"
            rel_path="${rel_path//\//_}"
        fi
        
        local dest_file="${dest_dir}/${rel_path}"
        
        # Check if file is readable
        if [[ ! -r "${config_file}" ]]; then
            log_warn "Cannot read: ${config_file} (permission denied)"
            ((skipped_count++))
            continue
        fi
        
        # Check for sensitive content (but still copy with warning)
        if [[ "${config_file}" =~ \.(key|pem|crt|p12|pfx)$ ]] || \
           [[ "${config_file}" =~ /id_rsa$ ]] || \
           [[ "${config_file}" =~ /\.gnupg/ ]] || \
           [[ "${config_file}" =~ authorized_keys$ ]]; then
            log_warn "Copying sensitive file: ${config_file}"
            log_warn "Review this file manually before committing to version control"
        fi
        
        # Copy the file
        if cp "${config_file}" "${dest_file}" 2>/dev/null; then
            ((copied_count++))
        else
            log_error "Failed to copy: ${config_file}"
            ((skipped_count++))
        fi
        
    done < "${config_list}"
    
    log_success "Copied ${copied_count} configuration files"
    if [[ ${skipped_count} -gt 0 ]]; then
        log_warn "Skipped ${skipped_count} files (permission issues)"
    fi
}

# Generate declarative configuration
generate_declarative_config() {
    local config_list="${1}"
    local declarative_file="${2}"
    
    log_info "Generating declarative configuration..."
    
    cat > "${declarative_file}" << EOF
# Declarative Configuration Files
# Generated on: $(date)
# This file defines what configuration files SHOULD exist
# Edit this file to declare desired state, not current state

# Configuration Files
# Format: config.<path>.state=<state>
# States: present, absent, template

$(while IFS= read -r config_file; do
    [[ -z "${config_file}" ]] && continue
    
    # Create a safe key name
    local key_name
    key_name="${config_file}"
    key_name="${key_name//\//.}"  # Replace / with .
    key_name="${key_name#..}"      # Remove leading ..
    
    # Handle home directory specially
    if [[ "${config_file}" =~ ^${HOME}/ ]]; then
        key_name="config.home.${USER}.${config_file#${HOME}/}"
        key_name="${key_name//\//.}"
    else
        key_name="config.system.${key_name}"
    fi
    
    echo "${key_name}.state=present"
    echo "${key_name}.source=inventory/config/$(basename "${config_file}" | sed 's/\//_/g')"
    echo "${key_name}.checksum=$(md5sum "${config_file}" 2>/dev/null | cut -d' ' -f1 || echo "unknown")"
    echo ""
done < "${config_list}")

# Configuration Management Policy
# config.policy.backup=true
# config.policy.preserve_permissions=true
# config.policy.preserve_ownership=true

# Sensitive file patterns (never commit to version control)
config.sensitive_pattern.*.key=true
config.sensitive_pattern.*.pem=true
config.sensitive_pattern.*.p12=true
config.sensitive_pattern.*.pfx=true
config.sensitive_pattern.ssh.id_*=true
config.sensitive_pattern.gnupg.=true
config.sensitive_pattern.authorized_keys=true

EOF
    
    log_success "Declarative configuration generated"
}

# Generate configuration restore script
generate_restore_script() {
    local restore_script="${1}"
    
    log_info "Generating configuration restore script..."
    
    cat > "${restore_script}" << 'EOF'
#!/usr/bin/env bash
# Configuration Files Restore Script
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

# Check if running as root for system files
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "Some operations require root privileges"
        log_warn "Consider running with sudo for system-wide configuration"
        return 1
    fi
    return 0
}

# Restore configuration files
restore_configs() {
    local config_dir="${SCRIPT_DIR}/../files"
    local declarative_file="${PROJECT_ROOT}/declarative/system.conf"
    
    if [[ ! -d "${config_dir}" ]]; then
        log_error "Configuration files directory not found: ${config_dir}"
        return 1
    fi
    
    log_info "Restoring configuration files..."
    
    # Get list of configurations to restore from declarative file
    if [[ -f "${declarative_file}" ]]; then
        grep '^config\.' "${declarative_file}" | while read -r line; do
            if [[ "${line}" =~ ^config\.([^.]+)\.([^.]+)\.state=present ]]; then
                local config_type="${BASH_REMATCH[1]}"
                local config_name="${BASH_REMATCH[2]}"
                
                # Handle different config types
                case "${config_type}" in
                    system)
                        restore_system_config "${config_name}"
                        ;;
                    home)
                        restore_user_config "${config_name}"
                        ;;
                    *)
                        log_warn "Unknown config type: ${config_type}"
                        ;;
                esac
            fi
        done
    else
        log_warn "Declarative configuration not found, using inventory files"
        
        # Fallback: restore all files in inventory
        find "${config_dir}" -type f | while read -r config_file; do
            local filename
            filename=$(basename "${config_file}")
            
            if [[ "${filename}" =~ ^home_${USER}_(.*)$ ]]; then
                local user_path="${BASH_REMATCH[1]}"
                user_path="${user_path//_//}"  # Replace _ with /
                restore_user_config "${user_path}"
            elif [[ "${filename}" =~ ^etc_(.*)$ ]]; then
                local system_path="/etc/${BASH_REMATCH[1]}"
                system_path="${system_path//_//}"  # Replace _ with /
                restore_system_config "${system_path}"
            fi
        done
    fi
    
    log_success "Configuration files restored"
}

# Restore system configuration
restore_system_config() {
    local config_path="${1}"
    local config_dir="${SCRIPT_DIR}/../files"
    
    if [[ ! -f "${config_dir}/etc_$(basename "${config_path}" | tr '/' '_')" ]]; then
        log_warn "System config not found in inventory: ${config_path}"
        return 0
    fi
    
    log_info "Restoring system config: ${config_path}"
    
    # Check if we have permissions
    if [[ $EUID -ne 0 ]]; then
        log_warn "Need root privileges to restore ${config_path}"
        return 0
    fi
    
    # Backup existing file
    if [[ -f "${config_path}" ]]; then
        local backup_path="${config_path}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${config_path}" "${backup_path}"
        log_info "Backed up existing file to: ${backup_path}"
    fi
    
    # Create directory if needed
    local config_dir_path
    config_dir_path="$(dirname "${config_path}")"
    if [[ ! -d "${config_dir_path}" ]]; then
        mkdir -p "${config_dir_path}"
        log_info "Created directory: ${config_dir_path}"
    fi
    
    # Copy file
    local source_file="${config_dir}/etc_$(basename "${config_path}" | tr '/' '_')"
    if cp "${source_file}" "${config_path}"; then
        log_success "Restored: ${config_path}"
        
        # Preserve permissions if possible
        if [[ -r "${config_path}.backup" ]]; then
            chmod --reference="${config_path}.backup" "${config_path}" 2>/dev/null || true
            chown --reference="${config_path}.backup" "${config_path}" 2>/dev/null || true
        fi
    else
        log_error "Failed to restore: ${config_path}"
    fi
}

# Restore user configuration
restore_user_config() {
    local config_path="${1}"
    local config_dir="${SCRIPT_DIR}/../files"
    
    local source_file="${config_dir}/home_${USER}_${config_path//\//_}"
    local target_file="${HOME}/${config_path}"
    
    if [[ ! -f "${source_file}" ]]; then
        log_warn "User config not found in inventory: ${config_path}"
        return 0
    fi
    
    log_info "Restoring user config: ${target_file}"
    
    # Backup existing file
    if [[ -f "${target_file}" ]]; then
        local backup_path="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${target_file}" "${backup_path}"
        log_info "Backed up existing file to: ${backup_path}"
    fi
    
    # Create directory if needed
    local target_dir
    target_dir="$(dirname "${target_file}")"
    if [[ ! -d "${target_dir}" ]]; then
        mkdir -p "${target_dir}"
        log_info "Created directory: ${target_dir}"
    fi
    
    # Copy file
    if cp "${source_file}" "${target_file}"; then
        log_success "Restored: ${target_file}"
    else
        log_error "Failed to restore: ${target_file}"
    fi
}

# Main restore function
main() {
    local mode="${1:-all}"
    
    case "${mode}" in
        system)
            check_root || exit 1
            restore_configs
            ;;
        user)
            restore_configs
            ;;
        all)
            restore_configs
            ;;
        *)
            log_error "Invalid mode: ${mode}"
            log_info "Usage: $0 [system|user|all]"
            exit 1
            ;;
    esac
    
    log_success "Configuration restore completed!"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

EOF
    
    chmod +x "${restore_script}"
    log_success "Configuration restore script generated"
}

# Main inventory function
main() {
    local includes_file="${INVENTORY_DIR}/includes.tmp"
    local excludes_file="${INVENTORY_DIR}/excludes.tmp"
    local config_list="${INVENTORY_DIR}/config_files_${TIMESTAMP}.tmp"
    local analysis_file="${INVENTORY_DIR}/config_analysis_${TIMESTAMP}.tmp"
    
    local inventory_file="${INVENTORY_DIR}/config_${TIMESTAMP}.inventory"
    local declarative_file="${PROJECT_ROOT}/declarative/system.conf"
    local config_files_dir="${INVENTORY_DIR}/files"
    local restore_script="${INVENTORY_DIR}/restore_config.sh"
    
    # Step 1: Load patterns
    load_patterns
    
    # Step 2: Find configuration files
    find_config_files "${includes_file}" "${excludes_file}" "${config_list}"
    
    # Step 3: Analyze configuration files
    analyze_configs "${config_list}" "${analysis_file}"
    
    # Step 4: Copy configuration files to inventory
    copy_config_files "${config_list}" "${config_files_dir}"
    
    # Step 5: Create comprehensive inventory
    cat > "${inventory_file}" << EOF
# Configuration Files Inventory
# Generated on: $(date)
# Host: $(hostname)

## Summary
$(grep -E '^-' "${analysis_file}" | head -5)

## Configuration Files Found
$(cat "${config_list}")

## Detailed Analysis
$(cat "${analysis_file}")

## Files Copied to Inventory
- Location: ${config_files_dir}/
- Count: $(find "${config_files_dir}" -type f 2>/dev/null | wc -l || echo 0)

## Patterns Used
### Includes:
$(cat "${includes_file}")

### Excludes:
$(cat "${excludes_file}")

EOF
    
    log_success "Configuration inventory saved: ${inventory_file}"
    
    # Step 6: Generate declarative configuration (append to system.conf)
    if [[ ! -f "${declarative_file}" ]]; then
        generate_declarative_config "${config_list}" "${declarative_file}"
    else
        log_info "Appending configuration to existing declarative file..."
        
        cat >> "${declarative_file}" << EOF

# === CONFIGURATION FILES (added $(date)) ===

EOF
        
        generate_declarative_config "${config_list}" "${declarative_file}.tmp"
        cat "${declarative_file}.tmp" >> "${declarative_file}"
        rm -f "${declarative_file}.tmp"
    fi
    
    # Step 7: Generate restore script
    generate_restore_script "${restore_script}"
    
    # Cleanup temporary files
    rm -f "${includes_file}" "${excludes_file}" "${config_list}" "${analysis_file}"
    
    log_info "Configuration inventory completed successfully"
    log_info "Important notes:"
    log_info "  1. Configuration files are copied to ${config_files_dir}/"
    log_info "  2. Review files for sensitive data before committing"
    log_info "  3. Edit ${declarative_file} to declare desired state"
    log_info "  4. Use ${restore_script} to restore configurations"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi