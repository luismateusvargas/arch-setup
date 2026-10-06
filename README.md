# arch-setup

Arch Linux install for **MINDEXTENSION**: Ryzen 7 5800X3D, RTX 3070, 32 GB, Kingston NV2, LG UltraWide + SuperFrame Ace 27.

Pure Arch with the CachyOS `x86-64-v3` repos and `linux-cachyos` kernel, NVIDIA open modules, Hyprland 0.56 (Lua config, uwsm), btrfs with bootable snapshots (Limine + snapper), zram, sched-ext, PipeWire tuning, and a per-core Curve Optimizer service.

- **Full guide:** [`arch_setup.md`](arch_setup.md), or download [`arch_setup.html`](arch_setup.html) and open it in a browser for copy buttons and progress checkboxes.
- The scripts do exactly what the guide describes, section by section.

## Before you start

Do section 1 (backups, onboard profiles, Memtest86+) and section 2 (BIOS: **Secure Boot off**, CPPC on) of the guide first.

## 1. Live ISO: wipe the NVMe and install

Boot the Arch ISO with Ethernet plugged in, then:

```bash
curl -L https://github.com/luismateusvargas/arch-setup/archive/refs/heads/main.tar.gz | tar xz
cd arch-setup-main
nano config.sh          # username, timezone, keymap, mirror countries
bash install.sh
```

`install.sh` does the following:
1. Finds the Kingston NVMe by model and makes you **type its path** before erasing anything.
2. Partitions it, creates the btrfs subvolumes, runs pacstrap and writes the fstab.
3. Runs [`scripts/chroot.sh`](scripts/chroot.sh) inside the new system. That sets up locale and users, adds the CachyOS repos via their official script, installs Limine, both kernels with NVIDIA, all packages, zram/sysctl and the services. It asks for the root and user passwords, and the CachyOS script asks for a few confirmations.

After the CachyOS repo change, `chroot.sh` forces a one-time package database refresh. If the chroot stage stops after partitioning, resolve the package error and resume with `arch-chroot /mnt /bin/bash /root/arch-setup/scripts/chroot.sh` from the live ISO. Do not rerun `install.sh`: its first stage erases the NVMe.

## 2. First boot

In the Limine menu choose **linux-cachyos**. At the `ly` login choose **Hyprland (uwsm-managed)**. Open a terminal with `SUPER+Q` on Hyprland's first-start config, then run:

```bash
~/arch-setup/post-install.sh
```

It sets up:
- snapper and the Limine snapshot menu;
- the uwsm environment and `hyprland.lua` (it detects the LG's DisplayPort name);
- hypridle, waybar and the session services;
- PipeWire latency and the WirePlumber rules (it detects the GPU's HDMI audio device).

Log out (`SUPER+SHIFT+E`) and back in afterwards.

## 3. Undervolt (Curve Optimizer)

```bash
cd ~/arch-setup
./undervolt.sh install    # ryzen_smu from the AUR (review the PKGBUILD) + pbo-curve + units
./undervolt.sh test       # apply once; a reboot clears it
./undervolt.sh enable     # only after the stability check it prints
```

Offsets live in [`files/usr/local/bin/pbo-curve`](files/usr/local/bin/pbo-curve).

## 4. Verify

```bash
./check.sh                # NVIDIA, ReBAR, monitors, amd_pstate, scheduler, zram, snapshots, audio, services
```

## Optional

```bash
./extras.sh hdd           # old Samsung HDD -> ext4 at /mnt/hdd + Thunar bookmark (erases it, typed confirmation)
./extras.sh dev           # Docker + VS Code
```

## Machine-specific values

Hardware serial numbers and disk UUIDs are never committed (the repo is public). Add them locally before running the steps that need them.

**`HDD_SERIAL`** in `config.sh`: needed only by `./extras.sh hdd`, which refuses to run without it. It makes sure the disk being erased is the exact internal HDD, not a same-model USB disk. Find the serial and add the line below `HDD_MODEL`:

```bash
lsblk -dno NAME,MODEL,SERIAL,TRAN      # use the SERIAL of the sata disk matching HDD_MODEL
```

```bash
HDD_SERIAL="<serial from lsblk>"           # exact internal SATA HDD; protects against a same-model USB disk
```

**`SETUP_NOTES.md`**: notes about this specific install (interruptions, fixes, disk serials and UUIDs). It is listed in `.gitignore`, so keep your own copy next to the scripts.

**Waybar hardware metrics** (installed by `post-install.sh`) assume an NVIDIA GPU and a Ryzen 5000 (Zen 3) CPU:
- `custom/gpu`: [`gpu-stats.service`](files/home/.config/systemd/user/gpu-stats.service) runs one resident `nvidia-smi` for every bar (one bar per monitor) and writes `$XDG_RUNTIME_DIR/waybar-gpu.json`, which each bar reads every 2 s. Shows load, VRAM and temperature; clocks are in the tooltip.
- `custom/cpu_voltage`: [`cpu_voltage.sh`](files/home/.config/waybar/scripts/cpu_voltage.sh) reads the core voltage from the `ryzen_smu` PM table (installed by `undervolt.sh install`). The offset is for PM table version `0x380905`; check yours with `od -An -tx4 /sys/kernel/ryzen_smu_drv/pm_table_version` after a BIOS update or on other CPUs.

On other hardware, remove those two modules from `modules-right` in [`config.jsonc`](files/home/.config/waybar/config.jsonc).

## Layout

| Path | What |
|---|---|
| `config.sh` | Username, host, timezone, keymap, disk models, monitor match |
| `install.sh`, `scripts/chroot.sh` | Stage 1 (live ISO) |
| `post-install.sh` | Stage 2 (first boot, as your user) |
| `undervolt.sh` | Stage 3 (Curve Optimizer) |
| `check.sh`, `extras.sh` | Verification, optional extras |
| `files/` | Every config file the scripts install, mirroring where it goes (`etc/`, `home/.config/`, `usr/local/bin/`) |
| `tools/build_html.py` | Regenerates `arch_setup.html` from the guide (`pip install markdown`) |

Install scripts stop at the first error and back up any existing config before replacing it (`*.bak.<timestamp>`). `check.sh` reports all failed checks together.
