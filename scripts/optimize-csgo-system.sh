#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"

echo "[1/4] Adding user '${TARGET_USER}' to the 'gamemode' group..."
sudo usermod -aG gamemode "${TARGET_USER}"

echo "[2/4] Writing /etc/gamemode.ini with AMD GPU optimizations..."
sudo tee /etc/gamemode.ini >/dev/null <<'EOF'
[general]
reaper_freq=5
desiredgov=performance
igpu_desiredgov=performance
igpu_power_threshold=-1
softrealtime=auto
renice=10
ioprio=0
inhibit_screensaver=1
disable_splitlock=1

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
amd_performance_level=high
EOF

echo "[3/4] Setting vm.swappiness=10 (live and persistent)..."
sudo sysctl -w vm.swappiness=10
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null

echo "[4/4] Setting AMD iGPU performance level to 'high' for current session..."
if [ -w /sys/class/drm/card0/device/power_dpm_force_performance_level ] || sudo test -w /sys/class/drm/card0/device/power_dpm_force_performance_level; then
    echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level >/dev/null
    echo "AMD GPU performance level is now: $(cat /sys/class/drm/card0/device/power_dpm_force_performance_level)"
fi

echo "Done! System optimizations applied successfully."
