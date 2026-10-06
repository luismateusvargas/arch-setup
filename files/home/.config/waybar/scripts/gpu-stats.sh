#!/bin/bash
# GPU stats for every waybar instance (one bar per monitor), written to one file.
# Run by gpu-stats.service; each bar's custom/gpu module just cats the file below.
#   NVIDIA: nvidia-smi stays resident in loop mode, so NVML is initialised once, not every 2 s.
#   AMD:    amdgpu exposes everything in sysfs; reading it costs nothing (no processes per tick).
out=$XDG_RUNTIME_DIR/waybar-gpu.json

# emit <load %> <VRAM used MiB> <temp °C> <core MHz> <VRAM MHz>
emit() {
    local vram=$(( $2 * 10 / 1024 )) class=normal   # GiB in tenths, integer math only
    if   (( $3 >= 80 )); then class=critical
    elif (( $3 >= 70 )); then class=warning
    fi
    printf '{"text":"GPU %s%% %d.%dG %s°C","tooltip":"GPU clock: %s MHz\\nVRAM clock: %s MHz","class":"%s"}\n' \
        "$1" $((vram / 10)) $((vram % 10)) "$3" "$4" "$5" "$class" > "$out.tmp"
    mv "$out.tmp" "$out"            # atomic swap, so a bar never reads a half-written file
}

if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu,clocks.gr,clocks.mem \
               --format=csv,noheader,nounits -lms 2000 |
    while IFS=', ' read -r load vused temp gclk mclk; do
        emit "$load" "$vused" "$temp" "$gclk" "$mclk"
    done
    exit
fi

for dev in /sys/class/drm/card[0-9]*/device; do
    [[ -r $dev/gpu_busy_percent ]] && break
done
[[ -r $dev/gpu_busy_percent ]] || { echo "gpu-stats: no NVIDIA or amdgpu GPU found" >&2; exit 0; }
hw=$(echo "$dev"/hwmon/hwmon*)

# Plain `read` from sysfs: no process per value. Missing files (older cards) read as 0.
while :; do
    read -r load 2>/dev/null < "$dev/gpu_busy_percent"   || load=0
    read -r vram 2>/dev/null < "$dev/mem_info_vram_used" || vram=0   # bytes
    read -r temp 2>/dev/null < "$hw/temp1_input"         || temp=0   # millidegrees, edge sensor
    read -r gclk 2>/dev/null < "$hw/freq1_input"         || gclk=0   # Hz
    read -r mclk 2>/dev/null < "$hw/freq2_input"         || mclk=0   # Hz
    emit "$load" $(( vram / 1048576 )) $(( temp / 1000 )) $(( gclk / 1000000 )) $(( mclk / 1000000 ))
    sleep 2
done
