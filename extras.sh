#!/usr/bin/env bash
# Optional extras (guide section 13). Run as your normal user.
#   ./extras.sh hdd   format the old Samsung HDD as ext4 and mount it at /mnt/hdd (ERASES it)
#   ./extras.sh dev   Docker + VS Code

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/config.sh"

[[ $EUID -ne 0 ]] || die "run as your normal user, not root or sudo"

cmd_hdd() {
    step "Bulk HDD ($HDD_MODEL)"
    [[ -n ${HDD_SERIAL:-} ]] || die "HDD_SERIAL is not set in config.sh (see README: Machine-specific values)"
    lsblk -dpo NAME,MODEL,SIZE,TYPE | grep -E 'NAME|disk'
    local disk
    disk=$(disk_by_model "$HDD_MODEL")
    [[ -n $disk ]] || die "no disk with model '$HDD_MODEL' found"
    [[ -b $disk ]] || die "$disk is not a block device"
    whole_disk "$disk" || die "$disk is not a whole disk"
    [[ $(lsblk -dnro TRAN "$disk") == sata ]] || die "$disk is not connected by SATA"
    [[ $(lsblk -dnro SERIAL "$disk") == "$HDD_SERIAL" ]] || die "$disk serial does not match $HDD_SERIAL"
    disk_has_mounts "$disk" && die "$disk or one of its partitions is mounted; unmount it before formatting"
    if grep -Eq '[[:space:]]/mnt/hdd[[:space:]]' /etc/fstab; then
        die "/mnt/hdd already has an fstab entry; inspect it before formatting"
    fi
    warn "about 49 000 power-on hours: bulk files or a second backup copy only"
    printf '\n%sEVERYTHING on %s (%s) will be erased.%s\n' "$c_red" "$disk" \
        "$(lsblk -dno MODEL,SIZE "$disk" | xargs)" "$c_off"
    local again
    read -r -p "Type the disk path again to confirm: " again
    [[ $again == "$disk" ]] || die "confirmation did not match, nothing was changed"

    sudo sgdisk -Z "$disk"
    sudo sgdisk -n1:0:0 -t1:8300 "$disk"
    sudo partprobe "$disk"
    sudo udevadm settle
    local hdd_part hdd_uuid
    hdd_part=$(part "$disk" 1)
    sudo mkfs.ext4 -F -L HDD "$hdd_part"
    hdd_uuid=$(sudo blkid -s UUID -o value "$hdd_part")
    [[ -n $hdd_uuid ]] || die "could not read the new ext4 filesystem UUID"
    sudo mkdir -p /mnt/hdd
    printf 'UUID=%s  /mnt/hdd  ext4  noatime,nofail,x-systemd.device-timeout=5s  0 2\n' "$hdd_uuid" \
        | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
    sudo mount /mnt/hdd
    [[ $(findmnt -n -o UUID -T /mnt/hdd) == "$hdd_uuid" ]] \
        || die "/mnt/hdd is not mounted from the expected Samsung HDD filesystem"
    sudo chown "$USER": /mnt/hdd
    local bookmarks="$HOME/.config/gtk-3.0/bookmarks"
    mkdir -p "${bookmarks%/*}"
    if ! grep -Eq '^file:///mnt/hdd([[:space:]]|$)' "$bookmarks" 2>/dev/null; then
        printf 'file:///mnt/hdd HDD\n' >> "$bookmarks"
    fi
    ok "mounted at /mnt/hdd and added to Thunar bookmarks; smartd watches its health"
}

cmd_dev() {
    step "Docker"
    sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
    sudo systemctl enable --now docker.socket
    sudo usermod -aG docker "$USER"
    warn "docker group = root-equivalent access; log out and back in to use it"

    step "VS Code"
    if confirm "Install Microsoft's build from the AUR (official marketplace)? No = OSS build 'code'"; then
        yay -S --needed visual-studio-code-bin
    else
        sudo pacman -S --needed --noconfirm code
    fi
    ok "dev tools installed"
}

case "${1:-}" in
    hdd) cmd_hdd ;;
    dev) cmd_dev ;;
    *) sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
