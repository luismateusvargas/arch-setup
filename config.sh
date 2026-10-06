# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are read by the scripts that source this file
#
# Fill this in BEFORE running install.sh. Every value says how to find it:
#   Windows:  from Windows, before you wipe it. tools/windows-inventory.ps1 prints most of them.
#   ISO:      from the Arch live ISO. `bash check-config.sh` compares this file with the hardware
#             and lists anything wrong; install.sh runs the same check before it erases anything.
# Example values are from the reference build (Ryzen 7 5800X3D + RTX 3070).
#
# Personal values can also go in config.local.sh (same variables, git-ignored, read after this file).

# ============================================================== 1. You
# Login name: lowercase letters, digits, - or _ (no spaces). Pick anything.   Example: luis
USERNAME=""
# Computer name: letters, digits and -.
#   Windows: Settings > System > About > Device name                           Example: MINDEXTENSION
HOST_NAME=""
# Time zone, IANA name.
#   Windows: the inventory script converts it; or pick your city from the list below.
#   ISO:     timedatectl list-timezones | grep -i <your city>                 Example: America/Sao_Paulo
TIMEZONE=""
# Languages to generate. The first is usually en_US.UTF-8; add yours.
#   Windows: Settings > Time & language > Language & region (pt-BR -> pt_BR.UTF-8)
#   ISO:     grep UTF-8 /usr/share/i18n/SUPPORTED | grep -i <language>        Example: (en_US.UTF-8 pt_BR.UTF-8)
LOCALES=(en_US.UTF-8)
# System language, one of LOCALES.                                           Example: en_US.UTF-8
LANG_DEFAULT=en_US.UTF-8
# Console keyboard map (text mode, before the desktop starts).
#   Windows: Settings > Time & language > Typing > Advanced keyboard settings > input method
#            US -> us, Portuguese (Brazil ABNT2) -> br-abnt2, German -> de-latin1, UK -> uk
#   ISO:     localectl list-keymaps | grep -i <country>; test with: loadkeys <name>
KEYMAP=us
# Desktop keyboard layout and variant (X keyboard names).
#   US -> us, Brazil ABNT2 -> br, Germany -> de, UK -> gb;  US-International -> us + variant intl
KB_LAYOUT=us
KB_VARIANT=""
# Countries for the package mirrors, nearest first (two-letter codes).
#   ISO:     reflector --list-countries                                       Example: BR,US
MIRROR_COUNTRIES=US

# ============================================================== 2. Install disk (ERASED)
# Model name of the disk Arch goes on. EVERYTHING on it is erased; install.sh also asks you
# to type its path before touching it.
#   Windows: PowerShell:  Get-PhysicalDisk | Format-Table FriendlyName, MediaType, Size
#   ISO:     lsblk -dno NAME,MODEL,SIZE,TRAN       (the MODEL column)          Example: KINGSTON SNV2S1000G
INSTALL_DISK_MODEL=""
# EFI partition: kernels, initramfs images and snapshot boot entries. 4G fits two kernels + snapshots.
ESP_SIZE=4G

# ============================================================== 3. CPU, GPU, kernel
# CPU maker: amd or intel. Picks the microcode and the CPU frequency driver.
#   Windows: Settings > System > About > Processor
#   ISO:     grep -m1 'model name' /proc/cpuinfo                               Example: amd
CPU_VENDOR=""
# Graphics driver for the card your monitors are plugged into:
#   nvidia-open    NVIDIA RTX 20/30/40/50, GTX 16xx            (open kernel modules, current driver)
#   nvidia-580xx   NVIDIA GTX 750/900/1000, Titan X/Xp, Quadro M/P  (580 series, last to support them)
#   amd            AMD Radeon HD 7000 and newer (R7/R9, RX)     (Mesa, in the kernel; HD 7000 and
#                  R7/R9 200/300 except the R9 285/380 get boot parameters that switch them to amdgpu)
#   intel          Intel Arc, or integrated graphics            (Mesa, in the kernel; 4th-gen Core
#                  "Haswell" and older have only partial Vulkan: many Proton games won't run)
# Not supported (no Vulkan driver for games): NVIDIA GTX 600/700 (Kepler, except 750/750 Ti) and
# older, AMD Radeon HD 6000 and older.
#   Windows: Device Manager > Display adapters
#   ISO:     lspci -nn | grep -Ei 'vga|3d|display'                             Example: nvidia-open
GPU_DRIVER=""
# Main kernel and the fallback offered in the boot menu if the main one ever breaks.
# Every option below is in the CachyOS repos, with matching NVIDIA modules:
#   linux-cachyos            EEVDF scheduler + LTO/AutoFDO/Propeller builds. Recommended default.
#   linux-cachyos-bore       BORE scheduler: favours interactive/game threads under heavy load.
#   linux-cachyos-eevdf      plain EEVDF (the upstream scheduler) with the Cachy patches.
#   linux-cachyos-bmq        BMQ scheduler (alternative design, some prefer it for latency).
#   linux-cachyos-rt-bore    real-time kernel (audio production); worse for gaming throughput.
#   linux-cachyos-server     tuned for throughput, not desktop latency.
#   linux-cachyos-hardened   extra security hardening; can break some programs and games.
#   linux-cachyos-deckify    handheld (Steam Deck-like) patches.
#   linux-cachyos-lts        long-term-support kernel: the safest fallback.
#   linux-cachyos-rc         release candidate: newest hardware support, least tested.
#   -lto suffix (e.g. linux-cachyos-bore-lto): the same kernel built with Clang LTO.
# Very new hardware (released in the last few months) may need linux-cachyos-rc as KERNEL.
# sched-ext (scx_bpfland, set up by the installer) replaces the scheduler at runtime on any of them.
KERNEL=linux-cachyos
FALLBACK_KERNEL=linux-cachyos-lts

