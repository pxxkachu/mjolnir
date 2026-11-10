# Mjolnir (OpenITX) — Arch install guide

Single guide for the OpenITX AI / desktop box (**hostname `mjolnir`**, user **`laika`**): live-ISO base install, then copy-paste post-install.

**Hardware:** Gigabyte B850I Rev 1.0 · 9800X3D · RTX 5090 · Samsung 990 PRO 2 TB — [`parts.md`](parts.md) · BIOS [`bios_optimize.md`](bios_optimize.md)

**Stack:** minimal GNOME (Wayland) · **Ghostty** (+ nautilus) · `llama-cpp` + `ggml-cuda` · `llama-server` · xcaddy + **Porkbun** → `https://ai.lehaus.io` · Tailscale · nftables · NetworkManager · Bluetooth · CoolerControl · Firefox / Files / Tweaks · monitors · OpenSSH

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

The installer creates EFI + root + home (ext4), installs **base** + selective firmware (`amd-ucode`, `linux-firmware-nvidia`, `linux-firmware-realtek`), NetworkManager, systemd-boot, and copies this repo to **`/opt/mjolnir`**. It does **not** install NVIDIA desktop drivers, GNOME, llama.cpp, or Caddy — that is all below.

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

## 1. System update + base tools

```bash
sudo pacman -Syu --needed git base-devel
```

## 2. NVIDIA (RTX 5090 / Wayland)

```bash
sudo pacman -S --needed nvidia-open nvidia-utils egl-wayland nvidia-settings
```

```bash
echo 'options nvidia_drm modeset=1' | sudo tee /etc/modprobe.d/nvidia.conf
sudo systemctl enable --now nvidia-persistenced.service
sudo mkinitcpio -P
```

(`nvidia-persistenced` is **not** a separate package — it ships in `nvidia-utils`.)

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

## 4. NetworkManager + Bluetooth + audio

```bash
sudo pacman -S --needed \
  networkmanager \
  bluez bluez-utils \
  pipewire pipewire-audio pipewire-pulse wireplumber
```

```bash
sudo systemctl enable --now NetworkManager.service bluetooth.service
```

## 5. Minimal GNOME (Wayland) + desktop apps

Not the full `gnome` group. **`gnome-console` is not required** by GNOME Shell — use **Ghostty** as the terminal (`extra/ghostty`):

```bash
sudo pacman -S --needed \
  gnome-shell gdm \
  gnome-control-center gnome-keyring \
  xdg-desktop-portal-gnome \
  nautilus gnome-tweaks firefox noto-fonts \
  ghostty ghostty-nautilus
```

```bash
sudo systemctl enable gdm.service
sudo systemctl set-default graphical.target
```

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

```bash
sudo pacman -S --needed tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
# follow the URL / auth prompt
tailscale ip -4
```

Note the `100.x` address for DNS in step 12.

## 8. nftables (Tailscale-only inbound)

Drop unsolicited WAN; allow loopback + Tailscale (+ ICMP):

```bash
sudo pacman -S --needed nftables
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
	chain input {
		type filter hook input priority filter; policy drop;

		ct state invalid drop
		ct state established,related accept

		iif "lo" accept

		# Tailscale fabric (Caddy / llama-server clients on the tailnet)
		iifname "tailscale0" accept

		ip protocol icmp accept
		ip6 nexthdr ipv6-icmp accept
	}

	chain forward {
		type filter hook forward priority filter; policy drop;
	}

	chain output {
		type filter hook output priority filter; policy accept;
	}
}
EOF
sudo systemctl enable --now nftables.service
sudo nft list ruleset
```

## 9. llama.cpp (CUDA)

Official Arch packages (pulls large **`cuda`** + **`nccl`** deps — use a fast mirror):

```bash
sudo pacman -S --needed llama-cpp ggml-cuda
```

```bash
mkdir -p ~/models
# Download a GGUF into ~/models/, then symlink as active.gguf (unit start gate)
```

Create the systemd unit (change `laika` if needed):

