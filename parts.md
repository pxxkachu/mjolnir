# OpenITX — System Profile

Desktop workstation for a **local GPU AI server** (llama.cpp), light development, and homelab control. **Arch Linux only.** **Entry point:** [`README.md`](README.md)

Use this file as the hardware and software source of truth when writing guides or troubleshooting docs.

---

## Machine identity

| Field | Value |
|-------|-------|
| Codename | **mjolnir** |
| Hostname | **mjolnir** |
| Login user | **laika** |
| Repo | [github.com/pxxkachu/mjolnir](https://github.com/pxxkachu/mjolnir) |
| Case | **OpenITX** (custom Mini-ITX) |
| Boot mode | UEFI + GPT · **Arch only** |
| Form factor | Desktop (Mini-ITX, SFF) |
| Primary use | GPU AI server (llama.cpp), light coding, homelab control |
| Virtualization | **No** — no local VMs |

---

## Hardware

### CPU

| Field | Value |
|-------|-------|
| Model | AMD Ryzen 7 **9800X3D** |
| Socket | AM5 |
| Architecture | Zen 5 (3D V-Cache) |

**BIOS tuning:** PBO Advanced, Curve Optimizer **−35** — see [`bios_optimize.md`](bios_optimize.md).

---

### GPU

| Field | Value |
|-------|-------|
| Model | NVIDIA GeForce **RTX 5090** (**HP OMEN** desktop OEM, 32 GB GDDR7) |
| Architecture | Blackwell |
| TGP (stock OEM) | ~**575 W** |
| Approx. size | ~**330 × 122 × 74 mm** (~3.5–4 slots) |
| Power connector | **12V-2x6 / 12VHPWR** — **confirmed** native cable, fully seated |
| Fit | **Confirmed** in OpenITX |
| Driver | **`nvidia-open`** + `nvidia-utils` (Arch) |

**Install notes:** Stock profile first for open-frame thermals; undervolt TBD in [`bios_optimize.md`](bios_optimize.md). Axial OEM cooler exhausts to ambient (open case).

---

### Motherboard

| Field | Value |
|-------|-------|
| Model | Gigabyte **B850I AORUS PRO** |
| Revision | **1.0** |
| Chipset | AMD B850 |
| Form factor | Mini-ITX |
| Socket | AM5 |
| LAN | Realtek **2.5GbE** |
| Wi‑Fi / BT | Realtek **RTL8922AE** Wi‑Fi 7 + Bluetooth 5.4 |
| Audio | Realtek **ALC4080** |
| Storage | 2× M.2 NVMe (OS on 990 PRO) |

**Install notes:** Disable **CSM/Legacy**; pure UEFI. **fTPM** on; Secure Boot via **sbctl** after Arch is stable. **Above 4G Decoding** + **Re-Size BAR**. Apply [`bios_optimize.md`](bios_optimize.md) before or right after OS install.

---

### Chassis & cooling

#### Case

| Field | Value |
|-------|-------|
| Model | **OpenITX** (custom) |
| Form factor | Mini-ITX SFF |
| GPU clearance | **Confirmed** — HP OMEN RTX 5090 (~**33 cm**, ~4-slot) fits |

#### CPU cooler

| Field | Value |
|-------|-------|
| Model | Thermalright **AXP90-X47** (full copper, low-profile) |
| Height | 47 mm |
| Type | Top-down low-profile |

#### Case fans

**None** — OpenITX is an open frame; no chassis intakes/exhausts. Cooling is **AXP90 (CPU)** + **GPU axial fans** + ambient air.

**Fan control:** **CoolerControl** on Arch for **CPU_FAN** (AXP90); GPU fans via NVIDIA/CoolerControl. Optional `it87` for motherboard PWM. BIOS Smart Fan unlock applies to **CPU_FAN** only — [`bios_optimize.md`](bios_optimize.md).

#### PSU

| Field | Value |
|-------|-------|
| Model | Corsair **1000 W SFF** (2025) |
| Form factor | SFX |
| GPU power | **Native 12V-2x6 confirmed**. ~575 W TGP — SF1000 is at the edge; use `nvidia-smi -pl` if transients trip the PSU under LLM load |

---

### Memory

| Field | Value |
|-------|-------|
| Model | G.Skill **Ripjaws S5** (F5-6800J3446F48GX2-RS5K) |
| Capacity | **96 GB** (2× 48 GB) |
| Kit rating (XMP) | **6800 MT/s** CL34-46-46-108 @ 1.35 V |
| **Stable running** | **6000 MT/s** CL30-36-36-30 @ 1.35 V, FCLK 2000, UCLK 1:1, SOC 1.15 V |
| Configuration | Dual-channel, **A2 + B2** |
| BIOS | **Done** — already applied; re-apply only after CMOS/BIOS reset ([`bios_optimize.md`](bios_optimize.md)) |

---

### Storage (OS)

| Field | Value |
|-------|-------|
| Model | Samsung **990 PRO** **2 TB** PCIe Gen4 NVMe M.2 Internal SSD |
| Interface | NVMe · **PCIe Gen4** · M.2 |
| Device node | Typically **`/dev/nvme0n1`** (confirm with `lsblk` on live ISO) |
| Role | Sole OS disk — **Arch Linux** |
| Layout | GPT — EFI 1 GB + root ~100 GB + `/home` remainder (**ext4**) |
| Encryption | Optional LUKS |
| Bootloader | **systemd-boot** |

**Install notes:** Fresh wipe via [`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh) `--disk /dev/nvme0n1`.

---

### Display

| Field | Value |
|-------|-------|
| Model | ASUS ROG Swift **PG32UCDP** |
| Panel | OLED, 32", 4K |
| Connection | DisplayPort (full bandwidth / VRR) |

**Post-install:** VRR in GNOME Settings / NVIDIA settings; OLED burn-in mitigation (screen blank, hide top bar idle) — [`arch_install.md`](arch_install.md).

---

## Software stack

| Layer | Choice |
|-------|--------|
| OS | **Arch Linux** only |
| Desktop | **GNOME** minimal (Wayland) + **GDM** |
| Boot | **UEFI** + **Secure Boot** (sbctl) + **fTPM** |
| GPU | **`nvidia-open`** + `nvidia-utils` |
| AI runtime | **llama-cpp** + **ggml-cuda** (`llama-server`) behind **Caddy** at **`https://ai.lehaus.io`** |
| Gaming | Deferred (Steam not installed) |
| Network | **NetworkManager** + **Bluetooth** (`bluez`) + **openssh** |
| Fans | **CoolerControl** (+ optional `--it87`); BIOS unlock for CPU_FAN |
| Install automation | [`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh) + [`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh) (required pkgs only + paru/xcaddy) |
| Homelab | **Tailscale** |
| HTTPS front | **xcaddy** → `/usr/local/bin/caddy` · **`ai.lehaus.io`** · **not** stock `caddy` / certbot |
| Firewall | **nftables** — inbound on `tailscale0` only |
| Idle / sleep | **Disabled** (always-on AI box) |
| SSD TRIM | **`fstrim.timer`** (weekly) |
| GPU daemon | **nvidia-persistenced** (from `nvidia-utils`) |

---

## Goals → packages

| Goal | Install |
|------|---------|
| Local AI server | `llama-cpp`, `ggml-cuda`, Tailscale — [`arch_install.md`](arch_install.md) |
| Light coding | Git, Cursor/VS Code, base-devel |
| Homelab control | Tailscale, browser, optional sshd |

---

## Quick reference (agent lookup)

```yaml
machine:
  codename: mjolnir
  hostname: mjolnir
  user: laika
  timezone: America/Chicago
  repo: https://github.com/pxxkachu/mjolnir
  form_factor: mini-itx
  case: OpenITX custom
  motherboard: Gigabyte B850I AORUS PRO
  motherboard_rev: "1.0"
  boot: uefi
  bootloader: systemd-boot
  secure_boot: sbctl
  tpm: ftpm

cpu:
  model: AMD Ryzen 7 9800X3D
  socket: AM5
  pbo: advanced
  curve_optimizer: -35

memory:
  model: G.Skill Ripjaws S5
  sku: F5-6800J3446F48GX2-RS5K
  capacity_gb: 96
  stable_speed_mts: 6000
  stable_timings: CL30-36-36-30
  stable_fclk_mhz: 2000
  stable_uclk: 1:1
  stable_soc_v: 1.15
  bios_status: done
  bios_profile: bios_optimize.md

gpu:
  model: NVIDIA RTX 5090
  variant: HP OMEN desktop OEM
  vram_gb: 32
  tgp_w: 575
  length_mm: ~330
  power_connector: 12V-2x6
  driver: nvidia-open
  tuning: stock_pending_sff_baseline

storage:
  model: Samsung 990 PRO 2TB PCIe Gen4 NVMe M.2
  capacity_tb: 2
  interface: nvme_pcie_gen4_m2
  device_node: /dev/nvme0n1
  layout: arch_only_gpt_ext4
  efi_gb: 1
  root_gb: ~100
  home: remainder_models_and_games
  motherboard: Gigabyte B850I AORUS PRO
  motherboard_rev: "1.0"
  firmware:
    - amd-ucode                 # 9800X3D microcode
    - linux-firmware-nvidia     # RTX 5090
    - linux-firmware-realtek    # Rev 1.0: 2.5G LAN + RTL8922AE Wi‑Fi/BT + ALC4080
    not:
      - linux-firmware          # meta → intel/broadcom/atheros/…
      - linux-firmware-intel
      - linux-firmware-mediatek # not on this Rev 1.0 (Realtek Wi‑Fi)
      - linux-firmware-amdgpu   # 9800X3D has no iGPU
      - linux-firmware-radeon
      - linux-firmware-amd      # SEV/NPU — not used here
      - linux-firmware-other

os:
  name: Arch Linux
  desktop: gnome_minimal
  display_server: wayland
  greeter: gdm
  ai: llama_cpp
  gaming: deferred
  case_fans: none
  fans: coolercontrol_cpu_and_gpu
  it87: optional_dkms_compile
  install_script: scripts/mjolnir-install.sh
  postinstall_script: scripts/mjolnir-postinstall.sh
  packages: official_repo_binaries
  aur_helper: paru-bin

network:
  tailscale: required
  llama_bind: "127.0.0.1:8080"
  llama_api: "https://ai.lehaus.io"
  caddy: xcaddy_porkbun_dns
  caddy_bin: /usr/local/bin/caddy
  caddy_unit: config/caddy.service
  caddy_domain: ai.lehaus.io
  caddy_not: [stock_arch_caddy, certbot, lego]
  wol: optional

power:
  sleep: disabled
  nvidia_persistenced: true
  fstrim_timer: true

workloads:
  - local_ai_server_llamacpp
  - light_coding
  - homelab_control

virtualization: false
```

---

## Install decisions

| Decision | Choice |
|----------|--------|
| Hostname | `mjolnir` |
| Login user | `laika` |
| Timezone | `America/Chicago` |
| Pacman mirrors | `reflector` — US HTTPS, sorted by rate (permanent conf + timer) |
| Repo | https://github.com/pxxkachu/mjolnir |
| OS | **Arch Linux only** (wipe Windows) |
| Desktop | **GNOME** minimal (Wayland) + **GDM** |
| AI stack | **llama-cpp** + **ggml-cuda** · **`https://ai.lehaus.io`** (xcaddy/Caddy) · Tailscale clients |
| Gaming | Deferred |
| Disk | Samsung **990 PRO 2 TB** PCIe Gen4 NVMe M.2 (`/dev/nvme0n1`) |
| Bootloader | **systemd-boot** |
| Disk encryption | Optional LUKS |
| BIOS / tuning | [`bios_optimize.md`](bios_optimize.md) |
| Install guide | [`arch_install.md`](arch_install.md) |
| Overview | [`README.md`](README.md) |
| Firewall / no-sleep / persistenced | [`arch_install.md`](arch_install.md) |
| Additional storage / NAS | TBD when `/home` fills (GGUF models) |
