# OpenITX — Arch Linux install (AI server)

**Entry point:** [`README.md`](README.md)

**Goal:** Fresh **Arch Linux only** on the **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 (`/dev/nvme0n1`). Local **GPU AI server** (**llama.cpp** / `llama-server` behind **Caddy** at **`https://ai.lehaus.io`** on Tailscale). Desktop: **minimal GNOME (Wayland)**. Steam/gaming packages are **not** installed for now.

Hardware: [`parts.md`](parts.md) · BIOS: [`bios_optimize.md`](bios_optimize.md)

**Confirmed:** OMEN 5090 **fits** OpenITX; **native 12V-2x6** on SF1000. Hostname **`mjolnir`**. This install **wipes the disk**.

**Packages:** prefer **official Arch repo binaries** (`pacman`) for the stack. **`paru-bin`** is installed by default. Use **`nvidia-open`** (prebuilt modules), not `nvidia-open-dkms`.

**HTTPS (chosen approach):** **`xcaddy-bin`** builds a custom Caddy with the **Porkbun DNS** plugin → **`/usr/local/bin/caddy`** (same as dxp480tp). We do **not** install the stock Arch `caddy` package and do **not** use certbot/lego. Optional **`--it87`**. Skip HTTPS with **`--no-caddy`**.

---

## Step-by-step install (follow in order)

You run commands in **two places only**:

| Phase | Where you type | Chroot? |
|-------|----------------|---------|
| **A–C** | Arch **live ISO** terminal (root) | **No** — do **not** run `arch-chroot` yourself |
| **D** | Installed system after reboot (GNOME or TTY as `laika`) | **No** |

The installer calls `arch-chroot` **internally** to configure the new disk and run postinstall. You never enter a chroot shell by hand for the recommended path.

### What the script does vs what you do

| Done by `mjolnir-install.sh` | You still do (Phases A / C / D) |
|------------------------------|--------------------------------|
| Wipe, partition, pacstrap, bootloader | Flash USB, BIOS boot settings, boot live ISO |
| Firmware, NVIDIA, GNOME/GDM | Set **`laika`** + **`root`** passwords when prompted |
| `llama-cpp` + `ggml-cuda`, xcaddy, Tailscale, nftables, paru | `umount -R /mnt` → `reboot` → remove USB → GDM login |
| Copies repo → `/opt/mjolnir` | **`tailscale up`**, Porkbun **A** for `ai.lehaus.io`, **Porkbun API keys**, restart caddy |
| Enables services (caddy waits for token; llama-server waits for GGUF) | BIOS **Smart Fan** unlock; optional `--it87`; symlink GGUF → start `llama-server` |

