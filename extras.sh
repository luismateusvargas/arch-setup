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
    lsblk -dpo NAME,MODEL,SIZE,TYPE | grep -E 'NAME|disk'
    local disk
    disk=$(disk_by_model "$HDD_MODEL")
    [[ -n $disk ]] || die "no disk with model '$HDD_MODEL' found"
    local mounted
    mounted=$(findmnt -rno SOURCE)
    if grep -q "^$disk" <<<"$mounted"; then die "$disk has mounted partitions"; fi
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
    sudo mkfs.ext4 -F -L HDD "$(part "$disk" 1)"
    sudo mkdir -p /mnt/hdd
    if ! grep -q '^LABEL=HDD ' /etc/fstab; then
        echo 'LABEL=HDD  /mnt/hdd  ext4  noatime,nofail,x-systemd.device-timeout=5s  0 2' | sudo tee -a /etc/fstab >/dev/null
    fi
    sudo systemctl daemon-reload
    sudo mount /mnt/hdd
    sudo chown "$USER": /mnt/hdd
    ok "mounted at /mnt/hdd; smartd watches its health"
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