```bash
sudo tee /etc/systemd/system/llama-server.service >/dev/null <<'EOF'
[Unit]
Description=llama.cpp server (CUDA)
Documentation=https://wiki.archlinux.org/title/Llama.cpp
After=network-online.target nvidia-persistenced.service
Wants=network-online.target
ConditionPathExists=/home/laika/models/active.gguf

[Service]
Type=simple
User=laika
Group=laika
WorkingDirectory=/home/laika
ExecStart=/usr/bin/llama-server --host 127.0.0.1 --port 8080 -ngl 99 -m /home/laika/models/active.gguf
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable llama-server.service
```

Start only after the model symlink exists:

```bash
ln -sfn ~/models/your-model.Q4_K_M.gguf ~/models/active.gguf
sudo systemctl start llama-server
systemctl status llama-server --no-pager
curl -fsS http://127.0.0.1:8080/v1/models
```

## 10. Install paru (AUR helper)

**Run as your normal user — do NOT use sudo for the clone/build:**

```bash
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
paru --version
```

## 11. Build Caddy with xcaddy (Porkbun DNS) — same as dxp480tp

Stock Arch `caddy` does **not** include Porkbun. Build a custom binary — **as your normal user, do NOT use sudo for `xcaddy`**:

```bash
sudo pacman -S --needed go
paru -S --needed xcaddy-bin
```

```bash
rm -f /tmp/caddy
xcaddy build --with github.com/caddy-dns/porkbun --output /tmp/caddy
```

If the latest Caddy release fails to build, pin (dxp480tp fallback):

```bash
xcaddy build v2.9.1 --with github.com/caddy-dns/porkbun --output /tmp/caddy
```

```bash
sudo install -m 755 /tmp/caddy /usr/local/bin/caddy
rm /tmp/caddy
/usr/local/bin/caddy version
/usr/local/bin/caddy list-modules | grep -i porkbun
```

### Pre-create `caddy` user + directories

```bash
sudo useradd --system --home-dir /var/lib/caddy --shell /usr/bin/nologin caddy 2>/dev/null || true
sudo passwd --lock caddy
sudo mkdir -p /var/lib/caddy
sudo chown caddy:caddy /var/lib/caddy
sudo chmod 750 /var/lib/caddy
```

### Porkbun API secrets

1. Porkbun → **Details** for `lehaus.io` → enable **API Access**
2. **Account** → **API Access** → create a key
3. Write the env file (mode 600, owner `caddy`):

```bash
sudo tee /var/lib/caddy/porkbun.env >/dev/null <<'EOF'
PORKBUN_API_KEY=pk1_REPLACE_ME
PORKBUN_SECRET_API_KEY=sk1_REPLACE_ME
EOF
sudo chown caddy:caddy /var/lib/caddy/porkbun.env
sudo chmod 600 /var/lib/caddy/porkbun.env
sudo nano /var/lib/caddy/porkbun.env   # paste real keys
```

### Caddyfile

```bash
sudo tee /var/lib/caddy/Caddyfile >/dev/null <<'EOF'
{
	email admin@lehaus.io
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

ai.lehaus.io {
	import tailnet
	encode gzip
	reverse_proxy 127.0.0.1:8080
}
EOF
sudo chown caddy:caddy /var/lib/caddy/Caddyfile
sudo chmod 640 /var/lib/caddy/Caddyfile
```

### systemd unit (dxp480tp-style — **no** `NoNewPrivileges`)

```bash
sudo tee /etc/systemd/system/caddy.service >/dev/null <<'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
Environment=HOME=/var/lib/caddy
Environment=XDG_CONFIG_HOME=/var/lib/caddy
EnvironmentFile=/var/lib/caddy/porkbun.env
ExecStart=/usr/local/bin/caddy run --environ --config /var/lib/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /var/lib/caddy/Caddyfile --force
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
sudo systemctl enable --now caddy
systemctl status caddy --no-pager
ss -tlnp | grep caddy
```

