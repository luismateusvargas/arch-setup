# Arch Linux: Gaming & Coding Workstation — MINDEXTENSION

Pure Arch base + CachyOS `x86-64-v3` repos, `linux-cachyos` kernel, NVIDIA open modules, Hyprland 0.56 (Lua config) under uwsm, btrfs with bootable snapper snapshots (Limine), zram, sched-ext, per-core Curve Optimizer via a systemd service.

**Everything here was checked against the live repos on 2026-10-01:** Arch `core/extra/multilib`, CachyOS `cachyos`, `cachyos-v3`, `cachyos-core-v3`, `cachyos-extra-v3`, and the AUR. Hyprland syntax was checked against the 0.56.2 source code.

---

## Scripted install

The repo <https://github.com/luismateusvargas/arch-setup> automates sections 3–11. Do sections 1 and 2 by hand first. The rest of this guide is the reference for what each script does.

| Script | When | Guide sections |
|---|---|---|
| `install.sh` (+ `scripts/chroot.sh`) | Live ISO, as root | 3, 4, 5 |
| `post-install.sh` | First boot, as your user, in a Hyprland terminal | 7, 8, 9 |
| `undervolt.sh install` / `test` / `enable` | After post-install; enable only after the stability check | 11 |
| `check.sh` | Any time | 14 |
| `extras.sh hdd` / `dev` | Optional | 13 |

On the live ISO:

```bash
curl -L https://github.com/luismateusvargas/arch-setup/archive/refs/heads/main.tar.gz | tar xz
cd arch-setup-main
nano config.sh          # username, timezone, keymap, mirror countries
bash install.sh
```

After the first boot, in Hyprland:

```bash
~/arch-setup/post-install.sh
cd ~/arch-setup && ./undervolt.sh install && ./undervolt.sh test
./undervolt.sh enable   # after the stability check
./check.sh
```

What the scripts do on their own:
- **Install disk:** picked by model. You must type its path before anything is erased.
- **LG port and GPU audio device:** detected automatically by `post-install.sh`.
- **Existing configs:** backed up before being replaced.

What still needs you: passwords, the CachyOS script's confirmations, reviewing the `ryzen_smu` PKGBUILD, and EasyEffects (9.3).

---

## 0. Hardware (from HWiNFO, 2026-10-01)

| Part | Detail | Linux notes |
|---|---|---|
| CPU | Ryzen 7 5800X3D (Zen 3, AVX2/FMA/BMI2, no AVX-512) | `x86-64-v3` repos. Not v4/znver4. |
| Board | Gigabyte B450M DS3H V2, BIOS F67d | No Curve Optimizer in BIOS → section 11. |
| RAM | 4×8 GB DDR4-3200, **mixed kits** (2× Crucial BL8G32C16U4B, 2× JUHOR) | Run memtest once (section 1). |
| GPU | RTX 3070 LHR (GA104), ReBAR **already enabled** (8 GB) | `nvidia-open` modules (driver 615.x). |
| NVMe | Kingston NV2 1 TB (SNV2S1000G), health 98 % | Install target. btrfs + zstd. |
| HDD | Samsung HD502HJ 500 GB, ~49 000 power-on hours | Optional bulk/backup disk only (section 13). |
| Monitor 1 | LG UltraWide (GSM76FE) 2560×1080 @ 144 Hz, **DisplayPort** (its only DP input) | VRR 50–144 Hz. |
| Monitor 2 | SuperFrame Ace 27" (SF-MN-ACE27FSIFD1B) 1920×1080 @ 144 Hz IPS, **HDMI** | Panel range 48–144 Hz. No VRR over HDMI on NVIDIA unless the monitor supports HDMI 2.1 VRR, so it's left off here. |
| Audio | Realtek ALC897 (onboard), NVIDIA HDMI/DP audio | In-kernel. |
| Headset | Logitech G PRO X, wired, through its USB DAC | UAC device + HeadsetControl (sidetone). |
| Mouse | Logitech G502 HERO | `piper` / `libratbag`. |
| Keyboard | Corsair K95 RGB Platinum | `ckb-next`. |
| Network | Realtek RTL8168/8111 Gigabit (wired only, no Wi-Fi/Bluetooth) | In-kernel `r8169`. |

---

## 1. Before you wipe Windows

