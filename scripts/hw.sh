# shellcheck shell=bash
# Hardware detection, config validation and per-hardware choices (packages, initramfs, cmdline).
# Sourced after lib.sh and load_config; never run directly.

# Kernel packages in the CachyOS repos (validated again with pacman inside the chroot).
KERNEL_RE='^linux-cachyos(-(bore|eevdf|bmq|cacule|deckify|hardened|lts|rc|rc-gcc|rt-bore|server|gcc))?(-lto)?$'
GPU_DRIVERS='nvidia-open nvidia-580xx amd intel'

# ---------------------------------------------------------------- detection

detect_cpu_vendor() {
    case $(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo 2>/dev/null) in
        AuthenticAMD) echo amd ;;
        GenuineIntel) echo intel ;;
        *)            echo unknown ;;
    esac
}

detect_cpu_model() {
    awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null
}

# One line per display controller: "<pci addr> <vendor id> <description>"
gpu_list() {
    local class
    for class in 0300 0302 0380; do
        lspci -Dnn -d "::$class" 2>/dev/null
    done | sed -E 's/^(\S+) [^:]+: (.*) \[([0-9a-f]{4}):[0-9a-f]{4}\].*/\1 \3 \2/'
}

# nvidia_driver_for "<lspci description>" -> nvidia-open | nvidia-580xx | unsupported
# lspci names NVIDIA chips by codename: TU/GA/AD/GB = Turing and newer (open modules),
# GM/GP/GV = Maxwell/Pascal/Volta (580xx, the last driver series that supports them).
nvidia_driver_for() {
    if [[ $1 =~ (^|[^A-Z])(TU|GA|AD|GB|GH)[0-9]{3} ]]; then echo nvidia-open
    elif [[ $1 =~ (^|[^A-Z])(GM|GP|GV)[0-9]{3} ]]; then echo nvidia-580xx
    elif [[ $1 =~ (^|[^A-Z])(GK|GF|GT|G)[0-9]{2,3} ]]; then echo unsupported
    else echo nvidia-open   # newer than this pci.ids database: assume a current card
    fi
}

# AMD generations by lspci codename (rebrands included).
#   TeraScale (HD 2000-6000, older APUs): only the old radeon driver, no Vulkan -> unsupported.
#   GCN 1 "Southern Islands" / GCN 2 "Sea Islands" (HD 7000, R7/R9 200, R9 290/390): work with amdgpu,
#   but some kernels still default to radeon for them (see amd_legacy_params).
AMD_TERASCALE_RE='(Cedar|Redwood|Juniper|Cypress|Hemlock|Caicos|Turks|Barts|Cayman|Antilles|Seymour|Whistler|Blackcomb|Palm|Sumo|Wrestler|Trinity|Richland|Devastator|Scrapper|Aruba|RV[0-9]{3}|R[67][0-9]{2})'
AMD_GCN12_RE='(Tahiti|Malta|Pitcairn|Curacao|Trinidad|Cape Verde|Verde|Oland|Hainan|Bonaire|Saturn|Tobago|Hawaii|Grenada|Vesuvius|Kaveri|Godavari|Kabini|Temash|Mullins|Beema|Kalindi|Spectre|Spooky)'

amd_driver_for() {
    if [[ $1 =~ $AMD_TERASCALE_RE ]]; then echo unsupported; else echo amd; fi
}

# Suggest GPU_DRIVER: a discrete NVIDIA or AMD card wins over an integrated GPU,
# and any supported GPU wins over one too old for this desktop.
detect_gpu_driver() {
    local addr vendor desc nvidia="" amd="" intel=""
    while read -r addr vendor desc; do
        [[ -n $addr ]] || continue
        case $vendor in
            10de) nvidia=$(nvidia_driver_for "$desc") ;;
            1002) amd=$(amd_driver_for "$desc") ;;
            8086) intel=intel ;;
        esac
    done < <(gpu_list)
    local pick
    for pick in "$nvidia" "$amd" "$intel"; do
        [[ -n $pick && $pick != unsupported ]] && { echo "$pick"; return; }
    done
    [[ $nvidia == unsupported || $amd == unsupported ]] && { echo unsupported; return; }
    echo unknown
}

