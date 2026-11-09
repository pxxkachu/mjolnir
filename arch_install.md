# OpenITX — Arch Linux install (AI server + Steam)

**Entry point:** [`README.md`](README.md)

**Goal:** Fresh **Arch Linux only** on the **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 (`/dev/nvme0n1`). Local **GPU AI server** (Ollama over Tailscale) + **Steam** gaming. Desktop: **minimal GNOME (Wayland)**.

Hardware: [`parts.md`](parts.md) · BIOS: [`bios_optimize.md`](bios_optimize.md)

**Confirmed:** OMEN 5090 **fits** OpenITX; **native 12V-2x6** on SF1000. Hostname **`mjolnir`**. This install **wipes the disk**.

**Packages:** prefer **official Arch repo binaries** (`pacman`) for the stack. **`paru-bin`** is installed by default (AUR helper binary PKGBUILD — not building paru from source). Use **`nvidia-open`** (prebuilt modules), not `nvidia-open-dkms`.

**Exception:** Gigabyte **`it87`** has no binary package on Arch — optional `--it87` installs `it87-dkms-git` via paru (local DKMS compile). CoolerControl userspace stays binary from `extra`.

---

## How to run the scripts

| Script | When | Where |
|--------|------|--------|
| [`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh) | **Full wipe + install** | Arch **live ISO** only (root) |
| [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) | Stack only / re-run | Installed system (`sudo`) or nested by the installer |

Both support **`--dry-run`** (prints the plan; no disk writes; no root required).

### Full automated install (recommended)

1. Flash/boot the **Arch Linux ISO** (UEFI, Secure Boot **off**).
2. Connect ethernet (or `iwctl` for Wi‑Fi).
3. Get this repo onto the live environment, then run the installer:

```bash
pacman -Sy --noconfirm git
git clone <your-mjolnir-repo-url> /root/mjolnir   # or: copy USB → /root/mjolnir
cd /root/mjolnir

# Preview (safe):
./scripts/mjolnir-install.sh --disk /dev/nvme0n1 --user YOURUSER --confirm-wipe --dry-run
./scripts/mjolnir-postinstall.sh --user YOURUSER --dry-run

# DANGER: wipes the entire disk
./scripts/mjolnir-install.sh \
  --disk /dev/nvme0n1 \
  --user YOURUSER \
  --confirm-wipe
# optional: --it87   --fs btrfs   --timezone America/Chicago
```

Confirm the target with `lsblk` before `--confirm-wipe` (expect **`/dev/nvme0n1`** for the 990 PRO).

[`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh) does the full path:

1. Zap + GPT (EFI 1 GB · root 100 GiB · home rest) — **ext4** default
2. `pacstrap` base + `systemd-boot` + user/sudo/locale/hostname
3. Runs [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) in chroot (NVIDIA, GNOME/GDM, CoolerControl, Ollama, Steam, Tailscale, paru-bin, no-sleep, fstrim, …)
4. Copies this repo to `/opt/mjolnir` (symlink `~/mjolnir`)

Then: `umount -R /mnt && reboot` → GDM → GNOME → `tailscale up` → rebind Ollama to the Tailscale IP.

### Post-install only (already installed)

```bash
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user YOURUSER
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user YOURUSER --it87   # optional DKMS
```

---

## Desktop: minimal GNOME

Not the full `gnome` meta. Post-install installs only:

| Package | Role |
|---------|------|
| `gnome-shell` | Desktop shell |
| `gdm` | Login manager |
| `gnome-control-center` | **Settings** |
| `gnome-tweaks` | **Tweaks** |
| `gnome-console` | Terminal |
| `nautilus` | **Files** |
| `gnome-keyring` | Secrets / login keyring |
| `xdg-desktop-portal-gnome` | Portals |
| `pipewire` / `wireplumber` | Audio |
| `firefox` | **Firefox** |
| `noto-fonts` | Fonts |
| `nvme-cli` / `smartmontools` | 990 PRO health |
| `nvtop` / `btop` | GPU + system monitors |
| `libva-nvidia-driver` | HW video decode |
| `vulkan-tools` | Vulkan check for Steam |
| `gamemode` | Game performance helper |
| `fwupd` | Firmware updates |

Plus NVIDIA packages for the 5090. AI workloads stay headless-capable via `nvidia-persistenced` (no GUI login required for Ollama).

---

## Disk plan (full 2 TB wipe)

| Partition | Size | FS | Mount | Notes |
|-----------|------|-----|-------|-------|
| EFI | **1 GB** | FAT32 | `/boot` | **systemd-boot** |
| Root | **100 GB** | **ext4** | `/` | System + packages |
| Home | **remainder (~1.8 TB)** | **ext4** | `/home` | Games + Ollama / HF models |
| Swap | **zram** | — | — | `zram-generator` — 96 GB RAM |

Optional: `--fs btrfs`, LUKS later. Extra NAS/disk when `/home` fills.

---

## BIOS before install

| Setting | Value |
|---------|-------|
| **CSM** | Disabled |
| **Secure Boot** | **Disabled** for first install; enable later with **sbctl** |
| **Boot** | USB (Arch ISO) via **F12**, then systemd-boot on 990 PRO |
| **fTPM** | Enabled |
| **SVM / IOMMU** | Disabled |
| **Wake on LAN** | Optional — enable if you remote-power the box |

