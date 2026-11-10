# OpenITX — BIOS tuning

**Entry point:** [`README.md`](README.md)

**Board:** Gigabyte **B850I AORUS PRO Rev 1.0** · **CPU:** Ryzen 7 **9800X3D** · **RAM:** G.Skill 2×48 GB @ **6000 CL30** *(stable; kit XMP 6800)* · **Storage:** Samsung **990 PRO** 2 TB PCIe Gen4 NVMe M.2 · **OS:** **Arch Linux** only

Apply after **Load Optimized Defaults** + latest stable BIOS flash. DIMMs in **A2 + B2** only. OS side: **`nvidia-open`**, GNOME, llama.cpp — see [`arch_install.md`](arch_install.md).

---

## Boot

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **CSM Support** | **Disabled** | Compatibility Support Module emulates legacy BIOS boot (MBR, 16-bit option ROMs). | Pure **UEFI + GPT** for Arch + systemd-boot. No legacy OS. |
| **Secure Boot** | **Disabled** for install → **Enabled** after **sbctl** | Only allows boot/load of OS and drivers signed with trusted keys. | Off during first Arch install; enroll keys with **sbctl** then turn on ([`arch_install.md`](arch_install.md)). Requires **CSM off**. |
| **Trusted Platform Module** | **Enable ASP fTPM** | Exposes a TPM 2.0 device using the CPU’s built-in firmware TPM. | Useful for optional LUKS TPM unlock and measured boot later. No physical TPM module needed. |
| **Boot Option Priorities** | **Linux Boot Manager / systemd-boot** on **990 PRO** | Order of devices tried at power-on. | Single-OS Arch. **F12** = USB for recovery/ISO. |
| **Fast Boot** | **Enabled** | Skips full POST device enumeration where safe. | Faster everyday boot on a stable single-OS build. |

---

## Storage (Samsung 990 PRO 2 TB PCIe Gen4 NVMe M.2)

*Single M.2 Internal SSD (PCIe Gen4) — typically `/dev/nvme0n1` — Arch Linux on full disk.*

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **NVMe RAID Mode** | **Disabled** | Treats NVMe drives as a RAID array. | Single OS drive — no RAID. |
| **M.2 PCIe Mode** | **Auto** | Link speed for the M.2 slot. | **990 PRO** is Gen4; **Auto** trains correctly. Force **Gen4** only if the drive fails to enumerate after a BIOS update. |

**Leave at default:** hot-plug, ASPM on NVMe.

---

## GPU (RTX 5090 — HP OMEN OEM)

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **Initial Display Output** | **PCIe 1 Slot** | Chooses which GPU drives the display during POST and early boot. | Ensures the **RTX 5090** (not unused iGPU) owns the monitor from first frame — fewer black-screen POST issues. |
| **Above 4G Decoding** | **Enabled** | Lets 64-bit PCIe devices use memory addresses above 4 GB. | Without this, a **32 GB** GPU cannot map all VRAM properly in UEFI; **required** before ReBAR works. |
| **Re-Size BAR Support** | **Enabled** | Lets the CPU access the full GPU VRAM window (Resizable BAR). | Small **gaming FPS uplift** on Blackwell; pairs with Above 4G. Safe default for this GPU + Arch. |
| **PCIEX16 Slot Link Speed** | **Gen5** *(or **Auto**)* | Caps the primary x16 slot to PCIe 3/4/5. | **RTX 5090** is Gen5. Use **Gen5** on B850I; fall back to **Auto** / **Gen4** only if link training fails. |
| **PCIe ASPM Mode** | **Disabled** | Active State Power Management — PCIe link power-down at idle. | Avoids link wake latency that can cause micro-stutter in some games. |

---

## CPU — 9800X3D