# Boot parameters that move GCN 1/2 Radeons from radeon to amdgpu (Vulkan, better power management).
# Only these generations read them; prints nothing for any other GPU.
amd_legacy_params() {
    if gpu_list | awk '$2 == "1002"' | grep -qE "$AMD_GCN12_RE"; then
        echo "amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0"
    fi
    return 0
}

# PCI addresses of HDMI/DP audio functions on NVIDIA (10de) and AMD Radeon (1002) cards.
# Intel iGPU HDMI audio shares the onboard HDA controller, so it can't be hidden separately.
gpu_audio_devices() {
    lspci -Dnn -d "::0403" 2>/dev/null | awk '/\[(10de|1002):[0-9a-f]{4}\]/ { print $1 }'
}

# Directory waybar's temperature module needs ("hwmon-path-abs") for the CPU sensor.
cpu_hwmon_dir() {
    local h
    for h in /sys/class/hwmon/hwmon*; do
        case $(cat "$h/name" 2>/dev/null) in
            k10temp|zenpower|coretemp)
                echo "$(realpath "$h/device")/hwmon"
                return 0 ;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------- per-hardware choices

cpu_ucode()   { echo "$CPU_VENDOR-ucode"; }

kernel_cmdline_extra() {
    local extra=()
    [[ $CPU_VENDOR == amd ]] && extra+=(amd_pstate=active)
    [[ $GPU_DRIVER == nvidia-* ]] && extra+=(nvidia_drm.modeset=1)
    if [[ $GPU_DRIVER == amd ]]; then
        local legacy
        read -ra legacy <<<"$(amd_legacy_params)"
        extra+=("${legacy[@]}")
    fi
    echo "${extra[*]}"
}

# NVIDIA modules load early from the initramfs; nouveau must not, so the kms hook goes away.
# AMD and Intel use the stock kms hook.
initramfs_modules() {
    [[ $GPU_DRIVER == nvidia-* ]] && echo "nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    return 0
}

initramfs_hooks() {
    local kms=" kms"
    [[ $GPU_DRIVER == nvidia-* ]] && kms=""
    echo "base systemd autodetect microcode modconf${kms} keyboard sd-vconsole block filesystems sd-btrfs-overlayfs fsck"
}

# Driver packages. Needs the CachyOS repos (run inside the chroot).
gpu_packages() {
    case $GPU_DRIVER in
        nvidia-open)
            # Prebuilt modules when both kernels have them, otherwise DKMS for every kernel
            # (prebuilt and DKMS modules can't be mixed).
            if pacman -Si "$KERNEL-nvidia-open" "$FALLBACK_KERNEL-nvidia-open" &>/dev/null; then
                echo "$KERNEL-nvidia-open $FALLBACK_KERNEL-nvidia-open"
            else
                echo nvidia-open-dkms
            fi
            echo nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver ;;
        nvidia-580xx)
            echo nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings \
                 egl-wayland libva-nvidia-driver ;;
        amd)
            echo mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon ;;
        intel)
            echo mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver ;;
    esac
}

# Optional peripheral/extra packages and the services they need.
optional_packages() {
    [[ $CORSAIR_KEYBOARD == yes ]] && echo ckb-next
    [[ $GAMING_MOUSE == yes ]]     && echo piper libratbag
    [[ $HEADSETCONTROL == yes ]]   && echo headsetcontrol
    [[ $BLUETOOTH == yes ]]        && echo bluez bluez-utils blueman
    return 0
}

optional_services() {
    [[ $CORSAIR_KEYBOARD == yes ]] && echo ckb-next-daemon.service
    [[ $GAMING_MOUSE == yes ]]     && echo ratbagd.service
    [[ $BLUETOOTH == yes ]]        && echo bluetooth.service
    return 0
}

# ---------------------------------------------------------------- validation

_errors=()
_warnings=()
_err()  { _errors+=("$*"); }
_warn() { _warnings+=("$*"); }

