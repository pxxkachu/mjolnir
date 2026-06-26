#!/usr/bin/env bash
#
# Run from the official Arch Linux live ISO, UEFI boot, as root.
# This script DESTROYS all data on the disk you select.
# BIOS: disable CSM/Legacy; disable Secure Boot for the live ISO.
# Enable Above 4G Decoding / Re-Size BAR for the RX 7900 XT.
# Ensure networking works (e.g. ping archlinux.org) before continuing.
#
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# -----------------------------
# Arch installer for Mjolnir desktop
# - OS: ext4 on a user-selected NVMe/SATA disk
# - Layout: 1G EFI + 200G / + remainder /home
# - GNOME Wayland + GDM autologin
# - Interactive: disk, hostname, username, password
# -----------------------------

readonly EFI_SIZE="1G"
readonly ROOT_SIZE="200G"
readonly LOCALE="en_US.UTF-8"
readonly TIMEZONE="UTC"

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

enable_multilib() {
  local conf="$1"
  if grep -q '^#\[multilib\]' "$conf"; then
    sed -i '/^\#\[multilib\]/,/^#Include/ s/^#//' "$conf"
  fi
}

verify_and_fix_fstab() {
  local fstab=/mnt/etc/fstab
  [[ -f "$fstab" ]] || err_exit "fstab not found at $fstab"

  grep -qE '[[:space:]]/[[:space:]]' "$fstab" || err_exit "fstab missing / entry"
  grep -qE '[[:space:]]/boot[[:space:]]' "$fstab" || err_exit "fstab missing /boot entry"

  if ! grep -qE '[[:space:]]/home[[:space:]]' "$fstab"; then
    local home_uuid
    home_uuid="$(blkid -s UUID -o value "$HOME_PART")"
    [[ -n "$home_uuid" ]] || err_exit "Could not read UUID for $HOME_PART"
    echo "UUID=${home_uuid}  /home  ext4  defaults,noatime  0  2" >> "$fstab"
    echo "  -> Added missing /home entry to fstab"
  fi

  sed -i '/ext4/ s/\([[:space:]]\)defaults\([[:space:]]\)/\1defaults,noatime\2/' "$fstab"
}

discover_disks() {
  AVAILABLE_DISKS=()
  AVAILABLE_SIZES=()
  AVAILABLE_MODELS=()
  while IFS= read -r line; do
    local name size model
    name="$(echo "$line" | awk '{print $1}')"
    size="$(echo "$line" | awk '{print $2}')"
    model="$(echo "$line" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')"
    [[ -z "$model" ]] && model="(unknown)"
    AVAILABLE_DISKS+=("$name")
    AVAILABLE_SIZES+=("$size")
    AVAILABLE_MODELS+=("$model")
  done < <(lsblk -dpno NAME,SIZE,MODEL | grep -E '/dev/(sd|nvme|mmcblk)')

  if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
    err_exit "No disks found."
  fi
}

print_disk_table() {
  local disks=("$@")
  printf "  %-4s  %-15s  %-10s  %s\n" "#" "DISK" "SIZE" "MODEL"
  printf "  %-4s  %-15s  %-10s  %s\n" "---" "---------------" "----------" "-----"
  local idx=1
  for d in "${disks[@]}"; do
    local i
    for i in "${!AVAILABLE_DISKS[@]}"; do
      if [[ "${AVAILABLE_DISKS[$i]}" == "$d" ]]; then
        printf "  %-4s  %-15s  %-10s  %s\n" "$idx" "$d" "${AVAILABLE_SIZES[$i]}" "${AVAILABLE_MODELS[$i]}"
        break
      fi
    done
    ((idx++))
  done
}

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

echo "== Ensuring required tools exist =="
need_cmd pacstrap    arch-install-scripts
need_cmd genfstab    arch-install-scripts
need_cmd arch-chroot arch-install-scripts
need_cmd sgdisk      gptfdisk
need_cmd mkfs.fat    dosfstools
need_cmd mkfs.ext4   e2fsprogs
need_cmd lsblk       util-linux
need_cmd blockdev    util-linux
need_cmd curl        curl
need_cmd reflector   reflector

