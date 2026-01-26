# Arch-Smart-Backup (Refactored)

**This is a minimal refactor intended to keep the project small and focused.**
The original project is a lightweight *system reproducibility / infra snapshot* toolkit for Arch Linux.
This refactor performs small, non-destructive changes:
- Extracts inline Bash helper functions found in `declarative/*.conf` into `scripts/lib.sh` and `scripts/*_setup.sh`.
- Leaves declarative files as simple configuration manifests (comments and key=value lines).
- Adds a small `scripts/lib.sh` with common helpers (`log_info`, `require_root`, `detect_aur_helper`).
- Adds this README explaining scope.

**What I did NOT attempt:**
- Complex behavior changes or full test coverage.
- Converting declarative files to YAML/JSON (kept them as simple shell-friendly configs).
- Running shellcheck or executing the scripts (no runtime changes made).

## Usage notes
- Helper functions have been moved to `scripts/lib.sh`. Call or source the specific `scripts/<name>_setup.sh` from your orchestration scripts.
- Keep declarative manifests minimal. If a declarative file must provide behavior, move that into a script under `scripts/`.

## Next steps (recommended)
1. Run `shellcheck` across `scripts/` and `execution/` and fix warnings.
2. Split `declarative/` into `system.base.conf`, `system.desktop.conf`, etc.
3. Add a small CI test that shells out `bash -n` on scripts to detect syntax errors.

