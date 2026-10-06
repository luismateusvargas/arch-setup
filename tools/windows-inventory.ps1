<#
Reads this Windows PC and suggests config.sh values for arch-setup. Read-only: changes nothing.

Run it from the repo folder (no admin needed):
    powershell -ExecutionPolicy Bypass -File tools\windows-inventory.ps1

It prints what it found and writes config.suggested.sh next to config.sh (Linux line endings).
Review every value, then either copy them into config.sh or rename the file to config.local.sh.
#>

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
function Section($title) { Write-Host ''; Write-Host "== $title" -ForegroundColor Cyan }
function Note($text)     { Write-Host "   $text" -ForegroundColor DarkGray }

# ------------------------------------------------------------------ CPU
Section 'CPU'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuVendor = ''
if ($cpu.Manufacturer -match 'AMD')   { $cpuVendor = 'amd' }
if ($cpu.Manufacturer -match 'Intel') { $cpuVendor = 'intel' }
Write-Host "   $($cpu.Name.Trim())  ->  CPU_VENDOR=$cpuVendor"

# ------------------------------------------------------------------ GPU
Section 'Graphics'
function Get-GpuDriver([string]$name) {
    if ($name -match 'NVIDIA') {
        if ($name -match 'RTX|GTX 16\d\d|Quadro T\d|\bT\d{3,4}\b|\bA\d{2,4}\b|\bL\d{1,2}\b') { return 'nvidia-open' }
        if ($name -match 'GTX (9\d\d|10\d\d|75\d|745)|TITAN (X|V)|Quadro [MP]\d|Tesla [MPV]') { return 'nvidia-580xx' }
        if ($name -match 'GTX [4-7]\d\d|GT [1-7]\d\d|TITAN') { return 'unsupported' }
        return 'nvidia-open'
    }
    if ($name -match 'AMD|Radeon|ATI') {
        if ($name -match 'Radeon HD [2-6]\d{3}|Radeon X\d') { return 'unsupported' }   # TeraScale: no Vulkan
        return 'amd'
    }
    if ($name -match 'Intel') { return 'intel' }
    return ''
}
$gpuDriver = ''
$rank = @{ 'nvidia-open' = 3; 'nvidia-580xx' = 3; 'unsupported' = 3; 'amd' = 2; 'intel' = 1; '' = 0 }
foreach ($gpu in Get-CimInstance Win32_VideoController) {
    $driver = Get-GpuDriver $gpu.Name
    Write-Host "   $($gpu.Name)  ->  $driver"
    if ($rank[$driver] -gt $rank[$gpuDriver]) { $gpuDriver = $driver }
}
if ($gpuDriver -eq 'unsupported') {
    Write-Host '   This card is too old: no Vulkan driver for games (NVIDIA before GTX 900, AMD before HD 7000).' -ForegroundColor Red
}
Note 'With two GPUs (e.g. Intel/AMD integrated + NVIDIA), the value is for the card your monitors are plugged into.'

# ------------------------------------------------------------------ Disks
Section 'Disks (INSTALL_DISK_MODEL is ERASED completely)'
$systemDisk = (Get-Partition -DriveLetter C -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue).Number
$installModel = ''
foreach ($d in Get-PhysicalDisk | Sort-Object DeviceId) {
    $size = [math]::Round($d.Size / 1GB)
    $mark = ''
    if ([string]$d.DeviceId -eq [string]$systemDisk) { $mark = '  <- Windows (C:) is here'; $installModel = $d.FriendlyName.Trim() }
    Write-Host ("   {0,-32} {1,-5} {2,-5} {3,6} GB{4}" -f $d.FriendlyName.Trim(), $d.MediaType, $d.BusType, $size, $mark)
}
Note 'Linux may show the model slightly differently: check-config.sh on the live ISO confirms it.'
Note 'For an old HDD to wipe later (HDD_MODEL/HDD_SERIAL): Get-PhysicalDisk | Format-Table FriendlyName, SerialNumber'

