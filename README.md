# OpenITX

Mini-ITX gaming and homelab workstation in a custom **OpenITX** case. **Arch Linux only** on a **Samsung 990 PRO 2 TB** PCIe Gen4 NVMe M.2 SSD.

**Hostname:** `mjolnir` · **Case:** OpenITX · **Use:** local GPU AI server, Steam gaming, light development, homelab control

---

## Hardware at a glance

| Component | Model | Notes |
|-----------|-------|-------|
| **Case** | **OpenITX** (custom) | Mini-ITX SFF |
| **CPU** | AMD Ryzen 7 **9800X3D** | PBO Advanced, CO **−35** |
| **GPU** | NVIDIA RTX **5090** HP OMEN OEM (32 GB) | Fit **confirmed** · `nvidia-open` + Ollama |
| **Board** | Gigabyte **B850I AORUS PRO** | UEFI, Secure Boot (sbctl), fTPM |
| **RAM** | G.Skill Ripjaws S5 2×48 GB | **6000 CL30-36-36-30** — BIOS **done** *(kit XMP 6800 failed)* |
| **Storage** | Samsung **990 PRO** 2 TB PCIe Gen4 NVMe M.2 | `/dev/nvme0n1` · GPT ext4 · Arch only |
| **Cooler** | Thermalright **AXP90-X47** | Low-profile top-down |
| **Case fans** | **None** | Open frame — CPU + GPU fans only |
| **PSU** | Corsair **1000 W SFF** | Native **12V-2x6 confirmed** · edge under LLM |
| **Display** | ASUS ROG Swift **PG32UCDP** | 32" OLED 4K |

Full BOM, YAML, and install decisions → [`parts.md`](parts.md)

---

## Software roles

| Layer | Choice |
|-------|--------|
| **OS** | Arch Linux (sole OS) |
| **Desktop** | **GNOME** minimal (Wayland) + GDM |
| **AI** | Ollama + CUDA · Tailscale-only API · no sleep · `nvidia-persistenced` |
| **Gaming** | Steam + Proton |
| **Fans** | CoolerControl for CPU/GPU (no case fans; optional `it87`) |

---

## Setup path

```
1. BIOS            →  bios_optimize.md
2. Arch live ISO   →  scripts/mjolnir-install.sh --disk … --user … --confirm-wipe
3. Reboot          →  GDM → GNOME → tailscale up
```

| Step | Doc / script | What you do |
|------|--------------|-------------|
| **1. BIOS** | [`bios_optimize.md`](bios_optimize.md) | Boot / CPU / GPU / Smart Fan unlock *(memory already done)* |
| **2. Full install** | [`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh) | Wipe → pacstrap → bootloader → stack + **paru-bin** (optional `--it87`) |
| **3. Verify** | [`arch_install.md`](arch_install.md) | `nvidia-smi`, Tailscale API, CoolerControl, Proton |

**How to run** (ISO steps, dry-run, post-install only): [`arch_install.md` — How to run the scripts](arch_install.md#how-to-run-the-scripts)

---

## Documentation

| File | Purpose |
|------|---------|
| **[`parts.md`](parts.md)** | Hardware source of truth — components, software stack, agent YAML |
| **[`bios_optimize.md`](bios_optimize.md)** | Gigabyte BIOS settings + NVIDIA GPU / fan notes |
| **[`arch_install.md`](arch_install.md)** | Install guide + verification |
| **[`scripts/mjolnir-install.sh`](scripts/mjolnir-install.sh)** | **Full** automated install from Arch ISO |
| **[`scripts/mjolnir-postinstall.sh`](scripts/mjolnir-postinstall.sh)** | Stack-only (or re-run after base) |

---

## Validated tuning (summary)

**Memory:** **Done** — 6000 MT/s · CL30-36-36-30 · FCLK 2000 · UCLK 1:1 · DRAM 1.35 V · SOC 1.15 V · **A2 + B2**

**CPU:** PBO Advanced · Curve Optimizer **−35** all cores · Scalar **1X** · SVM off

**GPU:** Stock OEM (~**575 W** TGP) first. **`nvidia-open`** + **persistenced**. `nvidia-smi -pl` if PSU trips under LLM. UV TBD.

**Fans:** No case fans. **CoolerControl** on **CPU_FAN** (+ GPU); BIOS unlock for CPU header only

**AI ops:** Ollama bound to **Tailscale IP** (or nftables) · sleep targets **masked** · chrony + reflector.timer + fstrim.timer

---

## Troubleshooting

| Problem | Where to look |
|---------|----------------|
| No POST / RAM training | [`bios_optimize.md`](bios_optimize.md) |
| WHEA / stutter / GPU power | [`bios_optimize.md`](bios_optimize.md) |
| Install / GNOME / Ollama / Steam | [`arch_install.md`](arch_install.md) |

---

## Agent quick reference

```yaml
machine: mjolnir
case: OpenITX
os: Arch Linux
desktop: GNOME minimal
cpu: Ryzen 7 9800X3D
gpu: RTX 5090 (HP OMEN OEM)
ram: 96GB @ 6000 CL30-36-36-30
storage: Samsung 990 PRO 2TB PCIe Gen4 NVMe M.2 (/dev/nvme0n1)
aur_helper: paru-bin
workloads:
  - local_ai_server_ollama
  - steam_gaming
  - homelab_control
docs:
  hardware: parts.md
  bios: bios_optimize.md
  install: arch_install.md
```

Extended YAML → [`parts.md`](parts.md#quick-reference-agent-lookup)
