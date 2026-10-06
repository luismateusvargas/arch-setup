"""Rendering of the hardware-dependent desktop configs (scripts/render.py)."""

import importlib.machinery
import json
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("render", str(ROOT / "scripts/render.py"))
render = types.ModuleType(LOADER.name)
LOADER.exec_module(render)

HYPR = (ROOT / "files/home/.config/hypr/hyprland.lua").read_text()
BAR = (ROOT / "files/home/.config/waybar/config.jsonc").read_text()
CONNECTED = [
    {"name": "DP-1", "description": "LG Electronics LG ULTRAWIDE 0x01010101", "make": "LG Electronics", "model": "LG ULTRAWIDE"},
    {"name": "HDMI-A-1", "description": "DHI ACE27FSIFD1B", "make": "DHI", "model": "ACE27FSIFD1B"},
]


class HyprlandTests(unittest.TestCase):
    def env(self, monitors, connected=CONNECTED, **extra):
        return {"MONITORS": "\n".join(monitors), "MONITORS_JSON": json.dumps(connected),
                "KB_LAYOUT": "br", "KB_VARIANT": "", **extra}

    def test_names_and_ports_resolve_to_main_and_side(self):
        out = render.render_hyprland(HYPR, self.env(
            ["ULTRAWIDE|2560x1080@144|1920x0|1|2", "HDMI-A-1|1920x1080@144|0x0|1|0"]))
        self.assertIn('local MAIN = "DP-1"', out)
        self.assertIn('local SIDE = "HDMI-A-1"', out)
        self.assertIn('hl.monitor({ output = MAIN, mode = "2560x1080@144", position = "1920x0", scale = 1, vrr = 2 })', out)
        self.assertIn('workspace = "3", monitor = SIDE', out)
        self.assertIn('kb_layout          = "br"', out)

    def test_unknown_monitor_is_skipped_and_fallback_kept(self):
        out = render.render_hyprland(HYPR, self.env(["SAMSUNG|highrr|auto|auto|0"]))
        self.assertNotIn("local MAIN", out)
        self.assertIn(render.FALLBACK, out)

    def test_ports_trusted_outside_hyprland(self):
        out = render.render_hyprland(HYPR, self.env(["DP-2|highrr|auto|1.5|0"], connected=[]))
        self.assertIn('local MAIN = "DP-2"', out)
        self.assertIn("scale = 1.5", out)

    def test_ckb_next_only_with_corsair(self):
        self.assertNotIn("ckb-next", render.render_hyprland(HYPR, self.env([])))
        self.assertIn("ckb-next", render.render_hyprland(HYPR, self.env([], CORSAIR_KEYBOARD="yes")))


class WaybarTests(unittest.TestCase):
    def modules(self, text):
        return json.loads(text)["modules-right"]

    def test_reference_build_keeps_everything(self):
        out = render.render_waybar(BAR, {"CPU_HWMON": "/sys/x/hwmon", "GPU_DRIVER": "nvidia-open", "UNDERVOLT": "yes"})
        self.assertIn("custom/gpu", self.modules(out))
        self.assertIn("custom/cpu_voltage", self.modules(out))
        self.assertEqual(json.loads(out)["temperature"]["hwmon-path-abs"], "/sys/x/hwmon")

    def test_intel_without_sensor_drops_modules(self):
        out = render.render_waybar(BAR, {"CPU_HWMON": "", "GPU_DRIVER": "intel", "UNDERVOLT": "no"})
        data = json.loads(out)
        for name in ("custom/gpu", "custom/cpu_voltage", "temperature"):
            self.assertNotIn(name, data["modules-right"])
            self.assertNotIn(name, data)


if __name__ == "__main__":
    unittest.main()
