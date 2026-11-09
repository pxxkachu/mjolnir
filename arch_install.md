# OpenITX — Arch Linux install (AI server + Steam)

**Entry point:** [`README.md`](README.md)

**Goal:** Fresh **Arch Linux only** on the **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 (`/dev/nvme0n1`). Local **GPU AI server** (Ollama over Tailscale) + **Steam** gaming. Desktop: **minimal GNOME (Wayland)**.

Hardware: [`parts.md`](parts.md) · BIOS: [`bios_optimize.md`](bios_optimize.md)

**Confirmed:** OMEN 5090 **fits** OpenITX; **native 12V-2x6** on SF1000. Hostname **`mjolnir`**. This install **wipes the disk**.

**Packages:** prefer **official Arch repo binaries** (`pacman`) for the stack. **`paru-bin`** is installed by default (AUR helper binary PKGBUILD — not building paru from source). Use **`nvidia-open`** (prebuilt modules), not `nvidia-open-dkms`.

**Exception:** Gigabyte **`it87`** has no binary package on Arch — optional `--it87` installs `it87-dkms-git` via paru (local DKMS compile). CoolerControl userspace stays binary from `extra`.

---

## Step-by-step install (follow in order)

You run commands in **two places only**:

| Phase | Where you type | Chroot? |
|-------|----------------|---------|
| **A–C** | Arch **live ISO** terminal (root) | **No** — do **not** run `arch-chroot` yourself |
| **D** | Installed system after reboot (GNOME or TTY as `laika`) | **No** |

The installer calls `arch-chroot` **internally** to configure the new disk and run postinstall. You never enter a chroot shell by hand for the recommended path.

---

### Phase A — Before the live ISO (hardware / USB)

