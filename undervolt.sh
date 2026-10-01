#!/usr/bin/env bash
# Stage 3: per-core Curve Optimizer for the Ryzen 7 5800X3D. Guide section 11.
#   ./undervolt.sh install   ryzen_smu driver (AUR) + pbo-curve + systemd units (not enabled)
#   ./undervolt.sh test      apply the offsets once and read them back (reboot clears them)
#   ./undervolt.sh enable    apply at every boot and after resume
#   ./undervolt.sh disable   stop applying them (reboot to return to stock)
#   ./undervolt.sh status    services + current per-core offsets
# Offsets live in files/usr/local/bin/pbo-curve (OFFSETS = [...]).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
FILES="$REPO_DIR/files"

[[ $EUID -ne 0 ]] || die "run as your normal user, not root or sudo"

cmd_install() {
    step "ryzen_smu driver (AUR)"
    warn "Arch has an open AUR malware incident (news 2026-06-12): read the PKGBUILD yay shows you."
    info "Its source must be github.com/amkillam/ryzen_smu and nothing else."
    yay -S --needed ryzen_smu-dkms-git
    echo ryzen_smu | sudo tee /etc/modules-load.d/ryzen_smu.conf >/dev/null
    sudo modprobe ryzen_smu
    [[ -e /sys/kernel/ryzen_smu_drv/version ]] || die "ryzen_smu loaded but /sys/kernel/ryzen_smu_drv is missing"
    ok "ryzen_smu loaded"

    step "pbo-curve + systemd units"
    install_file "$FILES/usr/local/bin/pbo-curve" /usr/local/bin/pbo-curve 755 sudo
    install_file "$FILES/etc/systemd/system/pbo-curve.service" /etc/systemd/system/pbo-curve.service 644 sudo
    install_file "$FILES/etc/systemd/system/pbo-curve-resume.service" /etc/systemd/system/pbo-curve-resume.service 644 sudo
    sudo systemctl daemon-reload
    ok "installed, NOT enabled. Next: ./undervolt.sh test"
}

cmd_test() {
    step "Applying offsets once"
    sudo pbo-curve apply
    sudo pbo-curve list
    cat <<'EOF'

    Stability check before './undervolt.sh enable':
      stress-ng --cpu 16 --cpu-method all --timeout 20m       (full load)
      then use the PC normally for a day                      (CO instability shows at light load)
      journalctl -k | grep -iE 'mce|hardware error'           (any hit: move that core 2-3 steps toward 0)
    A reboot clears the offsets if anything goes wrong.
EOF
}

cmd_enable() {
    sudo systemctl enable --now pbo-curve.service
    sudo systemctl enable pbo-curve-resume.service
    journalctl -b -u pbo-curve.service --no-pager | tail -n 3
    ok "offsets are applied at every boot and after resume"
}

cmd_disable() {
    sudo systemctl disable pbo-curve.service pbo-curve-resume.service
    ok "disabled; reboot to return to stock voltages"
}

cmd_status() {
    systemctl --no-pager status pbo-curve.service pbo-curve-resume.service || true
    sudo pbo-curve list
}

case "${1:-}" in
    install) cmd_install ;;
    test)    cmd_test ;;
    enable)  cmd_enable ;;
    disable) cmd_disable ;;
    status)  cmd_status ;;
    *) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
