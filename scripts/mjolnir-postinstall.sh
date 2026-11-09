#!/usr/bin/env bash
# Mjolnir post-install — official Arch repo packages + paru-bin (AUR helper binary).
# Stack stays pacman binaries; paru is installed by default for optional AUR later.
# Only --it87 triggers a local DKMS compile (it87-dkms-git).
#
#   sudo ./scripts/mjolnir-postinstall.sh
#   sudo ./scripts/mjolnir-postinstall.sh --user alice --it87
#
# Also invoked from mjolnir-install.sh inside arch-chroot (MJOLNIR_CHROOT=1).
# See ../arch_install.md

set -euo pipefail

IT87=0
TAILSCALE_UP=1
DRY_RUN=0
USER_NAME="${SUDO_USER:-}"
IN_CHROOT="${MJOLNIR_CHROOT:-0}"

usage() {
  cat <<'EOF'
Usage: sudo ./mjolnir-postinstall.sh [options]

  --user NAME         Target login user (required in chroot / if not via sudo)
  --it87              Install it87-dkms-git via paru (DKMS compile)
  --no-tailscale-up   Install Tailscale but skip interactive `tailscale up`
  --dry-run           Print the plan; make no changes (no root required)
  -h, --help          Show this help

Default: official repo binaries + paru-bin. Only --it87 compiles a kernel module.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="${2:?}"; shift 2 ;;
    --it87) IT87=1; shift ;;
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
  # NVIDIA
  nvidia-open nvidia-utils lib32-nvidia-utils egl-wayland nvidia-settings
  nvidia-persistenced
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
  # paru-bin needs these to build the AUR PKGBUILD (paru itself is a binary package)
  base-devel
)

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
  echo "DRY-RUN: write ollama.service.d/override.conf (127.0.0.1 or Tailscale IP)"
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

echo "==> Tailscale + nftables"
systemctl enable nftables.service tailscaled.service ollama.service
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl start nftables.service tailscaled.service || true
fi

if [[ "$TAILSCALE_UP" -eq 1 && "$IN_CHROOT" != "1" ]]; then
  echo "==> tailscale up (interactive)"
  sudo -u "$USER_NAME" tailscale up || tailscale up || true
fi

echo "==> Ollama override"
install -d /etc/systemd/system/ollama.service.d
TS_IP=""
if [[ "$IN_CHROOT" != "1" ]]; then
  TS_IP="$(tailscale ip -4 2>/dev/null || true)"
fi
if [[ -n "$TS_IP" ]]; then
  cat >/etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${TS_IP}:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF
  echo "    Bound OLLAMA_HOST=${TS_IP}:11434"
else
  cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
# After: tailscale up && systemctl daemon-reload && systemctl restart ollama
# Prefer: Environment="OLLAMA_HOST=$(tailscale ip -4):11434"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF
  echo "    Ollama on 127.0.0.1 until Tailscale IP is set"
fi
systemctl daemon-reload || true
if [[ "$IN_CHROOT" != "1" ]]; then
  systemctl restart ollama.service || systemctl start ollama.service || true
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
echo "    BIOS Smart Fan unlock still required — bios_optimize.md"
