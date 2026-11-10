# Mjolnir (OpenITX) — Arch install guide

Single guide for the OpenITX AI / desktop box (**hostname `mjolnir`**, user **`laika`**): live-ISO base install, then copy-paste post-install.

**Hardware:** Gigabyte B850I Rev 1.0 · 9800X3D · RTX 5090 · Samsung 990 PRO 2 TB — [`parts.md`](parts.md) · BIOS [`bios_optimize.md`](bios_optimize.md)

**Stack:** minimal GNOME (Wayland) · **Ghostty** (+ nautilus) · Extension Manager · `llama-cpp` + `ggml-cuda` · `llama-server` · Caddy (download API + **Porkbun**) → `https://ai.lehaus.io` · Tailscale · NetworkManager · Bluetooth · CoolerControl · Firefox / Files / Tweaks · monitors · OpenSSH

| Phase | Where | What |
|-------|--------|------|
| A | Live ISO | [`install.sh`](install.sh) — wipe disk, base Arch, bootloader |
| B | Installed system | Sections below — packages + configs (copy-paste) |

---

## Installation — run from the git repo (Arch live ISO)

Run these steps on the **official Arch Linux live ISO** (UEFI boot, networking required). The script **wipes the disk you select**.

### Before you start

1. **BIOS:** CSM off, Secure Boot off for first install, boot USB via **F12** — [`bios_optimize.md`](bios_optimize.md).
2. **Network:** Ethernet preferred — verify with `ping -c 3 archlinux.org`.
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

### What the installer prompts for

| Prompt | Default / example |
|--------|-------------------|
| OS disk | Prefer `/dev/nvme0n1` (990 PRO) |
| EFI size | `1G` |
| Root size GiB | `100` (home uses the remainder) |
| Hostname | `mjolnir` |
| Username | `laika` |
| Timezone | `America/Chicago` |
| Locale | `en_US.UTF-8` |
| Passwords | `laika`, then `root` |
| Confirmation | type `ERASE` |

The installer creates EFI + root + home (ext4), installs **base** + selective firmware (`amd-ucode`, `linux-firmware-nvidia`, `linux-firmware-realtek`), NetworkManager, systemd-boot (**timeout 0** — no OS menu; boot stays **verbose** so you can spot warnings), and copies this repo to **`/opt/mjolnir`**. It does **not** install NVIDIA desktop drivers, GNOME, llama.cpp, or Caddy — that is all below.

When it finishes: remove the USB, reboot, log in as **`laika`** on a TTY, then continue with **Post-install**.

---

## Post-install

Steps below run **after** the first successful boot into the installed system (TTY as `laika`). Repo path: **`/opt/mjolnir`** (also `~/mjolnir`).

Copy-paste each block in order. Adjust only if your username is not `laika`.

## Pre-flight

```bash
ping -c 3 archlinux.org
timedatectl   # America/Chicago
ls /opt/mjolnir
```

**SSH from Ghostty (macOS / another Arch box)** — same fix as dxp480tp. If `sudo` fails with `ncurses: … $TERM="xterm-ghostty"`:

```bash
# add to ~/.bashrc on mjolnir (and re-source)
[[ "$TERM" == xterm-ghostty ]] && export TERM=xterm-256color
```

One-shot: `sudo TERM=xterm-256color pacman -S …`

## 1. System update + base tools + mirrors

```bash
sudo pacman -Syu --needed git base-devel reflector pacman-contrib
```

Keep mirrors fresh (dxp/parts practice — US HTTPS by rate):

```bash
sudo tee /etc/xdg/reflector/reflector.conf >/dev/null <<'EOF'
--save /etc/pacman.d/mirrorlist
--country US
--protocol https
--latest 20
--sort rate
--age 12
EOF
sudo systemctl enable --now reflector.timer
sudo systemctl start reflector.service
```

Trim old package caches automatically (Reddit must-have — CUDA/llama updates are huge):

```bash
sudo systemctl enable --now paccache.timer
systemctl status paccache.timer --no-pager
```

## 2. NVIDIA (RTX 5090 / Wayland)

