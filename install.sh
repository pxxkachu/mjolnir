#!/usr/bin/env bash
#
# Run from the official Arch Linux live ISO, UEFI boot, as root.
# Wipes the OS disk you select (default target: Samsung 990 PRO / nvme0n1).
# BIOS: CSM off, Secure Boot off for first install — see bios_optimize.md.
# Network required (ping archlinux.org) before continuing.
#
# After reboot, follow arch_install.md (copy-paste guide) — this script does
# NOT install NVIDIA / GNOME / llama.cpp / Caddy.
#
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# -----------------------------
# Arch base installer for Mjolnir (OpenITX AI box)
# - GPT: EFI 1G + root 100G + home remainder (ext4)
# - Selective firmware (B850I Rev 1.0): nvidia + realtek + amd-ucode
# - Interactive — type ERASE to confirm wipe
# -----------------------------

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root."
  exit 1
fi

if [[ ! -d /sys/firmware/efi/efivars ]]; then
  echo "ERROR: Not booted in UEFI mode. This script requires UEFI."
  echo "Reboot and ensure UEFI boot is selected in BIOS, not CSM/Legacy."
  exit 1
fi

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
  echo "== Cleanup: unmounting filesystems =="
  umount -R /mnt 2>/dev/null || true
}
trap cleanup EXIT

err_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

