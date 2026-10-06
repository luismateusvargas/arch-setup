#!/bin/sh
# CPU core voltage (SVI2) from the Ryzen SMU PM table. Only table 0x380905 (Ryzen 5000 "Vermeer")
# is known: float[40] at byte 0xA0. Prints nothing otherwise, which hides the waybar module.
pm=/sys/kernel/ryzen_smu_drv
[ "$(od -An -tx4 "$pm/pm_table_version" 2>/dev/null | tr -d ' ')" = 00380905 ] || exit 0
od -An -tf4 -j 160 -N 4 "$pm/pm_table" | awk '{printf "%.3f V\n", $1}'
