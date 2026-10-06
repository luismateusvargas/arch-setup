# Arch Linux + CachyOS: Gaming & Coding Workstation (moving from Windows)

A desktop for gaming and coding, built from a pure Arch base with CachyOS's optimised repos and kernels: Hyprland 0.56 (Lua config) under uwsm, btrfs with bootable snapshots in the Limine boot menu, zram, the sched-ext `bpfland` scheduler, Proton for Windows games, and low-latency PipeWire audio.

It is written for someone leaving Windows on a **desktop PC** (AMD or Intel CPU; NVIDIA, AMD or Intel graphics). Everything that depends on your hardware is a value in `config.sh`, which you fill in **before** installing; this guide says where to find each one, first on Windows, then on the Arch live USB. Package names were checked against the live Arch and CachyOS repos on 2026-10-06. Hyprland syntax was checked against the 0.56.2 source.

The example values come from the reference build (Ryzen 7 5800X3D, RTX 3070, two 144 Hz monitors). Its full configuration is in the [appendix](#appendix-reference-build).

---

## How this works

The repo <https://github.com/luismateusvargas/arch-setup> automates sections 3–11. This guide explains what each script does, so you can follow or repair any step by hand.

| Script | Where and when | Guide sections |
|---|---|---|
| `tools/windows-inventory.ps1` | Windows, before wiping: suggests your `config.sh` values | 0 |
| `check-config.sh` | Live USB: compares `config.sh` with the real hardware; changes nothing | 0, 3 |
| `install.sh` (+ `scripts/chroot.sh`) | Live USB, as root: **erases the install disk** and installs | 3, 4, 5 |
| `post-install.sh` | First boot, as your user, in a Hyprland terminal | 7, 8, 9 |
| `undervolt.sh install` / `test` / `enable` | Ryzen 7 5800X3D only, optional | 11 |
| `check.sh` | Any time after post-install | 14 |
| `extras.sh hdd` / `dev` | Optional | 13 |

The whole path:

1. **On Windows:** run the inventory script, back up, set up peripheral profiles (sections 0–1).
2. **In the BIOS:** Secure Boot off, UEFI only (section 2).
3. **On the live USB:** get the repo and your config, then `bash check-config.sh` and `bash install.sh` (section 3).
4. **After the first boot:** `~/arch-setup/post-install.sh`, then `./check.sh` (sections 6–14).

What the scripts do on their own:
- **Install disk:** chosen by model name from `config.sh`. Nothing is erased until you type its path a second time.
- **Hardware checks:** `install.sh` refuses to start if `config.sh` doesn't match the CPU, GPU or disks it finds.
- **Monitor ports and the GPU's HDMI audio device:** detected by `post-install.sh`.
- **Existing configs:** backed up (`*.bak.<timestamp>`) before being replaced.

What still needs you: passwords, the CachyOS repo script's confirmations, EasyEffects (9.3) and, for the undervolt, reviewing the `ryzen_smu` PKGBUILD.

---

## 0. Collect your hardware values (on Windows)

### 0.1 Run the inventory script

1. On GitHub, **Code → Download ZIP**, and extract it (e.g. to `Downloads\arch-setup-main`).
2. Open PowerShell in that folder (in Explorer, right-click an empty spot in the folder → **Open in Terminal**) and run:

```
powershell -ExecutionPolicy Bypass -File tools\windows-inventory.ps1
```

It only reads information; it changes nothing and needs no admin rights. It prints what it found and writes **`config.suggested.sh`**: your username and PC name, time zone, languages, keyboard layout, the disk Windows is on, CPU and GPU type, every monitor's name, resolution, refresh rate and position, and guesses for the optional extras.

**Review every value** against the table below. Then either rename the file to `config.local.sh` (it is read after `config.sh` and overrides it), or copy the values into `config.sh`.

### 0.2 Every value, and how to find it

| Value | What it is | On Windows | On the live USB | Example |
|---|---|---|---|---|
| `USERNAME` | Your Linux login: lowercase, no spaces | Pick one | — | `luis` |
| `HOST_NAME` | Computer name | Settings → System → About → *Device name* | — | `MINDEXTENSION` |
| `TIMEZONE` | IANA time zone | Converted by the script | `timedatectl list-timezones \| grep -i <city>` | `America/Sao_Paulo` |
| `LOCALES` | Languages to generate | Settings → Time & language → Language & region (`pt-BR` → `pt_BR.UTF-8`) | `grep UTF-8 /usr/share/i18n/SUPPORTED` | `(en_US.UTF-8 pt_BR.UTF-8)` |
| `LANG_DEFAULT` | System language, one of `LOCALES` | — | — | `en_US.UTF-8` |
| `KEYMAP` | Keyboard in text mode | Settings → Time & language → Typing → Advanced keyboard settings | `localectl list-keymaps`; test with `loadkeys <name>` | `br-abnt2` |
| `KB_LAYOUT`, `KB_VARIANT` | Keyboard on the desktop | Same | — | `br`, `""` (US-International: `us` + `intl`) |
| `MIRROR_COUNTRIES` | Package download servers, nearest first | Your country | `reflector --list-countries` | `BR,US` |
| `INSTALL_DISK_MODEL` | **Disk that is erased** for Arch | PowerShell: `Get-PhysicalDisk \| Format-Table FriendlyName, MediaType, Size` | `lsblk -dno NAME,MODEL,SIZE,TRAN` (MODEL column) | `KINGSTON SNV2S1000G` |
| `CPU_VENDOR` | `amd` or `intel` | Settings → System → About → *Processor* | `grep -m1 'model name' /proc/cpuinfo` | `amd` |
| `GPU_DRIVER` | Graphics driver, see 0.3 | Device Manager → Display adapters | `lspci -nn \| grep -Ei 'vga\|3d\|display'` | `nvidia-open` |
| `KERNEL`, `FALLBACK_KERNEL` | CachyOS kernels, see 0.4 | — | — | `linux-cachyos`, `linux-cachyos-lts` |
| `MONITORS` | One entry per monitor, see 0.5 | Settings → System → Display → Advanced display | After the first boot: `hyprctl monitors all` | see 0.5 |
| `CORSAIR_KEYBOARD`, `GAMING_MOUSE`, `HEADSETCONTROL`, `BLUETOOTH` | Optional extras (section 10) | You use iCUE, G HUB / SteelSeries GG, a USB gaming headset, Bluetooth | — | `yes` / `no` |
| `HIDE_GPU_AUDIO` | Hide the graphics card's HDMI/DP audio output | `no` if you use your monitor's speakers | — | `yes` |
| `UNDERVOLT`, `CO_OFFSETS` | Ryzen 7 5800X3D Curve Optimizer (section 11) | PBO2 Tuner shows your per-core offsets | — | `yes`, `(-27 -29 …)` |
| `HDD_MODEL`, `HDD_SERIAL` | Old SATA drive to wipe for storage (13.1) | `Get-PhysicalDisk \| Format-Table FriendlyName, SerialNumber` | `lsblk -dno NAME,MODEL,SERIAL,TRAN` | keep in `config.local.sh` |

On the live USB, `bash check-config.sh --suggest` prints the CPU, GPU and disk values it detects.

### 0.3 Choosing `GPU_DRIVER`

Use the card your monitors are plugged into.

| Your card | `GPU_DRIVER` | What gets installed |
|---|---|---|
| NVIDIA RTX 20/30/40/50, GTX 16xx | `nvidia-open` | NVIDIA's open kernel modules, prebuilt for both kernels by CachyOS (no compiling on updates) |
| NVIDIA GTX 750/750 Ti, 900, 1000, Titan X/Xp/V, Quadro M/P | `nvidia-580xx` | The 580 driver series, the last that supports these cards (DKMS: rebuilt on each kernel update) |
| NVIDIA GTX 600/700 (Kepler) and older | — | **Not supported.** No current driver works with this Wayland desktop. |
| AMD Radeon R9 285/380, Fury, RX 400 and newer | `amd` | Mesa (RADV Vulkan); the `amdgpu` driver is in the kernel |
| AMD Radeon HD 7000, R7/R9 200 and 300 series (GCN 1/2, e.g. R9 290/390) | `amd` | Same, plus boot parameters that switch these cards from the old `radeon` driver to `amdgpu` (see below) |
| AMD Radeon HD 6000 and older (TeraScale) | — | **Not supported.** Only the old `radeon` driver, which has no Vulkan. |
| Intel Arc, or integrated Intel graphics | `intel` | Mesa (ANV Vulkan) + the VA-API video driver. 4th-gen Core (Haswell) and older have only partial Vulkan: many Proton games won't run. |

If the PC has integrated graphics *and* a graphics card, plug every monitor into the card. `check-config.sh` picks the card over the integrated GPU.

**Older Radeons (GCN 1/2).** Linux has two AMD kernel drivers: `amdgpu`, with Vulkan, and the old `radeon`, without it. Proton runs DirectX 9/10/11 games through Vulkan (DXVK), so without it most modern games won't start. Some kernels, including `linux-cachyos-lts`, still give HD 7000 and R7/R9 200/300 cards (except the R9 285/380) to `radeon` by default. The installer detects these cards and adds `amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0` to the kernel command line:
- **Gains:** Vulkan (Proton, DXVK), the same or better OpenGL (both drivers share Mesa's radeonsi), power profiles, fan and clock control, and full sensor data (the Waybar GPU module needs it).
- **Caveats:** analog outputs (VGA, or DVI-I with a VGA adapter) on HD 7000-era cards and older kernels; these generations get less testing, so rare suspend or display bugs are more likely. To undo: remove the four parameters from `/etc/kernel/cmdline` and run `sudo limine-update`.
- **Limits of the hardware itself:** DirectX 12 games (VKD3D-Proton) need Vulkan features GCN 1/2 partly lacks, so many run poorly or not at all; no ray tracing or mesh shaders. DirectX 9/10/11 games usually run as well as on Windows.

### 0.4 Choosing a kernel

Every CachyOS kernel ships with matching NVIDIA modules. You get two: `KERNEL`, and `FALLBACK_KERNEL` as a second boot-menu entry for the day an update breaks the first.

| Package | What it is | Pick it when |
|---|---|---|
| `linux-cachyos` | EEVDF scheduler, built with LTO + AutoFDO + Propeller | **Default.** Best all-round choice. |
| `linux-cachyos-bore` | BORE scheduler: favours interactive tasks under heavy load | Games stutter while something compiles or encodes |
| `linux-cachyos-eevdf` | Plain EEVDF with the Cachy patches | You want the upstream scheduler |
| `linux-cachyos-bmq` | BMQ scheduler | Experimenting with latency |
| `linux-cachyos-lts` | Long-term-support kernel | **Default fallback**; the most conservative |
| `linux-cachyos-rc` | Release candidate | Very new hardware that needs the newest drivers |
| `linux-cachyos-rt-bore` | Real-time kernel | Audio production; lower throughput for games |
| `linux-cachyos-server` | Throughput-tuned | Not for desktops |
| `linux-cachyos-hardened` | Extra security hardening | Can break some programs and games |
| `linux-cachyos-deckify` | Handheld patches | Steam Deck-style devices |
| `…-lto` suffix | The same kernel built with Clang LTO | Optional, e.g. `linux-cachyos-bore-lto` |

sched-ext (`bpfland`, section 5.7) replaces the CPU scheduler at runtime on any of them, so the kernel choice matters less than it sounds. Very new hardware (released in the last few months) may need `linux-cachyos-rc` as `KERNEL`.

### 0.5 Monitors

One line per monitor; the first is the main one (workspaces 1–2), the second gets workspace 3:

```bash
#          MATCH       MODE             POSITION  SCALE  VRR
MONITORS=("ULTRAWIDE|2560x1080@144|1920x0|1|2" "HDMI-A-1|1920x1080@144|0x0|1|0")
```

- **MATCH:** part of the monitor's name as Windows shows it (Advanced display → *Display information*), e.g. `LG ULTRAWIDE`, `VG27AQ`, or a Linux port name such as `DP-1` or `HDMI-A-1`. Port names only exist on Linux; names work from Windows.
- **MODE:** `WIDTHxHEIGHT@HZ`, or `highrr` (highest refresh rate), or `preferred`.
- **POSITION:** top-left corner in pixels. The leftmost monitor is `0x0`; a monitor to its right starts at the left one's width (`1920x0`). Or `auto`.
- **SCALE:** `1` for 100 %, `1.25`, `1.5`, `2`, as in Windows' *Scale* setting.
- **VRR** (FreeSync/G-Sync): `0` off, `1` always, `2` fullscreen apps only (best on NVIDIA: no desktop flicker). NVIDIA has no VRR over HDMI unless the monitor supports HDMI 2.1 VRR, so use `0` there.

`MONITORS=()` lets Hyprland pick every monitor's preferred mode. You can change monitors any time later: edit `MONITORS` and rerun `post-install.sh`.

### 0.6 Getting your config onto the live USB

The live USB starts from a clean copy of the repo, so your values have to travel with you. Pick one:

- **GitHub fork (easiest):** fork the repo, edit `config.sh` in the browser (pencil icon), and on the live USB download *your fork* in section 3. Never put a disk serial in a public fork.
- **USB stick:** copy the whole `arch-setup-main` folder (with `config.local.sh`) to any FAT32/exFAT stick. On the live USB:
  ```bash
  lsblk                                # find the stick, e.g. /dev/sdb1
  mkdir -p /root/usb && mount /dev/sdb1 /root/usb
  cp -r /root/usb/arch-setup-main /root/ && cd /root/arch-setup-main
  ```
- **Type it in:** note the values (phone photo) and edit `config.sh` with `nano` on the live USB.

Files edited on Windows may have Windows line endings; the scripts convert them automatically.

---

## 1. Before you wipe Windows

1. **Back up** everything on the install disk: Documents, Desktop, Pictures, Downloads, game saves that aren't in the cloud (`Documents\My Games`, `%APPDATA%`, `%LOCALAPPDATA%`), browser data (or turn on browser sync), license keys, and 2FA recovery codes. If `C:` is **BitLocker**-encrypted (the inventory script warns you), Linux can't read it later: copy everything out first.
2. **Check your games:** most Steam games run through Proton, but some anti-cheat systems block Linux. Look yours up on <https://areweanticheatyet.com> and <https://www.protondb.com>.
3. **Peripherals:** save settings to the device itself so they work on Linux immediately:
   - Logitech G HUB: switch the mouse to *On-board memory mode* and save DPI/buttons to it.
   - Corsair iCUE: save lighting and macros to a **hardware/onboard** profile.
   - Write down any software-only EQ or mic settings (G HUB, Blue VO!CE, NVIDIA Broadcast): you'll redo them in EasyEffects (9.3).
4. **Make the USB stick:** download the latest Arch ISO from <https://archlinux.org/download/> and verify its checksum. Write it with Rufus (**DD image mode**) or Ventoy.
5. **Test before wiping:**
   - Boot the Arch USB and pick **Memtest86+** from its menu. One full pass catches bad RAM, the most common cause of random crashes, especially with mixed RAM kits.
   - Optionally boot a CachyOS live USB, which has a desktop, to confirm your monitors, network, audio and peripherals work.
6. Optional: make a Windows install USB with Microsoft's Media Creation Tool, in case you ever want to go back.

> **Tip:** the Arch live USB has no browser. To copy-paste commands from this guide, run `passwd` and `systemctl start sshd` on it, then from another computer on the same network: `ssh root@<address shown by ip a>`.

---

## 2. BIOS settings

Enter the BIOS with Del or F2 at power-on. Menu names vary by board.

| Setting | Value | Why |
|---|---|---|
| **Secure Boot** | **Disabled** | The Arch USB and DKMS-built drivers (580xx NVIDIA, `ryzen_smu`) are unsigned. |
| CSM / Legacy boot | Disabled (UEFI only) | `install.sh` requires UEFI; also needed for ReBAR. |
| Above 4G Decoding / Re-Size BAR | Enabled | Resizable BAR: the CPU can see all of the GPU's memory. Free performance on RTX 30+ and RX 6000+. |
| XMP / EXPO memory profile | Profile 1 | Runs your RAM at its rated speed (Windows didn't change this either). |
| AMD only: CPPC and CPPC Preferred Cores (AMD CBS → NBIO / SMU options) | Enabled or Auto | Needed by the `amd_pstate` CPU frequency driver. |
| Fast Boot | Disabled | Reliable USB keyboard in the boot menu. |

To boot the USB, use the one-time boot menu key (often F8, F11 or F12) and pick the **UEFI** entry for the stick.

---

## 3. Live USB: config, network, install

Boot the USB in UEFI mode.

**Network.** Ethernet works on its own. For Wi-Fi:

```bash
iwctl device list                          # your Wi-Fi device, e.g. wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "<network name>"
ping -c 2 archlinux.org
```

**Get the repo** (or use your USB stick copy, see 0.6). For a fork, replace `luismateusvargas` with your GitHub name:

```bash
curl -L https://github.com/luismateusvargas/arch-setup/archive/refs/heads/main.tar.gz | tar xz
cd arch-setup-main
nano config.sh             # or put your config.local.sh here
bash check-config.sh       # compares config.sh with this PC; changes nothing
bash install.sh            # checks again, then asks before erasing the disk
```

`check-config.sh` lists the detected CPU, GPUs and disks, and every value that's wrong or doesn't match the hardware. `install.sh` runs the same check and stops before touching any disk if it fails.

`install.sh` then:
1. Finds `INSTALL_DISK_MODEL` and makes you **type its path** before erasing anything.
2. Partitions it, creates the btrfs subvolumes, runs pacstrap and writes the fstab (sections 3–4 below).
3. Runs `scripts/chroot.sh` inside the new system (section 5). It asks for the root and user passwords, and the CachyOS script asks for a few confirmations.

If the chroot stage stops after partitioning, fix the reported error and resume with `arch-chroot /mnt /bin/bash /root/arch-setup/scripts/chroot.sh`. **Do not rerun `install.sh`**: it erases the disk again.

### What the disk layout looks like

For reference, these are the commands `install.sh` runs (`DISK` is your install disk, e.g. `/dev/nvme0n1`; partitions are `p1`/`p2` on NVMe and `1`/`2` on SATA):

```bash
blkdiscard -f "$DISK"                         # full TRIM: clean slate for the SSD
sgdisk -Z "$DISK"
sgdisk -n1:0:+4G -t1:ef00 -c1:EFI \
       -n2:0:0   -t2:8304 -c2:ARCH "$DISK"
mkfs.fat -F 32 -n EFI  "${DISK}p1"
mkfs.btrfs -f -L ARCH  "${DISK}p2"
```

The 4 GiB EFI partition (`ESP_SIZE`) holds both kernels, their initramfs images and the snapshot boot entries; `limine-snapper-sync` recommends at least 4 GiB.

btrfs subvolumes. Only `@` gets snapshots; logs, the package cache and Docker stay out of them:

```bash
mount "${DISK}p2" /mnt
for sv in @ @home @log @pkg @docker; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o $OPTS,subvol=@        "${DISK}p2" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,var/lib/docker}
mount -o $OPTS,subvol=@home    "${DISK}p2" /mnt/home
mount -o $OPTS,subvol=@log     "${DISK}p2" /mnt/var/log
mount -o $OPTS,subvol=@pkg     "${DISK}p2" /mnt/var/cache/pacman/pkg
mount -o $OPTS,subvol=@docker  "${DISK}p2" /mnt/var/lib/docker
mount -o fmask=0077,dmask=0077 "${DISK}p1" /mnt/boot
```

No swap partition is needed (zram, section 5.6), and no `discard` option (btrfs enables async discard on SSDs by itself).

---

## 4. Base install

```bash
reflector --country "$MIRROR_COUNTRIES" --protocol https --latest 15 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap -K /mnt base base-devel linux-firmware "$CPU_VENDOR-ucode" btrfs-progs dosfstools efibootmgr \
                 networkmanager sudo git neovim nano man-db man-pages bash-completion \
                 pacman-contrib reflector smartmontools zram-generator python

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*//g' /mnt/etc/fstab   # snapshot restore changes subvolume IDs; mount by name only
```

`amd-ucode` or `intel-ucode` loads CPU microcode fixes at boot. No kernel yet: the CachyOS kernels come in 5.4. The fstab must have 6 entries: `/`, `/home`, `/var/log`, the package cache, Docker and `/boot`.

---

## 5. Inside the chroot

### 5.1 System basics

From `config.sh`: time zone, `LOCALES`, `LANG_DEFAULT`, `KEYMAP` and `HOST_NAME`. Then the root password, your user (`USERNAME`, in the `wheel` group) and its password, and `sudo` for `wheel`.

### 5.2 pacman: multilib + CachyOS repositories

`multilib` is enabled for Steam and 32-bit drivers. Then the official CachyOS script, which:
- detects your CPU's instruction-set level and adds the matching optimised repos: `[cachyos-v3]` (most CPUs since ~2015), `[cachyos-v4]` (AVX-512) or `[cachyos-znver4]` (Ryzen 7000/9000), plus `-core`/`-extra`, all above the Arch repos. `[cachyos]` is added for every CPU;
- imports the CachyOS key, installs the keyring, the mirrorlists and **CachyOS's patched pacman**, and sets `Architecture = auto`.

`check-config.sh` shows your level (`CPU level`). Don't hand-edit these repos into `pacman.conf`: stock pacman refuses the optimised packages.

```bash
grep -E '^\[|^Architecture' /etc/pacman.conf     # verify
```

After the repo change, `chroot.sh` forces a full database refresh (`pacman -Syyu`) once and checks that your `KERNEL` and `FALLBACK_KERNEL` exist, which also catches a typo in `config.sh` before anything else is installed.

### 5.3 Boot chain: Limine + mkinitcpio (installed BEFORE the kernels)

`limine-mkinitcpio-hook` replaces the stock mkinitcpio pacman hook and adds the `sd-btrfs-overlayfs` hook that lets you boot read-only snapshots. pacman only runs hooks that existed when a transaction started, so it is installed in its own transaction, before the kernels.

The kernel command line (`/etc/kernel/cmdline`, used by every Limine entry) and the initramfs depend on your hardware:

| | Always | AMD CPU | Intel CPU | NVIDIA (`nvidia-*`) | AMD / Intel GPU |
|---|---|---|---|---|---|
| cmdline | `root=UUID=… rootflags=subvol=/@ rw quiet nowatchdog zswap.enabled=0` | `amd_pstate=active` | — | `nvidia_drm.modeset=1` | GCN 1/2 Radeons only: `amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0` |
| `MODULES=` | | | | `nvidia nvidia_modeset nvidia_uvm nvidia_drm` (loaded early) | — |
| `HOOKS=` | `base systemd autodetect microcode modconf … keyboard sd-vconsole block filesystems sd-btrfs-overlayfs fsck` | | | without `kms`, so nouveau never loads | with `kms` |

- `zswap.enabled=0`: zram is used instead.
- `amd_pstate=active`: AMD's modern CPU frequency driver (needs CPPC in the BIOS). Intel CPUs use `intel_pstate` by default.
- `nvidia_drm.modeset=1`: already the driver's default; kept as a safety net.

### 5.4 Kernels + graphics driver

Both kernels with their headers (DKMS modules build against them), plus the driver packages for `GPU_DRIVER`:

| `GPU_DRIVER` | Packages |
|---|---|
| `nvidia-open` | `<kernel>-nvidia-open` for both kernels (prebuilt; `nvidia-open-dkms` if a kernel has none), `nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver` |
| `nvidia-580xx` | `nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings egl-wayland libva-nvidia-driver` |
| `amd` | `mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon` |
| `intel` | `mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver` |

Then Limine is installed, registered in the firmware, and copied to the fallback path `EFI/BOOT/BOOTX64.EFI` in case a BIOS update wipes the boot entries. `limine-list` shows an entry for each kernel.

### 5.5 Desktop, audio, gaming, peripherals

The package lists are in `scripts/chroot.sh`:

| Group | What |
|---|---|
| Desktop | Hyprland + portals, uwsm, hyprlock/hypridle, Waybar, swaync (notifications), rofi (app launcher), kitty (terminal), Thunar (files), Firefox, screenshots (grim/slurp), clipboard history, fonts, the `ly` login screen |
| Audio | PipeWire (+ PulseAudio/JACK compatibility), WirePlumber, pavucontrol, EasyEffects with LSP and Calf plugins |
| Gaming | Steam, Lutris, Heroic (Epic/GOG/Amazon), umu-launcher, `proton-cachyos-slr`, GameMode, MangoHud, gamescope, ProtonUp-Qt, winetricks |
| System | sched-ext schedulers, `yay` (AUR helper), DKMS, stress-ng |
| Optional (config.sh) | `ckb-next` (`CORSAIR_KEYBOARD`), `piper libratbag` (`GAMING_MOUSE`), `headsetcontrol` (`HEADSETCONTROL`), `bluez bluez-utils blueman` (`BLUETOOTH`) |

`yay`, Heroic, ProtonUp-Qt and `proton-cachyos-slr` come from the CachyOS repo, so none of them need the AUR.

### 5.6 Memory: zram + sysctl

Compressed swap in RAM instead of a swap partition: [`files/etc/systemd/zram-generator.conf`](files/etc/systemd/zram-generator.conf) (half the RAM, at most 16 GiB, zstd). [`files/etc/sysctl.d/99-workstation.conf`](files/etc/sysctl.d/99-workstation.conf) tunes swapping for zram and caps the dirty page cache so big writes (game patches, compiles) don't cause stalls. Arch already sets `vm.max_map_count = 1048576`, which is enough for Proton.

The NTSYNC driver is loaded at boot so Proton's Windows-synchronisation emulation can use it.

### 5.7 Services, scheduler, mirrors

- sched-ext: [`files/etc/scx_loader.toml`](files/etc/scx_loader.toml) starts `scx_bpfland` in *Gaming* mode.
- reflector refreshes the mirrors weekly using `MIRROR_COUNTRIES`.
- Enabled: NetworkManager, time sync, reflector and paccache timers, `smartd` (disk health), `scx_loader`, the `ly` login screen on tty2, and the optional services (`ckb-next-daemon`, `ratbagd`, `bluetooth`).
- Your user joins the `gamemode` group.

### 5.8 Leave and reboot

`install.sh` offers to unmount and reboot; remove the USB stick when the screen goes dark.

In the Limine menu pick your `KERNEL`. At the `ly` login choose the session **Hyprland (uwsm-managed)**. On first start Hyprland creates a default config where **`SUPER+Q` opens a terminal** (kitty).

---

## 6. First boot: quick checks

**On Wi-Fi?** The live USB's connection doesn't carry over. In the terminal, run `nmtui` → *Activate a connection*.

```bash
uname -r                          # contains "cachyos"
scxctl get                        # bpfland, Gaming
swapon --show                     # /dev/zram0
systemctl --failed                # should be empty
```

Graphics, depending on `GPU_DRIVER`:

```bash
nvidia-smi                                         # NVIDIA: driver version and your card
cat /sys/module/nvidia_drm/parameters/modeset      # NVIDIA: Y
lsmod | grep -E '^(amdgpu|i915|xe) '               # AMD / Intel: driver loaded
```

CPU frequency driver: `cat /sys/devices/system/cpu/amd_pstate/status` → `active` (AMD), or `cat /sys/devices/system/cpu/cpufreq/policy0/scaling_driver` → `intel_pstate` (Intel).

Then run `~/arch-setup/post-install.sh` (sections 7–9).

---

## 7. Bootable snapshots (snapper + Limine)

Every `pacman` transaction takes a pre/post snapshot (`snap-pac`). `limine-snapper-sync` adds each one to the Limine boot menu, so a broken update is one reboot away from being undone. This is the closest thing to Windows' System Restore, and it works when the system doesn't boot.

```bash
sudo pacman -S snapper snap-pac limine-snapper-sync btrfs-assistant
sudo snapper -c root create-config /
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
sudo systemctl enable --now limine-snapper-sync.service snapper-cleanup.timer
sudo snapper -c root create -d "fresh install"
limine-list                                             # a "Snapshots" submenu should now exist
```

**Restore after a bad update:**
1. Reboot and open *Snapshots* in the Limine menu, then boot the last good snapshot. It runs read-only with an overlay.
2. Run `sudo limine-snapper-restore`.
3. Reboot.

`btrfs-assistant` gives you a GUI for the same operations. `/home` is not snapshotted, and snapshots are not backups (section 15).

---

## 8. Hyprland

### 8.1 Session environment (`~/.config/uwsm/env`)

uwsm exports these to the whole session, including user services. Per the Hyprland wiki, environment variables go here, not in `hyprland.lua`.

- Always ([`files/home/.config/uwsm/env`](files/home/.config/uwsm/env)): cursor size, and Wayland first with X11 fallback for Electron, Qt and GTK apps.
- NVIDIA only ([`env-nvidia`](files/home/.config/uwsm/env-nvidia), appended by `post-install.sh`): the NVIDIA VA-API and GLX vendor, the direct NVDEC backend, and keeping NVIDIA's shader cache beyond 1 GB (fewer shader recompiles and stutters).

Do **not** set `SDL_VIDEODRIVER=wayland` globally. It breaks games that bundle older SDL builds.

### 8.2 `~/.config/hypr/hyprland.lua`

The template is [`files/home/.config/hypr/hyprland.lua`](files/home/.config/hypr/hyprland.lua). `post-install.sh` fills in, from `config.sh`:
- **Monitors:** each `MONITORS` entry is matched against `hyprctl monitors all` (by name or port) and written as `hl.monitor(...)` lines, with workspaces 1–2 on the main monitor and 3 on the second. A monitor it can't find is reported and left on automatic settings.
- **Keyboard:** `KB_LAYOUT` and `KB_VARIANT`.
- **ckb-next autostart:** only with `CORSAIR_KEYBOARD=yes`.

Hyprland reports config errors in a banner at the top of the screen. To change monitors later, edit `MONITORS` and rerun `post-install.sh` (it backs up the old file), or edit the generated block in `hyprland.lua` directly.

Keys, for anyone used to Windows (`SUPER` is the Windows key):

| Keys | Action |
|---|---|
| `SUPER+Return` | Terminal |
| `SUPER+D` | App launcher (like the Start menu search) |
| `SUPER+E` | File manager |
| `SUPER+Q` | Close window |
| `SUPER+F` / `SUPER+V` | Fullscreen / toggle floating |
| `SUPER+1…0`, `SUPER+SHIFT+1…0` | Go to workspace / move window to workspace |
| `SUPER+arrows` | Move focus |
| `SUPER+mouse drag` (left / right button) | Move / resize window |
| `SUPER+S` | Scratchpad workspace |
| `SUPER+L` | Lock |
| `SUPER+SHIFT+V` | Clipboard history |
| `Print` / `SHIFT+Print` | Screenshot of a region / the whole screen, to the clipboard |
| `SUPER+SHIFT+E` | Log out |

Notes on tearing and VRR:
- `allow_tearing` is on, and Steam games (plus the example rule for a game outside Steam) opt in with the `immediate` window rule for the lowest input latency. Tearing only happens when the game is fullscreen **and** nothing else is visible on that monitor; `hyprctl monitors` shows `tearingBlockedBy` if it's blocked.
- Inside a monitor's VRR range, VRR handles frame pacing; tearing only matters above the maximum refresh rate. Play on a VRR-capable monitor.
- To add a rule for another game, find its window class with `hyprctl clients` and copy the `black-desert` rule.

### 8.3 Session services, idle, lock, bar

- Waybar, swaync, hypridle and the polkit agent run as systemd user services in the uwsm session.
- [`hypridle.conf`](files/home/.config/hypr/hypridle.conf): lock after 10 minutes, screen off after 15; never while something is fullscreen.
- **Waybar** ([`config.jsonc`](files/home/.config/waybar/config.jsonc), [`style.css`](files/home/.config/waybar/style.css)): floating pills in the Hyprland colours. `post-install.sh` adapts it to your hardware:

| Module | Shows | Hardware |
|---|---|---|
| `cpu`, `memory`, `pulseaudio`, `network` | Load and clock, RAM, volume, IP or Wi-Fi network | All |
| `temperature` | CPU temperature | Sensor found automatically (`k10temp` on AMD, `coretemp` on Intel) |
| `custom/gpu` | GPU load, VRAM, temperature; clocks in the tooltip | NVIDIA (one resident `nvidia-smi`) and AMD (sysfs); not on Intel |
| `custom/cpu_voltage` | Core voltage | `UNDERVOLT=yes` (Ryzen 5000 via `ryzen_smu`) |

CPU load, temperature and GPU temperature turn amber, then red, when busy or hot. The GPU stats come from one background service (`gpu-stats.service`) shared by every monitor's bar.

The bundled Hyprland wallpaper is used until you put an image at `~/Pictures/wallpaper.jpg`.

---

## 9. Audio: PipeWire

### 9.1 Lower latency, fewer resampling cases

[`10-latency.conf`](files/home/.config/pipewire/pipewire.conf.d/10-latency.conf): the default quantum drops from 1024/48000 (about 21 ms) to 512 (about 10.7 ms). Apps that ask for less, such as games and voice chat, can go down to 64. `allowed-rates` lets 44.1 kHz music play without resampling when the hardware supports it.

### 9.2 WirePlumber rules

With `HIDE_GPU_AUDIO=yes`, `post-install.sh` hides the HDMI/DP audio output of NVIDIA and AMD graphics cards, so a monitor without speakers can't become the default output. (Intel's HDMI audio shares the motherboard's audio device and can't be hidden separately.) Set `HIDE_GPU_AUDIO=no` and rerun `post-install.sh` if you use your monitor's speakers.

```bash
wpctl status                            # sinks (outputs) and sources (inputs); * marks the defaults
wpctl set-default <id>                  # change the default output or input
pw-metadata -n settings | grep quantum  # 512
```

### 9.3 EasyEffects: mic processing and EQ

EasyEffects replaces G HUB's EQ, Blue VO!CE and NVIDIA Broadcast:
1. Under **Input** (the mic), add in order: **Noise Reduction** (RNNoise: keyboard and fan noise), **Gate**, **Compressor**, **Limiter**.
2. Under **Output**, add an **Equalizer** and re-enter your EQ, or import an AutoEq preset for your headphones.
3. In EasyEffects' settings, enable **Launch at startup**. uwsm handles XDG autostart.

Windows-only virtual surround (DTS:X, Dolby Atmos for Headphones) has no Linux equivalent.

### 9.4 Headset sidetone and Discord

With `HEADSETCONTROL=yes`, `headsetcontrol` controls sidetone, battery and lights on supported USB/wireless gaming headsets (list: <https://github.com/Sapd/HeadsetControl#supported-headsets>). It doesn't work through 3.5 mm jacks.

```bash
headsetcontrol -s 64      # sidetone 0–128
headsetcontrol -?         # features of your headset
```

If Discord crackles, it's asking for too small a buffer. [`files/optional/20-discord.conf`](files/optional/20-discord.conf) raises its minimum:

```bash
mkdir -p ~/.config/pipewire/pipewire-pulse.conf.d
cp ~/arch-setup/files/optional/20-discord.conf ~/.config/pipewire/pipewire-pulse.conf.d/
systemctl --user restart pipewire-pulse
```

---

## 10. Mouse & keyboard

- **Gaming mice** (`GAMING_MOUSE=yes`): open **Piper** for DPI steps, report rate, buttons and onboard profiles (`ratbagd` is enabled). Supported devices: <https://github.com/libratbag/libratbag/tree/master/data/devices>. A mouse whose profile is saved on-board (section 1) works the same without Piper.
- **Corsair keyboards and mice** (`CORSAIR_KEYBOARD=yes`): **ckb-next** for lighting, macros and hardware profiles. Its daemon is enabled and the tray app starts with Hyprland.
- Mouse acceleration is off (`accel_profile = "flat"`), like most games expect.

---

## 11. Per-core Curve Optimizer (Ryzen 7 5800X3D only)

Some boards don't expose Curve Optimizer for the 5800X3D in the BIOS. These scripts write the per-core offsets at runtime to the CPU's SMU through the `ryzen_smu` kernel driver, as PBO2 Tuner does on Windows. **Only the 5800X3D is supported**: the scripts refuse any other CPU. Offsets reset on every power cycle; a boot service and a resume service re-apply them.

1. In `config.sh`: `UNDERVOLT=yes` and `CO_OFFSETS` with one value per core (-30 to 0, core 0 first), e.g. the ones PBO2 Tuner uses on Windows.
2. `./undervolt.sh install`: builds `ryzen_smu-dkms-git` from the AUR, writes your offsets into `/usr/local/bin/pbo-curve` and installs the services (not enabled). **Read the PKGBUILD** `yay` shows you: its source must be `github.com/amkillam/ryzen_smu` only.
3. `./undervolt.sh test`: applies the offsets once and reads them back. A reboot clears them.
4. Stability check:
   - **Full load:** `stress-ng --cpu 16 --cpu-method all --timeout 20m`.
   - **Light and idle use:** use the PC normally for a day. Curve Optimizer instability usually shows at light load, not under stress.
   - **Hardware errors:** `journalctl -k | grep -iE 'mce|hardware error'`. Any hit means one core is too aggressive: move it 2–3 steps toward 0, rerun `undervolt.sh install`, test again.
5. `./undervolt.sh enable`: applies them at every boot and after resume. `./undervolt.sh disable` and a reboot return to stock.

`ryzenadj` can't do this: it doesn't support desktop Ryzen 5000 CPUs and has no per-core CO for them.

---

## 12. Gaming

### 12.1 Steam

In Steam, **Settings → Compatibility**: enable Steam Play for all titles and select **proton-cachyos-slr** as the default (installed system-wide from the CachyOS repo). If a game misbehaves, try another Proton version in the game's *Properties → Compatibility*, and check its ProtonDB page.

Per-game launch options:

```
gamemoderun %command%
mangohud gamemoderun %command%          # with the FPS / frametime overlay
```

If a game misbehaves on Wayland, run it through gamescope at your monitor's resolution and refresh rate:

```
gamescope -W 2560 -H 1440 -r 165 -f -- gamemoderun %command%
```

### 12.2 Other launchers

- **Epic, GOG, Amazon:** Heroic Games Launcher.
- **Battle.net, EA app, Ubisoft Connect, standalone launchers:** Lutris, with a GE-Proton runner (download runners in ProtonUp-Qt).
- For low-latency tearing in a game outside Steam, find its class with `hyprctl clients` and add a window rule like the `black-desert` example in `hyprland.lua`.

---

## 13. Optional

### 13.1 Old HDD as a bulk/backup disk

An old internal SATA drive can hold bulk files or a second copy of backups. `extras.sh hdd` **erases** it, creates ext4, mounts it at `/mnt/hdd` and adds a Thunar bookmark.

1. Set `HDD_MODEL` and `HDD_SERIAL` (`lsblk -dno NAME,MODEL,SERIAL,TRAN`) in `config.local.sh`. Keep the serial out of public repos.
2. Copy anything you want to keep off the drive. If the file manager mounted it, unmount it (`findmnt` shows where).
3. Run:

```bash
cd ~/arch-setup && ./extras.sh hdd
```

The script checks the SATA connection, model and serial, shows the drive's power-on hours from SMART, and asks you to type the disk path before erasing it. It adds the new filesystem to `/etc/fstab` by UUID and verifies the mount. `smartd` (5.7) watches its health.

### 13.2 Development stack

```bash
./extras.sh dev       # Docker (+ compose, buildx), and VS Code (OSS build, or Microsoft's from the AUR)
```

Joining the `docker` group gives root-equivalent access; log out and back in to use it. Docker's data lives on the `@docker` subvolume, so it stays out of system snapshots.

### 13.3 Bluetooth

With `BLUETOOTH=yes`, BlueZ and the Blueman tray app are installed and `bluetooth.service` is enabled: pair controllers and headphones from Blueman (or `bluetoothctl`). To add it later, set `BLUETOOTH=yes`, then `sudo pacman -S bluez bluez-utils blueman && sudo systemctl enable --now bluetooth`.

---

## 14. Final verification checklist

`./check.sh` runs these checks for your configuration and reports every failure together:

| Check | Expected |
|---|---|
| Graphics | NVIDIA: driver loaded, `nvidia_drm` modeset `Y`, **ReBAR** (BAR1 covers all VRAM). AMD: `amdgpu` + RADV. Intel: `i915`/`xe` + ANV. |
| Monitors | Every `MONITORS` entry with a refresh rate runs at that resolution and rate |
| CPU driver | `amd_pstate` `active` (AMD) or `intel_pstate` (Intel) |
| Scheduler, zram, NTSYNC | bpfland; `zram0` in use; `/dev/ntsync` present |
| Curve Optimizer | Offsets applied (`UNDERVOLT=yes` only) |
| Kernel and boot | A CachyOS kernel is running; snapshots in the Limine menu; `FALLBACK_KERNEL` entry present |
| Audio | Quantum 512; a default speaker and microphone set |
| Services, network | No failed units; network connected |

If ReBAR shows as off, enable *Above 4G Decoding* and *Re-Size BAR* in the BIOS (section 2). If `amd_pstate` is missing, enable CPPC in the BIOS.

---

## 15. Maintenance & recovery

- **Updates:** `yay` (or `sudo pacman -Syu`), about once a week. Read <https://archlinux.org/news/> before big updates; `yay -Pw` shows unread news. `snap-pac` snapshots every transaction automatically.
- **AUR:** only `ryzen_smu-dkms-git` (undervolt) and optionally VS Code. Review PKGBUILD diffs on every update.
- **Broken boot after an update:**
  1. In the Limine menu, boot your `FALLBACK_KERNEL` first.
  2. If that also fails, boot a snapshot, then run `sudo limine-snapper-restore`.
- **Limine boot entry gone** (e.g. after a BIOS update): the fallback at `EFI/BOOT/BOOTX64.EFI` still boots. Afterwards, run `sudo limine-install` to recreate the entry.
- **Changing kernel later:** `sudo pacman -S linux-cachyos-bore linux-cachyos-bore-headers` (+ `linux-cachyos-bore-nvidia-open` with `nvidia-open`); Limine adds the entry automatically.
- **Mirrors:** `reflector.timer` refreshes them weekly. **Package cache:** `paccache.timer` keeps the last 3 versions.
- **Kernel parameters:** edit `/etc/kernel/cmdline`, then run `sudo limine-update`.
- **Backups:** snapshots protect the system, not your files. Copy `/home` to another disk or a cloud service regularly.

---

## Appendix: reference build

The machine this guide was first written for, as an example of filled-in values.

| Part | Detail | Notes |
|---|---|---|
| CPU | Ryzen 7 5800X3D (Zen 3) | `x86-64-v3` repos; Curve Optimizer via section 11 |
| Board | Gigabyte B450M DS3H V2 | No Curve Optimizer in its BIOS |
| RAM | 4×8 GB DDR4-3200, mixed kits | Memtest before installing |
| GPU | RTX 3070 (GA104), ReBAR on | `nvidia-open` |
| Install disk | Kingston NV2 1 TB | btrfs + zstd |
| Monitors | LG UltraWide 2560×1080 @ 144 Hz (DisplayPort); SuperFrame Ace 27" 1920×1080 @ 144 Hz (HDMI) | VRR on the DisplayPort monitor only |
| Peripherals | Logitech G502 HERO, Corsair K95 RGB Platinum, Logitech G PRO X (3.5 mm) | Piper, ckb-next |
| Network | Realtek RTL8111 Gigabit, wired | In-kernel `r8169` |

Its `config.local.sh` (disk serial omitted):

```bash
USERNAME=htxzz77
HOST_NAME=MINDEXTENSION
TIMEZONE=America/Sao_Paulo
LOCALES=(en_US.UTF-8 pt_BR.UTF-8)
LANG_DEFAULT=en_US.UTF-8
KEYMAP=br-abnt2
KB_LAYOUT=br
MIRROR_COUNTRIES=BR,US
INSTALL_DISK_MODEL="KINGSTON SNV2S1000G"
CPU_VENDOR=amd
GPU_DRIVER=nvidia-open
KERNEL=linux-cachyos
FALLBACK_KERNEL=linux-cachyos-lts
MONITORS=("ULTRAWIDE|2560x1080@144|1920x0|1|2" "HDMI-A-1|1920x1080@144|0x0|1|0")
CORSAIR_KEYBOARD=yes
GAMING_MOUSE=yes
HEADSETCONTROL=yes
UNDERVOLT=yes
CO_OFFSETS=(-27 -29 -29 -30 -28 -30 -27 -28)
```

---

## Sources

- CachyOS: optimised repos <https://wiki.cachyos.org/features/optimized_repos/>, the official `cachyos-repo.sh`, kernel variants <https://wiki.cachyos.org/features/kernel/>
- Arch Wiki: [Installation guide](https://wiki.archlinux.org/title/Installation_guide), [iwd](https://wiki.archlinux.org/title/Iwd), [NVIDIA](https://wiki.archlinux.org/title/NVIDIA), [AMDGPU](https://wiki.archlinux.org/title/AMDGPU), [Intel graphics](https://wiki.archlinux.org/title/Intel_graphics), [Limine](https://wiki.archlinux.org/title/Limine), [PipeWire](https://wiki.archlinux.org/title/PipeWire), [Zram](https://wiki.archlinux.org/title/Zram)
- Arch news: [NVIDIA 590 drops Maxwell/Pascal/Volta and switches to open modules](https://archlinux.org/news/), [AUR malicious packages incident](https://archlinux.org/news/)
- Hyprland 0.56.2 source and wiki (Tearing, UWSM, Monitors, Environment variables): <https://github.com/hyprwm/Hyprland>, <https://github.com/hyprwm/hyprland-wiki>
- Limine tooling: <https://gitlab.com/Zesko/limine-entry-tool>, <https://gitlab.com/Zesko/limine-snapper-sync>
- sched-ext loader: <https://github.com/sched-ext/scx-loader>
- ly: <https://codeberg.org/fairyglade/ly>
- Linux game compatibility: <https://www.protondb.com>, <https://areweanticheatyet.com>
- 5800X3D undervolting on Linux: <https://github.com/svenlange2/Ryzen-5800x3d-linux-undervolting>, driver <https://github.com/amkillam/ryzen_smu>
- HeadsetControl: <https://github.com/Sapd/HeadsetControl>; libratbag/Piper: <https://github.com/libratbag/libratbag>