echo ""
echo "========================================"
echo "  Arch Linux Desktop Installer (Mjolnir)"
echo "========================================"
echo ""

discover_disks

echo "== Available disks =="
print_disk_table "${AVAILABLE_DISKS[@]}"
echo ""
while true; do
  read -r -p "Select the OS disk by number (e.g. 1): " OS_CHOICE
  if [[ "$OS_CHOICE" =~ ^[0-9]+$ ]] && (( OS_CHOICE >= 1 && OS_CHOICE <= ${#AVAILABLE_DISKS[@]} )); then
    OS_DISK="${AVAILABLE_DISKS[$((OS_CHOICE - 1))]}"
    break
  fi
  echo "Invalid selection. Enter a number between 1 and ${#AVAILABLE_DISKS[@]}."
done
echo "  -> OS disk: $OS_DISK"
echo ""

while true; do
  read -r -p "Hostname (e.g. mjolnir): " HOSTNAME
  if [[ "$HOSTNAME" =~ ^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    break
  fi
  echo "Invalid hostname. Letters, digits, and hyphens only. Must start with a letter, must not end with a hyphen (max 63 chars)."
done

while true; do
  read -r -p "Username (e.g. jhle): " USERNAME
  if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    break
  fi
  echo "Invalid username. Use lowercase letters, digits, underscores, and hyphens. Must start with a letter or underscore (max 32 chars)."
done

assert_whole_disk "$OS_DISK"
assert_disk_not_readonly "$OS_DISK"
if disk_has_mounts "$OS_DISK"; then
  err_exit "Refusing to erase $OS_DISK: one or more partitions are mounted. Unmount them first."
fi

OS_DISK_IDX=0
for i in "${!AVAILABLE_DISKS[@]}"; do
  if [[ "${AVAILABLE_DISKS[$i]}" == "$OS_DISK" ]]; then
    OS_DISK_IDX=$i
    break
  fi
done

echo ""
echo "========================================"
echo "  Configuration Summary"
echo "========================================"
echo ""
echo "  OS disk:          $OS_DISK (${AVAILABLE_MODELS[$OS_DISK_IDX]}, ${AVAILABLE_SIZES[$OS_DISK_IDX]})"
echo "  Partitions:       ${EFI_SIZE} EFI | ${ROOT_SIZE} / ext4 | remainder /home ext4"
echo "  Volume labels:    root, home"
echo ""
echo "  Hostname:         $HOSTNAME"
echo "  Username:         $USERNAME"
echo "  Locale:           $LOCALE (fixed)"
echo "  Timezone:         $TIMEZONE (fixed)"
echo ""
echo "  Encryption:       none"
echo "  Swap:             none (optional swap file in post_install.md)"
echo "  Bootloader:       systemd-boot + amd-ucode"
echo "  Desktop:          GNOME / GDM / Wayland (autologin)"
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "  DANGER: THIS WILL ERASE ALL DATA ON: $OS_DISK"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r -p "Type ERASE to continue: " CONFIRM
[[ "$CONFIRM" == "ERASE" ]] || exit 1

timedatectl set-ntp true || true

if ! curl -fsS --connect-timeout 10 --max-time 30 https://archlinux.org >/dev/null; then
  err_exit "No network. Verify connectivity before running this script."
fi

echo "== Selecting fastest mirrors =="
reflector --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist

if mountpoint -q /mnt; then
  echo "== /mnt is already mounted — cleaning up previous run =="
  umount -R /mnt
fi

EFI_PART="$(part "$OS_DISK" 1)"
ROOT_PART="$(part "$OS_DISK" 2)"
HOME_PART="$(part "$OS_DISK" 3)"

echo "== Partitioning OS disk ($OS_DISK) =="
sgdisk --zap-all "$OS_DISK"
sgdisk -n 1:0:+"$EFI_SIZE" -t 1:ef00 -c 1:"EFI"   "$OS_DISK"
sgdisk -n 2:0:+"$ROOT_SIZE" -t 2:8300 -c 2:"ROOT" "$OS_DISK"
sgdisk -n 3:0:0             -t 3:8300 -c 3:"HOME"  "$OS_DISK"
wait_for_partitions
reread_partition_table "$OS_DISK"
wait_for_partitions
assert_partitions_exist "$EFI_PART" "$ROOT_PART" "$HOME_PART"

echo "== Formatting partitions =="
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F -L root "$ROOT_PART"
mkfs.ext4 -F -L home "$HOME_PART"

echo "== Mounting filesystems =="
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot /mnt/home
mount -o fmask=0077,dmask=0077 "$EFI_PART" /mnt/boot
mount "$HOME_PART" /mnt/home

mkdir -p /mnt/etc
echo "KEYMAP=us" > /mnt/etc/vconsole.conf

echo "== Enabling multilib repository =="
enable_multilib /etc/pacman.conf
pacman -Sy

echo "== Installing packages (this may take a while) =="
pacstrap -K /mnt \
  base linux linux-firmware amd-ucode \
  e2fsprogs dosfstools \
  sudo git nano man-db man-pages texinfo \
  networkmanager openssh base-devel go pacman-contrib \
  gnome gnome-tweaks \
  pipewire pipewire-pulse pipewire-alsa wireplumber \
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
  gamemode lib32-gamemode nvme-cli smartmontools cpupower

genfstab -U /mnt > /mnt/etc/fstab
verify_and_fix_fstab

echo "== Configuring system inside chroot =="
if ! arch-chroot /mnt /bin/bash -euo pipefail <<EOF
enable_multilib() {
  local conf="\$1"
  if grep -q '^#\[multilib\]' "\$conf"; then
    sed -i '/^\#\[multilib\]/,/^#Include/ s/^#//' "\$conf"
  fi
}

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i 's/^#\(${LOCALE//./\\.} UTF-8\)/\1/' /etc/locale.gen
grep -q "^${LOCALE} UTF-8" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}

::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS

enable_multilib /etc/pacman.conf

if ! id "${USERNAME}" &>/dev/null; then
  useradd -m -G wheel -s /bin/bash "${USERNAME}"
fi
usermod -aG gamemode "${USERNAME}" 2>/dev/null || true
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-wheel
chmod 440 /etc/sudoers.d/99-wheel

cat > /etc/sysctl.d/99-gaming.conf <<SYSCTL
# Steam / Proton and some native games need a higher mmap limit
vm.max_map_count=1048576
SYSCTL

cat > /etc/gamemode.ini <<GAMEINI
; System-wide GameMode — mjolnir install.sh
[general]
renegotiate=0

[cpu]
; Request performance governor while a game runs (via amd-pstate EPP)
desiredgov=performance
; Keep 9800X3D cache-friendly CCD scheduling when GameMode supports it
park_cores_on_idle=0

[gpu]
; Required to apply AMD GPU performance level changes
apply_gpu_optimisations=accept-responsibility
amd_performance_level=high
GAMEINI

install -d /etc/gdm
cat > /etc/gdm/custom.conf <<GDM
# GDM configuration — mjolnir install.sh
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${USERNAME}
GDM

bootctl install
ROOTUUID=\$(blkid -s UUID -o value "${ROOT_PART}")

cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
editor  no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\${ROOTUUID} rw
ENTRY

mkinitcpio -P

systemctl enable NetworkManager gdm sshd systemd-timesyncd fstrim.timer
EOF
then
  err_exit "arch-chroot configuration failed. See messages above. /mnt may still be mounted for inspection."
fi

echo "== Set passwords =="
set_passwd root "Root"
set_passwd "${USERNAME}" "User ${USERNAME}"

trap - EXIT
umount -R /mnt

echo ""
echo "========================================"
echo "  Installation complete"
echo "========================================"
echo ""
echo "  Remove the installation medium, then reboot."
echo "  GDM will autologin as ${USERNAME} into a GNOME Wayland session."
echo ""
echo "  Next: follow post_install.md for paru, Tailscale, Steam, and display tweaks."
echo ""
read -r -p "Reboot now? [y/N]: " REBOOT
if [[ "${REBOOT,,}" == "y" ]]; then
  reboot
fi
