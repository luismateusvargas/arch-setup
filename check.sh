#!/usr/bin/env bash
# Verification checklist (guide section 14). Read-only; run as your user from inside Hyprland.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
trap - ERR
set +e

pass=0
fail=0

# check "label" "extended regex the output must match" command...
check() {
    local label=$1 want=$2 out
    shift 2
    out=$("$@" 2>&1)
    if grep -qE -- "$want" <<<"$out"; then
        ok "$label"
        pass=$((pass + 1))
    else
        printf '%s  ✗ %s%s\n' "$c_red" "$label" "$c_off"
        head -n 4 <<<"$out" | sed 's/^/        /'
        fail=$((fail + 1))
    fi
}

run() { bash -c "$1"; }

step "Graphics"
check "NVIDIA driver loaded"           'Driver Version: *6[0-9]{2}\.'  nvidia-smi
check "nvidia_drm modeset = Y"         '^Y$'                           cat /sys/module/nvidia_drm/parameters/modeset
check "ReBAR active (BAR1 = 8192 MiB)" 'Total *: *8192 MiB'            run "nvidia-smi -q | grep -A3 BAR1"
check "Both monitors at 144 Hz"        '^2$'                           run "hyprctl monitors | grep -cE '@14[34][.]'"
check "SuperFrame on HDMI-A-1"         '^Monitor HDMI-A-1'             hyprctl monitors

step "CPU, memory, scheduler"
check "amd_pstate active"              '^active$'                      cat /sys/devices/system/cpu/amd_pstate/status
check "sched-ext: bpfland"             'bpfland'                       scxctl get
check "zram swap active"               'zram0'                         swapon --show
check "NTSYNC device present"          '^present$'                     run "test -e /dev/ntsync && echo present"
if [[ -x /usr/local/bin/pbo-curve ]]; then
    check "Curve Optimizer applied"    'core 0: -[0-9]+'               sudo pbo-curve list
else
    info "pbo-curve not installed yet (./undervolt.sh install)"
fi

step "Boot and snapshots"
check "snapper root config"            'fresh install'                 sudo snapper -c root list
check "Limine snapshot menu"           '[Ss]napshots'                  limine-list
check "Fallback kernel entry"          'linux-cachyos-lts'             limine-list

step "Audio"
check "PipeWire quantum 512"           "clock.quantum' value:'512'"    pw-metadata -n settings
check "PRO X present"                  'PRO X'                         wpctl status

step "Services"
check "No failed system units"         '^0$'                           run "systemctl --failed --no-legend --plain | wc -l"
check "No failed user units"           '^0$'                           run "systemctl --user --failed --no-legend --plain | wc -l"
check "Network up"                     '^connected'                    nmcli -t -f STATE general

printf '\n%s%d passed%s, %s%d failed%s\n' "$c_green" "$pass" "$c_off" "$c_red" "$fail" "$c_off"
info "RAM in use right now: $(free -h | awk '/^Mem:/ { print $3 " of " $2 }')"
[[ $fail -eq 0 ]]
