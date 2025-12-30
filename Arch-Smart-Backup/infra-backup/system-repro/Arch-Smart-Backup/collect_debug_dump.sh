#!/usr/bin/env bash
set -euo pipefail

OUT="infra-backup-debug-$(date +%Y%m%d_%H%M%S).txt"

BASE="infra-backup"

FILES=(
  "$BASE/cli/menu.sh"
  "$BASE/execution/backup.sh"
  "$BASE/execution/restore.sh"
  "$BASE/execution/validate.sh"
  "$BASE/inventory/packages/inventory.sh"
  "$BASE/inventory/config/inventory.sh"
  "$BASE/inventory/services/inventory.sh"
  "$BASE/inventory/docker/inventory.sh"
)

echo "### ARCH SMART BACKUP – DEBUG DUMP" > "$OUT"
echo "# Generated at: $(date)" >> "$OUT"
echo >> "$OUT"

for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo "############################################################" >> "$OUT"
    echo "# FILE: $f" >> "$OUT"
    echo "############################################################" >> "$OUT"
    echo >> "$OUT"
    cat "$f" >> "$OUT"
    echo -e "\n\n" >> "$OUT"
  else
    echo "############################################################" >> "$OUT"
    echo "# FILE MISSING: $f" >> "$OUT"
    echo "############################################################" >> "$OUT"
    echo -e "\n\n" >> "$OUT"
  fi
done

echo "✔ Debug dump written to: $OUT"