1. **Back up** everything on `C:` you care about, plus `D:` (the HDD) if you will format it. Also back up `Documents\Black Desert\` (UI layout, settings).
2. **G HUB**: switch the G502 to *On-board memory mode* and save your DPI/buttons to the mouse. It then works identically on Linux even before `piper` is set up.
3. **iCUE**: save lighting and macros to the K95's **hardware/onboard** profile.
4. Write down the G HUB EQ settings for the PRO X. They are software-only and you'll redo them in EasyEffects.
5. Download the latest Arch ISO from <https://archlinux.org/download/> and verify its checksum. Write it with Rufus (**DD mode**) or Ventoy.
6. **Test before wiping:**
   - Boot the Arch ISO and pick **Memtest86+** from its boot menu. Do one full pass; the mixed RAM kits are the most likely source of random crashes.
   - Optionally boot a CachyOS live ISO, which has a desktop, to confirm both monitors at 144 Hz, Ethernet, audio and peripherals.
7. Optional: make a Windows 11 install USB with Microsoft's Media Creation Tool, in case you ever want to go back.

> **Tip for the install:** the Arch ISO has no browser. To copy-paste commands from this file, run `passwd` and `systemctl start sshd` on the ISO, then from a phone or laptop on the same network: `ssh root@<ip-shown-by-ip-a>`.

---

## 2. BIOS settings (F67d)

Menu names vary slightly between BIOS versions.

| Setting | Value | Why |
|---|---|---|
| Boot → **Secure Boot** | **Disabled** | Currently *Enabled*. The Arch ISO and the unsigned DKMS module (`ryzen_smu`) need it off. |
| Boot → CSM Support | Disabled | Required for ReBAR (already the case). |
| Settings → IO Ports → Above 4G Decoding / Re-Size BAR | Enabled / Auto | **Already on** (HWiNFO: ReBAR enabled, 8 GB). Leave it. |
| Tweaker → Extreme Memory Profile (XMP) | Profile 1 | Already running DDR4-3200. |
| Settings → AMD CBS → NBIO Common Options → SMU Common Options → **CPPC** / **CPPC Preferred Cores** | Enabled | Required by `amd_pstate`. |
| Boot → Fast Boot | Disabled | Reliable USB keyboard in the Limine menu. |

---

## 3. Live USB: disks

Boot the Arch ISO in UEFI mode, with Ethernet plugged in.

```bash
cat /sys/firmware/efi/fw_platform_size        # must print 64
ping -c 2 archlinux.org
timedatectl set-ntp true
lsblk -o NAME,MODEL,SIZE,TYPE                 # NVMe = KINGSTON SNV2S1000G (expected /dev/nvme0n1)
```

**Destructive from here on.** Set `DISK` to the Kingston NVMe shown by `lsblk`:

```bash
DISK=/dev/nvme0n1

blkdiscard -f "$DISK"                         # full TRIM: clean slate for the DRAM-less NV2
sgdisk -Z "$DISK"
sgdisk -n1:0:+4G -t1:ef00 -c1:EFI \
       -n2:0:0   -t2:8304 -c2:ARCH "$DISK"

mkfs.fat -F 32 -n EFI  "${DISK}p1"
mkfs.btrfs -f -L ARCH  "${DISK}p2"
```

The 4 GiB ESP holds both kernels, the NVIDIA initramfs images and the snapshot boot entries. `limine-snapper-sync` recommends at least 4 GiB.

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

Notes:
- No swap partition is needed; zram is configured in section 5.6.
- No `discard` mount option is needed: btrfs enables async discard on NVMe automatically.

---

## 4. Base install

```bash
reflector --country BR,US --protocol https --latest 15 --sort rate --save /etc/pacman.d/mirrorlist   # adjust countries

pacstrap -K /mnt base base-devel linux-firmware amd-ucode btrfs-progs dosfstools efibootmgr \
                 networkmanager sudo git neovim nano man-db man-pages bash-completion \
                 pacman-contrib reflector smartmontools zram-generator python

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*//g' /mnt/etc/fstab   # snapshot restore changes subvolume IDs; mount by name only
cat /mnt/etc/fstab                               # sanity check: 6 entries (/, /home, /var/log, pkg, docker, /boot)

arch-chroot /mnt
```

---

## 5. Inside the chroot

### 5.1 System basics

Adjust the timezone, keymap and username below. For a Brazilian ABNT2 keyboard use `KEYMAP=br-abnt2` (and `kb_layout = "br"` in section 8.2).

```bash
USERNAME=luis

ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc
sed -i -e 's/^#en_US.UTF-8/en_US.UTF-8/' -e 's/^#pt_BR.UTF-8/pt_BR.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us'        > /etc/vconsole.conf
echo 'MINDEXTENSION'    > /etc/hostname

passwd                                           # root password
useradd -m -G wheel -s /bin/bash "$USERNAME"
passwd "$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
```

### 5.2 pacman: multilib + CachyOS repositories

```bash
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf     # Steam, lib32 drivers

cd /tmp
curl -LO https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
./cachyos-repo.sh
```

The official script handles everything the repos need. It:
- detects `x86-64-v3` on the 5800X3D;
- imports the key `F3B607488DB35A47`;
- installs the keyring, the mirrorlists and **CachyOS's patched pacman**;
- sets `Architecture = auto`;
- adds `[cachyos-v3]`, `[cachyos-core-v3]`, `[cachyos-extra-v3]` and `[cachyos]` above the Arch repos;
- runs `pacman -Syu`.

Do not hand-edit these repos into `pacman.conf`: stock pacman refuses `x86_64_v3` packages.

Verify:

```bash
grep -E '^\[|^Architecture' /etc/pacman.conf
# Architecture = auto, then [cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] [core] [extra] [multilib]
```

### 5.3 Boot chain: Limine + mkinitcpio (install BEFORE the kernels)

`limine-mkinitcpio-hook` replaces the stock mkinitcpio pacman hook and provides the `sd-btrfs-overlayfs` hook that lets you boot read-only snapshots. pacman only runs hooks that existed when a transaction started, so this must be installed **before** the kernels, in its own transaction.

```bash
pacman -S limine limine-mkinitcpio-hook mkinitcpio