_yes_no() {
    local name=$1 value=${!1:-}
    [[ $value == yes || $value == no ]] || _err "$name must be yes or no (is '${value}')"
}

# validate_monitor "MATCH|MODE|POSITION|SCALE|VRR"
validate_monitor() {
    local match mode position scale vrr extra
    IFS='|' read -r match mode position scale vrr extra <<<"$1"
    [[ -n $match && -z $extra ]] || { _err "MONITORS entry '$1' needs 5 fields: MATCH|MODE|POSITION|SCALE|VRR"; return; }
    [[ $mode =~ ^(preferred|highrr|highres|[0-9]+x[0-9]+(@[0-9]+([.][0-9]+)?)?)$ ]] \
        || _err "MONITORS '$match': mode '$mode' (use preferred, highrr, or WIDTHxHEIGHT@HZ)"
    [[ $position =~ ^(auto(-(left|right|up|down))?|-?[0-9]+x-?[0-9]+)$ ]] \
        || _err "MONITORS '$match': position '$position' (use auto or XxY, e.g. 1920x0)"
    [[ $scale =~ ^(auto|[0-9]+([.][0-9]+)?)$ ]] \
        || _err "MONITORS '$match': scale '$scale' (use 1, 1.25, 1.5, 2 or auto)"
    [[ $vrr =~ ^[0-3]$ ]] || _err "MONITORS '$match': vrr '$vrr' (0 off, 1 on, 2 fullscreen only, 3 fullscreen video/games)"
}

