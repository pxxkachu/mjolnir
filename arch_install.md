# OpenITX — Arch Linux install (AI server + Steam)

**Entry point:** [`README.md`](README.md)

**Goal:** Fresh **Arch Linux only** on the **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 (`/dev/nvme0n1`). Local **GPU AI server** (**Ollama** behind **Caddy** at **`https://ai.lehaus.io`** on Tailscale) + **Steam** gaming. Desktop: **minimal GNOME (Wayland)**.

Hardware: [`parts.md`](parts.md) · BIOS: [`bios_optimize.md`](bios_optimize.md)

**Confirmed:** OMEN 5090 **fits** OpenITX; **native 12V-2x6** on SF1000. Hostname **`mjolnir`**. This install **wipes the disk**.

**Packages:** prefer **official Arch repo binaries** (`pacman`) for the stack. **`paru-bin`** is installed by default. Use **`nvidia-open`** (prebuilt modules), not `nvidia-open-dkms`.

**HTTPS (chosen approach):** **`xcaddy-bin`** builds a custom Caddy with the **Cloudflare DNS** plugin → **`/usr/local/bin/caddy`**, plus our own **`caddy.service` / sysuser**. We do **not** install the stock Arch `caddy` package and do **not** use certbot/lego. Optional **`--it87`**. Skip HTTPS with **`--no-caddy`**.

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
| Firmware, NVIDIA, GNOME/GDM, Steam pkgs | Set **`laika`** + **`root`** passwords when prompted |
| Ollama (localhost), xcaddy binary + unit, nftables, paru, fstrim, reflector | `umount -R /mnt` → `reboot` → remove USB → GDM login |
| Copies repo → `/opt/mjolnir` | **`tailscale up`**, Cloudflare **A** for `ai.lehaus.io`, **`CF_API_TOKEN`**, restart caddy |
| Enables services (caddy waits for token) | BIOS **Smart Fan** unlock; optional `--it87`; first model / Steam login |

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
5. **Still inside that automated chroot** — runs `mjolnir-postinstall.sh` (NVIDIA, GNOME/GDM, Ollama on localhost, **xcaddy** → `https://ai.lehaus.io`, Tailscale, nftables, paru-bin, fstrim, reflector, …)
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
4. Continue with **[Phase D](#phase-d--after-first-boot-you-do-these)** — Tailscale, Cloudflare DNS, `CF_API_TOKEN`, checks, BIOS fan unlock.

You are **not** in the live ISO anymore. You are **not** in a chroot. This is the real installed system. The OS stack is already installed; Phase D is only the remaining hand-finished items.

---

### Phase D — After first boot (you do these)

Open **Console** (or any terminal) as `laika`. These steps are **not** automated — the installer prints the same list at `FULL INSTALL COMPLETE`.

Ollama listens on **`127.0.0.1:11434` only**. Clients use **`https://ai.lehaus.io`** on the tailnet. TLS is terminated by **xcaddy-built Caddy** (Cloudflare DNS-01). nftables allows inbound only on **`tailscale0`**. Architecture: [HTTPS: ai.lehaus.io (xcaddy)](#https-ailehausio-xcaddy).

**Checklist (do in order)**

| # | Step | Done when |
|---|------|-----------|
| D1 | Join Tailscale | `tailscale ip -4` shows `100.x` |
| D2 | Cloudflare DNS `ai` → that IP (grey cloud) | Record resolves to Tailscale IP |
| D3 | Cloudflare API token with Zone:Read + DNS:Edit | Token created |
| D4 | Set `CF_API_TOKEN` in `/etc/caddy/caddy.env`, restart caddy | `curl https://ai.lehaus.io/api/tags` OK |
| D5 | Verify GPU / services | `nvidia-smi` + units healthy |
| D6 | BIOS Smart Fan unlock for **CPU_FAN** | CoolerControl can drive the header |
| D7 | Optional: `--it87` if PWM still stuck | `it87` loaded / fans move |
| D8 | Optional first-use: pull a model, Steam login | AI + games usable |

---

**D1. Join Tailscale**

```bash
sudo tailscale up
# follow the URL / auth prompt in the browser
tailscale ip -4
# note this 100.x.x.x address — needed for DNS next
```

(Installer uses `--no-tailscale-up` in chroot, so this never ran during Phase C.)

**D2. Point `ai.lehaus.io` at this machine (Cloudflare DNS)**

1. Cloudflare → **lehaus.io** → DNS → Add record:
   - **Type:** `A` (and `AAAA` if you use Tailscale IPv6)
   - **Name:** `ai`
   - **IPv4 / IPv6:** output of `tailscale ip -4` / `tailscale ip -6`
   - **Proxy status:** **DNS only** (grey cloud — **not** proxied / orange cloud)
2. Confirm from this box or another tailnet device: `getent hosts ai.lehaus.io` → Tailscale IP

**D3. Create a Cloudflare API token**

1. https://dash.cloudflare.com/profile/api-tokens → **Create Token**
2. Permissions: **Zone → Zone:Read** + **Zone → DNS:Edit** for zone **`lehaus.io`**
3. Copy the token once (needed in D4)

**D4. Give xcaddy-Caddy the token and start HTTPS**

```bash
# Confirm xcaddy binary (not stock /usr/bin/caddy):
/usr/local/bin/caddy version
systemctl cat caddy | grep ExecStart=
# expect: ExecStart=/usr/local/bin/caddy run ...

sudoedit /etc/caddy/caddy.env
# set exactly one line (mode 600):
#   CF_API_TOKEN=your_token_here

sudo systemctl restart caddy
sudo systemctl status caddy --no-pager
curl -fsS https://ai.lehaus.io/api/tags
```

From any other device **on the same Tailscale tailnet**:

```bash
export OLLAMA_HOST=https://ai.lehaus.io
curl "$OLLAMA_HOST/api/tags"
```

If cert/TLS fails: wait for DNS to propagate, re-check grey-cloud A record, `journalctl -u caddy -e`.

**D5. Quick checks**

```bash
nvidia-smi                                          # RTX 5090
systemctl status nvidia-persistenced sleep.target \
  fstrim.timer reflector.timer caddy nftables tailscaled --no-pager
/usr/local/bin/caddy version
paru --version
timedatectl                                         # America/Chicago
tailscale status
```

**D6. BIOS Smart Fan unlock (not a script)**

Reboot into BIOS and finish the **CPU_FAN** unlock curve — full table in [`bios_optimize.md`](bios_optimize.md) (Smart Fan 6). Without it, CoolerControl cannot take the AXP90 header (fans may sit ~40 %).

After unlock, in GNOME: open **CoolerControl**, confirm **CPU_FAN** responds; never set CPU fan to 0 %.

**D7. Optional — `it87` if CoolerControl still cannot drive CPU_FAN**

```bash
sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user laika --it87
# reboot if the module did not load cleanly, then re-check CoolerControl
```

**D8. Optional first-use**

```bash
# Pull a model (example — pick what fits 32 GB VRAM):
ollama pull llama3.2
ollama run llama3.2

# Steam: launch from app grid → sign in → enable Proton in Settings → Steam Play
```

**Phase D done when:** Tailscale up, `https://ai.lehaus.io/api/tags` works on-tailnet, `nvidia-smi` OK, and (if you care about CPU fan control) BIOS unlock ± `it87` complete.

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

## HTTPS: ai.lehaus.io (xcaddy)

**Decision:** use **xcaddy**, not stock Arch `caddy` and not certbot/lego.

| Piece | Value |
|-------|--------|
| Build tool | **`xcaddy-bin`** (AUR, via paru) |
| Plugins | `github.com/caddy-dns/cloudflare` (DNS-01 for Let’s Encrypt) |
| Binary | **`/usr/local/bin/caddy`** (only Caddy on the system) |
| Unit / user | [`config/caddy.service`](config/caddy.service), [`config/caddy.sysusers`](config/caddy.sysusers), [`config/caddy.tmpfiles`](config/caddy.tmpfiles) |
| Site config | [`config/Caddyfile`](config/Caddyfile) → `ai.lehaus.io` → `127.0.0.1:11434` |
| Secrets | `/etc/caddy/caddy.env` → `CF_API_TOKEN=…` |
| DNS | Cloudflare **A** `ai` → Tailscale `100.x` · **DNS only** (grey cloud) |
| Access | Tailnet only (`nftables` + `tailscale0`) |
| Upgrades | `/usr/local/lib/mjolnir/rebuild-caddy.sh` |

Why not stock Caddy alone? Auto-HTTPS uses HTTP-01 and needs a public `:80`. A Tailscale-only `100.x` name cannot complete that challenge. DNS-01 inside Caddy needs the Cloudflare plugin → **xcaddy**.

---

## No sleep / GNOME / CoolerControl / Tailscale / Ollama / Steam

Covered by [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh). Highlights:

| Piece | Notes |
|-------|--------|
| No sleep | logind drop-in + masked sleep targets |
| GNOME | Minimal shell + **GDM** (Wayland) |
| CoolerControl | Binary from `extra`; BIOS unlock for CPU_FAN |
| **paru-bin** | Installed by default (AUR helper) |
| **HTTPS** | **xcaddy** → `/usr/local/bin/caddy` + our unit → **`https://ai.lehaus.io`** (not stock `caddy`) |
| **it87** | Optional `--it87` — DKMS via paru |
| Tailscale + nftables | Inbound allowed on `tailscale0` only |
| Ollama | `ollama` + `ollama-cuda`; localhost only |
| Steam | `[multilib]` + `steam` |
| zram / chrony / fstrim | generator + timers (weekly TRIM on 990 PRO) |
| Mirrors | `reflector` US HTTPS, **sort rate** → mirrorlist; `reflector.service` + weekly timer |
| Timezone | **`America/Chicago`** (permanent) |

### Display (PG32UCDP)

Prefer DisplayPort. Set refresh / VRR in **Settings → Displays**. OLED: blank screen when idle.

### Fans (no case fans)

Open frame — only **AXP90 on CPU_FAN** + GPU axial fans. BIOS unlock for **CPU_FAN** — [`bios_optimize.md`](bios_optimize.md). CoolerControl: CPU package → CPU_FAN; never 0 % CPU fan. GPU: OEM/NVIDIA curve (or CoolerControl NVML).

```bash
# default (repo stack + paru-bin + xcaddy → Caddy w/ Cloudflare DNS):
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
| CLI | `export OLLAMA_HOST=https://ai.lehaus.io` (device must be on Tailscale) |
| Open WebUI / Cursor / Continue | `https://ai.lehaus.io` |
| curl | `curl https://ai.lehaus.io/api/tags` |

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
| API locked down | Off-tailnet: **fails**; on tailnet: `curl https://ai.lehaus.io/api/tags` OK |
| xcaddy Caddy | `systemctl status caddy` active; `ExecStart=/usr/local/bin/caddy`; cert after `CF_API_TOKEN` |
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
| API reachable from WAN | Check nftables (should only allow `tailscale0`); confirm Cloudflare record is **DNS only** |
| Caddy cert / TLS fail | `CF_API_TOKEN` in `/etc/caddy/caddy.env`; DNS A → Tailscale IP; `journalctl -u caddy` |
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
| [`config/Caddyfile`](config/Caddyfile) | `ai.lehaus.io` → Ollama |
| [`config/caddy.service`](config/caddy.service) | systemd unit for xcaddy binary |
| [`config/nftables.conf`](config/nftables.conf) | Tailscale-only inbound filter |