Full profile + Smart Fan **unlock** curve: [`bios_optimize.md`](bios_optimize.md).

---

## Base install (manual alternative)

Prefer [`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh). Manual steps match [ArchWiki Installation guide](https://wiki.archlinux.org/title/Installation_guide) + the disk plan above, then run `mjolnir-postinstall.sh`. Package/config detail below is what the scripts automate.

---

## NVIDIA (RTX 5090 / Blackwell)

Use repo **`nvidia-open`** (prebuilt for `linux`) — **not** `nvidia-open-dkms`.

```bash
pacman -S nvidia-open nvidia-utils lib32-nvidia-utils egl-wayland nvidia-settings nvidia-persistenced
```

`/etc/modprobe.d/nvidia.conf`: `options nvidia_drm modeset=1`

`systemctl enable --now nvidia-persistenced` — headless Ollama without GNOME login.

Stock thermals first; if SF1000 trips under LLM: `nvidia-smi -pl 450`. UV TBD — [`bios_optimize.md`](bios_optimize.md).

---

## No sleep / GNOME / CoolerControl / Tailscale / Ollama / Steam

Covered by [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh). Highlights:

| Piece | Notes |
|-------|--------|
| No sleep | logind drop-in + masked sleep targets |
| GNOME | Minimal shell + **GDM** (Wayland) |
| CoolerControl | Binary from `extra`; BIOS unlock for CPU_FAN |
| **paru-bin** | Installed by default (AUR helper) |
| **it87** | Optional `--it87` — **only compile step** (DKMS via paru) |
| Tailscale + nftables | Ollama bound to Tailscale IP (or 127.0.0.1 until `tailscale up`) |
| Ollama | `ollama` + `ollama-cuda` from `extra` |
| Steam | `[multilib]` + `steam` |
| zram / chrony / reflector / fstrim | generator + timers (weekly TRIM on 990 PRO) |

### Display (PG32UCDP)

Prefer DisplayPort. Set refresh / VRR in **Settings → Displays**. OLED: blank screen when idle.

### Fans (no case fans)

Open frame — only **AXP90 on CPU_FAN** + GPU axial fans. BIOS unlock for **CPU_FAN** — [`bios_optimize.md`](bios_optimize.md). CoolerControl: CPU package → CPU_FAN; never 0 % CPU fan. GPU: OEM/NVIDIA curve (or CoolerControl NVML).

```bash
# default (repo binaries + paru-bin):
sudo ./scripts/mjolnir-postinstall.sh
# Gigabyte ITE PWM for CPU_FAN (DKMS via paru):
sudo ./scripts/mjolnir-postinstall.sh --it87
```

### Clients on other machines

| Client | Point at |
|--------|----------|
| CLI | `export OLLAMA_HOST=http://mjolnir:11434` |
| Open WebUI / Cursor / Continue | `http://mjolnir:11434` over Tailscale |
| curl | `curl http://mjolnir:11434/api/tags` |

### VRAM (32 GB)

| Class | Fit |
|-------|-----|
| 7B–14B Q4/Q5 | Easy |
| 32B–70B Q4 | Fits with context care |
| Huge FP16 / long context | Quantize or offload |

### Secure Boot (optional)

```bash
pacman -S sbctl
sbctl create-keys && sbctl enroll-keys -m
```

---

## Verification

| Check | How |
|-------|-----|
| GPU | `nvidia-smi` → **RTX 5090** |
| Persistenced | `systemctl status nvidia-persistenced` |
| No sleep | `systemctl status sleep.target` → masked |
| Wayland / GNOME | GDM session · `echo $XDG_SESSION_TYPE` → `wayland` |
| Fans | CoolerControl moves **CPU_FAN** off 40 % unlock (no SYS case fans) |
| Ollama GPU | Model run shows process in nvidia-smi |
| API locked down | From off-tailnet host: connection **fails**; from tailnet: `/api/tags` OK |
| Steam | Proton title launches |
| Chrony | `chronyc tracking` |
| TRIM | `systemctl status fstrim.timer` → enabled |
| paru | `paru --version` |
| Memory | Skip — BIOS profile **already done** |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No NVIDIA device | `nvidia-open`, modeset, `journalctl -b` |
| GNOME / GDM black screen | Fix NVIDIA DRM; `nvidia-smi` in TTY; try GNOME on Xorg once from GDM gear menu |
| Ollama on CPU only | CUDA pkgs + persistenced + reboot |
| API reachable from WAN/LAN | Rebind to Tailscale IP; check nftables |
| PSU trip under LLM | `nvidia-smi -pl 450` (tune); check 12V-2x6 seat |
| Fans stuck ~40 % | `coolercontrold` + `it87`; BIOS unlock curve |
| Suspend broke GPU | Sleep targets should be masked — do not unmask |

---

## Related docs

| Doc | Purpose |
|-----|---------|
| [`README.md`](README.md) | Overview |
| [`parts.md`](parts.md) | Hardware source of truth |
| [`bios_optimize.md`](bios_optimize.md) | BIOS + GPU power / fan unlock |
| [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) | Automated post-install (repo stack + paru-bin) |
