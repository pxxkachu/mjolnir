#!/usr/bin/env bash
# Mjolnir FULL Arch install — run from the official Arch Linux live ISO (UEFI).
#
# Wipes the target disk, pacstraps Arch, configures systemd-boot + user, then
# runs mjolnir-postinstall.sh (repo binaries + paru-bin) inside the new root.
#
# Example:
#   # Boot Arch ISO, connect network, then:
#   pacman -Sy --noconfirm git
#   git clone https://github.com/pxxkachu/mjolnir.git /root/mjolnir && cd /root/mjolnir
#   chmod +x scripts/*.sh
#   bash scripts/mjolnir-install.sh
#   bash scripts/mjolnir-install.sh --dry-run
#
# Defaults: --disk /dev/nvme0n1 --user laika --confirm-wipe
# Runs mjolnir-postinstall.sh automatically (unless --skip-postinstall).
#
# Options:
#   --it87              Also DKMS-compile Gigabyte it87 (not binary)
#   --fs ext4|btrfs     Root/home filesystem (default: ext4)
#   --hostname NAME     Default: mjolnir
#   --timezone ZONE     Default: America/Chicago
#   --skip-postinstall  Only base + bootloader (run postinstall later)
#   --dry-run           Print the plan; make no changes (no root required)
#
# DANGER: default path wipes /dev/nvme0n1. Use --dry-run to preview.
# See ../arch_install.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POSTINSTALL="$SCRIPT_DIR/mjolnir-postinstall.sh"

DISK="/dev/nvme0n1"
CONFIRM_WIPE=1
USERNAME="laika"
HOSTNAME="mjolnir"
TIMEZONE="America/Chicago"
FS="ext4"
IT87=0
SKIP_POST=0
DRY_RUN=0
ROOT_SIZE_GIB=100
EFI_SIZE="1GiB"

# Firmware for THIS machine only:
#   Gigabyte B850I AORUS PRO Rev 1.0 + Ryzen 7 9800X3D + RTX 5090
# Do NOT install the linux-firmware metapackage (pulls intel/broadcom/atheros/…).
# 9800X3D has no iGPU → no amdgpu/radeon.
# Rev 1.0: Realtek 2.5GbE + Realtek RTL8922AE Wi‑Fi 7 / BT + ALC4080 → realtek only.
FIRMWARE_PKGS=(
  linux-firmware-nvidia
  linux-firmware-realtek
)

usage() {
  cat <<'EOF'
Mjolnir full installer (Arch live ISO → desktop/AI stack)

Defaults (this machine):
  --disk /dev/nvme0n1
  --user laika
  --confirm-wipe        (on — wipes the target disk)
  --hostname mjolnir
  --timezone America/Chicago
  --fs ext4
  --root-size-gib 100
  Post-install: runs automatically (NVIDIA, GNOME, Ollama, xcaddy, …)

Optional:
  --disk /dev/nvmeX     Override target disk
  --user NAME           Override first login user
  --hostname NAME
  --timezone ZONE
  --fs ext4|btrfs
  --root-size-gib N
  --it87                Install it87 via DKMS (compiles)
  --skip-postinstall    Stop after base + bootloader
  --dry-run             Show plan only; no disk writes
  -h, --help

Typical:
  bash scripts/mjolnir-install.sh --dry-run
  bash scripts/mjolnir-install.sh

Do NOT also run mjolnir-postinstall.sh for a fresh install — install runs it.
After reboot: GDM → GNOME → tailscale up → set CF_API_TOKEN → restart caddy.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk) DISK="${2:?}"; shift 2 ;;
    --user) USERNAME="${2:?}"; shift 2 ;;
    --confirm-wipe) CONFIRM_WIPE=1; shift ;;
    --hostname) HOSTNAME="${2:?}"; shift 2 ;;
    --timezone) TIMEZONE="${2:?}"; shift 2 ;;
    --fs) FS="${2:?}"; shift 2 ;;
    --root-size-gib) ROOT_SIZE_GIB="${2:?}"; shift 2 ;;
    --it87) IT87=1; shift ;;
    --skip-postinstall) SKIP_POST=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

[[ -n "$DISK" ]] || die "Missing --disk"
[[ -n "$USERNAME" ]] || die "Missing --user"
[[ "$FS" == "btrfs" || "$FS" == "ext4" ]] || die "--fs must be btrfs or ext4"
[[ -f "$POSTINSTALL" ]] || die "Missing $POSTINSTALL"

