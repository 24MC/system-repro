#!/usr/bin/env bash
# inventory/packages/inventory.sh
# Collect explicitly installed pacman packages and AUR-only packages (repo-agnostic)
# Safe: does NOT query remote repos, does NOT touch /etc/pacman.conf

set -euo pipefail

# --- helpers -----------------------------------------------------------------
log()  { printf '%s\n' "[INFO] $*"; }
warn() { printf '%s\n' "[WARN] $*"; }
err()  { printf '%s\n' "[ERROR] $*" >&2; }

# Resolve project root (two levels up from this script: packages -> inventory -> PROJECT_ROOT)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OUT_DIR="${PROJECT_ROOT}/inventory/packages"
mkdir -p "${OUT_DIR}"

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

# --- guards ------------------------------------------------------------------
# Do not touch pacman config or pacman.d; inventory must be repo-agnostic.
if [[ -f "/etc/pacman.conf" ]]; then
  # sanity check only, DO NOT MODIFY pacman.conf
  :
fi

# Ensure pacman DB is accessible locally (no remote queries)
if ! pacman -Q >/dev/null 2>&1; then
  err "pacman local database is not usable. Aborting package inventory."
  exit 1
fi

# --- collect lists -----------------------------------------------------------
TS="$(timestamp)"
AUR_FILE="${OUT_DIR}/aur.${TS}.list"
EXPLICIT_FILE="${OUT_DIR}/explicit.${TS}.list"
OFFICIAL_FILE="${OUT_DIR}/official.${TS}.list"
LATEST_AUR="${OUT_DIR}/aur.latest.list"
LATEST_EXPLICIT="${OUT_DIR}/explicit.latest.list"
LATEST_OFFICIAL="${OUT_DIR}/official.latest.list"

log "Collecting explicitly installed pacman packages (local DB only)..."
# pacman -Qqe lists explicitly installed packages (excluding dependencies)
if ! pacman -Qqe > "${EXPLICIT_FILE}" 2>/dev/null; then
  # If pacman -Qqe fails unexpectedly, fail gracefully.
  err "Failed to collect explicitly installed packages via pacman -Qqe"
  rm -f "${EXPLICIT_FILE}" || true
  exit 1
fi

EXPLICIT_COUNT=$(wc -l < "${EXPLICIT_FILE}" | tr -d ' ')
log "Found ${EXPLICIT_COUNT} explicitly installed packages"

log "Collecting AUR-only packages (pacman -Qm)..."
# pacman -Qm lists packages not in sync DB (usually AUR/local foreign)
if pacman -Qm > "${AUR_FILE}" 2>/dev/null; then
  AUR_COUNT=$(wc -l < "${AUR_FILE}" | tr -d ' ')
  log "Found ${AUR_COUNT} AUR/local (foreign) packages"
else
  # If none found, create empty file and set count 0
  : > "${AUR_FILE}"
  AUR_COUNT=0
  log "No AUR/local (foreign) packages found"
fi

# Official packages = explicit - aur
if [[ ${AUR_COUNT} -gt 0 ]]; then
  # Use grep -vxF -f for exact exclusion; preserve order from explicit list
  grep -vxF -f "${AUR_FILE}" "${EXPLICIT_FILE}" > "${OFFICIAL_FILE}" || true
else
  cp "${EXPLICIT_FILE}" "${OFFICIAL_FILE}"
fi

OFFICIAL_COUNT=$(wc -l < "${OFFICIAL_FILE}" | tr -d ' ')
log "Computed ${OFFICIAL_COUNT} official packages (explicit-installed minus AUR)"

# Update latest symlink-style files for convenience
cp -f "${AUR_FILE}" "${LATEST_AUR}"
cp -f "${EXPLICIT_FILE}" "${LATEST_EXPLICIT}"
cp -f "${OFFICIAL_FILE}" "${LATEST_OFFICIAL}"

# Also write a metadata summary
META_FILE="${OUT_DIR}/packages.metadata.${TS}.txt"
{
  echo "timestamp: ${TS}"
  echo "explicit_count: ${EXPLICIT_COUNT}"
  echo "aur_count: ${AUR_COUNT}"
  echo "official_count: ${OFFICIAL_COUNT}"
  echo "explicit_file: ${EXPLICIT_FILE}"
  echo "aur_file: ${AUR_FILE}"
  echo "official_file: ${OFFICIAL_FILE}"
} > "${META_FILE}"

log "Package inventory saved to: ${OUT_DIR}"
log " - explicit: ${EXPLICIT_FILE}"
log " - aur:      ${AUR_FILE}"
log " - official: ${OFFICIAL_FILE}"
log " - metadata: ${META_FILE}"

log "To reinstall official explicit packages later run (example):"
log "  xargs -a ${LATEST_OFFICIAL} sudo pacman -S --needed --noconfirm"

log "To inspect AUR/local packages (do NOT blindly reinstall):"
log "  cat ${LATEST_AUR}"

log "Inventory step completed successfully"
exit 0