# validate_config [hardware]
# Checks config values. With "hardware", also compares them with the machine it runs on
# (meant for the live ISO, before install.sh erases anything). Returns 1 on any error.
validate_config() {
    local hw=${1:-} v
    _errors=() _warnings=()

    [[ ${USERNAME:-} =~ ^[a-z_][a-z0-9_-]{0,31}$ && $USERNAME != root ]] \
        || _err "USERNAME '${USERNAME:-}': lowercase letters, digits, - or _, starting with a letter"
    [[ ${HOST_NAME:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] \
        || _err "HOST_NAME '${HOST_NAME:-}': letters, digits and -, no spaces"
    if [[ -z ${TIMEZONE:-} ]]; then _err "TIMEZONE is empty (e.g. America/Sao_Paulo)"
    elif [[ -d /usr/share/zoneinfo && ! -f /usr/share/zoneinfo/$TIMEZONE ]]; then
        _err "TIMEZONE '$TIMEZONE' not found (list: timedatectl list-timezones)"
    fi
    (( ${#LOCALES[@]} > 0 )) || _err "LOCALES is empty (e.g. (en_US.UTF-8))"
    for v in "${LOCALES[@]}"; do
        if [[ -f /usr/share/i18n/SUPPORTED ]] && ! grep -qx "$v UTF-8" /usr/share/i18n/SUPPORTED; then
            _err "LOCALES: '$v' is not a supported UTF-8 locale (see /usr/share/i18n/SUPPORTED)"
        fi
    done
    [[ " ${LOCALES[*]} " == *" ${LANG_DEFAULT:-} "* ]] || _err "LANG_DEFAULT '${LANG_DEFAULT:-}' must be one of LOCALES"
    if [[ -z ${KEYMAP:-} ]]; then _err "KEYMAP is empty (e.g. us, br-abnt2, de-latin1)"
    elif [[ -d /usr/share/kbd/keymaps ]] && [[ -z $(find /usr/share/kbd/keymaps -name "$KEYMAP.map.gz" -print -quit) ]]; then
        _err "KEYMAP '$KEYMAP' not found (list: localectl list-keymaps)"
    fi
    [[ -n ${KB_LAYOUT:-} ]] || _err "KB_LAYOUT is empty (e.g. us, br, de)"
    [[ ${MIRROR_COUNTRIES:-} =~ ^[A-Z]{2}(,[A-Z]{2})*$ ]] \
        || _err "MIRROR_COUNTRIES '${MIRROR_COUNTRIES:-}': two-letter codes separated by commas, e.g. BR,US"

    [[ -n ${INSTALL_DISK_MODEL:-} ]] || _err "INSTALL_DISK_MODEL is empty (see: lsblk -dno NAME,MODEL,SIZE)"
    [[ ${ESP_SIZE:-} =~ ^[0-9]+[MG]$ ]] || _err "ESP_SIZE '${ESP_SIZE:-}' (e.g. 4G)"

    [[ ${CPU_VENDOR:-} == amd || ${CPU_VENDOR:-} == intel ]] || _err "CPU_VENDOR must be amd or intel (is '${CPU_VENDOR:-}')"
    [[ " $GPU_DRIVERS " == *" ${GPU_DRIVER:-x} "* ]] || _err "GPU_DRIVER must be one of: $GPU_DRIVERS (is '${GPU_DRIVER:-}')"
    [[ ${KERNEL:-} =~ $KERNEL_RE ]] || _err "KERNEL '${KERNEL:-}' is not a CachyOS kernel package (see config.sh)"
    [[ ${FALLBACK_KERNEL:-} =~ $KERNEL_RE ]] || _err "FALLBACK_KERNEL '${FALLBACK_KERNEL:-}' is not a CachyOS kernel package"
    [[ ${KERNEL:-} != "${FALLBACK_KERNEL:-}" ]] || _err "KERNEL and FALLBACK_KERNEL must differ"

    for v in "${MONITORS[@]}"; do validate_monitor "$v"; done
    for v in CORSAIR_KEYBOARD GAMING_MOUSE HEADSETCONTROL BLUETOOTH HIDE_GPU_AUDIO UNDERVOLT; do _yes_no "$v"; done
    if [[ ${UNDERVOLT:-} == yes ]]; then
        (( ${#CO_OFFSETS[@]} > 0 )) || _err "UNDERVOLT=yes needs CO_OFFSETS (one value per core)"
        for v in "${CO_OFFSETS[@]}"; do
            if ! [[ $v =~ ^-?[0-9]+$ ]] || (( v < -30 || v > 0 )); then
                _err "CO_OFFSETS: '$v' must be between -30 and 0"
            fi
        done
    fi
    if [[ -n ${HDD_MODEL:-} && -z ${HDD_SERIAL:-} ]]; then
        _warn "HDD_MODEL is set but HDD_SERIAL is empty: extras.sh hdd will refuse to run"
    fi

    if [[ $hw == hardware ]]; then
        local cpu gpu disk
        cpu=$(detect_cpu_vendor)
        [[ -z ${CPU_VENDOR:-} || $cpu == "$CPU_VENDOR" ]] || _err "CPU_VENDOR is '${CPU_VENDOR:-}' but this CPU is '$cpu' ($(detect_cpu_model))"
        gpu=$(detect_gpu_driver)
        if [[ $gpu == unsupported ]]; then
            _err "this graphics card is too old: no Vulkan driver (NVIDIA before the GTX 900 series, AMD before the HD 7000 series)"
        elif [[ -n ${GPU_DRIVER:-} && $gpu != "$GPU_DRIVER" ]]; then
            _err "GPU_DRIVER is '${GPU_DRIVER:-}' but the detected GPU needs '$gpu'"
        fi
        if [[ -n ${INSTALL_DISK_MODEL:-} ]]; then
            disk=$(disk_by_model "$INSTALL_DISK_MODEL" 2>/dev/null) || true
            [[ -n $disk ]] || _err "no single disk matches INSTALL_DISK_MODEL '$INSTALL_DISK_MODEL' (see: lsblk -dno NAME,MODEL,SIZE)"
        fi
        if [[ ${UNDERVOLT:-} == yes && $(detect_cpu_model) != *5800X3D* ]]; then
            _err "UNDERVOLT=yes only supports the Ryzen 7 5800X3D (this CPU: $(detect_cpu_model))"
        fi
    fi

    for v in "${_warnings[@]}"; do warn "$v"; done
    for v in "${_errors[@]}"; do err "$v"; done
    (( ${#_errors[@]} == 0 ))
}