One command for the OS stack: `bash scripts/mjolnir-install.sh`. Do **not** also run postinstall on a fresh install. Full human checklist after the script: [Phase D](#phase-d--after-first-boot-you-do-these).

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
chmod +x scripts/*.sh
```

If **`zsh: permission denied`** when running a script: either `chmod +x scripts/*.sh`, or invoke with **`bash scripts/…`** (does not need the execute bit). Real install must be **root** on the live ISO.

**B4. Optional dry-run (safe — no writes)**

```bash
bash scripts/mjolnir-install.sh --dry-run
# (defaults: --disk /dev/nvme0n1 --user laika --confirm-wipe; nests postinstall dry-run)
```

---

### Phase C — Live ISO: run the full installer (wipes the disk)

Still on the live ISO, still in `/root/mjolnir`. **Do not** `arch-chroot` or reboot yet.

**Run one command only** — `mjolnir-install.sh` already runs `mjolnir-postinstall.sh` in chroot. Do **not** run postinstall separately for a fresh install.

```bash
bash scripts/mjolnir-install.sh
```

Defaults: disk `/dev/nvme0n1`, user `laika`, wipe confirmed, hostname `mjolnir`, timezone `America/Chicago`, ext4, US mirrors.  
Optional: `--it87`, `--fs btrfs`, `--skip-postinstall` (base only; then run postinstall later).

**What the script does for you (no action needed):**

1. Ranks fastest US HTTPS mirrors → writes `/etc/pacman.d/mirrorlist`
2. Wipes + partitions the disk (EFI / root / home), formats **ext4**
3. `pacstrap` base + **hardware firmware only** (B850I **Rev 1.0**): `amd-ucode`, `linux-firmware-nvidia`, `linux-firmware-realtek` — **never** meta / intel / mediatek / amdgpu / other
4. **`arch-chroot` automatically** — sets timezone, locale, hostname, creates user `laika`, installs systemd-boot
5. **Still inside that automated chroot** — runs `mjolnir-postinstall.sh` (NVIDIA, GNOME/GDM, **llama-cpp** + **ggml-cuda**, **xcaddy** → `https://ai.lehaus.io`, Tailscale, paru-bin, …)
6. Copies this repo to `/opt/mjolnir` and links `~/mjolnir` for `laika`

**Passwords (interactive — script pauses here)**

There are **no password flags** on the installer (nothing on the command line). Mid-way through Phase C, after locale/user setup, the script runs **`arch-chroot /mnt passwd …` on the live ISO TTY** (not inside the config heredoc — that would block input). The terminal will look like this:

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

**C1. Unmount and reboot (you run these — first steps after `FULL INSTALL COMPLETE`)**

```bash
umount -R /mnt
reboot
```

**C2. After reboot starts**

1. Remove the USB stick so the machine boots from the **990 PRO** (systemd-boot).
2. You should get **GDM** → log in as **`laika`** with the password you set above (GNOME Wayland).
3. If the screen is black: switch to a TTY with `Ctrl+Alt+F3`, log in as `laika` (or `root` if needed), run `nvidia-smi`, check [`Troubleshooting`](#troubleshooting).
4. Continue with **[Phase D](#phase-d--after-first-boot-you-do-these)** — Tailscale, Porkbun DNS, API keys, checks, BIOS fan unlock.

You are **not** in the live ISO anymore. You are **not** in a chroot. This is the real installed system. The OS stack is already installed; Phase D is only the remaining hand-finished items.

---

### Phase D — After first boot (you do these)

Open **Console** (or any terminal) as `laika`. These steps are **not** automated — the installer prints the same list at `FULL INSTALL COMPLETE`.

**llama-server** listens on **`127.0.0.1:8080` only** (OpenAI-compatible `/v1`). Clients use **`https://ai.lehaus.io`** on the tailnet. TLS is terminated by **xcaddy-built Caddy** (Porkbun DNS-01, same as dxp480tp). **nftables** drops WAN inbound and allows **`tailscale0`** (+ loopback). Architecture: [HTTPS: ai.lehaus.io (xcaddy)](#https-ailehausio-xcaddy).

**Checklist (do in order)**

| # | Step | Done when |
|---|------|-----------|
| D1 | Join Tailscale | `tailscale ip -4` shows `100.x` |
| D2 | Porkbun DNS `ai` → that IP | Record resolves to Tailscale IP |
| D3 | Porkbun API key + secret (API Access enabled for `lehaus.io`) | Keys saved |
| D4 | Set keys in `/var/lib/caddy/porkbun.env`, restart caddy | Caddy active (cert OK) |
| D5 | Drop a GGUF + start `llama-server` | `curl https://ai.lehaus.io/v1/models` OK |
| D6 | Verify GPU / services | `nvidia-smi` + units healthy |
| D7 | BIOS Smart Fan unlock for **CPU_FAN** | CoolerControl can drive the header |
| D8 | Optional: `--it87` if PWM still stuck | `it87` loaded / fans move |

---

**D1. Join Tailscale**

```bash
sudo tailscale up
# follow the URL / auth prompt in the browser
tailscale ip -4
# note this 100.x.x.x address — needed for DNS next
```

(Installer uses `--no-tailscale-up` in chroot, so this never ran during Phase C.)

**D2. Point `ai.lehaus.io` at this machine (Porkbun DNS)**

Same as dxp480tp DNS step — in [Porkbun](https://porkbun.com/) for **`lehaus.io`**:

| Type | Host | Answer | TTL |
|------|------|--------|-----|
| A | `ai` | output of `tailscale ip -4` | 600 |

Optional AAAA with `tailscale ip -6`. Confirm: `getent hosts ai.lehaus.io` → Tailscale IP.

**D3. Enable Porkbun API access**

1. Porkbun → **Details** for `lehaus.io` → enable **API Access**
2. **Account** → **API Access** → create a key (e.g. `caddy-mjolnir`)
3. Save **API key** + **secret key**

**D4. Give xcaddy-Caddy the Porkbun keys and start HTTPS**

Same layout as **dxp480tp** (`/var/lib/caddy` + xcaddy custom binary — not stock Arch `caddy`):

```bash
# Confirm xcaddy binary (not /usr/bin/caddy):
/usr/local/bin/caddy version
/usr/local/bin/caddy list-modules | grep -i porkbun
systemctl cat caddy | grep -E 'ExecStart=|EnvironmentFile='
# expect: ExecStart=/usr/local/bin/caddy run --environ --config /var/lib/caddy/Caddyfile
# expect: EnvironmentFile=/var/lib/caddy/porkbun.env

sudoedit /var/lib/caddy/porkbun.env
# PORKBUN_API_KEY=pk1_...
# PORKBUN_SECRET_API_KEY=sk1_...
# file owned by caddy, mode 600

sudo systemctl daemon-reload
sudo systemctl restart caddy
sudo systemctl status caddy --no-pager
ss -tlnp | grep caddy
```

If cert/TLS fails: wait for DNS to propagate, re-check Porkbun A record, `journalctl -u caddy -e`.  
Rebuild later (as `laika`, not root): `/usr/local/lib/mjolnir/rebuild-caddy.sh`

**D5. GGUF model + start llama-server**

The unit stays inactive until `~/models/active.gguf` exists (`ConditionPathExists`).

```bash
mkdir -p ~/models
# Download a GGUF (Hugging Face, etc.) into ~/models/, then:
ln -sfn ~/models/your-model.Q4_K_M.gguf ~/models/active.gguf
sudo systemctl start llama-server
systemctl status llama-server --no-pager
curl -fsS https://ai.lehaus.io/v1/models
# optional local CLI:
# llama-cli -m ~/models/active.gguf -ngl 99
```

From any other device **on the same Tailscale tailnet** (OpenAI-compatible):

```bash
curl -fsS https://ai.lehaus.io/v1/models
# Point Cursor / Open WebUI / etc. at https://ai.lehaus.io/v1
```

**D6. Quick checks**

```bash
nvidia-smi                                          # RTX 5090; llama-server process when loaded
systemctl status nvidia-persistenced sleep.target \
  NetworkManager bluetooth fstrim.timer caddy nftables tailscaled llama-server --no-pager
/usr/local/bin/caddy version
paru --version
timedatectl                                         # America/Chicago
tailscale status
```

**D7. BIOS Smart Fan unlock (not a script)**

Reboot into BIOS and finish the **CPU_FAN** unlock curve — full table in [`bios_optimize.md`](bios_optimize.md) (Smart Fan 6). Without it, CoolerControl cannot take the AXP90 header (fans may sit ~40 %).

After unlock, in GNOME: open **CoolerControl**, confirm **CPU_FAN** responds; never set CPU fan to 0 %.

**D8. Optional — `it87` if CoolerControl still cannot drive CPU_FAN**

```bash
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user laika --it87
# reboot if the module did not load cleanly, then re-check CoolerControl
```

**Phase D done when:** Tailscale up, `https://ai.lehaus.io/v1/models` works on-tailnet, `nvidia-smi` OK, and (if you care about CPU fan control) BIOS unlock ± `it87` complete.

---

### Re-run postinstall only (system already installed)

Use this **only** if Arch is already installed and you need to re-apply the stack (or add `--it87`). **Not** for first install from USB — the full installer already ran postinstall.

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

## Desktop + stack packages

GNOME Wayland + llama.cpp CUDA + Tailscale/xcaddy + NetworkManager + Bluetooth, plus desktop/ops extras. Not the full `gnome` group; no Steam/Ollama/`fwupd`.

| Package | Role |
|---------|------|
| `nvidia-open` `nvidia-utils` `egl-wayland` `nvidia-settings` | 5090 Wayland + CUDA userspace / persistenced + NVIDIA GUI |
| `gnome-shell` `gdm` | Desktop + login |
| `gnome-control-center` | Settings (displays, BT, network) |
| `gnome-console` `nautilus` `gnome-tweaks` `firefox` | Terminal, Files, Tweaks, browser |
| `gnome-keyring` `xdg-desktop-portal-gnome` `noto-fonts` | Secrets, portals, fonts |
| `pipewire` `pipewire-audio` `pipewire-pulse` `wireplumber` | Audio + Bluetooth audio |
| `networkmanager` | Ethernet / Wi‑Fi (enabled) |
| `bluez` `bluez-utils` | Bluetooth (`bluetooth.service`) |
| `llama-cpp` `ggml-cuda` | `llama-server` + CUDA (pulls `cuda` + `nccl`) |
| `coolercontrol` `lm_sensors` | CPU_FAN curves (BIOS unlock still required) |
| `nvtop` `btop` | GPU / system monitors |
| `openssh` | `sshd` (enabled) |
| `tailscale` `nftables` | Tailnet + inbound firewall (Tailscale-only) |
| `git` `base-devel` | `paru-bin` / `xcaddy-bin` build |

**`nftables`:** front-door lock — strangers dropped; Tailscale peers allowed. Rules: [`config/nftables.conf`](config/nftables.conf).  
**`fwupd`:** not installed — optional LVFS firmware updater.

AI stays headless-capable via `nvidia-persistenced`.

---

## Disk plan (full 2 TB wipe)

| Partition | Size | FS | Mount | Notes |
|-----------|------|-----|-------|-------|
| EFI | **1 GB** | FAT32 | `/boot` | **systemd-boot** |
| Root | **100 GB** | **ext4** | `/` | System + packages |
| Home | **remainder (~1.8 TB)** | **ext4** | `/home` | GGUF models (`~/models`) + data |
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
pacman -S nvidia-open nvidia-utils egl-wayland nvidia-settings
```

`nvidia-persistenced` is **not** a separate package — binary + unit come from **`nvidia-utils`**.

`/etc/modprobe.d/nvidia.conf`: `options nvidia_drm modeset=1`

`systemctl enable --now nvidia-persistenced` — headless `llama-server` without GNOME login.

Stock thermals first; if SF1000 trips under LLM: `nvidia-smi -pl 450`. UV TBD — [`bios_optimize.md`](bios_optimize.md).

---

## HTTPS: ai.lehaus.io (xcaddy)

**Decision:** use **xcaddy** + **Porkbun** DNS-01 — same as [`../dxp480tp/post_install.md`](../dxp480tp/post_install.md) §14. Not stock Arch `caddy`; not certbot/lego; not Cloudflare.

| Piece | Value |
|-------|--------|
| Build | As login user: `xcaddy build --with github.com/caddy-dns/porkbun --output /tmp/caddy` → `/usr/local/bin/caddy` (fallback pin **v2.9.1**) |
| Tool | **`xcaddy-bin`** via paru |
| Binary | **`/usr/local/bin/caddy`** — verify: `caddy list-modules \| grep -i porkbun` |
| Unit | [`config/caddy.service`](config/caddy.service) — `AmbientCapabilities=CAP_NET_BIND_SERVICE`; **no** `NoNewPrivileges` |
| Config dir | **`/var/lib/caddy/`** — `Caddyfile` + `porkbun.env` |
| Site | [`config/Caddyfile`](config/Caddyfile) — global `acme_dns porkbun` + `(tailnet)` ACL → `127.0.0.1:8080` |
| Secrets | `/var/lib/caddy/porkbun.env` → `PORKBUN_API_KEY` + `PORKBUN_SECRET_API_KEY` |
| DNS | Porkbun **A** `ai` → Tailscale `100.x` |
| Access | `(tailnet)` snippet + **nftables** (`tailscale0`) |
| Upgrades | `/usr/local/lib/mjolnir/rebuild-caddy.sh` (run as `laika`) |

Why not stock Caddy? HTTP-01 needs public `:80`. Tailscale `100.x` needs DNS-01 → Porkbun plugin → **xcaddy**.

---

## No sleep / GNOME / CoolerControl / Tailscale / llama.cpp

Covered by [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh). Highlights:

| Piece | Notes |
|-------|--------|
| No sleep | logind drop-in + masked sleep targets |
| GNOME | Minimal shell + **GDM** (Wayland) |
| **NetworkManager** | Enabled — Ethernet / Wi‑Fi |
| **Bluetooth** | `bluez` + `bluetooth.service`; GNOME Settings UI |
| **paru-bin** | AUR helper for `xcaddy-bin` |
| **HTTPS** | **xcaddy** → `/usr/local/bin/caddy` → **`https://ai.lehaus.io`** |
| **it87** | Optional `--it87` — DKMS via paru (CoolerControl not preinstalled) |
| Tailscale + nftables | Mesh VPN; inbound on `tailscale0` only |
| **llama.cpp** | `llama-cpp` + `ggml-cuda`; `llama-server` `:8080`; GGUF → `~/models/active.gguf` |
| TRIM | `fstrim.timer` (weekly; no extra package) |
| Timezone | **`America/Chicago`** (set at install) |

### Display (PG32UCDP)

Prefer DisplayPort. Set refresh / VRR in **Settings → Displays**. OLED: blank screen when idle.

### Fans (no case fans)

Open frame — only **AXP90 on CPU_FAN** + GPU axial fans. BIOS unlock for **CPU_FAN** — [`bios_optimize.md`](bios_optimize.md). CoolerControl: CPU package → CPU_FAN; never 0 % CPU fan. GPU: OEM/NVIDIA curve (or CoolerControl NVML).

```bash
# default (repo stack + paru-bin + xcaddy → Caddy w/ Porkbun DNS):
sudo ./scripts/mjolnir-postinstall.sh
# Gigabyte ITE PWM for CPU_FAN (DKMS via paru):
sudo ./scripts/mjolnir-postinstall.sh --it87
# Skip HTTPS front:
sudo ./scripts/mjolnir-postinstall.sh --no-caddy
# Later Caddy upgrades:
/usr/local/lib/mjolnir/rebuild-caddy.sh
```

### Clients on other machines

| Client | Point at |
|--------|----------|
| OpenAI-compatible clients | `https://ai.lehaus.io/v1` (device must be on Tailscale) |
| llama-server WebUI | `https://ai.lehaus.io` (browser on tailnet) |
| curl | `curl https://ai.lehaus.io/v1/models` |

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
| Network | `systemctl status NetworkManager` active; Wi‑Fi/Ethernet in Settings |
| Bluetooth | `systemctl status bluetooth` active; Settings → Bluetooth |
| llama-server GPU | Loaded model shows process in nvidia-smi |
| API locked down | Off-tailnet: **fails**; on tailnet: `curl https://ai.lehaus.io/v1/models` OK |
| xcaddy Caddy | `systemctl status caddy` active; `/var/lib/caddy/Caddyfile`; Porkbun keys in `porkbun.env` |
| TRIM | `systemctl status fstrim.timer` → enabled |
| paru | `paru --version` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No NVIDIA device | `nvidia-open`, modeset, `journalctl -b` |
| GNOME / GDM black screen | Fix NVIDIA DRM; `nvidia-smi` in TTY; try GNOME on Xorg once from GDM gear menu |
| llama-server on CPU only | Confirm `ggml-cuda` installed; `-ngl 99`; persistenced + reboot |
| API reachable from WAN | Check nftables (only `tailscale0`); Porkbun A → Tailscale IP only |
| Caddy cert / TLS fail | Porkbun keys in `/var/lib/caddy/porkbun.env`; DNS A → Tailscale IP; `journalctl -u caddy` |
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
| [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) | Automated post-install (stack + paru-bin + Caddy) |
| [`config/Caddyfile`](config/Caddyfile) | `ai.lehaus.io` → llama-server `:8080` |
| [`config/llama-server.service`](config/llama-server.service) | systemd unit for `llama-server` |
| [`config/caddy.service`](config/caddy.service) | systemd unit for xcaddy binary |
| [`config/nftables.conf`](config/nftables.conf) | Tailscale-only inbound filter |
