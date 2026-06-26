# Mjolnir — System Profile

Desktop workstation for gaming, light development, and homelab control. Use this file as the hardware and software source of truth when writing install scripts, post-install guides, or troubleshooting docs.

---

## Machine identity

| Field | Value |
|-------|-------|
| Codename | **mjolnir** |
| Hostname | **mjolnir** |
| Form factor | Desktop (Mini-ITX) |
| Boot mode | UEFI (assumed) |
| Primary use | Gaming, light coding, homelab control |
| Virtualization | **No** — no local VMs (no KVM/QEMU/libvirt) |

---

## Hardware

### CPU

| Field | Value |
|-------|-------|
| Model | AMD Ryzen 7 **9800X3D** |
| Socket | AM5 |
| Architecture | Zen 5 (3D V-Cache) |
| Kernel modules | `amd-ucode` |

**Install notes:** Install `amd-ucode` and include it in the EFI boot entry.

---

### GPU

| Field | Value |
|-------|-------|
| Model | AMD Radeon **RX 7900 XT** (Reference, 24 GB) |
| Architecture | RDNA 3 |
| Driver | Open-source `amdgpu` (default on Arch) |
| Firmware | `linux-firmware` (included with kernel) |

**Install notes:** No proprietary driver required. For gaming, install **Mesa** (`mesa`, `lib32-mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`). `lib32-mesa` covers 32-bit OpenGL; `lib32-vulkan-radeon` covers 32-bit Vulkan (Steam/Proton/Wine). Requires **multilib** enabled in `/etc/pacman.conf`. Prefer **Gamescope** or compositor VRR rather than forcing X11. Reference blower cards are loud under load — unrelated to install, but relevant for thermals/fan curves.

---

### Motherboard

| Field | Value |
|-------|-------|
| Model | Gigabyte **B850I AORUS PRO** |
| Chipset | AMD B850 |
| Form factor | Mini-ITX |
| Socket | AM5 |
| Typical storage | 1× M.2 NVMe (confirm slot layout in manual) |

**Install notes:** Disable **CSM/Legacy**; use pure UEFI. Confirm **Resizable BAR / Above 4G Decoding** is enabled for the GPU. Set boot order to the Samsung 990 Pro after install. Update BIOS before or immediately after first boot if a stable release fixes AM5/RDNA3 issues.

---

### Memory

