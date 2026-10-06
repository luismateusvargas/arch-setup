#!/usr/bin/env bash
# Stage 2: run after the first boot, as your normal user, from a terminal inside Hyprland.
# Snapshots, desktop/audio configs, session services. Guide sections 7-9.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/config.sh"
FILES="$REPO_DIR/files"
CFG="$HOME/.config"

[[ $EUID -ne 0 ]] || die "run as your normal user, not root or sudo"
[[ ! -d /run/archiso ]] || die "this is for the installed system, not the live ISO"
sudo -v

step "Bootable snapshots: snapper + Limine (7)"
sudo pacman -S --needed --noconfirm snapper snap-pac limine-snapper-sync btrfs-assistant
if ! sudo snapper -c root get-config &>/dev/null; then
    sudo snapper -c root create-config /
fi
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
sudo systemctl enable --now limine-snapper-sync.service snapper-cleanup.timer
snapshots=$(sudo snapper -c root list)
if ! grep -q 'fresh install' <<<"$snapshots"; then
    sudo snapper -c root create -d "fresh install"
fi
ok "snapper configured; Limine snapshot menu is kept in sync"

step "Session environment and Hyprland config (8.1, 8.2)"
install_file "$FILES/home/.config/uwsm/env"          "$CFG/uwsm/env"
install_file "$FILES/home/.config/uwsm/env-hyprland" "$CFG/uwsm/env-hyprland"

lua_tmp=$(mktemp)
cp "$FILES/home/.config/hypr/hyprland.lua" "$lua_tmp"
sed -i "s/kb_layout          = \"us\"/kb_layout          = \"$KB_LAYOUT\"/" "$lua_tmp"
sed -i "s/^local SIDE = \"[^\"]*\"/local SIDE = \"$SIDE_MONITOR_PORT\"/" "$lua_tmp"
main_port=""
if command -v hyprctl >/dev/null && monitors_json=$(hyprctl monitors all -j 2>/dev/null); then
    main_port=$(MATCH="$MAIN_MONITOR_MATCH" python3 -c '
import json, os, sys
match = os.environ["MATCH"].lower()
for m in json.load(sys.stdin):
    if match in (m.get("description", "") + " " + m.get("model", "")).lower():
        print(m["name"]); break
' <<<"$monitors_json")
fi
if [[ -n $main_port ]]; then
    sed -i "s/^local MAIN = \"[^\"]*\"/local MAIN = \"$main_port\"/" "$lua_tmp"
    ok "main monitor ($MAIN_MONITOR_MATCH) detected on $main_port"
else
    warn "couldn't detect the LG's port (is Hyprland running?). Keeping DP-1; check with: hyprctl monitors all"
fi
install_file "$lua_tmp" "$CFG/hypr/hyprland.lua"
rm -f "$lua_tmp"

step "Idle, lock, bar, session services (8.3)"
install_file "$FILES/home/.config/hypr/hypridle.conf"  "$CFG/hypr/hypridle.conf"
install_file "$FILES/home/.config/waybar/config.jsonc" "$CFG/waybar/config.jsonc"
install_file "$FILES/home/.config/waybar/scripts/cpu_voltage.sh" "$CFG/waybar/scripts/cpu_voltage.sh" 755
install_file "$FILES/home/.config/waybar/scripts/gpu-stats.sh"   "$CFG/waybar/scripts/gpu-stats.sh"   755
install_file "$FILES/home/.config/systemd/user/gpu-stats.service" "$CFG/systemd/user/gpu-stats.service"
systemctl --user daemon-reload
systemctl --user enable gpu-stats.service
[[ -e $CFG/hypr/hyprlock.conf ]] || install -Dm644 /usr/share/hypr/hyprlock.conf "$CFG/hypr/hyprlock.conf"
systemctl --user add-wants graphical-session.target \
    waybar.service swaync.service hypridle.service hyprpolkitagent.service
xdg-user-dirs-update
mkdir -p "$HOME/Pictures"
[[ -e $HOME/Pictures/wallpaper.jpg ]] || info "No custom wallpaper at ~/Pictures/wallpaper.jpg; using Hyprland's bundled wallpaper"

step "PipeWire + WirePlumber (9.1, 9.2)"
install_file "$FILES/home/.config/pipewire/pipewire.conf.d/10-latency.conf" \
             "$CFG/pipewire/pipewire.conf.d/10-latency.conf"
wp_tmp=$(mktemp)
cp "$FILES/home/.config/wireplumber/wireplumber.conf.d/51-devices.conf" "$wp_tmp"
nv_audio=$(lspci -D | awk '/NVIDIA/ && /Audio/ && !found { print $1; found = 1 }')
if [[ -n $nv_audio ]]; then
    card="alsa_card.pci-${nv_audio//:/_}"
    sed -i "s/alsa_card\.pci-[0-9a-f_]*\.[0-9]/$card/" "$wp_tmp"
    ok "NVIDIA HDMI/DP audio is $card (will be hidden)"
else
    warn "NVIDIA audio device not found by lspci; leaving the rule as in the guide"
fi
install_file "$wp_tmp" "$CFG/wireplumber/wireplumber.conf.d/51-devices.conf"
rm -f "$wp_tmp"
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 2
info "$(pw-metadata -n settings 2>/dev/null | grep -o "clock.quantum' value:'[0-9]*'" || echo 'quantum: check with pw-metadata -n settings')"

if pgrep -x Hyprland >/dev/null; then
    if hyprctl reload >/dev/null; then ok "Hyprland config reloaded"; else warn "hyprctl reload failed; log out and back in"; fi
fi

step "Stage 2 complete"
info "Log out (SUPER+SHIFT+E) and back in so waybar, swaync, hypridle and the polkit agent start."
info "Then: EasyEffects setup (guide 9.3); check the analog audio defaults with wpctl (guide 9.2),"
info "      undervolt: ./undervolt.sh install, ./undervolt.sh test, ./undervolt.sh enable"
info "      verify everything: ./check.sh"
