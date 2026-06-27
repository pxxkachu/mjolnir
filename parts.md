# Mjolnir — System Profile

Desktop workstation for gaming, light development, and homelab control. Use this file as the hardware and software source of truth when writing install scripts, post-install guides, or troubleshooting docs.

---

## Machine identity

| Field | Value |
|-------|-------|
| Codename | **mjolnir** (from Thorzone Mjolnir case) |
| Hostname | **mjolnir** |
| Case | Thorzone **Mjolnir** ITX |
| Boot mode | UEFI (assumed) |
| Form factor | Desktop (Mini-ITX, SFF) |
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

**Install notes:** Disable **CSM/Legacy**; use pure UEFI. Confirm **Resizable BAR / Above 4G Decoding** is enabled for the GPU. Set boot order to the Samsung 990 Pro after install. Update BIOS before or immediately after first boot if a stable release fixes AM5/RDNA3 issues. Configure fan curves in BIOS for SFF thermals (see [Chassis & cooling](#chassis--cooling)).

---

### Chassis & cooling

#### Case

| Field | Value |
|-------|-------|
| Model | Thorzone **Mjolnir** ITX |
| Form factor | Mini-ITX SFF |
| GPU clearance | Confirm against RX 7900 XT reference length (~28 cm) in case specs |

#### CPU cooler

| Field | Value |
|-------|-------|
| Model | Thermalright **AXP90-X47** (full copper, low-profile) |
| Height | 47 mm |
| Type | Top-down low-profile |
| Socket | AM5 (verify included mounting hardware) |

**Notes:** Low-profile cooler in a dense SFF case with a **9800X3D** (~120 W) — monitor CPU temps under gaming load. Undervolt/PBO limits in BIOS if thermals are tight; not an OS install concern.

#### Case fans

| Mount | Role | Model | Size | Notes |
|-------|------|-------|------|-------|
| Bottom | **Intake** | **Noctua NF-A12x15 chromax.black.swap** | 120 mm × 15 mm slim | Quiet; low profile for tight clearance |
| Bottom | **Intake** | **Phanteks T30** | 120 mm × 30 mm | High static pressure |

**Airflow:** Both fans pull cool air in from the **bottom**. Hot air exits via case vents, **PSU fan**, and **RX 7900 XT reference blower** (recirculates into case — bottom intake is critical). Positive-pressure bottom intake is the primary cooling strategy.

**Install notes:** **Manual flat BIOS handoff** ([`bios_optimize.md` Phase 2](bios_optimize.md#phase-2--fan-control-bios-handoff)) + **CoolerControl** ([`post_install.md` § 12](post_install.md#12-fan-control-coolercontrol)). Bottom intakes use **GPU + CPU mixed** curves in Linux. Optional **`lact`** (AUR) for GPU blower tuning. Dust filter on bottom intakes — clean periodically.

#### PSU

| Field | Value |
|-------|-------|
| Model | Corsair **1000 W SFF** (2025) |
| Form factor | SFX / SFF |
| Wattage | 1000 W |
| Headroom | Comfortable for 9800X3D + RX 7900 XT with transient spikes |

**Install notes:** Confirm **12V-2x6 (12VHPWR)** or required GPU power cables included for the 7900 XT (reference uses 2× 8-pin). Route cables for unobstructed bottom intake. PSU fan typically acts as exhaust — balance against bottom intake curves in BIOS.

---

### Memory

| Field | Value |
|-------|-------|
| Model | G.Skill **Ripjaws S5** (F5-6800J3446F48GX2-RS5K) |
| Capacity | **96 GB** (2× 48 GB) |
| Type | DDR5 U-DIMM |
| Speed | **6800 MT/s** |
| Timings | CL34-46-46-108 |
| Voltage | 1.35 V (XMP); SPD 5600 MT/s @ 1.10 V |
| Profile | **Intel XMP 3.0** |
| Height | **33 mm** (low-profile — fits AXP90-X47) |
| Color | Matte black |
| Configuration | Dual-channel (2 modules) |

**Install notes:** Enable **XMP** in BIOS for rated 6800 MT/s (boots at SPD 5600 until profile enabled). 2×48 GB dual-rank @ 6800 on AM5 is aggressive — update BIOS first, run stability tests, and step down to 6400/6000 if XMP will not train. With 96 GB, swap is not required for normal gaming or development. If a safety buffer is wanted, add a **16 GB swap file** on `/` after install (not a swap partition). Set `vm.swappiness=10` so swap is only used under real memory pressure. Hibernation not planned (would require swap ≈ RAM size).

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
| Desktop | **GNOME** (minimal: Console, Files, Settings, Tweaks) |
| Session | `gnome-wayland` via GDM **autologin** |
| Shell / terminal | TBD |
| AUR helper | **paru** (build from AUR git clone — not `paru-bin`) |

**Install notes:** Minimal GNOME via `install.sh` — `gnome-console`, `nautilus`, `gnome-control-center`, `gnome-tweaks`, **Firefox**; plus `gnome-browser-connector`, `bluez`, PipeWire. **GDM autologin** and **systemd-boot** (entry `arch`, timeout 0). Gaming: `steam`, etc. in [`post_install.md`](post_install.md).

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
  case: Thorzone Mjolnir ITX
  boot: uefi

cpu:
  model: AMD Ryzen 7 9800X3D
  socket: AM5
  ucode: amd-ucode

memory:
  model: G.Skill Ripjaws S5
  sku: F5-6800J3446F48GX2-RS5K
  type: DDR5
  form: UDIMM
  capacity_gb: 96
  modules: 2x48GB
  speed_mts: 6800
  timings: CL34-46-46-108
  voltage_v: 1.35
  spd_speed_mts: 5600
  profile: Intel_XMP_3.0
  height_mm: 33
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

cooling:
  cpu_cooler:
    model: Thermalright AXP90-X47
    type: low_profile_top_down
    height_mm: 47
    material: full_copper
  case_fans:
    - mount: bottom
      role: intake
      model: Noctua NF-A12x15 chromax.black.swap
      size_mm: 120
      thickness_mm: 15
    - mount: bottom
      role: intake
      model: Phanteks T30
      size_mm: 120
      thickness_mm: 30
  airflow: bottom_intake_positive_pressure

psu:
  model: Corsair 1000W SFF
  year: 2025
  wattage_w: 1000
  form_factor: sfx

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
  bootloader: systemd-boot

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
| BIOS / tuning | [`bios_optimize_plan.md`](bios_optimize_plan.md) (strategy), [`bios_optimize.md`](bios_optimize.md) (steps) — XMP, PBO/CO, Smart Fan 6, LACT GPU |
| Additional storage / NAS | TBD |