part() {
  local disk="$1" num="$2"
  if [[ "$disk" =~ (nvme|mmcblk) ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

wait_for_partitions() {
  udevadm settle --timeout=10
}

need_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 || pacman -Sy --noconfirm --needed "$pkg"
}

disk_has_mounts() {
  local disk="$1"
  lsblk -n -o MOUNTPOINT "$disk" | awk 'NF { exit 0 } END { exit 1 }'
}

assert_whole_disk() {
  local d="$1" t
  [[ -b "$d" ]] || err_exit "Not a block device: $d"
  t="$(lsblk -dn -o TYPE "$d" 2>/dev/null || true)"
  [[ "$t" == "disk" ]] || err_exit "Expected a whole disk (not a partition): $d (lsblk TYPE=${t:-unknown})"
}

assert_disk_not_readonly() {
  local d="$1"
  if [[ "$(blockdev --getro "$d" 2>/dev/null || echo 0)" == "1" ]]; then
    err_exit "Disk is read-only: $d"
  fi
}

assert_partitions_exist() {
  local p
  for p in "$@"; do
    [[ -b "$p" ]] || err_exit "Partition not found (kernel may need a moment): $p"
  done
}

reread_partition_table() {
  local d
  for d in "$@"; do
    blockdev --rereadpt "$d" 2>/dev/null || true
  done
}

echo "== Ensuring required tools exist =="
need_cmd pacstrap    arch-install-scripts
need_cmd sgdisk      gptfdisk
need_cmd wipefs      util-linux
need_cmd mkfs.fat    dosfstools
need_cmd mkfs.ext4   e2fsprogs
need_cmd lsblk       util-linux
need_cmd blockdev    util-linux
need_cmd reflector   reflector
need_cmd curl        curl

echo "== Checking network connectivity (before any wipe) =="
if ! curl -fsS --connect-timeout 10 --max-time 30 https://archlinux.org >/dev/null; then
  err_exit "No network. Verify connectivity (Ethernet preferred) before running this script."
fi

# ---- Disk discovery ----
AVAILABLE_DISKS=()
AVAILABLE_SIZES=()
AVAILABLE_MODELS=()
while IFS= read -r line; do
  name="$(echo "$line" | awk '{print $1}')"
  size="$(echo "$line" | awk '{print $2}')"
  model="$(echo "$line" | cut -d' ' -f3-)"
  AVAILABLE_DISKS+=("/dev/${name}")
  AVAILABLE_SIZES+=("$size")
  AVAILABLE_MODELS+=("${model:-unknown}")
done < <(
  lsblk -dn -e 7,11 -o NAME,SIZE,TYPE | awk '$3=="disk"{print $1,$2}' | while read -r n s; do
    model="$(lsblk -dn -o MODEL "/dev/$n" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    echo "$n $s ${model:-unknown}"
  done
)

((${#AVAILABLE_DISKS[@]} > 0)) || err_exit "No disks found."

echo ""
echo "Available disks:"
for i in "${!AVAILABLE_DISKS[@]}"; do
  printf "  %2d) %s  %s  %s\n" "$((i + 1))" "${AVAILABLE_DISKS[$i]}" "${AVAILABLE_SIZES[$i]}" "${AVAILABLE_MODELS[$i]}"
done
echo ""

DEFAULT_DISK_IDX=""
for i in "${!AVAILABLE_DISKS[@]}"; do
  if [[ "${AVAILABLE_DISKS[$i]}" == "/dev/nvme0n1" ]]; then
    DEFAULT_DISK_IDX=$((i + 1))
    break
  fi
done

while true; do
  if [[ -n "$DEFAULT_DISK_IDX" ]]; then
    read -r -p "Select OS disk by number [${DEFAULT_DISK_IDX} = nvme0n1]: " OS_CHOICE
    OS_CHOICE=${OS_CHOICE:-$DEFAULT_DISK_IDX}
  else
    read -r -p "Select OS disk by number: " OS_CHOICE
  fi
  if [[ "$OS_CHOICE" =~ ^[0-9]+$ ]] && ((OS_CHOICE >= 1 && OS_CHOICE <= ${#AVAILABLE_DISKS[@]})); then
    OS_DISK="${AVAILABLE_DISKS[$((OS_CHOICE - 1))]}"
    break
  fi
  echo "Invalid. Enter a number between 1 and ${#AVAILABLE_DISKS[@]}."
done
echo "  -> OS disk: $OS_DISK"
echo ""

read -r -p "EFI partition size [1G]: " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-1G}

while true; do
  read -r -p "Root partition size GiB [100]: " ROOT_SIZE_GIB
  ROOT_SIZE_GIB=${ROOT_SIZE_GIB:-100}
  if [[ "$ROOT_SIZE_GIB" =~ ^[0-9]+$ ]] && ((ROOT_SIZE_GIB >= 20)); then
    break
  fi
  echo "Invalid. Enter an integer GiB >= 20."
done

while true; do
  read -r -p "Hostname [mjolnir]: " HOSTNAME
  HOSTNAME=${HOSTNAME:-mjolnir}
  if [[ "$HOSTNAME" =~ ^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    break
  fi
  echo "Invalid hostname."
done

while true; do
  read -r -p "Username [laika]: " USERNAME
  USERNAME=${USERNAME:-laika}
  if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    break
  fi
  echo "Invalid username."
done

echo ""
echo "Timezone examples: America/Chicago, America/New_York, Europe/London"
while true; do
  read -r -p "Timezone [America/Chicago]: " TIMEZONE
  TIMEZONE=${TIMEZONE:-America/Chicago}
  if [[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
    break
  fi
  echo "Invalid timezone."
done

echo ""
while true; do
  read -r -p "Locale [en_US.UTF-8]: " LOCALE
  LOCALE=${LOCALE:-en_US.UTF-8}
  if grep -q "^#\?${LOCALE} " /etc/locale.gen 2>/dev/null; then
    break
  fi
  echo "Invalid locale."
done

assert_whole_disk "$OS_DISK"
assert_disk_not_readonly "$OS_DISK"
if disk_has_mounts "$OS_DISK"; then
  err_exit "Refusing to erase $OS_DISK: partitions are mounted. Unmount first."
fi

echo ""
echo "========================================"
echo "  Configuration Summary"
echo "========================================"
echo ""
echo "  OS disk:          $OS_DISK"
echo "  Layout:           EFI ${EFI_SIZE} + root ${ROOT_SIZE_GIB}G + home (rest) — ext4"
echo "  Firmware:         amd-ucode + linux-firmware-nvidia + linux-firmware-realtek"
echo "  Hostname:         $HOSTNAME"
echo "  Username:         $USERNAME"
echo "  Timezone:         $TIMEZONE"
echo "  Locale:           $LOCALE"
echo ""
echo "  Post-install:     manual — see arch_install.md after reboot"
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "  DANGER: THIS WILL ERASE: $OS_DISK"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r -p "Type ERASE to continue: " CONFIRM
[[ "$CONFIRM" == "ERASE" ]] || exit 1

timedatectl set-ntp true || true

if mountpoint -q /mnt; then
  echo "== /mnt is already mounted — cleaning up previous run =="
  umount -R /mnt
fi

EFI_PART="$(part "$OS_DISK" 1)"
ROOT_PART="$(part "$OS_DISK" 2)"
HOME_PART="$(part "$OS_DISK" 3)"

echo "== Partitioning OS disk ($OS_DISK) =="
sgdisk --zap-all "$OS_DISK"
sgdisk -n 1:0:+"$EFI_SIZE" -t 1:ef00 -c 1:"EFI" "$OS_DISK"
sgdisk -n 2:0:+"${ROOT_SIZE_GIB}G" -t 2:8300 -c 2:"ROOT" "$OS_DISK"
sgdisk -n 3:0:0 -t 3:8300 -c 3:"HOME" "$OS_DISK"
wait_for_partitions
reread_partition_table "$OS_DISK"
wait_for_partitions
assert_partitions_exist "$EFI_PART" "$ROOT_PART" "$HOME_PART"

echo "== Formatting =="
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.ext4 -F -L archroot "$ROOT_PART"
mkfs.ext4 -F -L archhome "$HOME_PART"

mount "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home}
mount -o fmask=0077,dmask=0077 "$EFI_PART" /mnt/boot
mount "$HOME_PART" /mnt/home

echo "== Selecting fastest US HTTPS mirrors =="
if ! reflector --country US --protocol https --age 12 --latest 20 --sort rate --save /etc/pacman.d/mirrorlist; then
  echo "WARNING: reflector failed or timed out — falling back to geo + Rackspace HTTPS mirrors."
  cat >/etc/pacman.d/mirrorlist <<'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
MIRRORS
fi

echo "== Installing base packages =="
# B850I Rev 1.0 + 9800X3D + RTX 5090 — no linux-firmware meta (pulls intel/etc.)
pacstrap -K /mnt \
  base linux amd-ucode \
  linux-firmware-nvidia linux-firmware-realtek \
  networkmanager sudo vim git efibootmgr

# Guard: remove meta if pulled transitively
arch-chroot /mnt pacman -Rns --noconfirm linux-firmware 2>/dev/null || true

install -d /mnt/etc/pacman.d
cp -a /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

genfstab -U /mnt >/mnt/etc/fstab

# Copy this repo into the new system (arch_install.md + docs)
echo "== Copying mjolnir repo → /opt/mjolnir =="
install -d /mnt/opt/mjolnir
cp -a "$SCRIPT_DIR"/. /mnt/opt/mjolnir/

echo "== Configuring system inside chroot =="
if ! arch-chroot /mnt /bin/bash -euo pipefail <<EOF
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo '${TIMEZONE}' >/etc/timezone

sed -i 's/^#\(${LOCALE//./\\.} UTF-8\)/\1/' /etc/locale.gen
grep -q "^${LOCALE} UTF-8" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" >/etc/locale.conf
echo "KEYMAP=us" >/etc/vconsole.conf

echo "${HOSTNAME}" >/etc/hostname
cat >/etc/hosts <<HOSTS
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}

::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS

echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/99-wheel
chmod 440 /etc/sudoers.d/99-wheel
if ! id "${USERNAME}" &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,input -s /bin/bash "${USERNAME}"
fi
ln -sfn /opt/mjolnir /home/${USERNAME}/mjolnir
chown -h ${USERNAME}:${USERNAME} /home/${USERNAME}/mjolnir

bootctl install
ROOTUUID=\$(blkid -s UUID -o value "${ROOT_PART}")
cat >/boot/loader/loader.conf <<LOADER
default arch.conf
timeout 0
console-mode keep
editor no
LOADER
cat >/boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux (Mjolnir)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\${ROOTUUID} rw nvidia_drm.modeset=1
ENTRY

mkinitcpio -P
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable fstrim.timer
echo 'mjolnir' >/etc/mjolnir-installed
EOF
then
  err_exit "arch-chroot configuration failed. /mnt may still be mounted for inspection."
fi

set_passwd() {
  local user="$1" label="$2"
  while true; do
    echo "${label}:"
    if arch-chroot /mnt passwd "$user"; then
      break
    fi
    echo "Password not set. Try again."
  done
}

echo "== Set passwords =="
set_passwd "${USERNAME}" "User ${USERNAME}"
set_passwd root "Root"

trap - EXIT
umount -R /mnt

echo ""
echo "========================================"
echo "  Base install complete"
echo "========================================"
echo "  1. Remove the USB stick"
echo "  2. reboot"
echo "  3. Log in as ${USERNAME} (TTY — no GNOME yet)"
echo "  4. Follow: /opt/mjolnir/arch_install.md   (or ~/mjolnir/arch_install.md)"
echo ""
read -r -p "Reboot now? [Y/n]: " REBOOT_NOW
REBOOT_NOW=${REBOOT_NOW:-Y}
if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
  reboot
fi
