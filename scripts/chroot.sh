#!/usr/bin/env bash
# Stage 1b: runs inside arch-chroot, started by install.sh. Guide section 5.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/hw.sh"
load_config "$REPO_DIR"
FILES="$REPO_DIR/files"

[[ $EUID -eq 0 ]] || die "must run as root inside arch-chroot"
# arch-chroot bind-mounts the live ISO's /run, including /run/archiso.

pac() { pacman -S --needed --noconfirm "$@"; }

step "Time, locale, hostname (5.1)"
[[ -f /usr/share/zoneinfo/$TIMEZONE ]] || die "unknown timezone $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
for loc in "${LOCALES[@]}"; do
    sed -i "s/^#\(${loc} \)/\1/" /etc/locale.gen
done
locale-gen
echo "LANG=$LANG_DEFAULT" > /etc/locale.conf
echo "KEYMAP=$KEYMAP"     > /etc/vconsole.conf
echo "$HOST_NAME"         > /etc/hostname

step "Users (5.1)"
echo "Set the ROOT password:"
until passwd; do warn "try again"; done
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -G wheel -s /bin/bash "$USERNAME"
fi
echo "Set the password for $USERNAME:"
until passwd "$USERNAME"; do warn "try again"; done
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel >/dev/null

step "pacman: multilib + CachyOS repositories (5.2)"
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
if ! grep -q '^\[cachyos-v3\]' /etc/pacman.conf; then
    info "running the official CachyOS repo script; answer Y to its prompts"
    tmp=$(mktemp -d)
    curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar -xJ -C "$tmp"
    (cd "$tmp/cachyos-repo" && ./cachyos-repo.sh)
    rm -rf "$tmp"
fi
grep -q '^Architecture = auto' /etc/pacman.conf || die "CachyOS script did not set Architecture = auto"
# The script adds [cachyos-v3|v4|znver4] (+ -core/-extra) when the CPU supports that level,
# and [cachyos] always.
for repo in cachyos multilib; do
    grep -q "^\[$repo\]" /etc/pacman.conf || die "[$repo] missing from /etc/pacman.conf"
done
# The repo helper may leave cached sync databases behind when it changes mirrors.
# Refresh them unconditionally before resolving packages from the new repos.
pacman -Syyu --noconfirm
pacman -Si "$KERNEL" "$FALLBACK_KERNEL" >/dev/null \
    || die "kernel $KERNEL or $FALLBACK_KERNEL not found in the repos (check KERNEL in config.sh)"
ok "repos: $(grep -oP '^\[\K[^]]+(?=\])' /etc/pacman.conf | grep -v options | xargs)"

step "Boot chain: Limine + mkinitcpio, before the kernels (5.3)"
# Separate transaction: pacman only runs hooks that existed when the transaction started.
pac limine limine-mkinitcpio-hook mkinitcpio
root_uuid=$(findmnt -no UUID /)
[[ -n $root_uuid ]] || die "could not read the root filesystem UUID"
echo "root=UUID=$root_uuid rootflags=subvol=/@ rw quiet nowatchdog zswap.enabled=0 $(kernel_cmdline_extra)" \
    | sed 's/ *$//' > /etc/kernel/cmdline
sed -i "s/^MODULES=.*/MODULES=($(initramfs_modules))/" /etc/mkinitcpio.conf
sed -i "s/^HOOKS=.*/HOOKS=($(initramfs_hooks))/" /etc/mkinitcpio.conf
info "cmdline: $(cat /etc/kernel/cmdline)"
grep -E '^(MODULES|HOOKS)=' /etc/mkinitcpio.conf | sed 's/^/    /'

step "Kernels + graphics driver: $KERNEL, $FALLBACK_KERNEL, $GPU_DRIVER (5.4)"
# Headers for both kernels: DKMS modules (580xx, nvidia-open-dkms, ryzen_smu) build against them.
read -ra gpu_pkgs <<<"$(gpu_packages | xargs)"
pac "$KERNEL" "$KERNEL-headers" "$FALLBACK_KERNEL" "$FALLBACK_KERNEL-headers" "${gpu_pkgs[@]}"

step "Installing Limine"
limine-install
limine-install --fallback
limine-update
limine-list | sed 's/^/    /'

step "Desktop, audio, gaming, peripherals (5.5)"
desktop=(hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm libnewt
         hyprpolkitagent hyprlock hypridle awww waybar swaync rofi kitty
         grim slurp wl-clipboard cliphist qt5-wayland qt6-wayland
         noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd otf-font-awesome ttf-liberation
         thunar gvfs xdg-user-dirs firefox nwg-look playerctl ly)
audio=(pipewire pipewire-alsa pipewire-pulse pipewire-jack lib32-pipewire lib32-pipewire-jack
       wireplumber rtkit pavucontrol easyeffects lsp-plugins-lv2 calf)
gaming=(steam lutris umu-launcher proton-cachyos-slr gamemode lib32-gamemode
        mangohud lib32-mangohud gamescope heroic-games-launcher protonup-qt winetricks)
system=(scx-scheds scx-tools yay dkms stress-ng)
read -ra extras <<<"$(optional_packages | xargs)"
pac "${desktop[@]}" "${audio[@]}" "${gaming[@]}" "${system[@]}" "${extras[@]}"

step "Memory: zram + sysctl, NTSYNC (5.6)"
install_file "$FILES/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
install_file "$FILES/etc/sysctl.d/99-workstation.conf" /etc/sysctl.d/99-workstation.conf
echo ntsync > /etc/modules-load.d/ntsync.conf

step "Scheduler, mirrors, services (5.7)"
install_file "$FILES/etc/scx_loader.toml" /etc/scx_loader.toml
cat > /etc/xdg/reflector/reflector.conf <<EOF
--save /etc/pacman.d/mirrorlist
--country $MIRROR_COUNTRIES
--protocol https
--latest 15
--sort rate
EOF
read -ra extra_units <<<"$(optional_services | xargs)"
systemctl enable NetworkManager.service systemd-timesyncd.service \
                 reflector.timer paccache.timer smartd.service \
                 scx_loader.service ly@tty2.service "${extra_units[@]}"
systemctl disable getty@tty2.service
if getent group gamemode >/dev/null; then usermod -aG gamemode "$USERNAME"; fi

step "Copying install assets to /home/$USERNAME/arch-setup for stage 2"
rm -rf "/home/$USERNAME/arch-setup"
cp -a "$REPO_DIR" "/home/$USERNAME/arch-setup"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/arch-setup"

ok "chroot configuration finished"
