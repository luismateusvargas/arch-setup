# shellcheck shell=bash
# Settings used by every script. Check these before running install.sh.
# shellcheck disable=SC2034  # variables are read by the scripts that source this file

USERNAME=htxzz77
HOST_NAME=MINDEXTENSION
TIMEZONE=America/Sao_Paulo
LOCALES=(en_US.UTF-8 pt_BR.UTF-8)
LANG_DEFAULT=en_US.UTF-8
KEYMAP=br-abnt2                  # console keymap (br-abnt2 for an ABNT2 keyboard)
KB_LAYOUT=br               # Hyprland keyboard layout (br for ABNT2)
MIRROR_COUNTRIES=BR,US     # reflector country codes

# Disks are picked by model name so the wrong one can't be chosen by accident.
INSTALL_DISK_MODEL="KINGSTON SNV2S1000G"   # NVMe: system install target
HDD_MODEL="SAMSUNG HD502HJ"                # old HDD: optional bulk disk (extras.sh hdd)
ESP_SIZE=4G                                # FAT32 /boot: kernels, initramfs, snapshot entries

# Monitor descriptions, matched case-insensitively against `hyprctl monitors all`
MAIN_MONITOR_MATCH="ULTRAWIDE"             # LG UltraWide on DisplayPort
SIDE_MONITOR_PORT="HDMI-A-1"               # SuperFrame Ace 27 on the card's HDMI port