# Kernel command line, used by every kernel entry Limine generates
ROOT_UUID=$(findmnt -no UUID /)
echo "root=UUID=$ROOT_UUID rootflags=subvol=/@ rw quiet nowatchdog zswap.enabled=0 amd_pstate=active nvidia_drm.modeset=1" > /etc/kernel/cmdline
cat /etc/kernel/cmdline

# Early-load NVIDIA (KMS), systemd initramfs, snapshot overlay hook
sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block filesystems sd-btrfs-overlayfs fsck)/' /etc/mkinitcpio.conf
grep -E '^(MODULES|HOOKS)=' /etc/mkinitcpio.conf
```

What the cmdline flags do:
- `zswap.enabled=0`: zram is used instead.
- `amd_pstate=active`: EPP CPU frequency driver.
- `nvidia_drm.modeset=1`: already the default in `nvidia-utils`; kept here as a belt-and-braces setting.

### 5.4 Kernels + NVIDIA

Two kernels, both with **prebuilt** NVIDIA open modules from CachyOS (no DKMS build on every kernel update). `linux-cachyos-lts` is the fallback if a mainline kernel or driver update ever breaks.

```bash
pacman -S linux-cachyos linux-cachyos-headers linux-cachyos-nvidia-open \
          linux-cachyos-lts linux-cachyos-lts-headers linux-cachyos-lts-nvidia-open \
          nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver
```

Install the bootloader, register it in NVRAM, and add a fallback copy at `EFI/BOOT/BOOTX64.EFI` in case a firmware update wipes the boot entries:

```bash
limine-install
limine-install --fallback
limine-update
limine-list          # expect entries for linux-cachyos and linux-cachyos-lts
```

### 5.5 Desktop, audio, gaming, peripherals

```bash
# Hyprland desktop (uwsm-managed session)
pacman -S hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm libnewt \
          hyprpolkitagent hyprlock hypridle awww waybar swaync rofi kitty \
          grim slurp wl-clipboard cliphist qt5-wayland qt6-wayland \
          noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd otf-font-awesome ttf-liberation \
          thunar gvfs xdg-user-dirs firefox nwg-look playerctl ly

# Audio
pacman -S pipewire pipewire-alsa pipewire-pulse pipewire-jack lib32-pipewire lib32-pipewire-jack \
          wireplumber rtkit pavucontrol easyeffects lsp-plugins-lv2 calf headsetcontrol

# Gaming
pacman -S steam lutris umu-launcher proton-cachyos-slr gamemode lib32-gamemode \
          mangohud lib32-mangohud gamescope heroic-games-launcher protonup-qt winetricks

# Scheduler, peripherals, AUR helper, DKMS (for ryzen_smu later)
pacman -S scx-scheds scx-tools piper libratbag ckb-next yay dkms stress-ng
```

`yay`, `heroic-games-launcher`, `protonup-qt` and `proton-cachyos-slr` come from the CachyOS repo, so none of them need the AUR.

### 5.6 Memory: zram + sysctl

```bash
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

cat > /etc/sysctl.d/99-workstation.conf <<'EOF'
# zram-optimised swap (Arch Wiki: Zram#Optimizing swap on zram)
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0

# Cap dirty page cache so big writes (compiles, game patches) don't cause stalls
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
EOF
```

Arch already ships `vm.max_map_count = 1048576`, which is enough for Proton, so it isn't set here.

Load the NTSYNC driver so Proton's Windows-sync emulation uses it:

```bash
echo ntsync > /etc/modules-load.d/ntsync.conf
```

### 5.7 Services, scheduler, mirrors

```bash
cat > /etc/scx_loader.toml <<'EOF'
default_sched = "scx_bpfland"
default_mode = "Gaming"
EOF

cat > /etc/xdg/reflector/reflector.conf <<'EOF'
--save /etc/pacman.d/mirrorlist
--country BR,US
--protocol https
--latest 15
--sort rate
EOF

systemctl enable NetworkManager.service systemd-timesyncd.service \
                 reflector.timer paccache.timer smartd.service \
                 scx_loader.service ratbagd.service ckb-next-daemon.service \
                 ly@tty2.service
systemctl disable getty@tty2.service