$bitlocker = $null
try { $bitlocker = (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection') } catch {}
if ($bitlocker -eq 1 -or $bitlocker -eq 3 -or $bitlocker -eq 5) {
    Write-Host '   C: is BitLocker-encrypted: Linux cannot read it. Copy everything you need to another drive first.' -ForegroundColor Yellow
}

# ------------------------------------------------------------------ Monitors
Section 'Monitors'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ArchSetupDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY;
        public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency;
        public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
        public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string device, int devNum, ref DISPLAY_DEVICE dd, int flags);
}
'@

# EDID names and connection types from WMI, keyed by the PnP hardware ID (e.g. GSM76FE).
$names = @{}
foreach ($m in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue) {
    $id = ($m.InstanceName -split '\\')[1]
    $names[$id] = (($m.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '').Trim()
}
$links = @{}
foreach ($c in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue) {
    $links[($c.InstanceName -split '\\')[1]] = $c.VideoOutputTechnology   # 5 = HDMI, 10/11 = DisplayPort
}

$screens = @()
for ($i = 0; $i -lt 16; $i++) {
    $adapter = New-Object ArchSetupDisplay+DISPLAY_DEVICE
    $adapter.cb = [Runtime.InteropServices.Marshal]::SizeOf($adapter)
    if (-not [ArchSetupDisplay]::EnumDisplayDevices($null, $i, [ref]$adapter, 0)) { break }
    if (($adapter.StateFlags -band 1) -eq 0) { continue }          # not part of the desktop
    $mode = New-Object ArchSetupDisplay+DEVMODE
    $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($mode)
    if (-not [ArchSetupDisplay]::EnumDisplaySettings($adapter.DeviceName, -1, [ref]$mode)) { continue }
    $monitor = New-Object ArchSetupDisplay+DISPLAY_DEVICE
    $monitor.cb = [Runtime.InteropServices.Marshal]::SizeOf($monitor)
    $hwid = ''
    if ([ArchSetupDisplay]::EnumDisplayDevices($adapter.DeviceName, 0, [ref]$monitor, 1)) {
        $hwid = ($monitor.DeviceID -split '#')[1]                  # \\?\DISPLAY#GSM76FE#...
    }
    $name = $names[$hwid]
    if (-not $name) { $name = $hwid }
    $screens += [pscustomobject]@{
        Name = $name; Width = $mode.dmPelsWidth; Height = $mode.dmPelsHeight; Hz = $mode.dmDisplayFrequency
        X = $mode.dmPositionX; Y = $mode.dmPositionY; Link = $links[$hwid]
        Primary = ($mode.dmPositionX -eq 0 -and $mode.dmPositionY -eq 0)
    }
}
$minX = ($screens | Measure-Object X -Minimum).Minimum
$minY = ($screens | Measure-Object Y -Minimum).Minimum
$monitorLines = @()
foreach ($s in $screens | Sort-Object @{ Expression = 'Primary'; Descending = $true }, X) {
    $link = 'other'
    if ($s.Link -eq 5) { $link = 'HDMI' }
    if ($s.Link -eq 10 -or $s.Link -eq 11) { $link = 'DisplayPort' }
    $vrr = 2
    if ($link -eq 'HDMI' -and $gpuDriver -like 'nvidia*') { $vrr = 0 }
    $line = '{0}|{1}x{2}@{3}|{4}x{5}|1|{6}' -f $s.Name, $s.Width, $s.Height, $s.Hz, ($s.X - $minX), ($s.Y - $minY), $vrr
    $monitorLines += $line
    $primary = ''
    if ($s.Primary) { $primary = '  (main)' }
    Write-Host ("   {0}: {1}x{2} @ {3} Hz via {4}{5}" -f $s.Name, $s.Width, $s.Height, $s.Hz, $link, $primary)
}
Note 'SCALE is written as 1: if Windows uses 125 %/150 % (Settings > Display > Scale), change it to 1.25/1.5.'
Note 'VRR is 2 (fullscreen apps only); 0 on HDMI with NVIDIA, which has no VRR over HDMI without HDMI 2.1 VRR.'

# ------------------------------------------------------------------ Language, keyboard, time zone
Section 'Language, keyboard, time zone'
$locales = @('en_US.UTF-8')
foreach ($lang in Get-WinUserLanguageList) {
    $loc = ($lang.LanguageTag -replace '-', '_') + '.UTF-8'
    if ($loc -match '^[a-z]{2,3}_[A-Z]{2}\.UTF-8$' -and $locales -notcontains $loc) { $locales += $loc }
}
Write-Host "   languages: $($locales -join ' ')"

# Keyboard layout ID (KLID) -> console keymap, X layout, X variant
$keyboards = @{
    '00000409' = @('us', 'us', '');        '00020409' = @('us-acentos', 'us', 'intl')
    '00000416' = @('br-abnt2', 'br', '');  '00010416' = @('br-abnt2', 'br', '')
    '00000816' = @('pt-latin1', 'pt', ''); '00000809' = @('uk', 'gb', '')
    '00000407' = @('de-latin1', 'de', ''); '0000040C' = @('fr-latin1', 'fr', '')
    '0000040A' = @('es', 'es', '');        '0000080A' = @('la-latin1', 'latam', '')
    '00000410' = @('it', 'it', '');        '00000413' = @('nl', 'nl', '')
    '00000807' = @('de_CH-latin1', 'ch', ''); '0000100C' = @('fr_CH', 'ch', 'fr')
    '00000813' = @('be-latin1', 'be', ''); '0000041D' = @('sv-latin1', 'se', '')
    '00000414' = @('no', 'no', '');        '00000406' = @('dk', 'dk', '')
    '0000040B' = @('fi', 'fi', '');        '00000415' = @('pl', 'pl', '')
    '00000411' = @('jp106', 'jp', '')
}
$keymap = 'us'; $kbLayout = 'us'; $kbVariant = ''
$tip = (Get-WinUserLanguageList)[0].InputMethodTips | Select-Object -First 1
$klid = ''
if ($tip -match ':([0-9A-Fa-f]{8})$') { $klid = $Matches[1].ToUpper() }
if ($keyboards.ContainsKey($klid)) {
    $keymap, $kbLayout, $kbVariant = $keyboards[$klid]
    Write-Host "   keyboard $klid -> KEYMAP=$keymap KB_LAYOUT=$kbLayout KB_VARIANT=$kbVariant"
} else {
    Write-Host "   keyboard $klid is not in this script's list: set KEYMAP/KB_LAYOUT by hand (see config.sh)" -ForegroundColor Yellow
}

$tz = Get-TimeZone
$iana = ''
$convert = [System.TimeZoneInfo].GetMethod('TryConvertWindowsIdToIanaId', [type[]]@([string], [string].MakeByRefType()))
if ($convert) {
    $out = $null
    $args2 = @($tz.Id, $out)
    if ($convert.Invoke($null, $args2)) { $iana = $args2[1] }
}
if (-not $iana) {
    $zones = @{
        'E. South America Standard Time' = 'America/Sao_Paulo'; 'Argentina Standard Time' = 'America/Argentina/Buenos_Aires'
        'SA Pacific Standard Time' = 'America/Bogota';          'Pacific SA Standard Time' = 'America/Santiago'
        'Central Standard Time (Mexico)' = 'America/Mexico_City'
        'Eastern Standard Time' = 'America/New_York';           'Central Standard Time' = 'America/Chicago'
        'Mountain Standard Time' = 'America/Denver';            'Pacific Standard Time' = 'America/Los_Angeles'
        'GMT Standard Time' = 'Europe/London';                  'W. Europe Standard Time' = 'Europe/Berlin'
        'Romance Standard Time' = 'Europe/Paris';               'Central Europe Standard Time' = 'Europe/Budapest'
        'Central European Standard Time' = 'Europe/Warsaw';     'GTB Standard Time' = 'Europe/Bucharest'
        'FLE Standard Time' = 'Europe/Kyiv';                    'Russian Standard Time' = 'Europe/Moscow'
        'Turkey Standard Time' = 'Europe/Istanbul';             'South Africa Standard Time' = 'Africa/Johannesburg'
        'India Standard Time' = 'Asia/Kolkata';                 'China Standard Time' = 'Asia/Shanghai'
        'Singapore Standard Time' = 'Asia/Singapore';           'Tokyo Standard Time' = 'Asia/Tokyo'
        'Korea Standard Time' = 'Asia/Seoul';                   'AUS Eastern Standard Time' = 'Australia/Sydney'
        'UTC' = 'UTC'
    }
    $iana = $zones[$tz.Id]
}
if ($iana) { Write-Host "   time zone $($tz.Id) -> TIMEZONE=$iana" }
else { Write-Host "   time zone $($tz.Id): find yours on the ISO with: timedatectl list-timezones" -ForegroundColor Yellow }

$country = ([System.Globalization.RegionInfo]::CurrentRegion).TwoLetterISORegionName.ToUpper()
$mirrors = $country
if ($country -ne 'US') { $mirrors = "$country,US" }

# ------------------------------------------------------------------ Peripherals
Section 'Peripherals'
$devices = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FriendlyName) $($_.Manufacturer)" }) -join "`n"
$corsair = 'no';   if ($devices -match 'Corsair') { $corsair = 'yes' }
$mouse = 'no';     if ($devices -match 'Logitech G|G502|G Pro|SteelSeries|ROCCAT|Razer') { $mouse = 'yes' }
$headset = 'no';   if ($devices -match 'G PRO X|G Pro X|G43\d|G53\d|G73\d|Arctis|HyperX Cloud|VOID') { $headset = 'yes' }
$bluetooth = 'no'; if (Get-PnpDevice -PresentOnly -Class Bluetooth -ErrorAction SilentlyContinue) { $bluetooth = 'yes' }
Write-Host "   CORSAIR_KEYBOARD=$corsair  GAMING_MOUSE=$mouse  HEADSETCONTROL=$headset  BLUETOOTH=$bluetooth"
Note 'Guesses from device names: check the supported-device lists linked in config.sh.'
if ($cpu.Name -match '5800X3D') { Note 'Ryzen 7 5800X3D: UNDERVOLT is possible; copy your per-core offsets from PBO2 Tuner into CO_OFFSETS.' }

$fw = ''
try { $fw = (Get-ComputerInfo -Property BiosFirmwareType).BiosFirmwareType } catch {}
if ($fw -and $fw -ne 'Uefi') {
    Write-Host "   Firmware boots in $fw mode: switch the BIOS to UEFI (CSM off) before installing." -ForegroundColor Yellow
}

# ------------------------------------------------------------------ Write config.suggested.sh
$user = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', '')
if ($user -notmatch '^[a-z_]') { $user = "u$user" }
$hostName = ($env:COMPUTERNAME -replace '[^A-Za-z0-9-]', '')
$monitorText = ($monitorLines | ForEach-Object { '"' + $_ + '"' }) -join ' '

$text = @"
# shellcheck shell=bash
# shellcheck disable=SC2034
# Suggested by tools/windows-inventory.ps1 on $(Get-Date -Format 'yyyy-MM-dd'). REVIEW EVERY VALUE.
# Use it as config.local.sh (read after config.sh), or copy the values into config.sh.

USERNAME=$user
HOST_NAME=$hostName
TIMEZONE=$iana
LOCALES=($($locales -join ' '))
LANG_DEFAULT=en_US.UTF-8
KEYMAP=$keymap
KB_LAYOUT=$kbLayout
KB_VARIANT="$kbVariant"
MIRROR_COUNTRIES=$mirrors

INSTALL_DISK_MODEL="$installModel"   # ERASED. Confirm on the ISO with: bash check-config.sh

CPU_VENDOR=$cpuVendor
GPU_DRIVER=$gpuDriver
KERNEL=linux-cachyos
FALLBACK_KERNEL=linux-cachyos-lts

MONITORS=($monitorText)

CORSAIR_KEYBOARD=$corsair
GAMING_MOUSE=$mouse
HEADSETCONTROL=$headset
BLUETOOTH=$bluetooth
HIDE_GPU_AUDIO=yes
UNDERVOLT=no
CO_OFFSETS=()
"@
$path = Join-Path $repo 'config.suggested.sh'
[IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
Section 'Done'
Write-Host "   Wrote $path"
Write-Host '   Next: review it, then rename it to config.local.sh (or copy the values into config.sh).'
