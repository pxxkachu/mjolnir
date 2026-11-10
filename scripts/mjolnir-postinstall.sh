#!/usr/bin/env bash
# Mjolnir post-install — official Arch repo packages + paru-bin (AUR helper binary).
#
# HTTPS for ai.lehaus.io (chosen approach — do NOT use stock caddy or certbot):
#   1. paru installs xcaddy-bin
#   2. xcaddy build --with github.com/caddy-dns/cloudflare → /usr/local/bin/caddy
#   3. Install our systemd unit/sysuser/tmpfiles from config/caddy.*
#   4. Caddyfile reverse_proxy → Ollama 127.0.0.1:11434; TLS via Cloudflare DNS-01
#
# Only --it87 triggers an extra DKMS compile (it87-dkms-git).
#
#   sudo ./scripts/mjolnir-postinstall.sh
#   sudo ./scripts/mjolnir-postinstall.sh --user laika --it87
#
# Also invoked from mjolnir-install.sh inside arch-chroot (MJOLNIR_CHROOT=1).
# See ../arch_install.md#https-ailehausio-xcaddy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IT87=0
SKIP_CADDY=0
TAILSCALE_UP=1
DRY_RUN=0
USER_NAME="${SUDO_USER:-}"
IN_CHROOT="${MJOLNIR_CHROOT:-0}"
CADDY_DOMAIN="ai.lehaus.io"
CADDY_BIN="/usr/local/bin/caddy"

usage() {
  cat <<'EOF'
Usage: sudo ./mjolnir-postinstall.sh [options]

  --user NAME         Target login user (required in chroot / if not via sudo)
  --it87              Install it87-dkms-git via paru (DKMS compile)
  --no-caddy          Skip xcaddy / ai.lehaus.io HTTPS front
  --no-tailscale-up   Install Tailscale but skip interactive `tailscale up`
  --dry-run           Print the plan; make no changes (no root required)
  -h, --help          Show this help

Default: repo binaries + paru-bin + xcaddy → /usr/local/bin/caddy (Cloudflare DNS)
for https://ai.lehaus.io. No stock caddy package; no certbot/lego.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="${2:?}"; shift 2 ;;
    --it87) IT87=1; shift ;;
    --no-caddy) SKIP_CADDY=1; shift ;;
    --no-tailscale-up) TAILSCALE_UP=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
  fi
  if [[ -z "$USER_NAME" || "$USER_NAME" == root ]]; then
    echo "Pass --user NAME (or run via sudo from that login)." >&2
    exit 1
  fi
  if ! id "$USER_NAME" &>/dev/null; then
    echo "User does not exist: $USER_NAME" >&2
    exit 1
  fi
else
  USER_NAME="${USER_NAME:-dryrun-user}"
  [[ "$USER_NAME" == root ]] && USER_NAME="dryrun-user"
fi

echo "==> Mjolnir post-install (repo packages + paru-bin)$([[ "$DRY_RUN" -eq 1 ]] && echo ' [DRY-RUN]')"
echo "    User: $USER_NAME"
[[ "$IN_CHROOT" == "1" ]] && echo "    (chroot mode — services enabled, not started)"

PKGS=(
  # NVIDIA (nvidia-persistenced binary + unit ship in nvidia-utils — not a separate pkg)
  nvidia-open nvidia-utils lib32-nvidia-utils egl-wayland nvidia-settings
  # Minimal GNOME (not the full `gnome` meta)
  # Settings=gnome-control-center · Files=nautilus · Tweaks=gnome-tweaks
  gnome-shell gdm gnome-control-center gnome-tweaks gnome-console nautilus
  gnome-keyring xdg-desktop-portal-gnome
  pipewire wireplumber
  firefox noto-fonts
  # Hardware utilities (990 PRO / 5090 / 9800X3D / Steam)
  nvme-cli smartmontools nvtop btop
  libva-nvidia-driver vulkan-tools gamemode fwupd
  # Stack
  coolercontrol lm_sensors
  ollama ollama-cuda tailscale nftables
  steam git openssh
  reflector chrony zram-generator
  ethtool
  # paru-bin / makepkg (xcaddy-bin is AUR; go is installed only when building Caddy)
  base-devel
)