*Tweaker → Advanced CPU Settings · Tweaker → **AMD Overclocking** (PBO / Curve Optimizer)*

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **Precision Boost Overdrive** | **Advanced** | Main PBO switch — unlocks limits, Curve Optimizer, and boost tuning. | **Advanced** exposes undervolt controls without enabling Gigabyte’s **PBO Enhancement** presets. |
| **PBO Limits** | **Motherboard** | Who sets PPT/TDC/EDC caps — AMD spec vs board maximum. | **Motherboard** lets the CPU boost freely within VRM/cooler limits; cap manually only if thermals require it. |
| **Boost Override** | **+0 MHz** | Adds MHz on top of stock boost ceiling. | **9800X3D** is cache-limited — manual frequency OC rarely helps games and adds heat; **+0** keeps stock boost tables. |
| **Scalar** | **1X** | Aggression multiplier for Curve Optimizer stability testing. | **1X** gives honest validation at **−35** CO; **10×** can pass short tests then crash in games. |
| **Curve Optimizer** | **Negative**, **All Cores**, **−35** | Per-core voltage offset along the boost curve — **negative** = undervolt. | Validated stable on this **9800X3D** — same FPS band, **less heat and power** in SFF. Critical for AXP90 in the OpenITX case. |
| **Global C-state Control** | **Enabled** | Allows cores to enter low-power **C-states** when idle (drop clock/voltage). | Keeps idle cool and quiet in SFF. On X3D, **Auto** sometimes behaves like **Disabled** and causes **core parking / game stutter** — set **Enabled** explicitly. If stutter worsens, try **Disabled**. |
| **SVM Enable** | **Disabled** | AMD-V virtualization — lets hypervisors (Hyper-V, VMware) run VMs. | This build runs **no local VMs**; disabling trims overhead and avoids some anti-cheat/VBS edge cases. Re-enable if a title or tool requires it. |
| **X3D Turbo Mode 2** | **Disabled** | Gigabyte heuristic that shifts load based on “X3D Turbo” profiles. | Unpredictable on **9800X3D** (single CCD); can hurt more than help vs stock boost. |
| **PBO Enhancement** | **Disabled** | *Separate from main PBO above* — extra boost tiers tied to **90 / 80 / 70 °C** targets. | Gigabyte-specific add-on; pushes clocks when cool. Bad fit for **SFF** thermals. |
| **ECO Mode** | **Disabled** | Caps CPU power to a lower TDP envelope. | Saves power/heat but **cuts gaming boost**; 9800X3D already benefits from undervolt (Curve Optimizer), not a hard ECO cap. |

**Leave at default**

| Setting | Default | What it does | Why leave it |
|---------|---------|--------------|--------------|
| **Core Performance Boost** | Enabled | AMD boost — raises clock above base under load. | Required for normal **9800X3D** performance; disabling forces all-core base clock only. |
| **SMT Mode** | Enabled | Exposes 2 threads per core (16 threads total). | Best for gaming + desktop; disable only for rare latency experiments. |

**AMD CBS / AMD Overclocking** *(if shown)*:

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **CPPC** | **Enabled** | Collaborative Processor Performance Control — OS sees per-core speed limits. | Linux scheduler uses this for **preferred-core** / boost behavior. |
| **CPPC Preferred Cores** | **Enabled** | Marks fastest cores for the scheduler. | Helps single-thread games hit the best cores on X3D. |
| **IOMMU** | **Disabled** | I/O Memory Management Unit — DMA remapping for VMs/pass-through. | Same as SVM off — not needed without VMs; can stay off unless you enable Hyper-V/VBS later. |

**Thermal cap** *(only if gaming still **> 90 °C** after CO + fans)*: PPT **120 W**, TDC **75 A**, EDC **140 A**.

**Do not:** positive CO, manual CPU voltage, 10× Scalar, manual CPU ratio.

---

## Memory — 6000 MHz CL30 *(done — already applied)*

**Status: complete on this machine.** Do not re-tune unless a CMOS clear / BIOS update resets settings. Table below is the recovery reference only.

*Kit:* G.Skill **Ripjaws S5** `F5-6800J3446F48GX2-RS5K` (2×48 GB dual-rank, Intel XMP 6800). **6800 XMP did not hold**; daily driver is **6000 CL30-36-36-30** manual.

