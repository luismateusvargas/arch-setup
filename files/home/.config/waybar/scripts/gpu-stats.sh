#!/bin/bash
# Single nvidia-smi for every waybar instance (one bar per monitor).
# Run by gpu-stats.service; each bar's custom/gpu module just cats the file below.
# nvidia-smi stays resident in loop mode, so NVML is initialised once instead of every 2 s.
out=$XDG_RUNTIME_DIR/waybar-gpu.json

nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu,clocks.gr,clocks.mem \
           --format=csv,noheader,nounits -lms 2000 |
while IFS=', ' read -r load vused temp gclk mclk; do
    vram=$(( vused * 10 / 1024 ))   # GiB in tenths, integer math only
    printf '{"text":"GPU %s%% %d.%dG %s°C","tooltip":"GPU clock: %s MHz\\nVRAM clock: %s MHz"}\n' \
        "$load" $((vram / 10)) $((vram % 10)) "$temp" "$gclk" "$mclk" > "$out.tmp"
    mv "$out.tmp" "$out"            # atomic swap, so a bar never reads a half-written file
done
