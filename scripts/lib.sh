# shellcheck shell=bash
# Shared helpers for the arch-setup scripts. Sourced, never run directly.

set -Eeuo pipefail

c_blue=$'\e[1;34m'
c_yellow=$'\e[1;33m'
c_red=$'\e[1;31m'
c_green=$'\e[1;32m'
c_off=$'\e[0m'

step() { printf '\n%s==> %s%s\n' "$c_blue" "$*" "$c_off"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '%s  ✓ %s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s  ! %s%s\n' "$c_yellow" "$*" "$c_off" >&2; }
die()  { printf '%s  ✗ %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

on_error() {
    local code=$?
    printf '%s  ✗ failed (exit %s) at %s:%s: %s%s\n' "$c_red" "$code" \
        "${BASH_SOURCE[1]:-?}" "${BASH_LINENO[0]:-?}" "$BASH_COMMAND" "$c_off" >&2
    exit "$code"
}
trap on_error ERR

# confirm "question" -> success only on y/yes
confirm() {
    local reply
    read -r -p "$1 [y/N] " reply
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

# install_file <src> <dest> [mode] [sudo]
# Copies src to dest, keeping a timestamped backup if a different file is already there.
install_file() {
    local src=$1 dest=$2 mode=${3:-644} as_root=${4:-}
    local run=()
    [[ -n $as_root ]] && run=(sudo)
    if [[ -e $dest ]] && ! "${run[@]}" cmp -s "$src" "$dest"; then
        "${run[@]}" cp -a "$dest" "$dest.bak.$(date +%Y%m%d-%H%M%S)"
        warn "existing $dest backed up"
    fi
    "${run[@]}" install -Dm"$mode" "$src" "$dest"
}

# disk_by_model "MODEL" -> /dev/... only when exactly one whole disk matches
disk_by_model() {
    lsblk -dpno NAME,MODEL,TYPE | awk -v m="$1" '
        $NF == "disk" && index($0, m) { disk = $1; count++ }
        END {
            if (count == 1) print disk
            if (count > 1) {
                print "multiple disks match model " m > "/dev/stderr"
                exit 2
            }
        }
    '
}

# part <disk> <n> -> partition path (nvme0n1 -> nvme0n1p1, sda -> sda1)
part() {
    if [[ $1 =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "${1}$2"; fi
}

whole_disk() {
    [[ $(lsblk -dnro TYPE "$1") == disk ]]
}

disk_has_mounts() {
    [[ -n $(lsblk -nrpo MOUNTPOINTS "$1" | tr -d '[:space:]') ]]
}
