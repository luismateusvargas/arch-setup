#!/usr/bin/env bash
# Hardware detection and config validation, without touching real hardware.

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
# shellcheck source=scripts/hw.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/hw.sh"
trap - ERR

fail_test() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
expect() { [[ $2 == "$3" ]] || fail_test "$1: expected '$3', got '$2'"; }

# NVIDIA generation from the lspci codename
expect 'RTX 3070'   "$(nvidia_driver_for 'NVIDIA Corporation GA104 [GeForce RTX 3070 Lite Hash Rate]')" nvidia-open
expect 'GTX 1660'   "$(nvidia_driver_for 'NVIDIA Corporation TU116 [GeForce GTX 1660 SUPER]')" nvidia-open
expect 'RTX 4090'   "$(nvidia_driver_for 'NVIDIA Corporation AD102 [GeForce RTX 4090]')" nvidia-open
expect 'RTX 5080'   "$(nvidia_driver_for 'NVIDIA Corporation GB203 [GeForce RTX 5080]')" nvidia-open
expect 'GTX 1080'   "$(nvidia_driver_for 'NVIDIA Corporation GP104 [GeForce GTX 1080]')" nvidia-580xx
expect 'GTX 970'    "$(nvidia_driver_for 'NVIDIA Corporation GM204 [GeForce GTX 970]')" nvidia-580xx
expect 'GTX 750 Ti' "$(nvidia_driver_for 'NVIDIA Corporation GM107 [GeForce GTX 750 Ti]')" nvidia-580xx
expect 'GTX 780'    "$(nvidia_driver_for 'NVIDIA Corporation GK110 [GeForce GTX 780]')" unsupported
expect 'unknown id' "$(nvidia_driver_for 'NVIDIA Corporation Device 2c05')" nvidia-open

# Discrete GPU wins over the integrated one
lspci() {
    case "$*" in
        '-Dnn -d ::0300') printf '%s\n' \
            '0000:00:02.0 VGA compatible controller [0300]: Intel Corporation Raptor Lake-S GT1 [UHD Graphics 770] [8086:a780] (rev 04)' \
            '0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786] (rev a1)' ;;
        *) ;;
    esac
}
expect 'Intel iGPU + RTX 4070' "$(detect_gpu_driver)" nvidia-open
lspci() {
    [[ $* == '-Dnn -d ::0300' ]] && printf '%s\n' \
        '0000:03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 32 [Radeon RX 7800 XT] [1002:747e] (rev c8)'
    return 0
}
expect 'RX 7800 XT' "$(detect_gpu_driver)" amd

# AMD generations: GCN 1/2 get the amdgpu boot parameters, TeraScale is refused
amd_card() {
    eval "lspci() { [[ \$* == '-Dnn -d ::0300' ]] && printf '%s\n' $(printf '%q' "$*"); return 0; }"
}
amd_card '0000:01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Hawaii PRO [Radeon R9 290/390] [1002:67b1] (rev 80)'
expect 'R9 390 driver' "$(detect_gpu_driver)" amd
expect 'R9 390 params' "$(amd_legacy_params)" 'amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0'
GPU_DRIVER=amd CPU_VENDOR=amd
expect 'R9 390 cmdline' "$(kernel_cmdline_extra)" 'amd_pstate=active amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0'
amd_card '0000:01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Pitcairn XT [Radeon HD 7870 GHz Edition] [1002:6818]'
expect 'HD 7870 params' "$(amd_legacy_params)" 'amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0'
amd_card '0000:01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Tonga PRO [Radeon R9 285/380] [1002:6939] (rev f1)'
expect 'R9 380 driver' "$(detect_gpu_driver)" amd
expect 'R9 380 params' "$(amd_legacy_params)" ''
expect 'R9 380 cmdline' "$(kernel_cmdline_extra)" 'amd_pstate=active'
amd_card '0000:01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Barts PRO [Radeon HD 6850] [1002:6739]'
expect 'HD 6850' "$(detect_gpu_driver)" unsupported
lspci() {
    [[ $* == '-Dnn -d ::0300' ]] && printf '%s\n' \
        '0000:00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-S GT2 [UHD Graphics 630] [8086:9bc5]' \
        '0000:01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Caicos [Radeon HD 6450/7450/8450 / R5 230 OEM] [1002:6779]'
    return 0
}
expect 'Intel iGPU + HD 6450' "$(detect_gpu_driver)" intel
unset -f lspci

# Boot settings per driver
GPU_DRIVER=nvidia-open CPU_VENDOR=amd
expect 'nvidia modules' "$(initramfs_modules)" 'nvidia nvidia_modeset nvidia_uvm nvidia_drm'
[[ $(initramfs_hooks) != *' kms '* ]] || fail_test 'kms hook kept with NVIDIA'
expect 'amd+nvidia cmdline' "$(kernel_cmdline_extra)" 'amd_pstate=active nvidia_drm.modeset=1'
GPU_DRIVER=amd CPU_VENDOR=intel
expect 'amd modules' "$(initramfs_modules)" ''
[[ $(initramfs_hooks) == *' modconf kms keyboard '* ]] || fail_test 'kms hook missing for AMD'
expect 'intel cmdline' "$(kernel_cmdline_extra)" ''
expect 'intel ucode' "$(cpu_ucode)" intel-ucode

# Config validation: the shipped template must fail, a filled-in config must pass
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
validate_config >/dev/null 2>&1 && fail_test 'empty template accepted'
USERNAME=friend HOST_NAME=gaming-pc TIMEZONE=Europe/Berlin KEYMAP=de-latin1 KB_LAYOUT=de MIRROR_COUNTRIES=DE,US
INSTALL_DISK_MODEL="Samsung SSD 990 PRO 2TB" CPU_VENDOR=intel GPU_DRIVER=amd KERNEL=linux-cachyos-bore
MONITORS=("ASUS VG27|2560x1440@165|0x0|1|2" "DP-2|highrr|auto|1.25|0")
validate_config >/dev/null 2>&1 || { validate_config; fail_test 'valid config rejected'; }
MONITORS=("ASUS|2560x1440|0x0|1")
validate_config >/dev/null 2>&1 && fail_test 'monitor entry with 4 fields accepted'
MONITORS=()
KERNEL=linux-zen
validate_config >/dev/null 2>&1 && fail_test 'non-CachyOS kernel accepted'
KERNEL=linux-cachyos-lts
validate_config >/dev/null 2>&1 && fail_test 'KERNEL equal to FALLBACK_KERNEL accepted'
KERNEL=linux-cachyos UNDERVOLT=yes CO_OFFSETS=(-10 -40)
validate_config >/dev/null 2>&1 && fail_test 'offset below -30 accepted'

printf 'hardware helper tests passed\n'