1. In BIOS ([`bios_optimize.md`](bios_optimize.md)): **CSM off**, **Secure Boot off** for first install, boot USB via **F12**.
2. Flash the official [Arch Linux ISO](https://archlinux.org/download/) to a USB stick.
3. Boot the USB on the OpenITX machine (UEFI mode).

---

### Phase B — Live ISO: network, confirm disk, get the repo

You are on the Arch live environment (prompt like `root@archiso ~`).

**B1. Network**

```bash
# Ethernet usually works immediately. Check:
ping -c 3 archlinux.org

# If Wi‑Fi only:
iwctl
# then: station wlan0 connect "SSID"   → exit
ping -c 3 archlinux.org
```

**B2. Confirm the wipe target (990 PRO)**

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN
# Expect something like:  nvme0n1  1.8T  Samsung SSD 990 PRO …  nvme
```

Use **`/dev/nvme0n1`** below only if that matches. Wrong disk = permanent data loss.

**B3. Clone this repo**

```bash
pacman -Sy --noconfirm git
git clone https://github.com/pxxkachu/mjolnir.git /root/mjolnir
cd /root/mjolnir
```

**B4. Optional dry-run (safe — no writes)**

```bash
./scripts/mjolnir-install.sh --disk /dev/nvme0n1 --user laika --confirm-wipe --dry-run
./scripts/mjolnir-postinstall.sh --user laika --dry-run
```

---

### Phase C — Live ISO: run the full installer (wipes the disk)

Still on the live ISO, still in `/root/mjolnir`. **Do not** `arch-chroot` or reboot yet.

```bash
./scripts/mjolnir-install.sh \
  --disk /dev/nvme0n1 \
  --user laika \
  --confirm-wipe
```

Optional flags: `--it87` (DKMS compile), `--fs btrfs`.  
Defaults: hostname `mjolnir`, timezone `America/Chicago`, US mirrors ranked by speed.

**What the script does for you (no action needed):**

1. Ranks fastest US HTTPS mirrors → writes `/etc/pacman.d/mirrorlist`
2. Wipes + partitions the disk (EFI / root / home), formats **ext4**
3. `pacstrap` base system; copies ranked mirrors into the new root
4. **`arch-chroot` automatically** — sets timezone, locale, hostname, creates user `laika`, installs systemd-boot
5. **Still inside that automated chroot** — runs `mjolnir-postinstall.sh` (NVIDIA, GNOME/GDM, Ollama, Steam, Tailscale, paru-bin, fstrim, reflector, …)
6. Copies this repo to `/opt/mjolnir` and links `~/mjolnir` for `laika`

**Passwords (interactive — script pauses here)**

There are **no password flags** on the installer (nothing on the command line). Mid-way through Phase C, after the disk is partitioned and the user account is created, `passwd` runs **inside the automated chroot**. The live ISO terminal will look like this:

```text
==> Set password for laika
New password:
Retype new password:
passwd: password updated successfully
==> Set password for root
New password:
Retype new password:
passwd: password updated successfully
```

| Account | Prompt order | Used for |
|---------|--------------|----------|
| **`laika`** | First | **GDM / GNOME login**, `sudo`, everyday use |
| **`root`** | Second | Recovery / emergency TTY only (`Ctrl+Alt+F3` → user `root`) |

Tips:

- Type each password **twice** when asked (`New` then `Retype`). Nothing is echoed to the screen.
- Pick a strong password for **`laika`** — that is what you use after reboot.
- Remember **`root`** too; you rarely need it if `sudo` works.
- To change later on the installed system: `passwd` (your user) or `sudo passwd root`.

After both passwords succeed, the script continues with bootloader + postinstall (no more password prompts). Wait until you see **`FULL INSTALL COMPLETE`**.

**C1. Unmount and reboot (you run these)**

```bash
umount -R /mnt
reboot
```

**C2. After reboot starts**

1. Remove the USB stick so the machine boots from the **990 PRO** (systemd-boot).
2. You should get **GDM** → log in as **`laika`** with the password you set above (GNOME Wayland).
3. If the screen is black: switch to a TTY with `Ctrl+Alt+F3`, log in as `laika` (or `root` if needed), run `nvidia-smi`, check [`Troubleshooting`](#troubleshooting).

You are **not** in the live ISO anymore. You are **not** in a chroot. This is the real installed system.

---

### Phase D — After first boot (installed system)

Open **Console** (or any terminal) as `laika`.

**D1. Join Tailscale**

```bash
sudo tailscale up
# follow the URL / auth prompt
tailscale ip -4
```

**D2. Bind Ollama to the Tailscale IP**

```bash
TS=$(tailscale ip -4)
sudo systemctl edit ollama
```

In the editor, put:

```ini
[Service]
Environment="OLLAMA_HOST=REPLACE_WITH_TS_IP:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
```

Replace `REPLACE_WITH_TS_IP` with the output of `tailscale ip -4`, then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
curl "http://$(tailscale ip -4):11434/api/tags"
```

**D3. Quick checks**

```bash
nvidia-smi
systemctl status nvidia-persistenced sleep.target fstrim.timer reflector.timer
paru --version
timedatectl   # should show America/Chicago
```

**D4. BIOS fan unlock (not a script)**

Finish the Smart Fan curve for **CPU_FAN** in BIOS — [`bios_optimize.md`](bios_optimize.md). CoolerControl cannot take the header until that unlock is done.

**D5. Optional later (only if CPU_FAN needs it87)**

```bash
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user laika --it87
```

---

### Re-run postinstall only (system already installed)

Use this if the base OS is already up and you only need the stack again. **Not** for first install from USB.

```bash
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user laika
```

---

### Script cheat sheet

| Script | Run from | When |
|--------|----------|------|
| [`mjolnir-install.sh`](scripts/mjolnir-install.sh) | Arch **live ISO** as root | First install only (wipes disk) |
| [`mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) | Called by installer **or** `sudo` on installed system | Stack / re-run / `--it87` |

Both accept `--dry-run` (no disk changes).

---

### Manual install (not recommended)

Only if you are not using `mjolnir-install.sh`: follow the [ArchWiki Installation guide](https://wiki.archlinux.org/title/Installation_guide) with the [disk plan](#disk-plan-full-2-tb-wipe) below, then **after** you have a bootable system (or from an `arch-chroot /mnt` you opened yourself), run:

```bash
# Example if you manually mounted the new system at /mnt:
arch-chroot /mnt
# inside chroot:
/opt/mjolnir/scripts/mjolnir-postinstall.sh --user laika --no-tailscale-up
exit
umount -R /mnt
reboot
```

Prefer the automated Phase A–D path above so you never manage chroot yourself.

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
| zram / chrony / fstrim | generator + timers (weekly TRIM on 990 PRO) |
| Mirrors | `reflector` US HTTPS, **sort rate** → mirrorlist; `reflector.service` + weekly timer |
| Timezone | **`America/Chicago`** (permanent) |

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
