# Mjolnir — Interactive Install Script Plan

Design document for `install.sh`: an Arch Linux UEFI installer for the Mjolnir desktop (see [`parts.md`](parts.md)). Run from the official Arch live ISO as **root**.

**Scope of this document:** plan only — implementation follows in `install.sh`. Gaming extras, Tailscale, paru, and optional swap file belong in a separate **`post_install.md`** (not covered here beyond boundaries).

---

## Goals

| Goal | Detail |
|------|--------|
| Reproducible base install | Fixed layout and stack from `parts.md`; no config file |
| Minimal prompts | User chooses **disk**, **hostname**, **username**, **password** only |
| Safe | Pre-flight checks, disk summary, type-`ERASE` confirmation |
| Agent-friendly | Numbered phases, explicit commands, validation rules |
| Consistent | Reuse patterns from [`dxp480t/install.sh`](../dxp480t/install.sh) where applicable |

---

## Prerequisites (human, before running script)

### BIOS (Gigabyte B850I AORUS PRO)

| Setting | Value |
|---------|-------|
| Boot mode | **UEFI** — disable CSM/Legacy |
| Secure Boot | **Disabled** for live ISO boot ([Arch wiki](https://wiki.archlinux.org/title/Installation_guide#Boot_the_live_environment)); may re-enable later with custom keys |
| Above 4G Decoding / Re-Size BAR | **Enabled** (RX 7900 XT) |
| Boot order | USB installer first, then Samsung 990 Pro after install |

### Live environment

1. Boot official Arch ISO (x86_64, UEFI).
2. Connect network (Ethernet preferred; Wi‑Fi via `iwctl` if needed).
3. Verify: `ping -c 3 archlinux.org`
4. Copy or clone this repo (or at least `install.sh`) onto the live system.
5. Run: `bash install.sh` as root.

---

## Interactive vs fixed configuration

### Prompted (4 user inputs)

| Variable | Validation | Default hint |
|----------|------------|--------------|
| **Disk** | Select by number from discovered whole disks (`/dev/nvme*`, `/dev/sd*`) | Expected: Samsung 990 Pro 2 TB |
| **Hostname** | `^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$` (RFC 1178) | `mjolnir` |
| **Username** | `^[a-z_][a-z0-9_-]{0,31}$` | — |
| **Password** | `passwd` for **root** and **user** (interactive, retry on failure) | — |

### Fixed (from `parts.md`, not prompted)

| Setting | Value |
|---------|-------|
| Partition table | GPT |
| EFI size | **1 GiB** |
| Root size | **200 GiB** ext4, label `root` |
| `/home` | **Remainder** of disk, ext4, label `home` |
| Swap | **None** at install (optional 16 GiB swap file in post-install) |
| Encryption | **None** |
| Locale | `en_US.UTF-8` |
| Timezone | `UTC` (change in post-install or GNOME Settings) |
| Keymap | `us` (`/etc/vconsole.conf`) |
| Bootloader | **systemd-boot** (ESP mounted at `/boot`) |
| CPU microcode | **amd-ucode** (9800X3D) |
| Desktop | **GNOME** on **Wayland** via **GDM** |
| GDM login | **Autologin** — skip login screen for install username |
| Mirror selection | **reflector** (HTTPS, rate-sorted) before `pacstrap` |

**Rationale for non-prompted locale/timezone:** User requested only four interactive choices. Defaults are sensible; homelab/gaming box can set timezone after first login.

---

## Repository layout (target)

```
mjolnir/
├── parts.md           # Hardware & decisions (source of truth)
├── install_plan.md    # This file
├── install.sh         # Live-ISO installer (to implement)
└── post_install.md    # paru, Tailscale, Steam, swap file, tweaks (later)
```

---

## Script architecture

### Header & shell options

```bash
#!/usr/bin/env bash
# Run from Arch live ISO, UEFI, as root. DESTROYS selected disk.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
export LC_ALL=C
```

### Phase overview

```
┌─────────────────────────────────────────────────────────────┐
│ 0. Pre-flight    root check, UEFI check, tool bootstrap    │
│ 1. Discover      list disks (lsblk), show table             │
│ 2. Interactive   disk, hostname, username                   │
│ 3. Validate      whole disk, not read-only, not mounted     │
│ 4. Confirm       summary + type ERASE                       │
│ 5. Prepare       NTP, reflector, cleanup stale /mnt         │
│ 6. Partition     sgdisk: EFI + root + home                  │
│ 7. Format        mkfs.fat, mkfs.ext4 ×2                     │
│ 8. Mount         /mnt, /mnt/boot, /mnt/home                 │
│ 9. Pacstrap      base + kernel + firmware + desktop stack   │
│10. Fstab         genfstab -U, verify /home entry            │
│11. Chroot        locale, time, hostname, user, boot, units   │
│12. Passwords     root + user (arch-chroot passwd)            │
│13. Finish        umount, reboot prompt                      │
└─────────────────────────────────────────────────────────────┘
```

### Helper functions (reuse from dxp480t)

| Function | Purpose |
|----------|---------|
| `err_exit` | Print error, exit 1 |
| `cleanup` / `trap EXIT` | `umount -R /mnt` on failure |
| `part disk num` | `/dev/nvme0n1p1` vs `/dev/sda1` naming |
| `wait_for_partitions` | `udevadm settle` |
| `need_cmd cmd [pkg]` | Install missing live-ISO tools via pacman |
| `discover_disks` | Populate `AVAILABLE_DISKS[]`, sizes, models |
| `print_disk_table` | Numbered table for selection |
| `assert_whole_disk` | Block device, TYPE=disk |
| `assert_disk_not_readonly` | Refuse read-only media |
| `assert_partitions_exist` | Post-partition sanity check |
| `reread_partition_table` | `blockdev --rereadpt` |
| `disk_has_mounts` | Refuse if any partition mounted |
| `set_passwd user label` | Retry loop around `arch-chroot passwd` |

---

## Step-by-step implementation detail

### Phase 0 — Pre-flight

1. **Root check:** `EUID -eq 0` or exit.
2. **UEFI check:** `[ -d /sys/firmware/efi/efivars ]` or exit with CSM message.
3. **Bootstrap tools on live ISO:**

   | Command | Package |
   |---------|---------|
   | `pacstrap` | `arch-install-scripts` |
   | `sgdisk` | `gptfdisk` |
   | `mkfs.fat` | `dosfstools` |
   | `mkfs.ext4` | `e2fsprogs` |
   | `reflector` | `reflector` |
   | `lsblk`, `blockdev` | `util-linux` |

4. Register `trap cleanup EXIT`.

### Phase 1 — Disk discovery

```bash
lsblk -dpno NAME,SIZE,MODEL | grep -E '/dev/(sd|nvme|mmcblk)'
```

- Exclude `rom`, `loop`, `airootfs` (already excluded by grep pattern).
- Show numbered table: `#`, `DISK`, `SIZE`, `MODEL`.
- User picks one number → `OS_DISK`.

### Phase 2 — Interactive prompts

**Disk** — loop until valid index.

**Hostname** — loop until regex match; suggest `mjolnir` in prompt text.

**Username** — loop until regex match; create as login user (not `root`).

Do **not** prompt for: timezone, locale, EFI size, root size, encryption.

### Phase 3 — Pre-destructive validation

On `OS_DISK`:

- Is whole disk (`TYPE=disk`).
- Not read-only.
- No mounted partitions (`disk_has_mounts`).

### Phase 4 — Summary & confirmation

Print:

```
OS disk:     /dev/nvme0n1  (Samsung 990 PRO 2TB)
Partitions:  1G EFI | 200G / ext4 | remainder /home ext4
Hostname:    mjolnir
Username:    alice
Locale:      en_US.UTF-8 (fixed)
Timezone:    UTC (fixed)
Encryption:  none
Swap:        none
Bootloader:  systemd-boot + amd-ucode
Desktop:     GNOME / GDM / Wayland (autologin)
```

Require: `Type ERASE to continue:` — exact match `ERASE`.

### Phase 5 — Prepare environment

1. `timedatectl set-ntp true`
2. Network check: `curl -fsS --connect-timeout 10 https://archlinux.org`
3. `reflector --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist`
4. If `/mnt` mounted from prior run: `umount -R /mnt`

### Phase 6 — Partition (`sgdisk`)

On `$OS_DISK` only — **zap entire disk**:

| Part | Size | Type | Label | Mount (installed) |
|------|------|------|-------|-------------------|
| 1 | `+1G` | `ef00` EFI | `EFI` | `/boot` |
| 2 | `+200G` | `8300` Linux root | `ROOT` | `/` |
| 3 | rest | `8300` Linux root | `HOME` | `/home` |

Commands (conceptual):

```bash
sgdisk --zap-all "$OS_DISK"
sgdisk -n 1:0:+1G  -t 1:ef00 -c 1:"EFI"  "$OS_DISK"
sgdisk -n 2:0:+200G -t 2:8300 -c 2:"ROOT" "$OS_DISK"
sgdisk -n 3:0:0   -t 3:8300 -c 3:"HOME" "$OS_DISK"
```

Resolve paths:

```bash
EFI_PART="$(part "$OS_DISK" 1)"
ROOT_PART="$(part "$OS_DISK" 2)"
HOME_PART="$(part "$OS_DISK" 3)"
```

Wait for udev, assert all three block devices exist.

### Phase 7 — Format

```bash
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F -L root "$ROOT_PART"
mkfs.ext4 -F -L home "$HOME_PART"
```

Use `-F` on ext4 for whole-partition format without confirmation.

### Phase 8 — Mount

```bash
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot /mnt/home
mount -o fmask=0077,dmask=0077 "$EFI_PART" /mnt/boot
mount "$HOME_PART" /mnt/home
```

**Order matters for `genfstab`:** root first, then `/boot`, then `/home`.

Pre-create `/mnt/etc/vconsole.conf` with `KEYMAP=us` before pacstrap (avoids locale/keymap warnings during package install).

### Phase 9 — Enable multilib & pacstrap

**Before pacstrap**, enable multilib in **live** `/etc/pacman.conf` (copied to target by pacstrap):

```bash
sed -i '/^\[multilib\]/,/^Include/ s/^#//' /etc/pacman.conf
pacman -Sy
```

Also enable multilib **inside chroot** after pacstrap (belt and suspenders — `pacstrap -P` copies host config but verify in chroot).

#### Package groups

**Tier A — boot & system (pacstrap):**

```
base linux linux-firmware amd-ucode
e2fsprogs dosfstools
sudo git nano man-db man-pages texinfo
networkmanager openssh
base-devel go pacman-contrib
```

- `go` + `base-devel`: needed to build **paru** in post-install without extra setup.
- `openssh` + enable `sshd`: homelab remote access (Tailscale comes post-install).

**Tier B — desktop & GPU (pacstrap):**

```
gnome gnome-tweaks
pipewire pipewire-pulse pipewire-alsa wireplumber
mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

- `gnome` meta package pulls GDM, mutter (Wayland), nautilus, etc.
- Mesa multilib stack per `parts.md` for Steam/Proton (Steam itself is post-install).

**Not in pacstrap (post_install.md):**

```
paru tailscale steam gamemode mangohud
linux-headers reflector (already on live ISO only)
optional: 16G swap file, OLED/VRR tweaks, fstrim already in install
```

Full command:

```bash
pacstrap -K /mnt \
  base linux linux-firmware amd-ucode \
  e2fsprogs dosfstools \
  sudo git nano man-db man-pages texinfo \
  networkmanager openssh base-devel go pacman-contrib \
  gnome gnome-tweaks \
  pipewire pipewire-pulse pipewire-alsa wireplumber \
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

### Phase 10 — fstab

```bash
genfstab -U /mnt > /mnt/etc/fstab
```

**Verify** (script must check, fail if missing):

- `/` → `$ROOT_PART` UUID
- `/boot` → vfat `$EFI_PART` UUID
- `/home` → `$HOME_PART` UUID

If `/home` missing (known genfstab edge case when mount order wrong):

```bash
# append manually using blkid UUID
UUID=<home-uuid>  /home  ext4  defaults  0  2
```

Optional fstab tweak for NVMe SSD (document, apply in script):

```
defaults,noatime
```

on ext4 entries — reduces unnecessary writes; safe for desktop.

Enable periodic TRIM via `fstrim.timer` in chroot (NVMe).

### Phase 11 — Chroot configuration

Single `arch-chroot /mnt /bin/bash -euo pipefail <<EOF ... EOF` block (pattern from dxp480t).

#### 11a. Locale & time

```bash
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
# vconsole.conf already KEYMAP=us
```

#### 11b. Hostname & hosts

```bash
echo "${HOSTNAME}" > /etc/hostname
# /etc/hosts: 127.0.0.1 localhost, 127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
# + standard IPv6 lines
```

#### 11c. Multilib in installed system

```bash
sed -i '/^\[multilib\]/,/^Include/ s/^#//' /etc/pacman.conf
```

(Only if not already enabled from host copy.)

#### 11d. User & sudo

```bash
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-wheel
chmod 440 /etc/sudoers.d/99-wheel
```

Passwords set **outside** heredoc in Phase 12 (interactive `passwd`).

#### 11d2. GDM autologin (skip login screen)

GDM still runs, but the greeter is bypassed and the install user lands straight in a GNOME Wayland session. Works well on this build (AMD GPU — no NVIDIA/Wayland-disable udev rule).

Append to `/etc/gdm/custom.conf` in chroot (file may not exist yet; create `[daemon]` section):

```bash
cat >> /etc/gdm/custom.conf <<GDM
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${USERNAME}
GDM
```

Or use a heredoc that writes the full file if cleaner. Do **not** set `WaylandEnable=false` — keep Wayland default.

**Security note:** Anyone with physical access gets a logged-in desktop without credentials. Acceptable for a single-user home desktop; disable by removing these lines or setting `AutomaticLoginEnable=False`.

**Not the same as:**

| Feature | Autologin | Effect |
|---------|-----------|--------|
| GDM autologin | Yes (planned) | Skips password at boot → straight to desktop |
| Lock screen after suspend | Separate | Still may prompt on wake unless disabled in GNOME Settings |
| `gdm disable` / start GNOME from TTY | No | Would bypass GDM entirely — fragile, not recommended |

If autologin fails after reboot, check from a TTY: `cat /etc/gdm/custom.conf`, `journalctl -u gdm -b`.

#### 11e. systemd-boot

ESP is `/boot`. Install loader:

```bash
bootctl install
ROOTUUID=$(blkid -s UUID -o value "${ROOT_PART}")
```

`/boot/loader/loader.conf`:

```ini
default arch.conf
timeout 3
editor  no
```

`/boot/loader/entries/arch.conf`:

```ini
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOTUUID} rw
```

**Notes:**

- **amd-ucode** initrd must come **before** main initramfs ([Arch wiki](https://wiki.archlinux.org/title/Microcode)).
- No `nvme_core.default_ps_max_latency_us=0` unless latency issues observed (NAS-specific in dxp480t).
- `bootctl` auto-enables `systemd-boot-update.service` when appropriate.

#### 11f. mkinitcpio

```bash
mkinitcpio -P
```

Rebuild after all config in place. No custom hooks needed for plain ext4 without LUKS.

#### 11g. Enable systemd units

| Unit | Reason |
|------|--------|
| `NetworkManager.service` | Network on boot |
| `gdm.service` | GNOME display manager (autologin → Wayland session) |
| `sshd.service` | Remote SSH (Tailscale post-install) |
| `systemd-timesyncd.service` | Time sync |
| `fstrim.timer` | NVMe weekly TRIM |

```bash
systemctl enable NetworkManager gdm sshd systemd-timesyncd fstrim.timer
```

### Phase 12 — Passwords

Outside heredoc (requires TTY interaction):

```bash
set_passwd root "Root"
set_passwd "${USERNAME}" "User ${USERNAME}"
```

### Phase 13 — Finish

1. `trap - EXIT` (successful path — or let reboot handle umount).
2. `umount -R /mnt`
3. Print success message: remove USB, reboot — desktop should autologin (no GDM password prompt).
4. Point user to **`post_install.md`** next steps (paru, Tailscale, Steam).
5. Optional: `read -p "Reboot now? [y/N]"` — default **N** so user can review; dxp480t auto-reboots — **recommend prompt** for desktop install.

---

## Safety & error handling

| Risk | Mitigation |
|------|------------|
| Wrong disk | Show model + size; require `ERASE` |
| BIOS/Legacy boot | UEFI gate at start |
| No network | curl check before pacstrap |
| Stale mounts | cleanup trap + pre-run umount |
| Missing `/home` in fstab | post-genfstab validation |
| Partial chroot failure | `arch-chroot ... || err_exit` with message to inspect `/mnt` |
| paru-bin on rolling | post_install uses git clone only (documented in parts.md) |

---

## Differences from dxp480t installer

| Aspect | dxp480t (NAS) | mjolnir (desktop) |
|--------|---------------|-------------------|
| Disks | OS + multi-disk Btrfs RAID | Single OS disk, 3 partitions |
| Filesystem | ext4 + Btrfs pool | ext4 only |
| Microcode | intel-ucode | amd-ucode |
| Boot options | `nvme_core.default_ps_max_latency_us=0` | default |
| Desktop | None (headless) | GNOME + GDM |
| Swap | zram-generator | none (optional swap file post-install) |
| Extra timers | btrfs scrub/snapshot | fstrim only |
| Watchdog | Intel iTCO | omit |
| Prompts | + timezone, locale, array config | disk, hostname, user only |
| Packages | NAS services | Mesa multilib, PipeWire, GNOME |

---

## Post-install boundary (`post_install.md` — later)

Not part of `install.sh`, but referenced at end of install:

1. **paru** — git clone + `makepkg -si` (as user, not root)
2. **Tailscale** — `pacman -S tailscale`, `systemctl enable --now tailscaled`, `tailscale up`
3. **Steam / gamemode / mangohud**
4. **Optional 16 GiB swap file** on `/` + `vm.swappiness=10`
5. **GNOME tweaks** — VRR, HDR, OLED burn-in, 4K scaling
6. **Hosts / Tailscale FQDN** if applicable

---

## Test checklist (before trusting on real hardware)

Run on live ISO (can use `-n` dry-run sections or QEMU later):

- [ ] Script exits if not root
- [ ] Script exits if not UEFI
- [ ] Disk table lists NVMe with correct model/size
- [ ] Invalid hostname/username rejected
- [ ] Confirmation aborts unless `ERASE`
- [ ] Partition layout: `sgdisk -p $disk` shows 1G / 200G / rest
- [ ] `lsblk -f` shows vfat + ext4 + ext4
- [ ] `genfstab -U /mnt` contains `/`, `/boot`, `/home`
- [ ] `arch-chroot /mnt bootctl status` shows loader installed
- [ ] `/boot/loader/entries/arch.conf` has amd-ucode + initramfs order
- [ ] After reboot: autologin to GNOME, Wayland session (`echo $XDG_SESSION_TYPE`), `glxinfo` or `vulkaninfo` works
- [ ] `/etc/gdm/custom.conf` has `AutomaticLogin=${USERNAME}`
- [ ] NetworkManager connects; SSH reachable on LAN

---

## References

- [Arch Installation guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Partitioning](https://wiki.archlinux.org/title/Partitioning) — separate `/home`
- [AMDGPU](https://wiki.archlinux.org/title/Amdgpu) — Mesa + Vulkan
- [GNOME](https://wiki.archlinux.org/title/Gnome) — GDM, Wayland
- [systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
- [Microcode](https://wiki.archlinux.org/title/Microcode) — amd-ucode in boot entry
- [Multilib](https://wiki.archlinux.org/title/Official_repositories#multilib)
- [reflector](https://wiki.archlinux.org/title/Mirrors#Automatically_ranking_mirrors)
- [`parts.md`](parts.md) — Mjolnir hardware & decisions
- [`../dxp480t/install.sh`](../dxp480t/install.sh) — helper patterns & interactive UX

---

## Implementation order

1. ~~Write this plan~~ ✓
2. Implement `install.sh` following phases 0–13
3. Dry-run partition steps on live ISO (optional QEMU disk)
4. Write `post_install.md` for paru, Tailscale, Steam, swap file
5. Update `parts.md` if any decisions change during implementation
