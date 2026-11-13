# CS:GO Legacy Linux Optimization Guide (AMD APU / Wayland)

Complete system, compositor, and Source 1 engine configuration to maximize FPS and minimize frame-time variance in **Counter-Strike: Global Offensive (Legacy, AppID 4465480)** on Linux (`AMD Ryzen 5 4600G` with integrated `Radeon Vega 7`, Mesa `RADV`, and `Sway` on Wayland).

## Quick path

1. **Set Steam Launch Options** for CS:GO Legacy (`AppID 4465480`):
   ```bash
   gamemoderun %command% -vulkan -novid -console -nojoy -tickrate 128 +fps_max 0 +exec autoexec.cfg
   ```
2. **Install the engine configurations**:
   ```bash
   cp cfg/autoexec.cfg "/mnt/games/SteamLibrary/steamapps/common/csgo legacy/csgo/cfg/autoexec.cfg"
   cp cfg/video.txt "$HOME/.local/share/Steam/userdata/141885893/4465480/local/cfg/video.txt"
   cp cfg/video.txt "$HOME/.local/share/Steam/userdata/141885893/4465480/local/cfg/videodefaults.txt"
   ```
3. **Apply system and GPU power profile tuning**:
   ```bash
   ./scripts/optimize-csgo-system.sh
   ```
4. **Verify active state**:
   ```bash
   gamemoded -t && cat /sys/class/drm/card0/device/power_dpm_force_performance_level
   ```

## Details

### 1. Architectural Decisions Summary

| Area | Configuration | Technical Reason |
|------|---------------|------------------|
| Graphics API | `-vulkan` (`shaderapivk_client.so` + `libdxvk_d3d9.so`) | Bypasses the legacy `libtogl_client.so` DirectX 9-to-OpenGL translation layer, reducing CPU draw-call overhead and running natively on Mesa `RADV`. |
| Resolution & Aspect Ratio | `1280x960` (`4:3`, fullscreen) | Reduces pixel fill-rate and fragment shader pressure on the integrated Radeon Vega 7 GPU. |
| GPU Clock Management | `amd_performance_level=high` via `/etc/gamemode.ini` | Prevents the Renoir APU from downclocking iGPU shader cores (`auto` DPM) between CPU-bound Source 1 frames. |
| Memory & Swap Pressure | `vm.swappiness=10` + `cl_forcepreload 0` | Because an APU uses system RAM as VRAM, swap traffic directly contends for memory bandwidth and causes frame-time spikes. |
| Material System Threading | `mat_queue_mode 2` in `video.txt` and `autoexec.cfg` | Forces asynchronous multi-threaded material queueing across Ryzen cores instead of defaulting to `-1`. |
| Wayland Compositor | `allow_tearing yes` + `opacity 1.0` for `csgo_linux64` | Enables direct scanout and tearing in Sway on the 144 Hz display (`HDMI-A-1`), eliminating compositor V-Sync input lag. |

### 2. Steam Launch Options Breakdown

```text
gamemoderun %command% -vulkan -novid -console -nojoy -tickrate 128 +fps_max 0 +exec autoexec.cfg
```

- **`gamemoderun %command%`**: Hooks Feral GameMode into the game process lifecycle (` desiredgov=performance`, `amd_performance_level=high`, `ioprio=0`, `renice=10`, `disable_splitlock=1`).
- **`-vulkan`**: Selects `shaderapivk_client.so` instead of OpenGL `libtogl_client.so`.
- **`-nojoy`**: Disables joystick initialization to save memory and input polling overhead.
- **`-tickrate 128`**: Sets local offline/practice servers to 128 tick.
- **Removed legacy Windows flags**: `-nod3d9ex` (Windows DX9Ex only, ignored by `csgo_linux64`) and `-lv` (deprecated low-violence flag).

### 3. Source 1 Engine Variables (`cfg/autoexec.cfg`)

| Cvar | Value | Why It Matters |
|------|-------|----------------|
| `r_dynamic` / `muzzleflash_light` | `0` | Disables real-time dynamic lights from gunfire and utility. Prevents fragment shader and CPU lightmap recalculation spikes during firefights. |
| `cl_forcepreload` | `0` | Avoids loading unused map assets into shared RAM/VRAM, preventing swap thrashing and mid-round stutter. |
| `mat_queue_mode` | `2` | Enforces multi-threaded material rendering queue. |
| `r_drawtracers_firstperson` | `0` | Hides own first-person bullet tracers while keeping enemy tracers visible. |
| `r_eyegloss` / `r_eyemove` | `0` | Removes unnecessary character eye shader passes and bone animations. |
| `snd_mix_async` / `snd_mixahead` | `1` / `0.025` | Moves audio mixing to an asynchronous thread with a 25 ms buffer so sound bursts never block frame rendering. |
| `rate` / `cl_cmdrate` / `cl_updaterate` | `786432` / `128` / `128` | Uncaps network bandwidth and locks client/server update rates for 128-tick servers. |

### 4. Vulkan Adapter Reset Gotcha (`cfg/video.txt`)

When switching `csgo_linux64` from OpenGL (`libtogl`) to `-vulkan` for the first time, DXVK reports the PCIe Vendor and Device IDs in decimal (`VendorID 4098` = `0x1002` AMD, `DeviceID 5686` = `0x1636` Renoir). If `video.txt` does not contain those exact IDs, Source 1 assumes a hardware change occurred and overwrites `video.txt` with `videodefaults.txt` (`1920x1080`, `mat_queue_mode -1`).

Both `video.txt` and `videodefaults.txt` must include `"VendorID" "4098"` and `"DeviceID" "5686"` alongside `"setting.defaultres" "1280"` and `"setting.defaultresheight" "960"` so the resolution persists across launches.

### 5. System & GameMode Configuration (`scripts/optimize-csgo-system.sh`)

- **Polkit Group Membership**: Adds the user to the `gamemode` group (`usermod -aG gamemode <user>`), required by `/usr/share/polkit-1/rules.d/gamemode.rules` to execute `gpuclockctl` and `cpugovctl` without authentication prompts.
- **Root `/etc/gamemode.ini`**: GameMode ignores `[gpu]` directives in user-writable `~/.config/gamemode.ini` files for security. Storing `[gpu]` in `/etc/gamemode.ini` allows `amd_performance_level=high`.
- **Kernel Swappiness (`/etc/sysctl.d/99-swappiness.conf`)**: Lowers `vm.swappiness` from `60` to `10` to prioritize keeping application pages in physical RAM and protect APU memory bandwidth.

## Checklist

- [ ] `gamemoded -t` passes all feature tests without errors.
- [ ] `/sys/class/drm/card0/device/power_dpm_force_performance_level` reports `high` while the game is running.
- [ ] `/proc/sys/vm/swappiness` reports `10`.
- [ ] `video.txt` and `videodefaults.txt` retain `1280x960` (`aspectratiomode 0`) and `mat_queue_mode 2` with `VendorID 4098` / `DeviceID 5686`.
- [ ] Sway config includes `allow_tearing yes` and `opacity 1.0` for `csgo_linux64`.

## Next step

Before launching a competitive match, close background processes that consume shared VRAM/RAM (such as idle browser tabs with Vulkan acceleration or background CLI agents) and verify in the CS:GO console that `>>> CS:GO Legacy autoexec.cfg loaded <<<` appears on startup.
