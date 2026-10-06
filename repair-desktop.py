#!/usr/bin/env python3
"""Apply the wallpaper and Waybar fixes without replacing local preferences."""

from pathlib import Path
import re


home = Path.home()
hyprland = home / ".config/hypr/hyprland.lua"
waybar = home / ".config/waybar/config.jsonc"

if not hyprland.is_file() or not waybar.is_file():
    raise SystemExit("Hyprland or Waybar config is missing; run post-install.sh first")

hypr_text = hyprland.read_text()
old_wallpaper = 'hl.exec_cmd("sh -c \'sleep 1; awww img ~/Pictures/wallpaper.jpg\'")'
new_wallpaper = (
    'hl.exec_cmd("sh -c \'sleep 1; if [ -f \\"$HOME/Pictures/wallpaper.jpg\\" ]; '
    'then awww img \\"$HOME/Pictures/wallpaper.jpg\\"; '
    'else awww img /usr/share/hypr/wall0.png; fi\'")'
)
if old_wallpaper in hypr_text:
    hypr_text = hypr_text.replace(old_wallpaper, new_wallpaper, 1)
elif new_wallpaper not in hypr_text:
    raise SystemExit("Wallpaper command differs from the installer; edit it manually")

if "disable_splash_rendering" not in hypr_text:
    logo = "        disable_hyprland_logo   = true,"
    if logo not in hypr_text:
        raise SystemExit("Hyprland misc settings differ from the installer; edit them manually")
    hypr_text = hypr_text.replace(
        logo, logo + "\n        disable_splash_rendering = true,", 1
    )

polkit_start = '    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")\n'
if polkit_start not in hypr_text:
    startup = 'hl.on("hyprland.start", function()\n'
    if startup not in hypr_text:
        raise SystemExit("Hyprland startup hook differs from the installer; edit it manually")
    hypr_text = hypr_text.replace(startup, startup + polkit_start, 1)

bar_text = waybar.read_text()
modules = re.search(r'("modules-right"\s*:\s*\[)([^\]]*)(\])', bar_text)
if modules is None:
    raise SystemExit("Could not find Waybar modules-right list")
if '"temperature"' not in modules.group(2):
    new_modules = modules.group(2).replace('"cpu",', '"cpu", "temperature",', 1)
    if new_modules == modules.group(2):
        raise SystemExit("Could not place temperature next to the CPU module")
    bar_text = bar_text[: modules.start(2)] + new_modules + bar_text[modules.end(2) :]

bar_text = bar_text.replace(
    '"hwmon-path-abs": "/sys/devices/pci0000:00/0000:00:18.3"',
    '"hwmon-path-abs": "/sys/devices/pci0000:00/0000:00:18.3/hwmon"',
)
bar_text = bar_text.replace("{temperatureC}ºC", "{temperatureC}°C")

hyprland.write_text(hypr_text)
waybar.write_text(bar_text)
print("Updated Hyprland wallpaper, Polkit startup, and Waybar temperature settings.")
print("Your monitor layout, keyboard layout, and other Waybar settings were preserved.")
