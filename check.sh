#!/usr/bin/env bash
# Verification checklist (guide section 14). Read-only; run as your user from inside Hyprland.
# What it expects comes from config.sh (GPU_DRIVER, CPU_VENDOR, MONITORS, kernels, extras).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/hw.sh"
load_config "$REPO_DIR"
trap - ERR
set +e

pass=0
fail=0

# check "label" "extended regex the output must match" command...
check() {
    local label=$1 want=$2 out status
    shift 2
    out=$("$@" 2>&1)
    status=$?
    if (( status == 0 )) && grep -qE -- "$want" <<<"$out"; then
        ok "$label"
        pass=$((pass + 1))
    else
        err "$label" 2>&1
        head -n 4 <<<"$out" | sed 's/^/        /'
        fail=$((fail + 1))
    fi
}

run() { bash -o pipefail -c "$1"; }

# ReBAR is active when the BAR1 aperture covers the whole VRAM.
nvidia_rebar() {
    nvidia-smi -q -d MEMORY | awk '
        /FB Memory Usage/   { s = "fb" }
        /BAR1 Memory Usage/ { s = "bar" }
        /Total/ && s        { v[s] = $3; s = "" }
        END { printf "VRAM %s MiB, BAR1 %s MiB\n", v["fb"], v["bar"]; if (v["bar"] >= v["fb"]) print "rebar=on" }'
}

# One line per configured monitor with an explicit refresh rate: "<match> ok|<what was found>"
monitor_modes() {
    hyprctl monitors -j | MONITORS="$(printf '%s\n' "${MONITORS[@]}")" python3 -c '
import json, os, sys
connected = json.load(sys.stdin)
bad = 0
for line in filter(None, os.environ["MONITORS"].splitlines()):
    match, mode = line.split("|")[:2]
    if "@" not in mode:
        continue
    size, hz = mode.split("@")
    w, h = map(int, size.split("x"))
    m = next((m for m in connected if m["name"] == match
              or match.lower() in (m["description"] + " " + m["model"]).lower()), None)
    if m is None:
        print(f"{match}: not connected"); bad += 1; continue
    width, height, rate, name = m["width"], m["height"], m["refreshRate"], m["name"]
    got = f"{width}x{height}@{rate:.0f}"
    if (width, height) != (w, h) or abs(rate - float(hz)) > 1:
        print(f"{match}: wanted {mode}, running {got}"); bad += 1
    else:
        print(f"{match} ({name}): {got}")
print("monitors ok" if bad == 0 else f"{bad} monitor(s) differ")
'
}

cpu_freq_driver() {
    local drv=/sys/devices/system/cpu/cpufreq/policy0/scaling_driver
    if [[ $CPU_VENDOR == amd ]]; then
        if [[ -r /sys/devices/system/cpu/amd_pstate/status ]]; then
            cat /sys/devices/system/cpu/amd_pstate/status
            return
        fi
        printf 'amd_pstate status unavailable; check that CPPC is enabled in the BIOS\n'
        [[ -r $drv ]] || printf 'No CPU frequency scaling driver is active\n'
        journalctl -b -k --no-pager -g 'amd_pstate:' 2>/dev/null | tail -n 1
        return 1
    fi
    cat "$drv"
}

default_audio() {
    wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m1 'node.description' | sed 's/.*= /sink: /'
    wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -m1 'node.description' | sed 's/.*= /source: /'
}

step "Graphics ($GPU_DRIVER)"
case $GPU_DRIVER in
    nvidia-*)
        check "NVIDIA driver loaded"     '^[0-9]+([.][0-9]+)+$'  nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits
        check "nvidia_drm modeset = Y"   '^Y$'                   cat /sys/module/nvidia_drm/parameters/modeset
        check "ReBAR active (BAR1 covers VRAM)" 'rebar=on'      nvidia_rebar ;;
    amd)
        check "amdgpu driver loaded"     'amdgpu'                run "lsmod | grep -w ^amdgpu"
        check "Vulkan driver (RADV)"     'radeon_icd'            ls /usr/share/vulkan/icd.d/ ;;
    intel)
        check "Intel GPU driver loaded"  '^(i915|xe) '           run "lsmod | grep -wE '^(i915|xe)'"
        check "Vulkan driver (ANV)"      'intel_icd'             ls /usr/share/vulkan/icd.d/ ;;
esac
if (( ${#MONITORS[@]} > 0 )); then
    check "Monitors match MONITORS in config.sh" 'monitors ok' monitor_modes
else
    info "MONITORS is empty: Hyprland picks each monitor's preferred mode"
fi

step "CPU, memory, scheduler"
if [[ $CPU_VENDOR == amd ]]; then
    check "amd_pstate active"            '^active$'              cpu_freq_driver
else
    check "intel_pstate driver"          '^intel_pstate$'        cpu_freq_driver
fi
check "sched-ext: bpfland"               '[Bb]pfland'            scxctl get
check "zram swap active"                 'zram0'                 swapon --show
check "NTSYNC device present"            '^present$'             run "test -e /dev/ntsync && echo present"
if [[ $UNDERVOLT == yes ]]; then
    if [[ -x /usr/local/bin/pbo-curve ]]; then
        check "Curve Optimizer applied"  'core 0: -[0-9]+'       sudo pbo-curve list
    else
        info "pbo-curve not installed yet (./undervolt.sh install)"
    fi
fi

step "Kernel, boot and snapshots"
check "Running a CachyOS kernel"         'cachyos'               uname -r
check "snapper root config"              'fresh install'         sudo snapper -c root list
check "Limine snapshot menu"             '[Ss]napshots'          limine-list
check "Fallback kernel entry ($FALLBACK_KERNEL)" "$FALLBACK_KERNEL" limine-list

step "Audio"
check "PipeWire quantum 512"             "clock.quantum' value:'512'" pw-metadata -n settings
check "Default speaker and microphone set" 'sink: .*'            default_audio

step "Services"
check "No failed system units"           '^0$'                   run "systemctl --failed --no-legend --plain | wc -l"
check "No failed user units"             '^0$'                   run "systemctl --user --failed --no-legend --plain | wc -l"
check "Network up"                       '^connected'            nmcli -t -f STATE general

printf '\n%s%d passed%s, %s%d failed%s\n' "$c_green" "$pass" "$c_off" "$c_red" "$fail" "$c_off"
info "RAM in use right now: $(free -h | awk '/^Mem:/ { print $3 " of " $2 }')"
[[ $fail -eq 0 ]]
