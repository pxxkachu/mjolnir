# OpenITX — Mjolnir

Mini-ITX gaming and homelab workstation in a custom **OpenITX** case. **Arch Linux only** on a **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 SSD.

**Hostname:** `mjolnir` · **User:** `laika` · **Case:** OpenITX · **Use:** local GPU AI server (llama.cpp), light development, homelab control

**Repo:** [github.com/pxxkachu/mjolnir](https://github.com/pxxkachu/mjolnir)

---

## Hardware at a glance

| Component | Model | Notes |
|-----------|-------|-------|
| **Case** | **OpenITX** (custom) | Mini-ITX SFF |
| **CPU** | AMD Ryzen 7 **9800X3D** | PBO Advanced, CO **−35** |
| **GPU** | NVIDIA RTX **5090** HP OMEN OEM (32 GB) | Fit **confirmed** · `nvidia-open` + llama.cpp |
| **Board** | Gigabyte **B850I AORUS PRO** **Rev 1.0** | Realtek 2.5G + RTL8922AE Wi‑Fi 7 · UEFI / fTPM |
| **RAM** | G.Skill Ripjaws S5 2×48 GB | **6000 CL30-36-36-30** — BIOS **done** |
| **Storage** | Samsung **990 PRO** 2 TB PCIe Gen4 NVMe M.2 | `/dev/nvme0n1` · GPT ext4 · Arch only |
| **Cooler** | Thermalright **AXP90-X47** | Low-profile top-down |
| **PSU** | Corsair **1000 W SFF** | Native **12V-2x6 confirmed** |
| **Display** | ASUS ROG Swift **PG32UCDP** | 32" OLED 4K |

Full BOM → [`parts.md`](parts.md)

---

## Software roles

| Layer | Choice |
|-------|--------|
| **OS** | Arch Linux (sole OS) |
| **Desktop** | **GNOME** minimal (Wayland) + GDM |
| **AI** | **llama-cpp** + **ggml-cuda** · `llama-server` · **Caddy** (download API + **Porkbun**) → `https://ai.lehaus.io` |
| **Gaming** | Deferred (Steam not installed) |
| **Fans** | CoolerControl (+ optional `it87`) |

---

## Setup path (dxp480tp-style)

```
1. BIOS            →  bios_optimize.md
2. Arch live ISO   →  bash install.sh          # base OS only; type ERASE
3. Reboot          →  continue arch_install.md (post-install sections)
```

| Step | Doc / script |
|------|----------------|
| **1. BIOS** | [`bios_optimize.md`](bios_optimize.md) |
| **2. Base install** | [`install.sh`](install.sh) + first half of [`arch_install.md`](arch_install.md) |
| **3. Stack** | Rest of [`arch_install.md`](arch_install.md) — NVIDIA, GNOME, llama.cpp, Caddy/Porkbun, … |

Live ISO:

```bash
pacman -Sy --needed git
git clone https://github.com/pxxkachu/mjolnir.git /tmp/mjolnir
cd /tmp/mjolnir
bash install.sh
```

---

## Documentation

| File | Purpose |
|------|---------|
| **[`arch_install.md`](arch_install.md)** | Full guide: live ISO + copy-paste stack (Caddyfile / units inline) |
| **[`install.sh`](install.sh)** | Base Arch installer (live ISO) |
| **[`parts.md`](parts.md)** | Hardware / stack source of truth |
| **[`bios_optimize.md`](bios_optimize.md)** | Gigabyte BIOS + fan unlock |

---

## Agent quick reference

```yaml
machine: mjolnir
user: laika
case: OpenITX
os: Arch Linux
desktop: GNOME minimal
cpu: Ryzen 7 9800X3D
gpu: RTX 5090 (HP OMEN OEM)
ram: 96GB @ 6000 CL30-36-36-30
storage: Samsung 990 PRO 2TB (/dev/nvme0n1)
aur_helper: paru-bin
repo: https://github.com/pxxkachu/mjolnir
llama_api: https://ai.lehaus.io
llama_bind: "127.0.0.1:8080"
caddy: download_api_porkbun_dns
caddy_bin: /usr/local/bin/caddy
caddy_home: /var/lib/caddy
caddy_user: caddy
workloads:
  - local_ai_server_llamacpp
  - homelab_control
docs:
  hardware: parts.md
  bios: bios_optimize.md
  install: arch_install.md
```
