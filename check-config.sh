#!/usr/bin/env bash
# Check config.sh (and config.local.sh) against this machine before installing. Read-only.
#   bash check-config.sh            validate the config against the hardware it runs on
#   bash check-config.sh --suggest  also print detected values in config.sh syntax
# install.sh runs the same validation before it erases anything.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/hw.sh"
load_config "$REPO_DIR"

step "Detected hardware"
info "CPU:   $(detect_cpu_model)  -> CPU_VENDOR=$(detect_cpu_vendor)"
while read -r addr vendor desc; do
    [[ -n $addr ]] && info "GPU:   $desc  ($addr)"
done < <(gpu_list)
info "       -> GPU_DRIVER=$(detect_gpu_driver)"
info "Disks:"
lsblk -dno NAME,MODEL,SIZE,TRAN | grep -v '^loop' | sed 's/^/         /'
level=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -oE 'x86-64-v[234] \(supported' | head -n 1 | cut -d' ' -f1)
info "CPU level: ${level:-x86-64 (v1)}   (the CachyOS repo script picks the matching repos itself)"

if [[ ${1:-} == --suggest ]]; then
    step "Suggested values (paste into config.sh, then check the rest by hand)"
    cat <<EOF
CPU_VENDOR=$(detect_cpu_vendor)
GPU_DRIVER=$(detect_gpu_driver)
INSTALL_DISK_MODEL="<MODEL column of the disk to erase, from the list above>"
EOF
fi

step "Checking config.sh"
if validate_config hardware; then
    ok "config.sh matches this machine"
    info "kernel: $KERNEL (fallback $FALLBACK_KERNEL)   monitors configured: ${#MONITORS[@]}"
else
    die "fix the values above in config.sh, then run this again"
fi
