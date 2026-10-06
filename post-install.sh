#!/usr/bin/env bash
# Stage 2: run after the first boot, as your normal user, from a terminal inside Hyprland.
# Snapshots, desktop/audio configs, session services. Guide sections 7-9.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/hw.sh"
load_config "$REPO_DIR"
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
env_tmp=$(mktemp)
cp "$FILES/home/.config/uwsm/env" "$env_tmp"
[[ $GPU_DRIVER == nvidia-* ]] && cat "$FILES/home/.config/uwsm/env-nvidia" >> "$env_tmp"
install_file "$env_tmp" "$CFG/uwsm/env"
rm -f "$env_tmp"
install_file "$FILES/home/.config/uwsm/env-hyprland" "$CFG/uwsm/env-hyprland"

# Monitors are matched by name against what Hyprland sees right now (MONITORS in config.sh).
lua_tmp=$(mktemp)
monitors_json=""
if command -v hyprctl >/dev/null && monitors_json=$(hyprctl monitors all -j 2>/dev/null); then
    info "connected: $(python3 -c 'import json,sys; print(", ".join(m["name"] + " (" + m["description"] + ")" for m in json.load(sys.stdin)))' <<<"$monitors_json")"
else
    monitors_json=""
    warn "Hyprland isn't running: monitor names in MONITORS can't be matched (port names still work)"
fi
MONITORS="$(printf '%s\n' "${MONITORS[@]}")" MONITORS_JSON="$monitors_json" \
KB_LAYOUT="$KB_LAYOUT" KB_VARIANT="$KB_VARIANT" CORSAIR_KEYBOARD="$CORSAIR_KEYBOARD" \
    python3 "$REPO_DIR/scripts/render.py" hyprland "$FILES/home/.config/hypr/hyprland.lua" "$lua_tmp"
install_file "$lua_tmp" "$CFG/hypr/hyprland.lua"
rm -f "$lua_tmp"
grep -E '^(local (MAIN|SIDE)|hl\.monitor)' "$CFG/hypr/hyprland.lua" | sed 's/^/    /'

step "Idle, lock, bar, session services (8.3)"
install_file "$FILES/home/.config/hypr/hypridle.conf"  "$CFG/hypr/hypridle.conf"
bar_tmp=$(mktemp)
CPU_HWMON="$(cpu_hwmon_dir || true)" GPU_DRIVER="$GPU_DRIVER" UNDERVOLT="$UNDERVOLT" \
    python3 "$REPO_DIR/scripts/render.py" waybar "$FILES/home/.config/waybar/config.jsonc" "$bar_tmp"
install_file "$bar_tmp" "$CFG/waybar/config.jsonc"
rm -f "$bar_tmp"
install_file "$FILES/home/.config/waybar/style.css"    "$CFG/waybar/style.css"
if [[ $UNDERVOLT == yes ]]; then
    install_file "$FILES/home/.config/waybar/scripts/cpu_voltage.sh" "$CFG/waybar/scripts/cpu_voltage.sh" 755
fi
if [[ $GPU_DRIVER != intel ]]; then
    install_file "$FILES/home/.config/waybar/scripts/gpu-stats.sh"   "$CFG/waybar/scripts/gpu-stats.sh"   755
    install_file "$FILES/home/.config/systemd/user/gpu-stats.service" "$CFG/systemd/user/gpu-stats.service"
    systemctl --user daemon-reload
    systemctl --user enable gpu-stats.service
fi
[[ -e $CFG/hypr/hyprlock.conf ]] || install -Dm644 /usr/share/hypr/hyprlock.conf "$CFG/hypr/hyprlock.conf"
systemctl --user add-wants graphical-session.target \
    waybar.service swaync.service hypridle.service hyprpolkitagent.service
xdg-user-dirs-update
mkdir -p "$HOME/Pictures"
[[ -e $HOME/Pictures/wallpaper.jpg ]] || info "No custom wallpaper at ~/Pictures/wallpaper.jpg; using Hyprland's bundled wallpaper"

step "PipeWire + WirePlumber (9.1, 9.2)"
install_file "$FILES/home/.config/pipewire/pipewire.conf.d/10-latency.conf" \
             "$CFG/pipewire/pipewire.conf.d/10-latency.conf"
mapfile -t gpu_audio < <(gpu_audio_devices)
if [[ $HIDE_GPU_AUDIO == yes && ${#gpu_audio[@]} -gt 0 ]]; then
    wp_tmp=$(mktemp)
    {
        echo "# Hide the graphics card's HDMI/DP audio (HIDE_GPU_AUDIO=yes in config.sh)"
        echo "monitor.alsa.rules = ["
        for dev in "${gpu_audio[@]}"; do
            card="alsa_card.pci-${dev//:/_}"
            printf '  {\n    matches = [ { device.name = "%s" } ]\n' "$card"
            printf '    actions = { update-props = { device.disabled = true } }\n  }\n'
            ok "GPU HDMI/DP audio $card will be hidden"
        done
        echo "]"
    } > "$wp_tmp"
    install_file "$wp_tmp" "$CFG/wireplumber/wireplumber.conf.d/51-devices.conf"
    rm -f "$wp_tmp"
else
    info "GPU HDMI/DP audio left enabled (HIDE_GPU_AUDIO=$HIDE_GPU_AUDIO, devices found: ${#gpu_audio[@]})"
fi
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 2
info "$(pw-metadata -n settings 2>/dev/null | grep -o "clock.quantum' value:'[0-9]*'" || echo 'quantum: check with pw-metadata -n settings')"

if pgrep -x Hyprland >/dev/null; then
    if hyprctl reload >/dev/null; then ok "Hyprland config reloaded"; else warn "hyprctl reload failed; log out and back in"; fi
fi

step "Stage 2 complete"
info "Log out (SUPER+SHIFT+E) and back in so waybar, swaync, hypridle and the polkit agent start."
info "Then: EasyEffects setup (guide 9.3); check your default speaker and mic with wpctl status (guide 9.2),"
[[ $UNDERVOLT == yes ]] && info "      undervolt: ./undervolt.sh install, ./undervolt.sh test, ./undervolt.sh enable"
info "      verify everything: ./check.sh"
