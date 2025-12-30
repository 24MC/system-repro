#!/usr/bin/env bash
set -euo pipefail

ROOT="Arch-Smart-Backup"

echo "[INFO] Cleaning repo: keeping ONLY program files"
echo "[INFO] Root: $ROOT"
echo "[INFO] DRY-RUN mode (no deletion yet)"
echo

# Pattern-uri NON-CODE
NON_CODE_PATTERNS=(
  "*.tmp"
  "*.inventory"
  "*.list"
  "*.metadata.*"
  "*.backup-*"
  "*.txt"
)

# Colectăm fișierele ce vor fi șterse
FILES_TO_DELETE=()

for pattern in "${NON_CODE_PATTERNS[@]}"; do
  while IFS= read -r f; do
    FILES_TO_DELETE+=("$f")
  done < <(find "$ROOT" -type f -name "$pattern")
done

if [ "${#FILES_TO_DELETE[@]}" -eq 0 ]; then
  echo "[INFO] Nothing to delete."
  exit 0
fi

echo "[INFO] Files that would be deleted:"
for f in "${FILES_TO_DELETE[@]}"; do
  echo "  $f"
done

echo
read -rp "Proceed with deletion? [y/N] " confirm
if [[ "$confirm" != "y" ]]; then
  echo "[ABORT] Nothing deleted."
  exit 0
fi

echo
echo "[INFO] Deleting non-program files..."
for f in "${FILES_TO_DELETE[@]}"; do
  rm -f "$f"
done

echo "[SUCCESS] Cleanup completed. Only program files remain."
