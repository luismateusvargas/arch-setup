#!/bin/sh
# CPU core voltage (SVI2) from the Ryzen SMU PM table, table 0x380905 (Vermeer): float[40] at byte 0xA0.
od -An -tf4 -j 160 -N 4 /sys/kernel/ryzen_smu_drv/pm_table | awk '{printf "%.3f V\n", $1}'
