# Mjolnir Desktop Setup

Arch Linux install (`install.sh`) and post-install configuration for the Mjolnir gaming workstation. Hardware profile: [`parts.md`](parts.md).

---

## Installation — run from the git repo (Arch live ISO)

Run these steps on the **official Arch Linux live ISO** (UEFI boot, networking required). The script **wipes the disk you select**.

### Before you start

1. **BIOS:** UEFI mode (CSM off), Secure Boot off for the live USB, Above 4G Decoding / Re-Size BAR on.
2. **Network:** Ethernet or Wi‑Fi via `iwctl` — verify with `ping -c 3 archlinux.org`.
3. **Live session:** Open a root shell (you are root on tty1 by default).

### Clone the repo and run `install.sh`

Repo: [github.com/pxxkachu/mjolnir](https://github.com/pxxkachu/mjolnir)

```bash
pacman -Sy --needed git
git clone https://github.com/pxxkachu/mjolnir.git /tmp/mjolnir
cd /tmp/mjolnir
bash install.sh
```

SSH clone (if you use GitHub SSH keys):

```bash
git clone git@github.com:pxxkachu/mjolnir.git /tmp/mjolnir
cd /tmp/mjolnir
bash install.sh
```

**No git network access?** Copy the repo onto a second USB stick, mount it, and run from there:

```bash
mount /dev/sdX1 /mnt/usb    # use lsblk to find the stick
cd /mnt/usb/mjolnir
bash install.sh
```

### What the installer prompts for

| Prompt | Example |
|--------|---------|
| OS disk | Pick the Samsung 990 Pro by number (confirm model + size in the table) |
| Hostname | `mjolnir` |
| Username | your login name |
| Password | root, then your user |
| Confirmation | type `ERASE` to destroy the selected disk |

When it finishes, remove the install medium and reboot. Log in at GDM (GNOME Wayland). Then continue with **Post-install** below (on the installed system, mostly as your normal user).

---

## Post-install

Steps below run **after** the first successful boot into the installed system.

All commands include `sudo` where needed. Section **2** (paru) **must not** use sudo — AUR builds run as your normal user.

---

## Pre-flight checks

Confirm the base install looks correct:

```bash
# Wayland session (should print "wayland")
echo "$XDG_SESSION_TYPE"

# GPU driver (should show "AMD Radeon RX 7900 XT" or similar)
lspci -k | grep -A3 'VGA\|Display'

# Separate /home mounted
findmnt /home

# rEFInd boot config present
test -f /boot/refind_linux.conf && test -f /boot/EFI/refind/refind.conf

# Fonts and audio mixer (installed by install.sh)
pacman -Q ttf-liberation noto-fonts pavucontrol rtkit
```

Update the system before adding more packages:

```bash
sudo pacman -Syu
```

---

## 1. Enable RealtimeKit (PipeWire low latency)

`install.sh` installs **`rtkit`** and enables **`rtkit-daemon`**. RealtimeKit lets PipeWire request real-time CPU priority safely, which reduces crackling when the CPU is under load (gaming).

Confirm the package is installed and the service is enabled and running:

```bash
pacman -Q rtkit
sudo systemctl enable --now rtkit-daemon
systemctl status rtkit-daemon
```

If status shows **active**, PipeWire can use RealtimeKit on demand. The daemon may also start via D-Bus activation when audio first needs it; enabling the unit ensures it is allowed to run at boot.

---

## 2. Install paru (AUR helper)

Builds from source against your installed `pacman` / `libalpm`. `install.sh` already installed `base-devel`, `go`, and `git`.

Avoid **`paru-bin`** on a rolling system: its prebuilt binary is tied to a specific `libalpm.so` soname and can break after a `pacman` upgrade.

**Run as your normal user — do NOT use sudo:**

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru
makepkg -si --noconfirm
cd -
rm -rf /tmp/paru
```

---

## 3. Install and authenticate Tailscale

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Follow the printed authentication link in a browser.

After authenticating, note the assigned IP and MagicDNS name:

```bash
tailscale ip -4
tailscale status
```

Replace placeholders below with your values:

- `<TS_IP>` — Tailscale IPv4 (can change; FQDN is stable)
- `<TS_FQDN>` — e.g. `mjolnir.your-tailnet.ts.net`
- `<HOSTNAME>` — system hostname from install (e.g. `mjolnir`)

### Update `/etc/hosts`

```bash
sudo nano /etc/hosts
```

```text
127.0.0.1   localhost
127.0.1.1   <HOSTNAME>.localdomain <HOSTNAME>

::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters

<TS_IP>     <TS_FQDN> <HOSTNAME>
```

---

## 4. Install gaming stack

Mesa multilib (`mesa`, `lib32-mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`) was installed by `install.sh`.

```bash
sudo pacman -S --needed steam mangohud lib32-mangohud
```

`gamemode`, `lib32-gamemode`, `nvme-cli`, `smartmontools`, and `cpupower` were installed by `install.sh`. Your user was added to the **`gamemode`** group and `/etc/gamemode.ini` was configured for CPU governor + AMD GPU `high` performance level while games run.

Log out and back in once so group membership applies (or reboot after install).

Verify GameMode:

```bash
gamemoded -t
systemctl --user status gamemoded
```

Enable Steam Play for Proton on titles that need it: Steam → Settings → Compatibility → **Enable Steam Play for all other titles**.

Optional launch options for heavy titles (Steam → game → Properties → Launch Options):

```text
gamemoderun %command%
```

Or with an FPS overlay:

```text
gamemoderun mangohud %command%
```

Verify Vulkan (RADV):

```bash
vulkaninfo --summary 2>/dev/null | head -20
```

Per-app volume and output routing: launch **PulseAudio Volume Control** (`pavucontrol`) from the app grid — installed by `install.sh`.

---

## 5. Performance tuning (NVMe, RAM, CPU, GPU)

Summary of what `install.sh` already applied vs optional tweaks below.

### Already configured by `install.sh`

| Area | What | Why |
|------|------|-----|
| **NVMe TRIM** | `fstrim.timer` enabled (weekly) | Preferred over continuous `discard` on ext4 — trims free blocks without write-amp under load |
| **NVMe mounts** | `noatime` on ext4 `/` and `/home` | Fewer metadata writes on SSD |
| **CPU microcode** | `amd-ucode` in rEFInd `refind_linux.conf` | Security + stability fixes for 9800X3D |
| **RAM (maps)** | `vm.max_map_count=1048576` | Required by Steam/Proton and some AAA titles |
| **GameMode** | Package + `/etc/gamemode.ini` + `gamemode` group | Raises CPU governor and GPU power level while games run |
| **Audio RT** | `rtkit` + `rtkit-daemon` | PipeWire low-latency scheduling (see [section 1](#1-enable-realtimekit-pipewire-low-latency)) |
| **Monitoring** | `nvme-cli`, `smartmontools`, `cpupower` | Health checks and governor inspection |

Verify TRIM timer:

```bash
systemctl status fstrim.timer
sudo fstrim -av --dry-run   # preview what weekly trim will do
```

### NVMe (Samsung 990 Pro)

**Do not** add `discard` to fstab — weekly `fstrim` is the intended approach on this install.

Check drive health and temperature:

```bash
sudo smartctl -a /dev/nvme0n1    # adjust device if needed
sudo nvme id-ctrl /dev/nvme0n1 | head -20
sudo nvme smart-log /dev/nvme0n1
```

Optional firmware updates (when Samsung releases them):

```bash
sudo pacman -S fwupd
sudo fwupdmgr refresh
sudo fwupdmgr get-updates
```

**Optional kernel param** — lowers NVMe idle power-state exit latency; slightly higher idle power. Only add if you notice storage latency spikes:

```bash
sudo nano /boot/refind_linux.conf
```

Append to the quoted options on the **Boot Arch Linux** line (before the closing `"`):

```text
 nvme_core.default_ps_max_latency_us=0
```

Then reboot.

**Optional udev rule** — force `none` scheduler on NVMe (usually already default on recent kernels):

```bash
sudo tee /etc/udev/rules.d/60-nvme-scheduler.rules <<'UDEV'
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
UDEV
sudo udevadm control --reload-rules && sudo udevadm trigger
cat /sys/block/nvme0n1/queue/scheduler
```

### RAM (96 GB)

| Tweak | Recommendation |
|-------|----------------|
| **zram** | **Skip** — 96 GB makes compressed RAM swap unnecessary |
| **swap file** | Optional 16 GiB buffer — see [section 6](#6-optional-16-gib-swap-file) |
| **`vm.swappiness`** | Set to `10` only if you create a swap file |
| **`vm.max_map_count`** | Already `1048576` from install |

Confirm:

```bash
sysctl vm.max_map_count
free -h
```

### CPU (Ryzen 7 9800X3D)

Zen 5 uses **`amd-pstate`** in active/EPP mode by default — no manual cpufreq driver setup required.

**Desktop power profile** (when not gaming):

- **Settings → Power → Power Mode** → **Performance** for lowest latency, or **Balanced** for cooler/quieter idle

Inspect governors:

```bash
cpupower frequency-info
cpupower idle-info | head -20
```

GameMode temporarily pushes **`performance`** governor while `gamemoderun` is active (see `/etc/gamemode.ini`).

If you ever see instability from deep C-states (rare on desktop), try disabling **Global C-state Control** in UEFI — only as a last resort.

### GPU (RX 7900 XT / amdgpu + RADV)

Drivers are open-source (`amdgpu`, Mesa RADV) — no proprietary stack needed.

While gaming, GameMode sets `power_dpm_force_performance_level` to **high** (see `gamemoded -t` with a game running).

Check current GPU state:

```bash
cat /sys/class/drm/card*/device/power_dpm_force_performance_level
cat /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | awk '{print $1/1000 " C"}'
```

Optional per-game environment (Steam launch options — usually unnecessary):

```text
RADV_PERFTEST=gpl
```

Optional GUI tuning (AUR):

```bash
paru -S lact
```

Use LACT for fan curves / clocks if the reference blower is too loud — monitor thermals.

### Quick performance checklist

```bash
systemctl is-enabled fstrim.timer          # enabled
grep noatime /etc/fstab                    # ext4 entries
sysctl vm.max_map_count                    # 1048576
gamemoded -t                               # GameMode responds
cpupower frequency-info | grep governor    # schedutil or powersave at idle
echo "$XDG_SESSION_TYPE"                   # wayland
```

---

## 6. Optional: 16 GiB swap file

With 96 GB RAM, swap is not required for normal use. Skip this section unless you want an OOM safety buffer.

```bash
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

Add to fstab:

```bash
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
```

Lower swappiness so swap is only used under real pressure:

```bash
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
```

---

## 7. Timezone

Install used UTC. Set your local timezone:

```bash
timedatectl list-timezones | grep -i america   # or your region
sudo timedatectl set-timezone America/Chicago   # example
```

Or use **Settings → Date & Time** in GNOME.

---

## 8. Display tweaks (ASUS PG32UCDP OLED, 4K)

### Variable refresh rate (VRR)

1. **Settings → Displays** — confirm 4K resolution and expected refresh rate.
2. **Settings → Displays → Variable Refresh Rate** — set to **Always** or **Automatic** (wording varies by GNOME version).
3. Use **DisplayPort** for full bandwidth.
4. Enable the mutter VRR experimental feature (log out and back in after):

```bash
gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"
```

If you also use fractional scaling (below), combine both in one setting:

```bash
gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate', 'scale-monitor-framebuffer']"
```

Verify VRR is active (while a full-screen app runs):

```bash
gnome-monitor-config --help 2>/dev/null || true
# Or check mutter debug logs if troubleshooting
```

### HDR

1. **Settings → Displays** — enable **HDR** if shown for the panel.
2. Some games need HDR enabled in-game separately.

### 4K scaling / fractional scaling

For a 32" 4K panel, try **Settings → Displays → Scale** at **100%** or **125%** depending on preference.

Fractional scaling: **Settings → Displays → Scale** → enable fractional options if offered, or:

```bash
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
```

If VRR is already enabled (see above), use the combined command instead of overwriting it.

Log out and back in after changing scaling experiments.

### OLED burn-in mitigation

Recommended GNOME settings:

- **Settings → Power** — screen blank after 5–10 minutes idle.
- **Settings → Privacy → Screen Lock** — enable lock screen on suspend; adjust automatic screen lock delay.
- Avoid static HUDs at max brightness for hours (consider hiding mangohud when idle).

Optional screensaver:

```bash
sudo pacman -S gnome-screensaver
```

---

## 9. Disable lock screen on resume (optional)

GDM autologin skips the login screen at boot, but suspend may still show a lock screen. To disable automatic lock on suspend:

```bash
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
```

**Security tradeoff:** anyone can wake the machine straight to the desktop. Only use on a trusted physical location.

---

## 10. SSH hardening (optional)

`sshd` is enabled by install. For Tailscale-only access, consider listening on the tailnet interface or using `tailscale serve` / ACLs in the Tailscale admin console.

Basic LAN check:

```bash
systemctl status sshd
ssh localhost
```

---

## 11. Full system update workflow

After paru is installed, keep the system current:

```bash
paru -Syu
```

Or pacman-only for official repos:

```bash
sudo pacman -Syu
```

---

---

## 12. Fan control (CoolerControl)

**Prerequisite:** [`bios_optimize.md` Phase 2](bios_optimize.md#phase-2--fan-control-bios-handoff) — flat Manual BIOS curves on `CPU_FAN`, `SYS_FAN1`, `SYS_FAN2`.

Gigabyte firmware locks fan curves (CPU_FAN @ 70 °C, SYS_FAN1 @ 60 °C). BIOS holds a flat **~40 % PWM** at boot; **CoolerControl** applies real curves in Linux (including **GPU + CPU mix** for bottom intakes).

### 12.1 Install packages

Requires **paru** (§ 2).

```bash
sudo pacman -S --needed lm_sensors
paru -S it87-dkms-git coolercontrol
```

### 12.2 Load `it87` module

```bash
echo 'options it87 ignore_resource_conflict=1' | sudo tee /etc/modprobe.d/it87.conf
echo it87 | sudo tee /etc/modules-load.d/it87.conf
sudo modprobe it87
sudo sensors
```

Look for an **`it86xx`** (or similar) entry with **`fan1`–`fan3`** and **`pwm1`–`pwm3`**. If `modprobe` fails, see [it87 issues](https://github.com/frankcrawford/it87/issues) and [Arch lm_sensors — Gigabyte](https://wiki.archlinux.org/title/Lm_sensors#Gigabyte_motherboards).

Reboot (full **shutdown** preferred on Gigabyte if PWM ever sticks):

```bash
sudo reboot
```

### 12.3 Map fan headers

List motherboard PWM channels:

```bash
for d in /sys/class/hwmon/hwmon*; do
  [[ -f "$d/name" ]] || continue
  echo "=== $(basename "$d") name=$(cat "$d/name") ==="
  ls "$d"/fan*_input 2>/dev/null
  ls "$d"/pwm* 2>/dev/null
done
```

**Match `pwmN` to physical headers:** power off, unplug one fan at a time, boot to BIOS Smart Fan 6 and note which RPM drops — or watch RPM in `sensors` after boot.

| Header | Physical fan | Notes |
|--------|--------------|-------|
| CPU_FAN | AXP90-X47 | |
| SYS_FAN1 | Noctua A12x15 | fill from your build |
| SYS_FAN2 | Phanteks T30 | fill from your build |

**Temperature sensors for curves:**

| Sensor | `sensors` name | Use |
|--------|----------------|-----|
| CPU | `k10temp` | CPU fan curve |
| GPU | `amdgpu` edge / junction | Case intake mix |

### 12.4 Enable CoolerControl

```bash
sudo systemctl enable --now coolercontrol
```

Open **CoolerControl** from the app menu.

1. Under the **`it87`** / **`it86xx`** device, confirm three **`pwm`** channels.
2. Rename and link each channel to the correct **`fanN`** RPM sensor.

### 12.5 Fan curves

**CPU fan (`CPU_FAN`)** — sensor: **`k10temp`**

| Temp °C | PWM % |
|---------|-------|
| 35 | 25 |
| 50 | 38 |
| 65 | 55 |
| 75 | 75 |
| 85 | 90 |
| 90 | 100 |

**Bottom intakes** — sensor: **Mix (maximum)** of **`k10temp`** + **`amdgpu`** GPU edge or junction. The blower 7900 XT dumps heat into the case while CPU can still be under 60 °C; BIOS cannot see GPU temp.

**Noctua (SYS_FAN1):**

| Temp °C | PWM % |
|---------|-------|
| 35 | 20 |
| 50 | 35 |
| 65 | 50 |
| 75 | 70 |
| 85 | 90 |
| 90 | 100 |

**Phanteks T30 (SYS_FAN2)** — same mix sensor, lower PWM (more airflow per RPM):

| Temp °C | PWM % |
|---------|-------|
| 35 | 18 |
| 50 | 30 |
| 65 | 45 |
| 75 | 62 |
| 85 | 80 |
| 90 | 92 |

**Advanced (each channel):** hysteresis **2–3 °C**; step up **2–3 s**; step down **5–8 s**. Export/back up the CoolerControl profile when done.

### 12.6 Validate

```bash
watch -n 2 sensors
```

Stress test — RPM should change within seconds:

```bash
stress-ng --cpu 8 --timeout 60s
```

Gaming (30 min): CPU ≤ 90 °C, GPU junction ≤ 95 °C. Adjust 75–85 °C PWM points if too loud or too hot.

Confirm Linux owns PWM (replace `hwmonN` / `pwmM` with your paths):

```bash
echo 128 | sudo tee /sys/class/hwmon/hwmonN/pwmM
sensors | grep -i fan
```

### 12.7 Fan control troubleshooting

| Symptom | Fix |
|---------|-----|
| No `it87` / no `pwm*` | `dmesg \| grep it87`; check `/etc/modprobe.d/it87.conf` |
| Fans at ~40 % until login | Expected until `coolercontrol` starts — check `systemctl status coolercontrol` |
| Fans ignore CoolerControl | Recheck BIOS flat curve + **Apply**; full shutdown (not warm reboot) |
| Wrong fan responds | Fix channel mapping in CoolerControl |
| Too loud gaming | Lower 75–85 °C PWM; [`bios_optimize.md` Phase 3](bios_optimize.md#phase-3--cpu-undervolt-9800x3d) CO undervolt |
| Too hot | Raise 65–75 °C points +5–10 %; clean bottom dust filter |

---

## Verification checklist

| Check | Command / action |
|-------|------------------|
| Wayland session | `echo $XDG_SESSION_TYPE` → `wayland` |
| AMD GPU driver | `lspci -k \| grep -A2 VGA` → `Kernel driver in use: amdgpu` |
| Vulkan | `vulkaninfo --summary` runs without `ERROR_INITIALIZATION_FAILED` |
| Audio | `wpctl status` — PipeWire default sink present |
| RealtimeKit | `systemctl status rtkit-daemon` — enabled, active |
| Tailscale | `tailscale status` — connected |
| Steam | Launch Steam, sign in, install a Proton game |
| Autologin | Reboot — lands on desktop without GDM password |
| TRIM | `systemctl status fstrim.timer` — enabled |
| NVMe health | `sudo smartctl -a /dev/nvme0n1` — no critical warnings |
| GameMode | `gamemoded -t` — passes |
| CPU governor (idle) | `cpupower frequency-info` — amd-pstate active |
| mmap limit | `sysctl vm.max_map_count` → `1048576` |

---

## Troubleshooting

### GDM autologin not working

From a TTY (`Ctrl+Alt+F3`):

```bash
sudo cat /etc/gdm/custom.conf
sudo journalctl -u gdm -b --no-pager | tail -40
```

Ensure `AutomaticLogin=` matches your username exactly.

### Wrong session (X11 instead of Wayland)

At login screen, use the session menu → **GNOME** (not GNOME on Xorg). With autologin, confirm:

```bash
echo "$XDG_SESSION_TYPE"
```

Do **not** set `WaylandEnable=false` in `/etc/gdm/custom.conf` on this AMD build.

### Steam / Proton graphics issues

Confirm multilib Mesa is installed:

```bash
pacman -Q mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

Force RADV if another ICD takes priority:

```bash
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.i686.json:/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
```

### Tailscale not starting

```bash
sudo systemctl status tailscaled
sudo journalctl -u tailscaled -b --no-pager | tail -30
```

---

## Next: BIOS & performance tuning

After post-install is stable, follow **[`bios_optimize.md`](bios_optimize.md)** for XMP, CPU/GPU tuning, and **Phase 2 BIOS fan handoff**. Linux fan curves: **§ 12** above. Strategy: [`bios_optimize_plan.md`](bios_optimize_plan.md).

---

## Deferred (install later if needed)

- **Docker / distrobox** — homelab containers
- **Heroic Games Launcher** — `paru -S heroic-games-launcher-bin`
- **Gamescope** — `paru -S gamescope` for per-game compositor/VRR
- **Additional storage / NAS mounts** — TBD in `parts.md`