if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ "$(id -u)" -eq 0 ]] || die "Run as root from the Arch live ISO"
  [[ "$CONFIRM_WIPE" -eq 1 ]] || die "Refusing to wipe without --confirm-wipe (default is on for this machine)"
  [[ -b "$DISK" ]] || die "Not a block device: $DISK"
  command -v pacstrap >/dev/null || die "pacstrap not found — boot the official Arch ISO"
  [[ -d /sys/firmware/efi ]] || die "UEFI required (CSM off)"
  if [[ -f /etc/mjolnir-installed ]]; then
    die "This looks like an installed Mjolnir system. Use mjolnir-postinstall.sh instead."
  fi
else
  [[ "$CONFIRM_WIPE" -eq 1 ]] || echo "NOTE: dry-run without --confirm-wipe (would be required for real run)"
fi

part_name() {
  local disk="$1" num="$2"
  if [[ "$disk" =~ [0-9]$ ]] || [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

P_EFI="$(part_name "$DISK" 1)"
P_ROOT="$(part_name "$DISK" 2)"
P_HOME="$(part_name "$DISK" 3)"

echo "==> Mjolnir FULL install$([[ "$DRY_RUN" -eq 1 ]] && echo ' [DRY-RUN]')"
echo "    Disk:     $DISK"
echo "    Parts:    $P_EFI (EFI) · $P_ROOT (root) · $P_HOME (home)"
echo "    User:     $USERNAME"
echo "    Hostname: $HOSTNAME"
echo "    Timezone: $TIMEZONE"
echo "    FS:       $FS (EFI ${EFI_SIZE}, root ${ROOT_SIZE_GIB}GiB, home = rest)"
echo "    Mirrors:  reflector --country US --sort rate (saved permanently)"
echo "    Firmware: ${FIRMWARE_PKGS[*]} + amd-ucode (no intel / no linux-firmware meta)"
echo "    Post:     $([[ "$SKIP_POST" -eq 1 ]] && echo skip || echo mjolnir-postinstall.sh)$([[ "$IT87" -eq 1 ]] && echo ' + it87')"
echo "    THIS WILL DESTROY ALL DATA ON $DISK"
[[ "$DRY_RUN" -eq 0 ]] && sleep 2

# Rank HTTPS US mirrors by download rate; same flags as permanent reflector.conf
rank_mirrors() {
  local dest="${1:-/etc/pacman.d/mirrorlist}"
  if ! command -v reflector >/dev/null; then
    pacman -Sy --noconfirm --needed reflector || return 0
  fi
  reflector \
    --verbose \
    --country US \
    --protocol https \
    --age 12 \
    --latest 20 \
    --sort rate \
    --save "$dest"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "==> Planned steps"
  run timedatectl set-ntp true
  run pacman -Sy --noconfirm --needed archlinux-keyring reflector
  echo "DRY-RUN: reflector --country US --protocol https --age 12 --latest 20 --sort rate --save /etc/pacman.d/mirrorlist"
  echo "DRY-RUN: timezone ${TIMEZONE} → /etc/localtime (permanent)"
  run sgdisk --zap-all "$DISK"
  run sgdisk -n "1:0:+${EFI_SIZE}" -t 1:ef00 -c 1:EFI "$DISK"
  run sgdisk -n "2:0:+${ROOT_SIZE_GIB}GiB" -t 2:8300 -c 2:root "$DISK"
  run sgdisk -n 3:0:0 -t 3:8300 -c 3:home "$DISK"
  run mkfs.fat -F32 -n EFI "$P_EFI"
  if [[ "$FS" == "ext4" ]]; then
    run mkfs.ext4 -F -L root "$P_ROOT"
    run mkfs.ext4 -F -L home "$P_HOME"
    run mount "$P_ROOT" /mnt
    run mkdir -p /mnt/boot /mnt/home
    run mount "$P_EFI" /mnt/boot
    run mount "$P_HOME" /mnt/home
  else
    run mkfs.btrfs -f -L root "$P_ROOT"
    run mkfs.btrfs -f -L home "$P_HOME"
    echo "DRY-RUN: btrfs subvol=@ mount sequence"
  fi
  BASE_PKGS=(base linux amd-ucode "${FIRMWARE_PKGS[@]}" networkmanager sudo vim git efibootmgr)
  [[ "$FS" == "btrfs" ]] && BASE_PKGS+=(btrfs-progs)
  [[ "$IT87" -eq 1 ]] && BASE_PKGS+=(linux-headers dkms base-devel)
  echo "DRY-RUN: pacstrap firmware=${FIRMWARE_PKGS[*]} (no linux-firmware meta / no intel)"
  run pacstrap -K /mnt "${BASE_PKGS[@]}"
  echo "DRY-RUN: install ranked mirrorlist → /mnt/etc/pacman.d/mirrorlist"
  run genfstab -U /mnt
  echo "DRY-RUN: arch-chroot configure locale/user/sudo/bootctl + timezone ${TIMEZONE}"
  echo "DRY-RUN: arch-chroot passwd ${USERNAME}  (interactive TTY)"
  echo "DRY-RUN: arch-chroot passwd root         (interactive TTY)"
  echo "DRY-RUN: then postinstall + boot entry"
  echo "DRY-RUN: write /boot/loader/entries/arch.conf (root UUID + nvidia_drm.modeset=1)"
  echo "DRY-RUN: copy $REPO_ROOT → /mnt/opt/mjolnir"
  if [[ "$SKIP_POST" -eq 0 ]]; then
    POST_ARGS=(--user "$USERNAME" --no-tailscale-up --dry-run)
    [[ "$IT87" -eq 1 ]] && POST_ARGS+=(--it87)
    echo "DRY-RUN: arch-chroot MJOLNIR_CHROOT=1 $POSTINSTALL ${POST_ARGS[*]}"
    # Nested dry-run of postinstall (no root needed)
    MJOLNIR_CHROOT=1 bash "$POSTINSTALL" "${POST_ARGS[@]}"
  else
    echo "DRY-RUN: skip postinstall"
  fi
  echo "DRY-RUN: ln -sfn /opt/mjolnir /home/${USERNAME}/mjolnir"
  echo
  echo "==> DRY-RUN complete (no changes made)"
  exit 0
fi

# --- live environment ---
echo "==> Network / clock / fastest US mirrors"
timedatectl set-ntp true || true
pacman -Sy --noconfirm --needed archlinux-keyring reflector || true
rank_mirrors /etc/pacman.d/mirrorlist || true
echo "    Timezone will be permanently set to ${TIMEZONE}"

# --- wipe + partition ---
echo "==> Wiping and partitioning $DISK"
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+${EFI_SIZE} -t 1:ef00 -c 1:EFI "$DISK"
sgdisk -n 2:0:+${ROOT_SIZE_GIB}GiB -t 2:8300 -c 2:root "$DISK"
sgdisk -n 3:0:0 -t 3:8300 -c 3:home "$DISK"
partprobe "$DISK" || true
sleep 1

P_EFI="$(part_name "$DISK" 1)"
P_ROOT="$(part_name "$DISK" 2)"
P_HOME="$(part_name "$DISK" 3)"
[[ -b "$P_EFI" && -b "$P_ROOT" && -b "$P_HOME" ]] || die "Partitions not found after sgdisk"

echo "==> Formatting"
mkfs.fat -F32 -n EFI "$P_EFI"
case "$FS" in
  btrfs)
    mkfs.btrfs -f -L root "$P_ROOT"
    mkfs.btrfs -f -L home "$P_HOME"
    mount "$P_ROOT" /mnt
    btrfs subvolume create /mnt/@
    umount /mnt
    mount -o subvol=@,compress=zstd:1,noatime "$P_ROOT" /mnt
    mkdir -p /mnt/{boot,home}
    mount "$P_EFI" /mnt/boot
    mount -o compress=zstd:1,noatime "$P_HOME" /mnt/home
    ;;
  ext4)
    mkfs.ext4 -F -L root "$P_ROOT"
    mkfs.ext4 -F -L home "$P_HOME"
    mount "$P_ROOT" /mnt
    mkdir -p /mnt/{boot,home}
    mount "$P_EFI" /mnt/boot
    mount "$P_HOME" /mnt/home
    ;;
esac

# --- pacstrap base ---
echo "==> pacstrap base system (hardware-matched firmware only)"
BASE_PKGS=(
  base linux amd-ucode
  "${FIRMWARE_PKGS[@]}"
  networkmanager sudo vim git
  efibootmgr
)
[[ "$FS" == "btrfs" ]] && BASE_PKGS+=(btrfs-progs)
[[ "$IT87" -eq 1 ]] && BASE_PKGS+=(linux-headers dkms base-devel)

pacstrap -K /mnt "${BASE_PKGS[@]}"
# Guard: never leave the meta package (would re-pull intel/etc. on upgrades)
arch-chroot /mnt pacman -Rns --noconfirm linux-firmware 2>/dev/null || true

echo "==> Installing ranked mirrorlist into new system"
install -d /mnt/etc/pacman.d
if [[ -f /etc/pacman.d/mirrorlist ]]; then
  cp -a /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
else
  rank_mirrors /mnt/etc/pacman.d/mirrorlist || true
fi

echo "==> fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# --- chroot configure ---
echo "==> Configuring system (locale, timezone=${TIMEZONE}, user, bootloader)"
ROOT_UUID="$(blkid -s UUID -o value "$P_ROOT")"

# Copy installer scripts into the new system for postinstall + future use
install -d /mnt/opt/mjolnir
cp -a "$REPO_ROOT"/. /mnt/opt/mjolnir/
chmod +x /mnt/opt/mjolnir/scripts/*.sh

arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
set -euo pipefail
# Permanent timezone (America/Chicago by default)
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo '${TIMEZONE}' >/etc/timezone


sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' >/etc/locale.conf
echo '${HOSTNAME}' >/etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo 'mjolnir' >/etc/mjolnir-installed

echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
if ! id '${USERNAME}' &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,input -s /bin/bash '${USERNAME}'
fi
# passwd is NOT run here — heredoc steals stdin; see interactive passwd below

systemctl enable NetworkManager.service

bootctl install
install -d /boot/loader/entries
cat >/boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF
mkinitcpio -P
CHROOT

# Interactive passwords need a real TTY (cannot run inside <<CHROOT heredoc)
echo "==> Set password for ${USERNAME} (type twice; nothing will echo)"
arch-chroot /mnt passwd "${USERNAME}"
echo "==> Set password for root (type twice; nothing will echo)"
arch-chroot /mnt passwd root

# Boot entry written from host (clear UUID / btrfs flags)
{
  echo "title   Arch Linux (Mjolnir)"
  echo "linux   /vmlinuz-linux"
  echo "initrd  /amd-ucode.img"
  echo "initrd  /initramfs-linux.img"
  if [[ "$FS" == "btrfs" ]]; then
    echo "options root=UUID=${ROOT_UUID} rootflags=subvol=@ rw nvidia_drm.modeset=1"
  else
    echo "options root=UUID=${ROOT_UUID} rw nvidia_drm.modeset=1"
  fi
} >/mnt/boot/loader/entries/arch.conf

# --- postinstall inside chroot ---
if [[ "$SKIP_POST" -eq 0 ]]; then
  echo "==> Running mjolnir-postinstall.sh inside new root"
  POST_ARGS=(--user "$USERNAME" --no-tailscale-up)
  [[ "$IT87" -eq 1 ]] && POST_ARGS+=(--it87)
  arch-chroot /mnt env MJOLNIR_CHROOT=1 /opt/mjolnir/scripts/mjolnir-postinstall.sh "${POST_ARGS[@]}"
else
  echo "==> Skipping postinstall (--skip-postinstall)"
fi

# Symlink docs into user home for convenience
arch-chroot /mnt /bin/bash -c "ln -sfn /opt/mjolnir /home/${USERNAME}/mjolnir && chown -h ${USERNAME}:${USERNAME} /home/${USERNAME}/mjolnir"

echo
echo "==> FULL INSTALL COMPLETE"
echo "    umount -R /mnt"
echo "    reboot"
echo "    Remove USB → boot systemd-boot → GDM → GNOME"
echo "    Then: tailscale up"
echo "          Point DNS A ai.lehaus.io → \$(tailscale ip -4)  (Cloudflare DNS only)"
echo "          sudoedit /etc/caddy/caddy.env   # CF_API_TOKEN=..."
echo "          /usr/local/bin/caddy version    # xcaddy build (not stock /usr/bin/caddy)"
echo "          sudo systemctl restart caddy"
echo "          curl https://ai.lehaus.io/api/tags"
echo "    BIOS Smart Fan unlock: bios_optimize.md"
echo "    Optional later: sudo /opt/mjolnir/scripts/mjolnir-postinstall.sh --user ${USERNAME} --it87"