*Path (if re-applying):* **Tweaker** → **Advanced Memory Settings** · **DRAM Timing Control** for sub-timings.

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **XMP/EXPO Profile** | **XMP I** then manual override | Loads kit baseline before manual 6000 profile. | Ripjaws kit is Intel XMP — use **XMP I**, then apply values below. |
| **System Memory Multiplier** | **6000 MT/s** | RAM data rate. | Stable sweet spot for 2×48 GB dual-rank on AM5; 6800 XMP failed to hold. |
| **FCLK** | **2000 MHz** | Infinity Fabric clock. | Async from UCLK 3000 — validated stable pairing with 6000 MT/s on AM5. |
| **UCLK DIV1 MODE** | **UCLK = MEMCLK** | Memory controller clock matches RAM speed. | **1:1 at 6000** (3000 MHz UCLK) — best latency sweet spot for 2×48 GB on AM5. |
| **tCL** | **30** | CAS latency. | Part of validated CL30 primary set. |
| **tRCD (Read & Write)** | **36** | RAS to CAS delay. | Validated stable primary timing. |
| **tRP** | **36** | Row precharge time. | Validated stable primary timing. |
| **tRAS** | **30** | Row active time. | Validated stable on this build. |
| **tRC** | **66** | Row cycle time. | **tRAS + tRP** (30 + 36). |
| **tRFC1 / tRFC2** | **Auto** | Refresh cycle timings. | Stable at Auto on this profile. |
| **DRAM VDD / VDDQ** | **1.35 V** | Module core / I/O voltage. | Stable voltage for 6000 CL30 on this kit. |
| **SOC / CPU VDDIO** | **1.15 V** | Memory controller I/O voltage. | Conservative SOC — stable for 2×48 GB @ 6000; bump to **1.20 V** if training fails after a BIOS update. |
| **CPU VDDQ SOC** | **1.15 V** | SOC DQ voltage. | Matches validated profile. |
| **DDR5 Auto Booster** | **Disabled** | Dynamically switches between JEDEC and a higher “boost” speed. | Avoids mid-session frequency changes; one fixed speed. |
| **EXPO AI BOOST** | **Disabled** | Gigabyte AI memory tuning via AORUS software. | Opaque vs known manual profile. |
| **XMP/EXPO High Bandwidth Support** | **Enabled** | Wider memory mode when XMP/EXPO is active. | Extra throughput with manual profile active. |
| **XMP/EXPO Low Latency Support** | **Enabled** | Tighter controller behavior with profile active. | Pairs with High Bandwidth for latency. |
| **Gear Down Mode (GDM)** | **Disabled** | Half-rate command/address clocking. | Cleaner training on manual timings. |
| **Memory Context Restore** | **Enabled** | Saves trained RAM context to skip full re-train on warm boot. | Faster POST on a proven-stable profile. |
| **Power Down Enable (PDM)** | **Enabled** | Allows memory power-down between accesses. | Pairs with MCR for faster warm boot. |

---


## Virtualization & extras

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **IOMMU** | **Disabled** | PCIe DMA remapping (Settings menu duplicate of AMD CBS). | No VMs or passthrough on this machine. |
| **SR-IOV Support** | **Disabled** | Single Root I/O Virtualization — splits one PCIe device into many virtual functions. | Datacenter/VM feature; unused on a desktop gaming box. |
| **Network Stack** | **Disabled** | UEFI PXE/HTTP network boot stack. | Not installing over the network; saves POST time and avoids accidental network boot. |
| **Gigabyte Utilities Downloader Configuration** | **Disabled** | Auto-downloads Gigabyte Control Center from the internet at first boot. | You install utilities manually when wanted — avoids unwanted background install. |
| **3DMark01 Enhancement** | **Disabled** | Legacy tweak for old **3DMark 2001** benchmark scores. | Irrelevant to modern games; can skew timing behavior for no benefit. |

---

## Power & QoL

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **ErP** | **Disabled** | EuP/ErP — cuts standby power to near zero in S5 shutdown (USB off, no wake). | **Disabled** keeps **USB power + wake** (keyboard, mouse, WoL) working. |
| **Wake on LAN** *(Platform Power / AC Back)* | **Enabled** if you remote-power the AI box | Boots / wakes from magic packet. | Optional — pair with Arch `wol` on the NIC; keep **ErP Disabled**. |
| **Power Loading** | **Enabled** | Adds a dummy load so the PSU sees minimum current on +12V. | Some **SFX PSUs** shut off or trip at very low load. |
| **Full Screen LOGO Show** | **Disabled** | Gigabyte splash screen during POST. | Slightly faster visual boot to systemd-boot / Arch. |

---

## Smart Fan 6 — CPU_FAN unlock only (not the daily controller)

*F2 → **CPU_FAN*** (OpenITX has **no case fans** — ignore / leave unused **SYS_FAN*** headers)

