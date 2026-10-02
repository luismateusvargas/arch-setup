#!/usr/bin/env bash
# Stage 1: run from the Arch Linux live ISO, as root.
# Wipes the install NVMe, creates the btrfs layout, installs the base system,
# then configures it inside arch-chroot (scripts/chroot.sh). Guide sections 3-5.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/config.sh"

[[ $EUID -eq 0 ]] || die "run as root: bash install.sh"
[[ -d /run/archiso ]] || die "this must run from the Arch Linux live ISO"
[[ $(cat /sys/firmware/efi/fw_platform_size 2>/dev/null) == 64 ]] \
    || die "not booted in 64-bit UEFI mode (disable CSM, boot the USB's UEFI entry)"

step "Settings (config.sh)"
info "user: $USERNAME   host: $HOST_NAME   timezone: $TIMEZONE"
info "keymap: $KEYMAP   locales: ${LOCALES[*]}   mirrors: $MIRROR_COUNTRIES"
confirm "Are these correct?" || die "edit config.sh, then run install.sh again"

step "Network and clock"
ping -c 1 -W 5 archlinux.org >/dev/null || die "no network: plug in Ethernet"
timedatectl set-ntp true
ok "online"

step "Install disk"
lsblk -dpo NAME,MODEL,SIZE,TYPE | grep -E 'NAME|disk'
DISK=$(disk_by_model "$INSTALL_DISK_MODEL")
if [[ -n $DISK ]]; then
    info "found $INSTALL_DISK_MODEL at $DISK"
else
    warn "no disk with model '$INSTALL_DISK_MODEL' found"
    read -r -p "Type the disk to install to (e.g. /dev/nvme0n1): " DISK
fi
[[ -b $DISK ]] || die "$DISK is not a block device"
whole_disk "$DISK" || die "$DISK is not a whole disk"
mountpoint -q /mnt && die "/mnt is already mounted: run 'umount -R /mnt' first"
disk_has_mounts "$DISK" && die "$DISK or one of its partitions is mounted"

printf '\n%sEVERYTHING on %s (%s) will be erased.%s\n' "$c_red" "$DISK" \
    "$(lsblk -dno MODEL,SIZE "$DISK" | xargs)" "$c_off"
read -r -p "Type the disk path again to confirm: " again
[[ $again == "$DISK" ]] || die "confirmation did not match, nothing was changed"

ESP=$(part "$DISK" 1)
ROOT=$(part "$DISK" 2)

step "Partitioning $DISK"
blkdiscard -f "$DISK" || warn "blkdiscard failed (not fatal)"
sgdisk -Z "$DISK"
sgdisk -n1:0:+"$ESP_SIZE" -t1:ef00 -c1:EFI \
       -n2:0:0           -t2:8304 -c2:ARCH "$DISK"
partprobe "$DISK"
udevadm settle
mkfs.fat -F 32 -n EFI "$ESP"
mkfs.btrfs -f -L ARCH "$ROOT"
ok "ESP $ESP ($ESP_SIZE FAT32), root $ROOT (btrfs)"

step "btrfs subvolumes and mounts"
mount "$ROOT" /mnt
for sv in @ @home @log @pkg @docker; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

opts=noatime,compress=zstd:1
mount -o "$opts,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,var/lib/docker}
mount -o "$opts,subvol=@home"   "$ROOT" /mnt/home
mount -o "$opts,subvol=@log"    "$ROOT" /mnt/var/log
mount -o "$opts,subvol=@pkg"    "$ROOT" /mnt/var/cache/pacman/pkg
mount -o "$opts,subvol=@docker" "$ROOT" /mnt/var/lib/docker
mount -o fmask=0077,dmask=0077  "$ESP"  /mnt/boot
findmnt -R /mnt -o TARGET,SOURCE,OPTIONS | sed 's/^/    /'

step "Mirrors"
reflector --country "$MIRROR_COUNTRIES" --protocol https --latest 15 --sort rate \
    --save /etc/pacman.d/mirrorlist || warn "reflector failed; keeping the ISO's mirrorlist"

step "Base system (pacstrap)"
pacstrap -K /mnt base base-devel linux-firmware amd-ucode btrfs-progs dosfstools efibootmgr \
                 networkmanager sudo git neovim nano man-db man-pages bash-completion \
                 pacman-contrib reflector smartmontools zram-generator python

step "fstab"
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*//g' /mnt/etc/fstab   # snapshot restore changes subvolume IDs
grep -v '^#' /mnt/etc/fstab | grep -v '^$' | sed 's/^/    /'
[[ $(grep -c '^UUID=' /mnt/etc/fstab) -eq 6 ]] || die "expected 6 fstab entries"

step "Configuring the new system (arch-chroot)"
rm -rf /mnt/root/arch-setup
mkdir -p /mnt/root/arch-setup
# Copy only install assets; the working directory may contain private reports.
cp -a "$REPO_DIR"/{.gitattributes,.gitignore,README.md,arch_setup.md,arch_setup.html,\
config.sh,install.sh,post-install.sh,undervolt.sh,check.sh,extras.sh,files,scripts,tools} \
    /mnt/root/arch-setup/
arch-chroot /mnt /bin/bash /root/arch-setup/scripts/chroot.sh

step "Stage 1 complete"
info "Next: reboot, pick 'linux-cachyos' in Limine, log in with session 'Hyprland (uwsm-managed)',"
info "open a terminal (SUPER+Q on the first-start config) and run:  ~/arch-setup/post-install.sh"
if confirm "Unmount and reboot now? (remove the USB stick when the screen goes dark)"; then
    umount -R /mnt
    reboot
fi