### Rebuild Caddy later

```bash
# as laika (not root for xcaddy):
rm -f /tmp/caddy
xcaddy build --with github.com/caddy-dns/porkbun --output /tmp/caddy \
  || xcaddy build v2.9.1 --with github.com/caddy-dns/porkbun --output /tmp/caddy
sudo install -m 755 /tmp/caddy /usr/local/bin/caddy
rm -f /tmp/caddy
sudo systemctl restart caddy
```

## 12. Porkbun DNS for `ai.lehaus.io`

| Type | Host | Answer | TTL |
|------|------|--------|-----|
| A | `ai` | output of `tailscale ip -4` | 600 |

Optional AAAA with `tailscale ip -6`.

```bash
getent hosts ai.lehaus.io
curl -fsS https://ai.lehaus.io/v1/models
```

From another device on the same Tailscale tailnet:

```bash
curl -fsS https://ai.lehaus.io/v1/models
# OpenAI-compatible base URL: https://ai.lehaus.io/v1
```

## 13. Reboot into GNOME (recommended once)

```bash
sudo reboot
```

GDM → log in as **`laika`** → GNOME Wayland. Check:

```bash
echo $XDG_SESSION_TYPE    # wayland
nvidia-smi
systemctl status nvidia-persistenced NetworkManager bluetooth \
  tailscaled nftables caddy llama-server coolercontrold sshd --no-pager
```

## 14. Optional — `it87` (only if CoolerControl cannot drive CPU_FAN)

Skip unless step 6 left fans stuck after BIOS unlock.

```bash
sudo pacman -S --needed linux-headers dkms
paru -S --needed it87-dkms-git
echo it87 | sudo tee /etc/modules-load.d/it87.conf
echo 'options it87 mmio=on' | sudo tee /etc/modprobe.d/it87.conf
sudo modprobe it87 || sudo modprobe it87 ignore_resource_conflict=1
sudo systemctl restart coolercontrold.service
```

---

## Verification checklist

| Check | Command / expectation |
|-------|------------------------|
| GPU | `nvidia-smi` → RTX 5090 |
| Persistenced | `systemctl status nvidia-persistenced` |
| No sleep | `systemctl status sleep.target` → masked |
| Wayland | `echo $XDG_SESSION_TYPE` → `wayland` |
| Tailscale | `tailscale status` |
| nftables | `sudo nft list ruleset` includes `tailscale0` |
| llama-server | `curl http://127.0.0.1:8080/v1/models` |
| HTTPS | `curl https://ai.lehaus.io/v1/models` on-tailnet |
| Caddy binary | `caddy list-modules \| grep porkbun`; `ExecStart=/usr/local/bin/caddy` |
| TRIM | `systemctl status fstrim.timer` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No NVIDIA / black GDM | `nvidia-open`, modeset, `journalctl -b`; TTY `Ctrl+Alt+F3` |
| llama-server inactive | Need `~/models/active.gguf` symlink; `journalctl -u llama-server` |
| llama on CPU only | Confirm `ggml-cuda`; `-ngl 99` in unit; persistenced |
| Caddy cert fail | Porkbun keys in `/var/lib/caddy/porkbun.env`; DNS A → Tailscale IP; `journalctl -u caddy` |
| Caddy won't bind 443 | Ensure unit has `AmbientCapabilities=CAP_NET_BIND_SERVICE` and **no** `NoNewPrivileges` |
| API from WAN | Expected blocked by nftables; use Tailscale |
| Fans stuck ~40 % | BIOS Smart Fan unlock + CoolerControl; optional `it87` |

---

## Related docs

| File | Purpose |
|------|---------|
| [`install.sh`](install.sh) | Base Arch wipe + install (live ISO) |
| [`parts.md`](parts.md) | Hardware / stack source of truth |
| [`bios_optimize.md`](bios_optimize.md) | BIOS + fan unlock |

Config files (nftables, Caddyfile, units) are created inline in the steps above — nothing under `config/`.