**Reddit / Arch Wiki (2025–26):** Blackwell needs **`nvidia-open`** (not closed `nvidia`). Arch `nvidia-utils` already defaults `modeset=1` + `fbdev=1` since ~560 — we still set modeset explicitly and load modules early for GDM/Wayland reliability ([r/archlinux RTX 5090](https://www.reddit.com/r/archlinux/comments/1imrvj7/anyone_get_a_rtx_5090_5080_to_work/), [ArchWiki NVIDIA](https://wiki.archlinux.org/title/NVIDIA)).

```bash
sudo pacman -S --needed nvidia-open nvidia-utils egl-wayland nvidia-settings
```

```bash
echo 'options nvidia_drm modeset=1' | sudo tee /etc/modprobe.d/nvidia.conf
# Early KMS → less flicker; GDM sees DRM sooner (breaks hibernation — we mask sleep anyway)
# Prefer empty MODULES=() from a fresh install; this replaces the MODULES= line only.
sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
grep '^MODULES=' /etc/mkinitcpio.conf
# enable only — --now often fails on first TTY before modules are loaded / reboot
sudo systemctl enable nvidia-persistenced.service
sudo mkinitcpio -P
```

(`nvidia-persistenced` ships in `nvidia-utils` — useful for CUDA/llama cold-start latency on always-on boxes.)

**Reboot once here** (or after §5) before expecting a working GPU session:

```bash
# after reboot:
cat /sys/module/nvidia_drm/parameters/modeset   # expect Y
cat /sys/module/nvidia_drm/parameters/fbdev     # expect Y
nvidia-smi
systemctl status nvidia-persistenced --no-pager
```

If GDM only offers Xorg after NVIDIA is in: optional last-resort `sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules` then reboot (only if needed — modern Arch often works without it).

## 3. Disable sleep (always-on AI box)

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/no-sleep.conf >/dev/null <<'EOF'
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl restart systemd-logind.service
```

## 4. Bluetooth + audio

NetworkManager is already installed and enabled by `install.sh`. Add Bluetooth + PipeWire:

```bash
sudo pacman -S --needed \
  bluez bluez-utils \
  pipewire pipewire-audio pipewire-pulse wireplumber
```


```bash
sudo systemctl enable --now NetworkManager.service bluetooth.service
```

## 5. Minimal GNOME (Wayland) + desktop apps

Not the full `gnome` group. **`gnome-console` is not required** by GNOME Shell — use **Ghostty** as the terminal (`extra/ghostty`). **Extension Manager** (`extra/extension-manager`) installs/manages extensions from extensions.gnome.org without a browser bridge.

```bash
sudo pacman -S --needed \
  gnome-shell gdm \
  gnome-control-center gnome-keyring seahorse \
  xdg-desktop-portal-gnome xdg-user-dirs \
  nautilus gnome-tweaks extension-manager \
  firefox noto-fonts noto-fonts-emoji \
  ghostty ghostty-nautilus
```

```bash
xdg-user-dirs-update   # Desktop / Downloads / … (as laika)
sudo systemctl enable gdm.service
sudo systemctl set-default graphical.target
```

### Fast boot + GDM autologin (verbose until clean)

Goal: **no OS picker**, **no password**, straight into GNOME as **`laika`** — but keep the boot **verbose** so kernel/systemd warnings are visible. Only silence later if a few boots look clean. Physical access = unlocked desktop (fine for a one-user always-on box).

**Already set by `install.sh`:** systemd-boot `timeout 0` (hold a key at POST for the menu), `console-mode keep`. Kernel line stays **without** `quiet` on purpose.

```bash
# Clear any EFI overrides that could re-enable the boot menu
sudo bootctl set-timeout ""
sudo bootctl set-default ""

# Confirm: timeout 0, and options line has NO quiet/loglevel silencing
cat /boot/loader/loader.conf
cat /boot/loader/entries/arch.conf

# Do not block boot waiting on network (NM still starts; just no wait-online)
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

# GDM → auto Wayland session as laika (no greeter password)
sudo tee /etc/gdm/custom.conf >/dev/null <<'EOF'
[daemon]
AutomaticLogin=laika
AutomaticLoginEnable=True
# WaylandEnable=false   # keep commented — Wayland is default
EOF

sudo tee /var/lib/AccountsService/users/laika >/dev/null <<'EOF'
[User]
Language=
Session=gnome
XSession=gnome
SystemAccount=false
EOF
```

BIOS: **Full Screen LOGO Show = Disabled** ([`bios_optimize.md`](bios_optimize.md)). After reboot, watch the scroll for warnings, then:

```bash
journalctl -b -p warning..alert --no-pager
systemd-analyze
systemd-analyze blame | head
```

**Optional — silence only after a clean boot** (no unexpected warnings above). Edit the `options` line in `/boot/loader/entries/arch.conf` and append:

```text
quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0
```

Keep `nvidia_drm.modeset=1`. Skip Plymouth (splash cost, no speed win). To un-silence later, remove those tokens and reboot.

### Firefox fonts (Wayland + PG32UCDP OLED)

Native `extra/firefox` (not Flatpak/Snap) so it reads GNOME font settings. On Arch + Wayland, Reddit’s recurring blur is almost always **fractional scaling** and/or wrong AA for OLED—not missing fonts.

After first GNOME login:

```bash
# OLED: grayscale AA (subpixel/rgba assumes LCD RGB stripes — fringes on WOLED)
gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
```

If the display uses **fractional scale** (125% / 150% / 175%) and Firefox text/UI looks soft or “shimmering” after Firefox ≥146:

1. Open `about:config`
2. Set **`widget.wayland.fractional-scale.enabled`** → **`false`**
3. Restart Firefox

That toggle is the fix repeatedly confirmed on r/firefox / r/archlinux for blurry Wayland Firefox under fractional scaling ([thread](https://www.reddit.com/r/firefox/comments/1pj2vfd/firefox_1460_wayland_fractional_scaling_support/)). Prefer **100% or 200%** integer scale when possible on 4K OLED for the sharpest result.

## 6. CoolerControl + monitors + OpenSSH

```bash
sudo pacman -S --needed coolercontrol lm_sensors nvtop btop openssh
sudo systemctl enable --now coolercontrold.service sshd.service
yes | sudo sensors-detect --auto >/dev/null 2>&1 || true
```

BIOS **Smart Fan** unlock for **CPU_FAN** is still required first — [`bios_optimize.md`](bios_optimize.md).

### About `it87` — do you need it?

**What it is:** Linux kernel driver for Gigabyte’s **ITE Super I/O** chip (often IT8689). It exposes motherboard fan headers (e.g. **CPU_FAN**) as hwmon PWM so CoolerControl can drive them from the OS.

**Recommended?** **Not by default.** Order of operations:

1. Set the BIOS Smart Fan **unlock** curve on **CPU_FAN** (required either way).
2. Reboot into Arch, open CoolerControl — if **CPU_FAN** responds, you’re done; **skip `it87`**.
3. Install `it87` only if the header stays stuck (~40 %) and CoolerControl cannot take control after unlock.

`it87` is DKMS (compiles against your kernel) — see optional step 14.

## 7. Tailscale

Join the tailnet; DNS for `ai.lehaus.io` uses this machine's Tailscale IP. Caddy binds that IP after a static env file + wait-gate (step 10).

```bash
sudo pacman -S --needed tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
# follow the URL / auth prompt
tailscale ip -4
```

Note the `100.x` address for Porkbun DNS (step 11) and for the static `tailscale.env` in step 10. Do **not** port-forward LAN/WAN to 443/22 — clients use Tailscale.


## 8. llama.cpp (CUDA)

Official Arch packages (pulls large **`cuda`** + **`nccl`** deps — use a fast mirror):

```bash
sudo pacman -S --needed llama-cpp ggml-cuda python-huggingface-hub
```

API key first (defense in depth — Reddit/r/LocalLLaMA: Tailscale ≠ auth). `llama-server` reads **`LLAMA_API_KEY`** from the environment — do **not** put the key on `ExecStart` (shows in `ps`).

```bash
mkdir -p ~/.config ~/models
# subshell keeps umask from sticking in your interactive shell
( umask 077
  echo "LLAMA_API_KEY=$(openssl rand -hex 32)" > ~/.config/llama-server.env
)
chmod 600 ~/.config/llama-server.env
# show once for your password manager:
grep LLAMA_API_KEY ~/.config/llama-server.env
```

**User systemd unit — on demand (not always-on).** Install the unit but **do not** `enable` it, so nothing loads the model at boot. Linger only starts your **user systemd manager** so `systemctl --user` works over SSH/Tailscale without a GUI session — it does **not** auto-start llama.

```bash
mkdir -p ~/.config/systemd/user
tee ~/.config/systemd/user/llama-server.service >/dev/null <<'EOF'
[Unit]
Description=llama.cpp server (CUDA)
Documentation=https://wiki.archlinux.org/title/Llama.cpp
After=network-online.target
Wants=network-online.target
ConditionPathExists=%h/models/active.gguf
ConditionPathExists=%h/.config/llama-server.env

[Service]
Type=simple
WorkingDirectory=%h
EnvironmentFile=%h/.config/llama-server.env
# LLAMA_API_KEY from EnvironmentFile (native llama-server env) — not argv
ExecStart=/usr/bin/llama-server --host 127.0.0.1 --port 8080 -ngl 99 -m %h/models/active.gguf
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
# large GGUFs can take minutes to map into VRAM
TimeoutStartSec=0

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
# Do NOT enable — on-demand only. (If you previously enabled it: systemctl --user disable llama-server)
sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger   # expect Linger=yes
```

Download a GGUF (example is a small Q4 for first bring-up — swap repo/file for your production model), then gate the unit with `active.gguf`:

```bash
MODEL_FILE=Qwen2.5-7B-Instruct-Q4_K_M.gguf
# Example ~4–5 GB smoke-test model; replace with your preferred GGUF when ready
hf download bartowski/Qwen2.5-7B-Instruct-GGUF \
  "$MODEL_FILE" \
  --local-dir ~/models

# hf may place the file at ~/models/$MODEL_FILE or nested — resolve before linking
MODEL_PATH="$(find ~/models -type f -name "$MODEL_FILE" | head -n1)"
[[ -n "$MODEL_PATH" ]] || { echo "ERROR: $MODEL_FILE not found under ~/models"; exit 1; }
ln -sfn "$MODEL_PATH" ~/models/active.gguf
ls -l ~/models/active.gguf

# smoke-test once, then stop so VRAM stays free until you need it
systemctl --user start llama-server
systemctl --user status llama-server --no-pager
source ~/.config/llama-server.env
curl -fsS -H "Authorization: Bearer ${LLAMA_API_KEY}" http://127.0.0.1:8080/v1/models
systemctl --user stop llama-server
```

### Start / stop on demand (local or remote)

Caddy can stay up; `https://ai.lehaus.io` returns **502** while llama is stopped.

```bash
# on mjolnir
systemctl --user start llama-server
systemctl --user stop llama-server
systemctl --user restart llama-server
systemctl --user status llama-server
journalctl --user -u llama-server -f
```

From another Tailscale device:

```bash
ssh laika@$(tailscale ip -4) 'systemctl --user start llama-server'
ssh laika@mjolnir 'systemctl --user stop llama-server'   # if MagicDNS / hostname works
```

Optional always-on later: `systemctl --user enable --now llama-server` (linger already set).

To switch models: download GGUF → update `active.gguf` → `systemctl --user restart llama-server` (only needed if it is running).

## 9. Install paru (AUR helper)

**Run as your normal user — do NOT use sudo for the clone/build:**

```bash
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
paru --version
```

## 10. Set up Caddy for HTTPS (`ai.lehaus.io`) — same layout as dxp480tp

Layout matches **dxp480tp**: user/group `caddy`, config + secrets under `/var/lib/caddy`, binary at `/usr/local/bin/caddy`, custom unit (not the Arch `caddy` package).

### Pre-create `caddy` user + directories

Same as dxp480tp — create the account **before** any Caddy package could ship sysusers:

```bash
sudo useradd --system --home-dir /var/lib/caddy --shell /usr/bin/nologin caddy 2>/dev/null || true
sudo passwd --lock caddy
sudo mkdir -p /var/lib/caddy
sudo chown caddy:caddy /var/lib/caddy
sudo chmod 750 /var/lib/caddy
```

### Install Caddy with the Porkbun DNS module

Stock Arch `caddy` does **not** include Porkbun. Prefer a **prebuilt** custom binary from Caddy’s download API (no Go toolchain). Do **not** install the Arch `caddy` package — it conflicts with `/usr/local/bin` and can overwrite a custom binary on upgrade.

```bash
curl -fL --retry 3 --retry-delay 2 -o /tmp/caddy \
  "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fcaddy-dns%2Fporkbun"
# sanity: must be an ELF binary (~40–60 MB), not an HTML error page
file /tmp/caddy | grep -q 'ELF.*executable' || { echo "ERROR: Caddy download was not an ELF binary"; ls -la /tmp/caddy; exit 1; }
chmod +x /tmp/caddy
sudo install -m 755 /tmp/caddy /usr/local/bin/caddy
rm /tmp/caddy
/usr/local/bin/caddy version
/usr/local/bin/caddy list-modules | grep -i porkbun
```

If the download API fails (non-ELF / HTTP error), **fall back to xcaddy** (needs Go; builds can use several GB of `/tmp` and RAM) — install paru in §9 first if you skipped it:

```bash
sudo pacman -S --needed go
paru -S --needed xcaddy-bin
# run as your normal user — do NOT use sudo for xcaddy build
rm -f /tmp/caddy
xcaddy build --with github.com/caddy-dns/porkbun --output /tmp/caddy \
  || xcaddy build v2.9.1 --with github.com/caddy-dns/porkbun --output /tmp/caddy
sudo install -m 755 /tmp/caddy /usr/local/bin/caddy
rm /tmp/caddy
/usr/local/bin/caddy list-modules | grep -i porkbun
```

### Porkbun API secrets

1. Porkbun → **Details** for `lehaus.io` → enable **API Access**
2. **Account** → **API Access** → create a key (e.g. `caddy-lehaus`)
3. Store credentials under `/var/lib/caddy` (not in the Caddyfile), mode 600, owner `caddy`:

```bash
sudo tee /var/lib/caddy/porkbun.env >/dev/null <<'EOF'
PORKBUN_API_KEY=pk1_REPLACE_ME
PORKBUN_SECRET_API_KEY=sk1_REPLACE_ME
EOF
sudo chown caddy:caddy /var/lib/caddy/porkbun.env
sudo chmod 600 /var/lib/caddy/porkbun.env
sudo nano /var/lib/caddy/porkbun.env   # paste real keys
```

### Static Tailscale bind address

Caddy binds **only** to the Tailscale IPv4 (`default_bind {$TS_IP}`). Write **`/var/lib/caddy/tailscale.env` once** — the address rarely changes. Rewrite it only if `tailscale ip -4` ever differs, then `sudo systemctl restart caddy`.

```bash
echo "TS_IP=$(tailscale ip -4)" | sudo tee /var/lib/caddy/tailscale.env >/dev/null
sudo chown caddy:caddy /var/lib/caddy/tailscale.env
sudo chmod 600 /var/lib/caddy/tailscale.env
cat /var/lib/caddy/tailscale.env
```

Optional AAAA later: add `TS_IP6=…` and `default_bind {$TS_IP} {$TS_IP6}`.

### Wait until that IP exists (boot gate)

`tailscaled` can be “active” before `100.x` is on the interface. This oneshot **reads** the static `TS_IP` and blocks until that address appears — it does **not** overwrite the env file. Caddy starts only after the gate succeeds. Keep the `(tailnet)` ACL as defense in depth.

```bash
sudo tee /usr/local/bin/caddy-wait-tailscale-ip >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
envf=/var/lib/caddy/tailscale.env
if [[ ! -f "$envf" ]]; then
  echo "ERROR: missing $envf — write TS_IP=100.x.y.z once before enabling Caddy" >&2
  exit 1
fi
ts_ip="$(grep -E '^TS_IP=' "$envf" | head -n1 | cut -d= -f2- | tr -d '[:space:]')"
if [[ "$ts_ip" != 100.* ]]; then
  echo "ERROR: TS_IP in $envf must be a Tailscale CGNAT address (100.x), got: '${ts_ip:-empty}'" >&2
  exit 1
fi
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$ts_ip"; then
    echo "Tailscale IP $ts_ip is present — Caddy may bind"
    exit 0
  fi
  sleep 1
done
echo "ERROR: $ts_ip not assigned to any interface within 120s" >&2
exit 1
EOF
sudo chmod 755 /usr/local/bin/caddy-wait-tailscale-ip

sudo tee /etc/systemd/system/caddy-wait-tailscale-ip.service >/dev/null <<'EOF'
[Unit]
Description=Wait for static Tailscale IP before Caddy bind
After=network-online.target tailscaled.service
Requires=tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/caddy-wait-tailscale-ip
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
```

### Caddyfile

`default_bind {$TS_IP}` (static env), Porkbun DNS-01, `(tailnet)` ACL on `100.64.0.0/10`, localhost upstream, `(proxy_headers)`. llama-server stays on `127.0.0.1`. Global email is `admin@lehaus.io`.

```bash
sudo tee /var/lib/caddy/Caddyfile >/dev/null <<'EOF'
{
	email admin@lehaus.io
	default_bind {$TS_IP}
	acme_dns porkbun {
		api_key {env.PORKBUN_API_KEY}
		api_secret_key {env.PORKBUN_SECRET_API_KEY}
	}
}

(tailnet) {
	@blocked not remote_ip 100.64.0.0/10
	respond @blocked "Unauthorized" 403
	tls {
		resolvers 1.1.1.1
	}
}

(proxy_headers) {
	header_up Host {host}
	header_up X-Real-IP {remote_host}
}

ai.lehaus.io {
	import tailnet
	encode gzip
	reverse_proxy 127.0.0.1:8080 {
		import proxy_headers
	}
}
EOF
sudo chown caddy:caddy /var/lib/caddy/Caddyfile
sudo chmod 640 /var/lib/caddy/Caddyfile
```

### systemd unit (dxp480tp-aligned — **no** `NoNewPrivileges`)

Requires the wait-gate (so the static `TS_IP` is on an interface before validate/start), Porkbun + Tailscale env, validate-on-start, `Restart=on-abnormal`, `AmbientCapabilities` for port 443.

```bash
sudo tee /etc/systemd/system/caddy.service >/dev/null <<'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network-online.target caddy-wait-tailscale-ip.service
Wants=network-online.target
Requires=caddy-wait-tailscale-ip.service
StartLimitIntervalSec=14400
StartLimitBurst=10

[Service]
Type=notify
User=caddy
Group=caddy
Environment=HOME=/var/lib/caddy
Environment=XDG_CONFIG_HOME=/var/lib/caddy
EnvironmentFile=/var/lib/caddy/porkbun.env
EnvironmentFile=/var/lib/caddy/tailscale.env
ExecStartPre=/usr/local/bin/caddy validate --config /var/lib/caddy/Caddyfile
ExecStart=/usr/local/bin/caddy run --environ --config /var/lib/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /var/lib/caddy/Caddyfile --force
Restart=on-abnormal
TimeoutStopSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/caddy
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable caddy-wait-tailscale-ip.service caddy.service
# Start after Porkbun DNS (step 11) so ACME can issue — or start now and restart after DNS:
# sudo systemctl start caddy   # pulls in wait-gate via Requires=
```

### Upgrade / replace Caddy later

Prefer the download API again (same as install):

```bash
curl -fsSL -o /tmp/caddy \
  "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fcaddy-dns%2Fporkbun"
chmod +x /tmp/caddy
sudo install -m 755 /tmp/caddy /usr/local/bin/caddy
rm /tmp/caddy
sudo systemctl restart caddy
/usr/local/bin/caddy list-modules | grep -i porkbun
```

## 11. Porkbun DNS for `ai.lehaus.io` + start Caddy

| Type | Host | Answer | TTL |
|------|------|--------|-----|
| A | `ai` | output of `tailscale ip -4` | 600 |

Optional AAAA with `tailscale ip -6`.

```bash
getent hosts ai.lehaus.io
sudo systemctl enable --now caddy-wait-tailscale-ip.service caddy.service
systemctl status caddy-wait-tailscale-ip caddy --no-pager
ss -tlnp | grep caddy   # expect 100.x:443 — not *:443
source ~/.config/llama-server.env
curl -fsS -H "Authorization: Bearer ${LLAMA_API_KEY}" https://ai.lehaus.io/v1/models
```

From another device on the same Tailscale tailnet:

```bash
curl -fsS -H "Authorization: Bearer <LLAMA_API_KEY>" https://ai.lehaus.io/v1/models
# OpenAI-compatible base URL: https://ai.lehaus.io/v1
# Clients must send the same Bearer token (llama-server --api-key)
```

## 12. Reboot into GNOME (recommended once)

```bash
sudo reboot
```

GDM → log in as **`laika`** → GNOME Wayland. Check:

```bash
echo $XDG_SESSION_TYPE    # wayland
nvidia-smi
systemctl status nvidia-persistenced NetworkManager bluetooth \
  tailscaled caddy coolercontrold sshd --no-pager
systemctl --user status llama-server --no-pager
```

Optional GPU/thermal watch under load:

```bash
watch -n 1 'nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu --format=csv; echo; sensors'
```

## 13. Optional — Secure Boot (`sbctl`)

Do this **only after** a clean GNOME/NVIDIA boot with Secure Boot still **Disabled**. Wrong order can leave the box unbootable.

1. Reboot → BIOS → put Secure Boot into **Setup Mode** (clear/delete factory keys). Leave Secure Boot **not** enforcing yet if the board separates those options — see [`bios_optimize.md`](bios_optimize.md).
2. Boot Arch, then:

```bash
sudo pacman -S --needed sbctl
sudo sbctl status          # expect Setup Mode / not enrolled
sudo sbctl create-keys
sudo sbctl enroll-keys -m  # -m keeps Microsoft keys (NVIDIA modules / some FW)
sudo sbctl sign -s /boot/vmlinuz-linux
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sudo sbctl verify
```

3. Reboot → BIOS → **enable Secure Boot** → boot Arch → `sbctl status` should show Secure Boot enabled.

`sbctl` installs a pacman hook that re-signs kernels/bootloader on updates.

## 14. Optional — `it87` (only if CoolerControl cannot drive CPU_FAN)

Skip unless step 6 left fans stuck after BIOS unlock. Reddit (Gigabyte B550/B850 + CoolerControl): in-kernel ITE often fails ACPI resource claim — use **`it87-dkms-git`** and, if still unbound, boot with **`acpi_enforce_resources=lax`**.

```bash
sudo pacman -S --needed linux-headers dkms
paru -S --needed it87-dkms-git
echo it87 | sudo tee /etc/modules-load.d/it87.conf
echo 'options it87 mmio=on' | sudo tee /etc/modprobe.d/it87.conf
sudo modprobe it87 || sudo modprobe it87 ignore_resource_conflict=1
sudo systemctl restart coolercontrold.service
```

If the module still will not bind, append to `/boot/loader/entries/arch.conf` `options` line:

```text
acpi_enforce_resources=lax
```

Then reboot and re-check CoolerControl.

---

## Verification checklist

| Check | Command / expectation |
|-------|------------------------|
| GPU | `nvidia-smi` → RTX 5090 |
| Persistenced | `systemctl status nvidia-persistenced` |
| No sleep | `systemctl status sleep.target` → masked |
| Wayland | `echo $XDG_SESSION_TYPE` → `wayland` |
| Autologin (verbose) | Reboot → scroll shows messages → GNOME, no menu/password; `bootctl status` → timeout 0 |
| Boot health | `journalctl -b -p warning..alert`; then `systemd-analyze` |
| Tailscale | `tailscale status` |
| Caddy bind | `ss -tlnp | grep caddy` → listen on `100.x:443` only (not `*:443` / LAN IP) |
| llama on demand | unit **not** enabled; `start` → Bearer curl → `stop`; `Linger=yes` |
| HTTPS | same Bearer header → `https://ai.lehaus.io/v1/models` on-tailnet |
| NVIDIA KMS | `modeset` / `fbdev` both `Y` under `/sys/module/nvidia_drm/parameters/` |
| Reflector | `systemctl status reflector.timer` |
| paccache | `systemctl status paccache.timer` |
| Linger | `loginctl show-user laika -p Linger` → `yes` |
| Caddy binary | `/usr/local/bin/caddy list-modules \| grep porkbun`; unit `ExecStart=/usr/local/bin/caddy`; configs in `/var/lib/caddy` |
| TRIM | `systemctl status fstrim.timer` |
| Secure Boot (if §13) | `sbctl status` → installed + enabled |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No NVIDIA / black GDM | `nvidia-open`, modeset, `journalctl -b`; TTY `Ctrl+Alt+F3` |
| Firefox fonts blurry | Native pacman Firefox; OLED → `font-antialiasing grayscale`; fractional scale → `widget.wayland.fractional-scale.enabled=false` |
| Boot menu still appears | `sudo bootctl set-timeout ""` then confirm `/boot/loader/loader.conf` has `timeout 0` |
| Stuck at GDM / no autologin | Check `/etc/gdm/custom.conf`; TTY `Ctrl+Alt+F3` and comment `AutomaticLogin*` if broken |
| Need messages again after quiet | Remove `quiet`/`loglevel=`/… from `arch.conf` options; reboot |
| llama inactive / 502 from Caddy | Expected when stopped — `systemctl --user start llama-server`; need `active.gguf` + env; `Linger=yes` for remote `--user` |
| llama starts at every boot | `systemctl --user disable llama-server` (on-demand default) |
| llama 401 | Missing/wrong `Authorization: Bearer` (matches `LLAMA_API_KEY` in env file) |
| nvidia-persistenced failed on first enable | Expected before reboot — `systemctl enable` only, then reboot; check `nvidia-smi` |
| Caddy download not ELF | Retry curl, or use xcaddy fallback in §10 |
| CUDA / ggml-cuda crawl | `reflector.service` + fast mirror; expect multi‑GB `cuda` dep |
| llama on CPU only | Confirm `ggml-cuda`; `-ngl 99` in unit; persistenced |
| GDM Xorg only | Confirm modeset=`Y`; optional null `61-gdm.rules`; `echo $XDG_SESSION_TYPE` |
| Caddy cert fail | Porkbun keys in `/var/lib/caddy/porkbun.env`; DNS A → Tailscale IP; `journalctl -u caddy` |
| Caddy won't bind 443 | Ensure unit has `AmbientCapabilities=CAP_NET_BIND_SERVICE` and **no** `NoNewPrivileges` |
| API from WAN / LAN | static `default_bind` TS IP + wait-gate + `(tailnet)` ACL; no port-forward |
| Fans stuck ~40 % | BIOS Smart Fan unlock + CoolerControl; optional §14 `it87` |
| Secure Boot won't boot | Stay in Setup Mode; resign with `sbctl sign -s …`; verify paths under `/boot/EFI` |

---

## Practices audit (Reddit + dxp480tp)

Aligned with current Reddit consensus (r/archlinux, r/LocalLLaMA, r/Tailscale, Gigabyte/CoolerControl threads) and the **dxp480tp** NAS guide:

| Practice | Source | Mjolnir |
|----------|--------|---------|
| Interactive wipe installer + copy-paste post guide | dxp480tp | `install.sh` + this file |
| `nvidia-open` for RTX 50 / Blackwell | r/archlinux | §2 |
| Early NVIDIA modules + modeset (fbdev default in Arch) | ArchWiki / r/archlinux | §2 |
| Minimal GNOME Wayland + GDM (not full `gnome` group) | common Arch | §5 |
| Autologin single-user; verbose boot until clean | this box + Silent boot wiki | §5 |
| Tailscale for private access (not CF Tunnel / WAN open) | r/LocalLLaMA | §7 |
| llama-server on `127.0.0.1` + Caddy reverse proxy | dxp HTTPS-only + Reddit | §8–10 |
| User systemd + linger; **on-demand** start/stop (not enabled at boot) | r/LocalLLaMA + this box | §8 |
| `LLAMA_API_KEY` / Bearer even on tailnet | r/LocalLLaMA | §8 |
| `pacman-contrib` / `paccache.timer` | r/archlinux | §1 |
| `noto-fonts-emoji`, `xdg-user-dirs`, `seahorse` | r/archlinux minimal GNOME | §5 |
| Download-API Caddy + Porkbun DNS-01; `/var/lib/caddy` + `caddy` user; **no** `NoNewPrivileges`; `AmbientCapabilities` | dxp480tp | §10 |
| static `TS_IP` + wait-gate + `default_bind` + `(tailnet)` ACL | dxp480tp | §10 |
| Ghostty `$TERM` sudo fix | dxp480tp | Pre-flight |
| CoolerControl; `it87` + optional `acpi_enforce_resources=lax` | Reddit Gigabyte | §6 / §14 |
| Reflector timer US HTTPS | parts.md / Arch mirrors | §1 |
| Skip Plymouth; optional `quiet` only after clean journal | Silent boot wiki + your choice | §5 |

**Intentionally not copied from dxp** (NAS-only): *arr stack, Plex, Vaultwarden, Btrfs media pool, wildcard `*.lehaus.io`. Mjolnir keeps a single `ai.lehaus.io` host.

**Intentionally skipped (Reddit optional / not a fit):** Plymouth splash; Cloudflare Tunnel; binding llama to `0.0.0.0`; closed `nvidia` driver; forcing `61-gdm.rules` unless Xorg-only GDM.

---

## Related docs

| File | Purpose |
|------|---------|
| [`install.sh`](install.sh) | Base Arch wipe + install (live ISO) |
| [`scripts/pressure-test-install.sh`](scripts/pressure-test-install.sh) | Dry-run / pressure-test (no wipe) |
| [`parts.md`](parts.md) | Hardware / stack source of truth |
| [`bios_optimize.md`](bios_optimize.md) | BIOS + fan unlock |
| dxp480tp / [dxp480t_arch](https://github.com/pxxkachu/dxp480t_arch) | Sibling NAS guide (Caddy/Porkbun/Tailscale pattern source) |

Config files (Caddyfile, units) are created inline in the steps above — nothing under `config/`.
