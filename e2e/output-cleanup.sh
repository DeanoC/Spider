#!/usr/bin/env bash

e2e_is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

e2e_cleanup_output_dir() {
    local exit_code="$1"
    local output_dir="$2"
    local output_dir_was_explicit="${3:-0}"
    local keep_output="${4:-}"

    if [[ ! -d "$output_dir" ]]; then
        return 0
    fi

    if e2e_is_truthy "$keep_output"; then
        echo "[INFO] Preserving E2E artifacts at $output_dir because KEEP_OUTPUT is enabled"
        return 0
    fi

    if [[ "$exit_code" -ne 0 ]]; then
        echo "[INFO] Preserving failed E2E artifacts at $output_dir"
        return 0
    fi

    if [[ "$output_dir_was_explicit" == "1" ]]; then
        echo "[INFO] Preserving E2E artifacts at $output_dir because OUTPUT_DIR was set explicitly"
        return 0
    fi

    rm -rf "$output_dir"
    echo "[INFO] Removed transient E2E artifacts at $output_dir"
}