**Daily fan control is CoolerControl on Arch** for the AXP90 — see [`arch_install.md`](arch_install.md). BIOS does **not** own the CPU curve after boot. GPU fans stay on the card (NVIDIA / CoolerControl NVML).

Gigabyte ITE chips (often **IT8689**) only allow OS manual PWM after this specific BIOS curve is set on the header you control. Without it, CoolerControl / `it87` cannot take **CPU_FAN**.

| Setting | Set to | What it does | Why this value |
|---------|--------|--------------|----------------|
| **Fan Speed Control** | **Manual** | BIOS curve mode vs preset. | Required so the EC exposes manual PWM to the `it87` driver. |
| **FAN/PUMP Control Mode** | **PWM** | **PWM** (4-pin) vs **Voltage** (3-pin). | AXP90 is **4-pin PWM**. |
| **FAN/PUMP Stop** | **Disabled** *(CPU fan)* | Fan-stop below a temp threshold. | Never allow CPU fan stop under load. |
| **Curve** *(IT8689 unlock)* | PWM **40 / 40 / 40 / 40 / 40 / 40 / 100** · temps **0 / 90 / 90 / 90 / 90 / 90 / 90** | EC curve points CoolerControl docs require. | Holds **40 %** only until `coolercontrold` starts; **100 % @ 90 °C** failsafe. **Not** your tuned profile. |

**Apply** on **CPU_FAN** → **F3** save → **F10**. Then build the real CPU curve in CoolerControl (CPU package temp → CPU_FAN).

---

## GPU tuning — Arch (NVIDIA)

**Card:** HP **OMEN** desktop OEM **RTX 5090** 32 GB (~**575 W** stock TGP, ~**330 mm**, axial cooler). Heat dumps into the SFF chassis — establish a stock thermal baseline (games **and** LLM load) before undervolting.

**Driver:** `nvidia-open` — see [`arch_install.md`](arch_install.md).

| Setting | Value | What it does | Why for OpenITX |
|---------|-------|--------------|-----------------|
| **Power limit** | **Stock** first | Caps sustained board power (TGP). | OEM ~**575 W** stresses SF1000 + OpenITX airflow. Lower with `nvidia-smi -pl` after measuring soak. |
| **Voltage / curve** | **Stock** → TBD undervolt | Shifts V/F curve (Coolbits / third-party tools). | No validated UV yet for this OEM card in this case. |
| **Core / mem clock** | **Stock** | Manual GPU/VRAM offset. | Prefer undervolt over OC in SFF; VRAM OC adds heat for little gain. |
| **Fan curve** | OEM auto, or custom below | Temp → fan %. | Axial cooler must move air; never **0 %** fan under load. |

### Provisional fan targets

Target **≤ 85 °C** GPU hotspot in games / sustained inference when possible.

| GPU temp °C | Fan % |
|-------------|-------|
| ≤ 40 | **30** |
| 55 | **40** |
| 65 | **55** |
| 75 | **70** |
| 85 | **85** |
| 90+ | **100** |

**Do not:** 0 % fan under load; raising power limit above stock in this case.

**Power cable:** **Native 12V-2x6 confirmed** — keep fully seated; avoid sharp bends at the GPU plug. If PSU trips under LLM load: `nvidia-smi -pl 450` (tune to taste).

**Targets:** CPU gaming/inference **70–85 °C** (≤ 90 °C) · GPU **≤ 85–90 °C** under sustained load · watch PSU transient headroom on SF1000

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No POST after memory change | Clear CMOS → one stick in A2 → JEDEC 5600 → re-apply Memory table |
| RAM training fails after BIOS update | Retry; if needed bump **SOC** to **1.20 V** |
| WHEA / idle freeze with CO **−35** | Back off Curve Optimizer by **5**; test light-load stability |
| Game stutter | Toggle **Global C-state Control** Enabled ↔ Disabled |
| Fans stuck ~40 % | CoolerControl / `it87` not loaded — see [`arch_install.md`](arch_install.md); confirm BIOS unlock curve |
| GPU crash / black screen under load | Reseat **12V-2x6**; `nvidia-smi -pl` −5–10 %; check SF1000 headroom |

Hardware: [`parts.md`](parts.md) · Install: [`arch_install.md`](arch_install.md) · Overview: [`README.md`](README.md)