getent group gamemode && usermod -aG gamemode "$USERNAME"
```

### 5.8 Leave and reboot

```bash
exit
umount -R /mnt
reboot      # remove the USB stick
```

In the Limine menu pick **linux-cachyos**. At the `ly` login, choose the session **Hyprland (uwsm-managed)**. On first start Hyprland generates a default `hyprland.lua`, where `SUPER+Q` opens kitty. Open this guide in Firefox and continue there.

---

## 6. First boot: quick checks

```bash
nvidia-smi                                         # driver 615.x, RTX 3070
cat /sys/module/nvidia_drm/parameters/modeset      # Y
cat /sys/devices/system/cpu/amd_pstate/status      # active
scxctl get                                         # bpfland, Gaming
swapon --show                                      # /dev/zram0
systemctl --failed                                 # should be empty
```

---

## 7. Bootable snapshots (snapper + Limine)

Every `pacman` transaction takes a pre/post snapshot (`snap-pac`). `limine-snapper-sync` adds each one to the Limine boot menu, so a broken update is one reboot away from being undone.

```bash
sudo pacman -S snapper snap-pac limine-snapper-sync btrfs-assistant
sudo snapper -c root create-config /                    # creates /.snapshots inside @ (tool default: /@/.snapshots)
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
sudo systemctl enable --now limine-snapper-sync.service snapper-cleanup.timer

sudo snapper -c root create -d "fresh install"
limine-list                                             # a "Snapshots" submenu should now exist
```

**Restore after a bad update:**
1. Reboot and open *Snapshots* in the Limine menu, then boot the last good snapshot. It runs read-only with an overlay.
2. Run `sudo limine-snapper-restore`.
3. Reboot.

`btrfs-assistant` gives you a GUI for the same operations.

`/home` is not snapshotted. Snapshots are not backups either; see section 13.

---

## 8. Hyprland

### 8.1 Session environment (`~/.config/uwsm/env`)

uwsm exports these to the whole session, including systemd user services. Per the Hyprland wiki, env vars go here, not in `hyprland.lua`.

```bash
mkdir -p ~/.config/uwsm
cat > ~/.config/uwsm/env <<'EOF'
export XCURSOR_SIZE=24
# NVIDIA
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
# Keep NVIDIA's shader cache instead of pruning it at 1 GB (fewer re-compiles / stutters)
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
# Toolkits: prefer Wayland, fall back to X11
export ELECTRON_OZONE_PLATFORM_HINT=auto
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11,*"
EOF

cat > ~/.config/uwsm/env-hyprland <<'EOF'
export HYPRCURSOR_SIZE=24
EOF
```

Do **not** set `SDL_VIDEODRIVER=wayland` globally. It breaks games that bundle older SDL builds.

### 8.2 `~/.config/hypr/hyprland.lua`

**Monitor ports:** the SuperFrame is on the card's only HDMI port, so it's `HDMI-A-1`. The LG's name depends on which of the RTX 3070's three DisplayPorts it's plugged into (`DP-1`, `DP-2` or `DP-3`). Run `hyprctl monitors all` and set `MAIN` to match. Hyprland shows config errors in a banner at the top of the screen.

If `availableModes` for `HDMI-A-1` doesn't list a 144 Hz mode, set `SIDE`'s `mode` to the highest one listed. Your HWiNFO capture only showed modes up to 75 Hz on this connection, but that list doesn't always include the monitor's high-refresh modes.

```lua
-- Hyprland 0.56 Lua config. Environment variables live in ~/.config/uwsm/env.

----------------------------------------------------------------------
-- Monitors   (verify port names with: hyprctl monitors all)
----------------------------------------------------------------------
local MAIN = "DP-1"       -- LG UltraWide 2560x1080 @ 144 Hz, DisplayPort (check DP-1/2/3)
local SIDE = "HDMI-A-1"   -- SuperFrame Ace 27" 1920x1080 @ 144 Hz, HDMI

-- vrr = 2: VRR only for fullscreen apps (avoids NVIDIA desktop flicker)
-- vrr = 0 on HDMI: NVIDIA has no VRR over HDMI without HDMI 2.1 VRR
hl.monitor({ output = MAIN, mode = "2560x1080@144", position = "0x0",    scale = 1, vrr = 2 })
hl.monitor({ output = SIDE, mode = "1920x1080@144", position = "2560x0", scale = 1, vrr = 0 })
hl.monitor({ output = "",   mode = "preferred",     position = "auto",   scale = 1 })

hl.workspace_rule({ workspace = "1", monitor = MAIN, default = true })  -- games, editor
hl.workspace_rule({ workspace = "2", monitor = MAIN })                  -- browser
hl.workspace_rule({ workspace = "3", monitor = SIDE, default = true })  -- docs, Discord, terminal

----------------------------------------------------------------------
-- Programs
----------------------------------------------------------------------
local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "rofi -show drun"

-- Launch apps as systemd units inside the uwsm session
local function app(cmd) return hl.dsp.exec_cmd("uwsm app -- " .. cmd) end

----------------------------------------------------------------------
-- Autostart   (waybar, swaync, hypridle, polkit agent run as user services, see 8.3)
----------------------------------------------------------------------
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- awww-daemon")
    hl.exec_cmd("uwsm app -- wl-paste --watch cliphist store")
    hl.exec_cmd("uwsm app -- ckb-next --background")
    hl.exec_cmd("sh -c 'sleep 1; awww img ~/Pictures/wallpaper.jpg'")
end)