# ============================================================== 4. Monitors
# One line per monitor; the first is the main one (workspaces 1-2), the second gets workspace 3.
# Leave empty to let Hyprland pick each monitor's preferred mode automatically.
#   "MATCH|MODE|POSITION|SCALE|VRR"
#   MATCH     part of the monitor's name (e.g. ULTRAWIDE, LG, ASUS VG27) or its port (DP-1, HDMI-A-1).
#             The port names only exist on Linux: after the first boot, `hyprctl monitors all`.
#             Windows: Settings > System > Display > Advanced display > Display information (name)
#   MODE      WIDTHxHEIGHT@HZ (e.g. 2560x1440@165), or highrr (highest refresh), or preferred.
#             Windows: same Advanced display page (Desktop mode, Refresh rate)
#   POSITION  where its top-left corner sits, in pixels: 0x0 for the leftmost; a monitor to its
#             right starts at the left one's width (1920x0). Or auto.
#             Windows: Settings > System > Display shows the arrangement.
#   SCALE     1 for 100 %, 1.25, 1.5, 2 (Windows: Display > Scale), or auto.
#   VRR       adaptive sync (FreeSync/G-Sync): 0 off, 1 always, 2 fullscreen apps only (best for
#             NVIDIA, avoids desktop flicker). NVIDIA has no VRR over HDMI unless the monitor
#             supports HDMI 2.1 VRR: use 0 there.
# Example (reference build: LG UltraWide on DisplayPort right of a 1080p monitor on HDMI):
#   MONITORS=("ULTRAWIDE|2560x1080@144|1920x0|1|2" "HDMI-A-1|1920x1080@144|0x0|1|0")
MONITORS=()

# ============================================================== 5. Optional extras (yes/no)
# Corsair keyboard/mouse lighting and macros (ckb-next). Windows: you use iCUE.
CORSAIR_KEYBOARD=no
# Gaming mouse DPI/buttons (Piper + libratbag: Logitech, SteelSeries, some Razer/Roccat).
# Windows: you use G HUB / SteelSeries GG. Supported list: https://github.com/libratbag/libratbag/tree/master/data/devices
GAMING_MOUSE=no
# Headset sidetone/battery for USB/wireless gaming headsets (HeadsetControl).
# Supported list: https://github.com/Sapd/HeadsetControl#supported-headsets
HEADSETCONTROL=no
# Bluetooth (controllers, headphones). Windows: Settings > Bluetooth & devices.
BLUETOOTH=no
# Hide the graphics card's HDMI/DP audio output so it can't become the default speaker.
# Set no if you use your monitor's speakers.
HIDE_GPU_AUDIO=yes
# Per-core Curve Optimizer undervolt, Ryzen 7 5800X3D ONLY (undervolt.sh, guide section 11).
# CO_OFFSETS: one value per core (-30..0), core 0 first; on Windows, PBO2 Tuner shows yours.
UNDERVOLT=no
CO_OFFSETS=()
# Old internal SATA hard drive to wipe and use as bulk storage (extras.sh hdd). Optional.
#   ISO/Linux: lsblk -dno NAME,MODEL,SERIAL,TRAN   (the SERIAL of the sata disk)
#   Windows:   Get-PhysicalDisk | Format-Table FriendlyName, SerialNumber, BusType
# Never commit a real serial to a public repo: put HDD_* in config.local.sh.
HDD_MODEL=""
HDD_SERIAL=""
