# arch-setup

Move a Windows gaming PC to **Arch Linux with CachyOS's optimised repos and kernels**: Hyprland 0.56 (Lua config, uwsm), btrfs with bootable snapshots (Limine + snapper), zram, sched-ext, Proton gaming and low-latency PipeWire audio.

For desktops with an **AMD or Intel CPU** and **NVIDIA, AMD or Intel graphics**. Everything hardware-specific is a value in [`config.sh`](config.sh) that you fill in **before** installing; each one says how to find it on Windows and on the live USB.

- **Full guide:** [`arch_setup.md`](arch_setup.md), or download [`arch_setup.html`](arch_setup.html) and open it in a browser for copy buttons and progress checkboxes.
- The scripts do exactly what the guide describes, section by section.

## 0. On Windows: collect your values

Download this repo (**Code → Download ZIP**), extract it, open a terminal in the folder and run:

```
powershell -ExecutionPolicy Bypass -File tools\windows-inventory.ps1
```

It reads your CPU, GPU, disks, monitors, time zone and keyboard (changing nothing) and writes `config.suggested.sh`. Review it, then rename it to `config.local.sh` or copy the values into `config.sh`. Guide section 0 explains every value, how to choose a [graphics driver](arch_setup.md#03-choosing-gpu_driver) and a [kernel](arch_setup.md#04-choosing-a-kernel), and how to [bring the config to the live USB](arch_setup.md#06-getting-your-config-onto-the-live-usb).

Then do guide section 1 (backups, peripheral profiles, Memtest86+) and section 2 (BIOS: **Secure Boot off**, UEFI only, ReBAR on).

## 1. Live USB: check the config, then install

Boot the Arch USB, connect to the network (Ethernet, or Wi-Fi with `iwctl`, guide section 3), then:

```bash
curl -L https://github.com/luismateusvargas/arch-setup/archive/refs/heads/main.tar.gz | tar xz
cd arch-setup-main
nano config.sh            # or copy your config.local.sh here
bash check-config.sh      # compares config.sh with this PC; changes nothing
bash install.sh
```

`install.sh` does the following:
1. Runs the same check and stops if `config.sh` doesn't match the CPU, GPU or disks.
2. Finds `INSTALL_DISK_MODEL` and makes you **type its path** before erasing anything.
3. Partitions it, creates the btrfs subvolumes, runs pacstrap and writes the fstab.
4. Runs [`scripts/chroot.sh`](scripts/chroot.sh) inside the new system: locale and users, the CachyOS repos (official script, picks v3/v4/znver4 for your CPU), Limine, your two kernels with the driver for `GPU_DRIVER`, all packages, zram/sysctl and the services. It asks for the root and user passwords, and the CachyOS script asks for a few confirmations.

If the chroot stage stops after partitioning, resolve the error and resume with `arch-chroot /mnt /bin/bash /root/arch-setup/scripts/chroot.sh` from the live USB. Do not rerun `install.sh`: its first stage erases the disk.

## 2. First boot

In the Limine menu choose your kernel. At the `ly` login choose **Hyprland (uwsm-managed)**. Open a terminal with `SUPER+Q` on Hyprland's first-start config (on Wi-Fi, connect with `nmtui` first), then run:

```bash
~/arch-setup/post-install.sh
```

It sets up:
- snapper and the Limine snapshot menu;
- the session environment (NVIDIA variables only with an NVIDIA driver) and `hyprland.lua`, with `MONITORS` matched against the connected monitors and your keyboard layout;
- hypridle, Waybar (CPU sensor and GPU stats picked for your hardware) and the session services;
- PipeWire latency, and hides the graphics card's HDMI audio (`HIDE_GPU_AUDIO`).

Log out (`SUPER+SHIFT+E`) and back in afterwards. To change monitors later, edit `MONITORS` and run `post-install.sh` again.

## 3. Verify

```bash
cd ~/arch-setup
./check.sh                # graphics, ReBAR, monitors, CPU driver, scheduler, zram, snapshots, audio, services
```

## Optional

```bash
./undervolt.sh install    # Ryzen 7 5800X3D only: per-core Curve Optimizer from CO_OFFSETS (guide section 11)
./extras.sh hdd           # wipe HDD_MODEL -> ext4 at /mnt/hdd + Thunar bookmark (typed confirmation)
./extras.sh dev           # Docker + VS Code
```

Corsair (ckb-next), gaming mice (Piper), headset sidetone (HeadsetControl) and Bluetooth are switched on in `config.sh` before installing.

## Machine-specific values stay local

The repo is public, so hardware serial numbers and personal values never go in it:
- **`config.local.sh`** (git-ignored) is read after `config.sh` and overrides it. Keep your own values there, including `HDD_SERIAL`.
- **`config.suggested.sh`** (git-ignored) is the Windows inventory script's output.
- **`SETUP_NOTES.md`** (git-ignored): notes about one specific install.

## Layout

| Path | What |
|---|---|
| `config.sh` | Every setting, with how to find it on Windows and the live USB |
| `check-config.sh` | Validates the config against the hardware (live USB or installed system) |
| `install.sh`, `scripts/chroot.sh` | Stage 1 (live USB) |
| `post-install.sh` | Stage 2 (first boot, as your user) |
| `undervolt.sh` | Optional: 5800X3D Curve Optimizer |
| `check.sh`, `extras.sh` | Verification, optional extras |
| `scripts/hw.sh` | Hardware detection, config validation, per-hardware packages and boot settings |
| `scripts/render.py` | Fills monitors, keyboard and Waybar modules into the configs |
| `files/` | Every config file the scripts install, mirroring where it goes (`etc/`, `home/.config/`, `usr/local/bin/`) |
| `tools/windows-inventory.ps1` | Suggests config values from Windows |
| `tools/build_html.py` | Regenerates `arch_setup.html` from the guide (`pip install markdown`) |
| `tests/` | Disk, hardware-detection and rendering tests (run in CI) |

Install scripts stop at the first error and back up any existing config before replacing it (`*.bak.<timestamp>`). `check.sh` reports all failed checks together.