----------------------------------------------------------------------
-- Look and feel
----------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout        = "dwindle",
        allow_tearing = true,   -- master switch; games opt in with the `immediate` rule below
    },

    decoration = {
        rounding           = 10,
        active_opacity     = 0.95,
        inactive_opacity   = 0.85,
        fullscreen_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 15,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            ignore_opacity    = true,
        },
    },

    animations = { enabled = true },

    render = {
        direct_scanout = 2,     -- auto: fullscreen games bypass composition. Set 0 if fullscreen flickers.
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        vrr                     = 0,    -- per-monitor vrr above takes over
    },

    input = {
        kb_layout          = "us",      -- "br" for ABNT2
        numlock_by_default = true,
        follow_mouse       = 1,
        sensitivity        = 0,
        accel_profile      = "flat",    -- raw 1:1 mouse input for the G502
    },

    dwindle = { preserve_split = true },
})

hl.curve("overshot",  { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("smoothOut", { type = "bezier", points = { {0.36, 0},   {0.66, -0.56} } })
hl.curve("smoothIn",  { type = "bezier", points = { {0.25, 1},   {0.5, 1} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4,  bezier = "overshot",  style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4,  bezier = "smoothOut", style = "slide" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 5,  bezier = "smoothIn" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5,  bezier = "overshot",  style = "slidevert" })

----------------------------------------------------------------------
-- Keybinds
----------------------------------------------------------------------
local mod = "SUPER"

hl.bind(mod .. " + Return",      app(terminal))
hl.bind(mod .. " + D",           app(menu))
hl.bind(mod .. " + E",           app(fileManager))
hl.bind(mod .. " + Q",           hl.dsp.window.close())
hl.bind(mod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",           hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + P",           hl.dsp.window.pseudo())
hl.bind(mod .. " + L",           hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + E",   hl.dsp.exec_cmd("uwsm stop"))       -- clean logout (don't use hl.dsp.exit with uwsm)
hl.bind(mod .. " + SHIFT + V",   hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy"))
hl.bind("Print",                 hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + Print",         hl.dsp.exec_cmd('grim - | wl-copy'))

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- K95 media keys / volume wheel
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

----------------------------------------------------------------------
-- Window rules
----------------------------------------------------------------------
-- Black Desert (Wine/Proton via Lutris). Verify the class with: hyprctl clients
hl.window_rule({
    name      = "black-desert",
    match     = { class = "(?i)^blackdesert64\\.exe$" },
    immediate = true,   -- allow tearing (lowest input latency) when fullscreen
    opaque    = true,
})

-- Steam games run as XWayland windows with class steam_app_<appid>
hl.window_rule({
    name      = "steam-games",
    match     = { class = "^steam_app_[0-9]+$" },
    immediate = true,
    opaque    = true,
})

-- Never lock or blank the screen while something is fullscreen (games, video)
hl.window_rule({
    name         = "idle-inhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
```

Notes on tearing and VRR:
- Tearing only happens when the game is fullscreen **and** nothing else is visible on that monitor. `hyprctl monitors` shows `tearingBlockedBy` if it's being blocked.
- On the LG, inside its VRR range (50–144 fps), VRR handles frame pacing, and tearing only matters above 144 fps. Play on the LG; the SuperFrame has no VRR over HDMI.

### 8.3 Session services, idle, lock, bar

```bash
# Run as systemd user services, started by the uwsm session
systemctl --user add-wants graphical-session.target \
    waybar.service swaync.service hypridle.service hyprpolkitagent.service

cp /usr/share/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf

cat > ~/.config/hypr/hypridle.conf <<'EOF'
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}

listener {
    timeout = 600
    on-timeout = loginctl lock-session
}

listener {
    timeout = 900
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}
EOF

mkdir -p ~/.config/waybar ~/Pictures
cat > ~/.config/waybar/config.jsonc <<'EOF'
{
  "layer": "top",
  "height": 30,
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["tray", "pulseaudio", "cpu", "memory", "network"],
  "clock": { "format": "{:%a %d %b  %H:%M}" },
  "pulseaudio": { "format": "{volume}% {icon}", "format-icons": { "default": ["", "", ""] }, "on-click": "pavucontrol" },
  "cpu": { "format": "{usage}% " },
  "memory": { "format": "{used:0.1f}G " },
  "network": { "format-ethernet": "{ipaddr} ", "format-disconnected": "offline ⚠" }
}
EOF

xdg-user-dirs-update
```

Put a wallpaper at `~/Pictures/wallpaper.jpg`, then log out (`SUPER+SHIFT+E`) and back in.

---

## 9. Audio: PipeWire + Logitech G PRO X (wired)

Wired through its USB DAC, the PRO X is a standard USB Audio Class device and works out of the box. Plugged into the 3.5 mm jack it's just analog via the ALC897, and HeadsetControl can't talk to it.

### 9.1 Lower latency, fewer resampling cases

The default quantum is 1024/48000 (about 21 ms). 512 (about 10.7 ms) is a safe step down. Apps that ask for less, such as games and voice apps, can go as low as 64.

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/10-latency.conf <<'EOF'
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 512
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 2048
}
EOF
```

`allowed-rates` lets 44.1 kHz music play without resampling when the DAC supports it.

### 9.2 WirePlumber rules

These rules do two things:
- **Never suspend the PRO X.** That removes the pop and the cut-off first syllable when sound starts.
- **Hide the NVIDIA HDMI/DP audio device**, so the SuperFrame's HDMI audio never becomes the default output. Delete the second block if you ever want sound through the monitor.

```bash
# Check the real names first:
pw-cli ls Node   | grep node.name    # look for alsa_output.usb-Logitech_PRO_X...
pw-cli ls Device | grep device.name  # GPU audio is alsa_card.pci-0000_07_00.1 (bus 07 per HWiNFO)

mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cat > ~/.config/wireplumber/wireplumber.conf.d/51-devices.conf <<'EOF'
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_.*usb-Logitech_PRO_X.*" } ]
    actions = { update-props = { session.suspend-timeout-seconds = 0 } }
  }
  {
    matches = [ { device.name = "alsa_card.pci-0000_07_00.1" } ]
    actions = { update-props = { device.disabled = true } }
  }
]
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber
pw-metadata -n settings | grep clock.quantum      # 512
wpctl status                                      # PRO X present, NVIDIA HDMI gone
```

### 9.3 Blue VO!CE and EQ replacement: EasyEffects

1. Open EasyEffects. Under **Input** (the mic), add these in order:
   - **Noise Reduction** (RNNoise): removes keyboard and fan noise.
   - **Gate**
   - **Compressor**
   - **Limiter**
2. Under **Output**, add an **Equalizer** and re-enter your G HUB EQ curve. Alternatively, import an AutoEq preset for the G PRO X.
3. In EasyEffects settings, enable **Launch at startup**. uwsm handles XDG autostart.

G HUB's DTS:X virtual 7.1 has no Linux equivalent.

### 9.4 Sidetone (HeadsetControl)

`headsetcontrol` supports the G PRO X (USB ID `046d:0aaa`). The package installs udev rules, so no root is needed.

```bash
headsetcontrol -s 64      # sidetone 0–128
headsetcontrol -?         # all supported features for your device
```

If Discord crackles, it's asking for too small a buffer. Raise its minimum:

```bash
mkdir -p ~/.config/pipewire/pipewire-pulse.conf.d
cat > ~/.config/pipewire/pipewire-pulse.conf.d/20-discord.conf <<'EOF'
pulse.rules = [
  {
    matches = [ { application.process.binary = "Discord" } ]
    actions = { update-props = { pulse.min.quantum = 1024/48000 } }
  }
]
EOF
systemctl --user restart pipewire-pulse
```

---

## 10. Mouse & keyboard

- **G502 HERO**: open **Piper** to set DPI steps, report rate (1000 Hz), buttons and onboard profiles. `ratbagd` is already enabled. Your G HUB onboard profile also keeps working without Piper.
- **K95 RGB Platinum**: open **ckb-next** for lighting, G-key macros and hardware profiles. The daemon is enabled and the tray app autostarts from `hyprland.lua`.

---

## 11. Per-core Curve Optimizer (systemd service)

The B450M DS3H V2 BIOS doesn't expose Curve Optimizer for the 5800X3D, so the offsets are written at runtime to the CPU's SMU through the `ryzen_smu` kernel driver. That's the same thing PBO2 Tuner does on Windows.

The offsets **reset on every power cycle**. A boot service and a resume service re-apply them.

> `ryzenadj` cannot do this. It doesn't support desktop Vermeer CPUs and has no per-core CO flag for them.

### 11.1 Driver (AUR)

`ryzen_smu-dkms-git` is the only AUR package this build needs. Arch has an open AUR malware incident (Arch news, 2026-06-12), so **read the PKGBUILD before building**. `yay` shows it to you. The source should be `github.com/amkillam/ryzen_smu` only.

```bash
yay -S ryzen_smu-dkms-git
echo ryzen_smu | sudo tee /etc/modules-load.d/ryzen_smu.conf
sudo modprobe ryzen_smu
cat /sys/kernel/ryzen_smu_drv/version        # must print a version
```

DKMS builds it for both kernels, using the headers installed in section 5.4.

### 11.2 `/usr/local/bin/pbo-curve`

```bash
sudo tee /usr/local/bin/pbo-curve >/dev/null <<'EOF'
#!/usr/bin/env python3
"""Per-core Curve Optimizer for the Ryzen 7 5800X3D via the ryzen_smu driver.

SMU MP1 opcodes (0x35 set per-core, 0x48 get per-core, 0x36 reset all) are the ones
used by github.com/svenlange2/Ryzen-5800x3d-linux-undervolting (ruv.py).
Offsets reset on every power cycle; pbo-curve.service re-applies them.
"""
import struct
import sys
import time

# Core 0..7, same order and values as PBO2 Tuner on Windows (all negative).
OFFSETS = [-27, -29, -29, -30, -28, -30, -27, -28]

DRV = "/sys/kernel/ryzen_smu_drv/"
SMU_ARGS = DRV + "smu_args"
MP1_CMD = DRV + "mp1_smu_cmd"

OP_SET_CORE = 0x35
OP_RESET_ALL = 0x36
OP_GET_CORE = 0x48
SMU_OK = 0x01


def die(msg):
    print(f"pbo-curve: {msg}", file=sys.stderr)
    sys.exit(1)


def read32(path):
    with open(path, "rb") as f:
        return struct.unpack("<I", f.read(4))[0]


def wait_ready():
    for _ in range(50):
        status = read32(MP1_CMD)
        if status != 0:
            return status
        time.sleep(0.1)
    die("SMU stayed busy for 5 s")


def smu(op, arg0=0):
    wait_ready()
    with open(SMU_ARGS, "wb") as f:
        f.write(struct.pack("<6I", arg0, 0, 0, 0, 0, 0))
    with open(MP1_CMD, "wb") as f:
        f.write(struct.pack("<I", op))
    status = wait_ready()
    if status != SMU_OK:
        die(f"SMU command 0x{op:02X} failed (status 0x{status:02X})")
    with open(SMU_ARGS, "rb") as f:
        return struct.unpack("<6I", f.read(24))[0]


def core_arg(core):
    return ((core & 8) << 5 | core & 7) << 20


def get_offset(core):
    value = smu(OP_GET_CORE, core_arg(core))
    return value - 2**32 if value >= 2**31 else value


def set_offset(core, offset):
    smu(OP_SET_CORE, core_arg(core) | (offset & 0xFFFF))


def preflight():
    try:
        with open("/proc/cpuinfo") as f:
            if "5800X3D" not in f.read():
                die("CPU is not a Ryzen 7 5800X3D; refusing to touch the SMU")
        read32(DRV + "version")
    except FileNotFoundError:
        die("ryzen_smu driver not loaded (modprobe ryzen_smu)")
    except PermissionError:
        die("must run as root")
    if len(OFFSETS) != 8 or any(not -30 <= o <= 0 for o in OFFSETS):
        die("OFFSETS must be 8 values between -30 and 0")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    preflight()
    if cmd == "apply":
        for core, offset in enumerate(OFFSETS):
            set_offset(core, offset)
            readback = get_offset(core)
            if readback != offset:
                die(f"core {core}: wrote {offset}, read back {readback}")
        print("pbo-curve: applied " + " ".join(f"{c}:{o}" for c, o in enumerate(OFFSETS)))
    elif cmd == "list":
        for core in range(len(OFFSETS)):
            print(f"core {core}: {get_offset(core)}")
    elif cmd == "reset":
        smu(OP_RESET_ALL, 0)
        print("pbo-curve: all offsets reset to 0")
    else:
        die("usage: pbo-curve [apply|list|reset]")


if __name__ == "__main__":
    main()
EOF
sudo chmod 755 /usr/local/bin/pbo-curve
```

### 11.3 Test by hand first

Do this before enabling the service. If the values are unstable, a reboot clears them.

```bash
sudo pbo-curve list        # all 0 after a fresh boot
sudo pbo-curve apply       # pbo-curve: applied 0:-27 1:-29 ...
sudo pbo-curve list        # matches OFFSETS
```

Stability check:
- **Full load:** `stress-ng --cpu 16 --cpu-method all --timeout 20m`.
- **Light and idle use:** use the PC normally for a day. Curve Optimizer instability usually shows up at light load, not under stress.
- **Watch for hardware errors:** `journalctl -k | grep -iE 'mce|hardware error'`. Any hit means one core's offset is too aggressive; move that core 2–3 steps toward 0.

### 11.4 Apply at boot and after resume

```bash
sudo tee /etc/systemd/system/pbo-curve.service >/dev/null <<'EOF'
[Unit]
Description=Apply per-core Curve Optimizer offsets (Ryzen 7 5800X3D)
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/modprobe ryzen_smu
ExecStart=/usr/local/bin/pbo-curve apply

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/pbo-curve-resume.service >/dev/null <<'EOF'
[Unit]
Description=Re-apply Curve Optimizer offsets after resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pbo-curve apply

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pbo-curve.service
sudo systemctl enable pbo-curve-resume.service
journalctl -b -u pbo-curve.service                    # "applied ..."
```

To undo: `sudo systemctl disable pbo-curve.service pbo-curve-resume.service`, then reboot.

---

## 12. Gaming

### 12.1 Steam

In Steam, go to **Settings → Compatibility** and enable Steam Play for all titles. Select **proton-cachyos-slr** as the default; it's installed system-wide from the CachyOS repo.

Per-game launch options:

```
gamemoderun %command%
mangohud gamemoderun %command%          # with the FPS / frametime overlay
```

If a game misbehaves on Wayland, run it through gamescope at native resolution:

```
gamescope -W 2560 -H 1080 -r 144 -f -- gamemoderun %command%
```

### 12.2 Black Desert (standalone launcher)

Run it through Lutris (installed) with a GE-Proton runner. Once the game window is up, run `hyprctl clients` and check its `class`. If it isn't `blackdesert64.exe`, update the `black-desert` window rule in `hyprland.lua` so tearing and opacity apply.

---

## 13. Optional

### 13.1 Old HDD as a bulk/backup disk

The Samsung HD502HJ has about 49 000 power-on hours. Use it for bulk files or a second copy of backups only, never as the only copy of anything. `smartd` (enabled in 5.7) watches its health.

```bash
lsblk -o NAME,MODEL,SIZE              # confirm it's SAMSUNG HD502HJ (expected /dev/sda); destroys D:
sudo sgdisk -Z /dev/sda
sudo sgdisk -n1:0:0 -t1:8300 /dev/sda
sudo mkfs.ext4 -L HDD /dev/sda1
sudo mkdir -p /mnt/hdd
echo 'LABEL=HDD  /mnt/hdd  ext4  noatime,nofail,x-systemd.device-timeout=5s  0 2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /mnt/hdd
sudo chown "$USER": /mnt/hdd
```

### 13.2 Development stack

```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker.socket
sudo usermod -aG docker "$USER"       # root-equivalent access; log out/in to apply

sudo pacman -S code                   # VS Code (OSS build, Open VSX extensions)
# or Microsoft's build with the official marketplace (AUR):  yay -S visual-studio-code-bin
```

Docker's data lives on the `@docker` subvolume, so it stays out of system snapshots.

---

## 14. Final verification checklist

| Check | Command | Expected |
|---|---|---|
| NVIDIA driver + KMS | `nvidia-smi`; `cat /sys/module/nvidia_drm/parameters/modeset` | 615.x; `Y` |
| ReBAR | `nvidia-smi -q \| grep -A3 BAR1` | Total 8192 MiB |
| CPU driver | `cat /sys/devices/system/cpu/amd_pstate/status` | `active` |
| Scheduler | `scxctl get` | bpfland, Gaming |
| Curve Optimizer | `sudo pbo-curve list` | -27 -29 -29 -30 -28 -30 -27 -28 |
| zram | `zramctl`; `swapon --show` | zram0, zstd |
| Monitors | `hyprctl monitors` | DP-x 2560x1080@144 (VRR), HDMI-A-1 1920x1080@144 |
| Audio | `wpctl status`; `pw-metadata -n settings` | PRO X default sink/source; quantum 512 |
| Snapshots | `snapper -c root list`; `limine-list` | "fresh install" + Snapshots menu |
| Fallback kernel | Limine menu | linux-cachyos-lts boots |
| Services | `systemctl --failed`; `systemctl --user --failed` | none |
| RAM in use at idle | `free -h` | measure it; don't trust guesses |

---

## 15. Maintenance & recovery

- **Updates:** `yay` (or `sudo pacman -Syu`). Read <https://archlinux.org/news/> before big updates; `yay -Pw` shows unread news. `snap-pac` snapshots every transaction automatically.
- **AUR:** only `ryzen_smu-dkms-git` (and optionally VS Code). Review PKGBUILD diffs on every update.
- **Broken boot after an update:**
  1. In the Limine menu, boot **linux-cachyos-lts** first.
  2. If that also fails, boot a snapshot, then run `sudo limine-snapper-restore`.
- **Limine boot entry gone** (e.g. after a BIOS update): the fallback at `EFI/BOOT/BOOTX64.EFI` still boots. Afterwards, run `sudo limine-install` to recreate the NVRAM entry.
- **Mirrors:** `reflector.timer` refreshes them weekly. **Package cache:** `paccache.timer` keeps the last 3 versions.
- **Kernel parameters:** edit `/etc/kernel/cmdline`, then run `sudo limine-update`.

---

## Sources

- CachyOS repo setup: <https://wiki.cachyos.org/features/optimized_repos/> and the official `cachyos-repo.sh`
- Arch Wiki: [NVIDIA](https://wiki.archlinux.org/title/NVIDIA), [NVIDIA/Tips and tricks](https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks), [Limine](https://wiki.archlinux.org/title/Limine), [PipeWire](https://wiki.archlinux.org/title/PipeWire), [Zram](https://wiki.archlinux.org/title/Zram)
- Arch news: [NVIDIA 590 switches to open modules](https://archlinux.org/news/), [AUR malicious packages incident](https://archlinux.org/news/)
- Hyprland 0.56.2 source (`example/hyprland.lua`, `src/config`) and wiki (Tearing, UWSM, Monitors, Environment variables): <https://github.com/hyprwm/Hyprland>, <https://github.com/hyprwm/hyprland-wiki>
- Limine tooling: <https://gitlab.com/Zesko/limine-entry-tool>, <https://gitlab.com/Zesko/limine-snapper-sync>
- sched-ext loader: <https://github.com/sched-ext/scx-loader>
- ly: <https://codeberg.org/fairyglade/ly>
- 5800X3D undervolting on Linux: <https://github.com/svenlange2/Ryzen-5800x3d-linux-undervolting>, driver <https://github.com/amkillam/ryzen_smu>
- HeadsetControl (G PRO X support): <https://github.com/Sapd/HeadsetControl>
- SuperFrame Ace 27 specs: <https://www.kabum.com.br/produto/1057758>