| Field | Value |
|-------|-------|
| Capacity | **96 GB** RAM |
| Swap | Optional — small **swap file** if enabled (see [Install decisions](#install-decisions)) |
| Hibernation | **No** (would require swap ≈ RAM size; not planned) |

**Install notes:** With 96 GB, swap is not required for normal gaming or development. If a safety buffer is wanted, add a **16 GB swap file** on `/` after install (not a swap partition). Set `vm.swappiness=10` so swap is only used under real memory pressure.

---

### Storage (OS)

| Field | Value |
|-------|-------|
| Model | Samsung **990 PRO** 2 TB |
| Interface | NVMe (PCIe) |
| Role | OS + primary user data |
| Filesystem | **ext4** |
| Layout | ESP + `/` + `/home` (separate `/home` partition) |
| Encryption | **None** (no LUKS) |
| Swap | **None at partition time**; optional 16 GB swap file on `/` post-install |

**Partition plan (2 TB Samsung 990 Pro):**

| Mount | FS | Size | Notes |
|-------|-----|------|-------|
| `/boot/efi` | FAT32 | 1 GiB | EFI System Partition |
| `/` | ext4 | ~200 GiB | Root (OS, packages, optional swap file) |
| `/home` | ext4 | remainder | User data, games (Steam library), dev projects |

Exact root size is flexible; 200 GiB leaves ample room for `/` without swap. Adjust in the install script if desired.

**Install notes:** Identify in live ISO with `lsblk` / `nvme list`. Samsung drives often appear as `/dev/nvme0n1` but **always confirm by size and model** before partitioning.

---

### Display

| Field | Value |
|-------|-------|
| Model | ASUS ROG Swift **PG32UCDP** |
| Panel | OLED, 32" |
| Resolution | 4K (3840×2160); dual-mode panel (high refresh at lower res — check manual) |
| Connection | DisplayPort preferred for full bandwidth / VRR |

**Install notes:** Wayland + GNOME on `amdgpu` supports VRR and HDR on recent stacks. Verify `mutter` VRR and correct refresh in Settings after install. OLED burn-in mitigation (idle dim, screensaver) is a post-install preference, not an installer concern.

---

## Software stack

| Layer | Choice |
|-------|--------|
| Distribution | **Arch Linux** (rolling) |
| Init | systemd |
| Display server | **Wayland** |
| Desktop | **GNOME** |
| Session | `gnome-wayland` (default on Arch GNOME) |
| Shell / terminal | TBD |
| AUR helper | **paru** (build from AUR git clone — not `paru-bin`) |

**Install notes:** Install `gnome`, `gnome-tweaks`, and `pipewire` + `wireplumber` for audio. For gaming: `steam`, `gamemode`, `mangohud`. Install **Tailscale** for homelab remote access. Optional containers (Docker/distrobox) deferred to post-install.

---

## Goals → install implications

| Goal | Likely packages / config |
|------|---------------------------|
| Gaming | `steam`, `gamemode`, `mesa`, `lib32-mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`, Proton (via Steam), optional `heroic-games-launcher` |
| Light coding | `git`, editor of choice, `base-devel`, Docker or `distrobox` if desired |
| Homelab control | `openssh`, **`tailscale`**, browser, optional Docker or `distrobox` |

---

## Quick reference (agent lookup)

```yaml
machine:
  codename: mjolnir
  hostname: mjolnir
  form_factor: mini-itx
  boot: uefi

cpu:
  model: AMD Ryzen 7 9800X3D
  socket: AM5
  ucode: amd-ucode

memory:
  ram_gb: 96
  swap: optional_swap_file_16g
  hibernation: false

gpu:
  model: AMD RX 7900 XT
  vram_gb: 24
  driver: amdgpu
  mesa: mesa
  mesa_lib32: lib32-mesa
  vulkan: vulkan-radeon
  vulkan_lib32: lib32-vulkan-radeon

motherboard:
  model: Gigabyte B850I AORUS PRO
  chipset: B850

storage:
  os:
    model: Samsung 990 Pro
    capacity_tb: 2
    interface: nvme
    filesystem: ext4
    encryption: none
    partitions:
      - mount: /boot/efi
        fs: fat32
        size_gib: 1
      - mount: /
        fs: ext4
        label: root
        size_gib: 200
      - mount: /home
        fs: ext4
        label: home
        size: remainder

display:
  model: ASUS PG32UCDP
  resolution: 3840x2160
  panel: oled

os:
  distro: arch
  compositor: wayland
  de: gnome
  gdm_autologin: true

aur_helper:
  name: paru
  method: git_clone  # aur.archlinux.org/paru — avoid paru-bin on rolling

network:
  tailscale: required

workloads:
  - gaming
  - light_coding
  - homelab_control

virtualization: false
```

---

## Install decisions

| Decision | Choice |
|----------|--------|
| Hostname | `mjolnir` |
| Root filesystem | ext4 |
| Separate `/home` | **Yes** |
| Disk encryption | **No** |
| AUR helper | **paru** via `git clone https://aur.archlinux.org/paru.git` + `makepkg -si` |
| Tailscale | **Yes** — required for homelab access |
| Swap | **Optional** — skip or add 16 GB **swap file** on `/` (not a partition) |
| Hibernation | **No** |
| ext4 volume labels | `root`, `home` |
| GDM | **Autologin** for install user (skip login screen) |
| NVMe TRIM | **`fstrim.timer`** weekly (not continuous `discard`) |
| Performance | GameMode, `vm.max_map_count`, `noatime`, `nvme-cli`, `smartmontools`, `cpupower` in `install.sh` |
| Additional storage / NAS | TBD |
