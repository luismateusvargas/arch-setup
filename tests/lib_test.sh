#!/usr/bin/env bash

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

fail_test() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

lsblk() {
    case "$*" in
        '-dnro TYPE /dev/nvme0n1') printf 'disk\n' ;;
        '-dnro TYPE /dev/nvme0n1p1') printf 'part\n' ;;
        '-nrpo MOUNTPOINTS /dev/nvme0n1') printf '\n\n' ;;
        '-nrpo MOUNTPOINTS /dev/sda') printf '\n/mnt/hdd\n' ;;
        '-dpno NAME,MODEL,TYPE') printf '/dev/nvme0n1 KINGSTON SNV2S1000G disk\n/dev/sda SAMSUNG HD502HJ disk\n' ;;
        *) fail_test "unexpected lsblk call: $*" ;;
    esac
}

[[ $(part /dev/nvme0n1 2) == /dev/nvme0n1p2 ]] || fail_test 'NVMe partition path'
[[ $(part /dev/sda 1) == /dev/sda1 ]] || fail_test 'SATA partition path'
whole_disk /dev/nvme0n1 || fail_test 'whole disk rejected'
if whole_disk /dev/nvme0n1p1; then fail_test 'partition accepted as a disk'; fi
if disk_has_mounts /dev/nvme0n1; then fail_test 'unmounted disk marked mounted'; fi
disk_has_mounts /dev/sda || fail_test 'mounted disk marked unmounted'
[[ $(disk_by_model 'KINGSTON SNV2S1000G') == /dev/nvme0n1 ]] || fail_test 'disk model match'
[[ -z $(disk_by_model 'NONEXISTENT') ]] || fail_test 'missing model accepted'
if disk_by_model disk >/dev/null 2>&1; then fail_test 'ambiguous model accepted'; fi

printf 'disk helper tests passed\n'