install_xcaddy_caddy() {
  echo "==> xcaddy: build Caddy with Cloudflare DNS for https://${CADDY_DOMAIN}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: paru -S xcaddy-bin"
    echo "DRY-RUN: xcaddy build --with github.com/caddy-dns/cloudflare --output ${CADDY_BIN}"
    return 0
  fi
  pacman -S --needed --noconfirm go
  # Prebuilt xcaddy helper (AUR)
  if ! command -v xcaddy >/dev/null; then
    sudo -u "$USER_NAME" paru -S --needed --noconfirm xcaddy-bin
  fi
  local build_dir
  build_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$build_dir'" RETURN
  chmod -R a+rwX "$build_dir"
  # Build as the login user (module cache in homedir)
  sudo -u "$USER_NAME" bash -c "
    set -euo pipefail
    cd '$build_dir'
    xcaddy build --with github.com/caddy-dns/cloudflare --output '$build_dir/caddy'
  "
  install -d /usr/local/bin
  install -m 755 "$build_dir/caddy" "$CADDY_BIN"
  echo "    Installed ${CADDY_BIN} ($("$CADDY_BIN" version 2>/dev/null | head -n1 || true))"
}

install_paru_bin() {
  if command -v paru >/dev/null; then
    echo "==> paru already present"
    return 0
  fi
  echo "==> Installing paru-bin (AUR helper, prebuilt binary)"
  run pacman -S --needed --noconfirm git base-devel
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: clone aur/paru-bin && makepkg -si as ${USER_NAME}"
    return 0
  fi
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  chmod -R a+rwX "$tmp"
  (cd "$tmp/paru-bin" && sudo -u "$USER_NAME" makepkg -si --noconfirm)
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> Would enable [multilib] if needed"
  run pacman -Syu --noconfirm
  echo "==> Would install ${#PKGS[@]} packages:"
  printf '    %s\n' "${PKGS[@]}"
  install_paru_bin
  run install -d /etc/systemd
  echo "DRY-RUN: write /etc/systemd/zram-generator.conf"
  echo "DRY-RUN: write /etc/modprobe.d/nvidia.conf (modeset=1)"
  run systemctl enable nvidia-persistenced.service
  echo "DRY-RUN: write logind no-sleep drop-in + mask sleep targets"
  echo "DRY-RUN: write /etc/xdg/reflector/reflector.conf (US HTTPS, sort rate)"
  echo "DRY-RUN: reflector --country US --sort rate → /etc/pacman.d/mirrorlist"
  run systemctl enable reflector.timer reflector.service fstrim.timer chronyd.service coolercontrold.service gdm.service
  run systemctl enable nftables.service tailscaled.service ollama.service
  echo "DRY-RUN: enable GDM → GNOME Wayland session"
  echo "DRY-RUN: write ollama.service.d/override.conf (OLLAMA_HOST=127.0.0.1:11434)"
  echo "DRY-RUN: install nftables.conf (Tailscale-only input)"
  if [[ "$SKIP_CADDY" -eq 0 ]]; then
    install_xcaddy_caddy
    echo "DRY-RUN: install config/caddy.{service,sysusers,tmpfiles} + Caddyfile"
    run systemctl enable caddy.service
  else
    echo "DRY-RUN: skip xcaddy/Caddy (--no-caddy)"
  fi
  if [[ "$IT87" -eq 1 ]]; then
    echo "DRY-RUN: --it87 would install it87-dkms-git via paru (COMPILE)"
    run pacman -S --needed --noconfirm linux-headers dkms
  else
    echo "DRY-RUN: skip it87"
  fi
  if [[ "$TAILSCALE_UP" -eq 1 && "$IN_CHROOT" != "1" ]]; then
    echo "DRY-RUN: would run tailscale up"
  else
    echo "DRY-RUN: skip interactive tailscale up"
  fi
  echo
  echo "==> DRY-RUN complete (no changes made)"
  exit 0
fi

# --- multilib ---
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  echo "==> Enabling [multilib]"
  sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' /etc/pacman.conf
fi

pacman -Syu --noconfirm

echo "==> Installing packages"
pacman -S --needed --noconfirm "${PKGS[@]}"

install_paru_bin

echo "==> zram-generator"
install -d /etc/systemd
cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
EOF

echo "==> NVIDIA modprobe + persistenced"
install -d /etc/modprobe.d
cat >/etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1
EOF
systemctl enable nvidia-persistenced.service
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl start nvidia-persistenced.service || true
fi
if command -v mkinitcpio >/dev/null; then
  mkinitcpio -P || true
fi

echo "==> Disabling sleep/suspend"
install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/no-sleep.conf <<'EOF'
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl restart systemd-logind.service || true
fi

echo "==> Fastest US mirrors (permanent reflector.conf) + fstrim.timer + chronyd"
install -d /etc/xdg/reflector
# Used by reflector.service / reflector.timer — re-ranks by download rate
cat >/etc/xdg/reflector/reflector.conf <<'EOF'
--save /etc/pacman.d/mirrorlist
--country US
--protocol https
--age 12
--latest 20
--sort rate
EOF
# Rank now (also runs on boot via reflector.service; weekly via timer)
if [[ "$IN_CHROOT" != "1" ]]; then
  reflector \
    --verbose \
    --country US \
    --protocol https \
    --age 12 \
    --latest 20 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist || true
fi
systemctl enable reflector.timer reflector.service fstrim.timer chronyd.service
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl start reflector.timer fstrim.timer chronyd.service || true
fi

echo "==> coolercontrold"
systemctl enable coolercontrold.service
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl start coolercontrold.service || true
  yes | sensors-detect --auto >/dev/null 2>&1 || true
fi

echo "==> GDM → minimal GNOME (Wayland) for user ${USER_NAME}"
systemctl enable gdm.service
systemctl set-default graphical.target || true
# Prefer Wayland session (GNOME default on modern installs)

echo "==> Tailscale + nftables (Tailscale-only inbound)"
if [[ -f "$REPO_ROOT/config/nftables.conf" ]]; then
  install -m 644 "$REPO_ROOT/config/nftables.conf" /etc/nftables.conf
else
  echo "    WARN: missing $REPO_ROOT/config/nftables.conf"
fi
systemctl enable nftables.service tailscaled.service ollama.service
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl start nftables.service tailscaled.service || true
fi

if [[ "$TAILSCALE_UP" -eq 1 && "$IN_CHROOT" != "1" ]]; then
  echo "==> tailscale up (interactive)"
  sudo -u "$USER_NAME" tailscale up || tailscale up || true
fi

echo "==> Ollama on 127.0.0.1:11434 (HTTPS via Caddy → ${CADDY_DOMAIN})"
install -d /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
# Reachable on the tailnet as https://ai.lehaus.io (Caddy). Do not bind :11434 to WAN.
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF
systemctl daemon-reload || true
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl restart ollama.service || systemctl start ollama.service || true
fi

if [[ "$SKIP_CADDY" -eq 0 ]]; then
  install_xcaddy_caddy

  echo "==> Caddy systemd unit + sysuser (no stock caddy package)"
  install -d /etc/caddy /var/lib/caddy /var/log/caddy /usr/lib/sysusers.d /usr/lib/tmpfiles.d
  install -m 644 "$REPO_ROOT/config/caddy.sysusers" /usr/lib/sysusers.d/caddy.conf
  install -m 644 "$REPO_ROOT/config/caddy.tmpfiles" /usr/lib/tmpfiles.d/caddy.conf
  install -m 644 "$REPO_ROOT/config/caddy.service" /etc/systemd/system/caddy.service
  if [[ -f "$REPO_ROOT/config/Caddyfile" ]]; then
    install -m 644 "$REPO_ROOT/config/Caddyfile" /etc/caddy/Caddyfile
  fi
  if [[ ! -f /etc/caddy/caddy.env ]]; then
    if [[ -f "$REPO_ROOT/config/caddy.env.example" ]]; then
      install -m 600 "$REPO_ROOT/config/caddy.env.example" /etc/caddy/caddy.env
    else
      umask 077
      printf 'CF_API_TOKEN=\n' >/etc/caddy/caddy.env
    fi
  fi
  systemd-sysusers caddy.conf || systemd-sysusers || true
  systemd-tmpfiles --create caddy.conf || systemd-tmpfiles --create || true
  chown -R caddy:caddy /var/lib/caddy /var/log/caddy 2>/dev/null || true

  # Rebuild helper for later Caddy upgrades
  install -d /usr/local/lib/mjolnir
  cat >/usr/local/lib/mjolnir/rebuild-caddy.sh <<'REBUILD'
#!/usr/bin/env bash
# Rebuild /usr/local/bin/caddy with Cloudflare DNS (needs xcaddy + go on PATH).
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
xcaddy build --with github.com/caddy-dns/cloudflare --output "$tmp/caddy"
sudo install -m 755 "$tmp/caddy" /usr/local/bin/caddy
sudo systemctl restart caddy
/usr/local/bin/caddy version
REBUILD
  chmod 755 /usr/local/lib/mjolnir/rebuild-caddy.sh

  systemctl daemon-reload || true
  systemctl enable caddy.service
  if [[ "$IN_CHROOT" != "1" ]]; then
    if grep -qE '^CF_API_TOKEN=.+' /etc/caddy/caddy.env 2>/dev/null; then
      systemctl restart caddy.service || systemctl start caddy.service || true
    else
      echo "    CF_API_TOKEN empty — set /etc/caddy/caddy.env then: systemctl start caddy"
    fi
  fi
  echo "    binary: ${CADDY_BIN}  unit: /etc/systemd/system/caddy.service"
  echo "    DNS: A/AAAA ${CADDY_DOMAIN} → \$(tailscale ip -4)  (Cloudflare DNS only, grey cloud)"
  echo "    Rebuild later: /usr/local/lib/mjolnir/rebuild-caddy.sh"
else
  echo "==> Skipping xcaddy/Caddy (--no-caddy)"
fi

if [[ "$IT87" -eq 1 ]]; then
  echo "==> --it87: it87-dkms-git via paru (WILL COMPILE)"
  pacman -S --needed --noconfirm linux-headers dkms
  sudo -u "$USER_NAME" paru -S --needed --noconfirm it87-dkms-git
  install -d /etc/modules-load.d /etc/modprobe.d
  echo it87 >/etc/modules-load.d/it87.conf
  cat >/etc/modprobe.d/it87.conf <<'EOF'
options it87 mmio=on
EOF
  if [[ "$IN_CHROOT" != "1" ]]; then
    modprobe -r it87 2>/dev/null || true
    modprobe it87 || modprobe it87 ignore_resource_conflict=1 || true
    systemctl restart coolercontrold.service || true
  fi
else
  echo "==> Skipping it87. Later: sudo $0 --user $USER_NAME --it87"
fi

echo
echo "==> Post-install complete."
if [[ "$IN_CHROOT" == "1" ]]; then
  echo "    Continue: umount -R /mnt && reboot"
else
  echo "    Reboot recommended. Then: nvidia-smi && tailscale up"
fi
echo "    HTTPS: set CF_API_TOKEN in /etc/caddy/caddy.env → systemctl restart caddy"
echo "    Clients: export OLLAMA_HOST=https://${CADDY_DOMAIN}"
echo "    BIOS Smart Fan unlock still required — bios_optimize.md"
