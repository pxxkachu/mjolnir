# Mjolnir — BIOS & Performance Tuning Guide

Step-by-step instructions to tune **BIOS settings**, **fan curves**, **CPU undervolt**, **RAM (XMP)**, and **GPU undervolt** on the Mjolnir SFF build.

**Read first:** strategy and research — [`bios_optimize_plan.md`](bios_optimize_plan.md)  
**Hardware reference:** [`parts.md`](parts.md)  
**Prerequisite:** Arch installed via [`post_install.md`](post_install.md) (at least through gaming stack + monitoring tools)

---

## Overview

| Phase | What | Where |
|-------|------|--------|
| 0 | Foundation BIOS | Gigabyte B850I BIOS |
| 1 | RAM — XMP @ 6800 | BIOS |
| 2 | Fan control | BIOS flat handoff — Phase 2 here; Linux — [`post_install.md` § 12](post_install.md#12-fan-control-coolercontrol) |
| 3 | CPU undervolt (PBO + Curve Optimizer) | BIOS |
| 4 | RAM tighten *(optional)* | BIOS |
| 5 | GPU undervolt + blower fan | Arch — LACT |
| 6 | Validation & lock-in | BIOS + Linux |

**Order is mandatory.** Do not tune Curve Optimizer until XMP and fan curves are stable.

---

## Before you begin

### Tools & access

| Item | Detail |
|------|--------|
| BIOS key | **Del** at POST |
| Save & exit | **F10** |
| Smart Fan 6 | **F2** or **Tuner** tab |
| Clear CMOS | Rear I/O button or jumper — use when POST fails |
| BIOS manual | [Gigabyte AMD 800 Series](https://download.gigabyte.com/FileList/Manual/mb_manual_amd800-bios_e_20260512.pdf) |

### Linux packages (installed system)

```bash
sudo pacman -S --needed stress-ng lm_sensors mangohud
sudo sensors-detect   # accept defaults for AMD; optional
paru -S lact          # Phase 5 — after paru is installed
```

### Record baseline (fill in before tuning)

| Metric | Before tuning | After tuning |
|--------|---------------|--------------|
| Game (title: ________) FPS avg | | |
| CPU peak gaming °C | | |
| GPU junction peak gaming °C | | |
| GPU power avg gaming W | | |
| Subjective noise (1–10) | | |

### Fan header map *(fill at build time)*

| Fan | Connected to | Notes |
|-----|--------------|-------|
| Thermalright AXP90-X47 | **CPU_FAN** | 4-pin PWM |
| Noctua NF-A12x15 (bottom intake) | **SYS_FAN___** | 4-pin PWM |
| Phanteks T30 (bottom intake) | **SYS_FAN___** | 4-pin PWM |

### Final settings log *(fill when done)*

| Setting | Final value |
|---------|-------------|
| BIOS version | |
| XMP profile | XMP I / Enabled |
| Curve Optimizer (all-core) | −____ |
| PPT / TDC / EDC limits | Auto / Manual: ____ |
| GPU voltage offset (LACT) | −____ mV |
| Date locked in | |

---

## Phase 0 — Foundation BIOS

Do this on **first boot** (Windows not required — can use Arch live USB or installed Arch).

### 0.1 Update BIOS

1. On another machine, download latest **non-beta** BIOS for **B850I AORUS PRO** from [Gigabyte support](https://www.gigabyte.com/Motherboard/B850I-AORUS-PRO/support).
2. Copy to FAT32 USB.
3. Boot → **Del** → **Q-Flash** (or **F8**) → update from file.
4. Reboot; **Load Optimized Defaults** if prompted, then re-apply settings below.

### 0.2 Essential settings

Enter BIOS → use **Advanced** mode (not Easy Mode).

| # | Setting | Value | Navigation (typical) |
|---|---------|-------|----------------------|
| 1 | **CSM Support** | **Disabled** | BIOS → Settings → Miscellaneous |
| 2 | **Secure Boot** | **Disabled** *(Linux)* or Enabled per preference | BIOS → Settings → Trusted Computing |
| 3 | **Above 4G Decoding** | **Enabled** | Settings → IO Ports |
| 4 | **Re-Size BAR Support** | **Enabled** | Settings → IO Ports |
| 5 | **IOMMU / SVM Mode** | **Disabled** | Settings → IO Ports *(no VMs on this build)* |
| 6 | **ERP** | **Disabled** | Settings → Platform Power |
| 7 | **Boot Mode** | **UEFI** only | Verify in Boot menu |

Press **F10** → Save & reset.

**Do not change yet:** CPU ratio, manual voltage, memory timings beyond XMP (Phase 1).

---

## Phase 1 — RAM (XMP @ 6800)

**Kit:** G.Skill Ripjaws S5 `F5-6800J3446F48GX2-RS5K` — 2×48 GB, 6800 MT/s, CL34-46-46-108, **Intel XMP 3.0**, 33 mm height.

### 1.1 Physical install check

- DIMMs in **2 slots only** — use **A2 + B2** (2nd and 4th slots from CPU) per motherboard manual for dual-channel.
- Both modules fully seated until clips click.
- **33 mm** Ripjaws S5 clears the AXP90-X47 without issue.

### 1.2 Enable XMP

1. **Del** → **M.I.T.** tab.
2. **Advanced Memory Settings**.
3. **XMP** → **XMP I** → **Enabled** *(profile showing **6800 MT/s**)*.
4. Confirm on screen:
   - **6800 MT/s**
   - **CL34-46-46-108**
   - **1.35 V** DRAM
5. Set **FCLK** to **3400 MHz** if exposed *(UCLK 1:1 at 6800)*.
6. **Memory Context Restore** → **Disabled** *(during tuning; enable in Phase 6)*.
7. **F10** → Save.

If the board fails to POST (loops, no display):

1. Power off → **Clear CMOS**.
2. Boot with one stick in **A2** only → BIOS → disable XMP → shut down → install second stick → enable XMP again.
3. Update BIOS if still failing (common fix for 2×48 GB kits).
4. If XMP 6800 will not train: try **6400** or **6000** manual speed before aggressive SOC tweaks.

### 1.3 Verify in Linux

```bash
sudo dmidecode -t memory | grep -E 'Speed|Size|Locator|Configured'
```

Expected: **6800 MT/s** configured *(or highest stable speed you locked in)*, **48 GB** per module.

```bash
# Check for memory errors after boot
dmesg | grep -iE 'mce|hardware error|edac'
```

### 1.4 Stability tests

Run after **every** RAM or BIOS change in later phases too.

**Quick (required):**

```bash
# 30+ minutes of normal use + one gaming session
```

**Memory stress (recommended after XMP enable):**

```bash
# Leave ~8–12 GB for OS — adjust bytes if needed
stress-ng --vm 2 --vm-bytes 42G --vm-method all --timeout 1h
```

**Pass criteria:**

- No reboot or freeze
- `dmesg | grep -i mce` shows nothing new
- Games do not stutter abnormally

### 1.5 XMP troubleshooting

If unstable, try in order — **one change at a time**, retest:

| Step | Action |
|------|--------|
| 1 | Update BIOS |
| 2 | Reseat RAM |
| 3 | Clear CMOS → XMP only |
| 4 | Manual: **6800**, timings **34-46-46-108**, **1.35 V**, **FCLK 3400** (1:1 UCLK) |
| 5 | Step down: **6400** / **6000** if 6800 will not train |
| 6 | VSOC: leave **Auto** first; if needed small increase — **never exceed 1.30 V** long-term |

**Do not** assume 6800 will POST first try on 2×48 GB AM5 — have a fallback speed in mind.

---

## Phase 2 — Fan control (BIOS handoff)

Gigabyte Smart Fan 6 **cannot** tune gaming curves in BIOS on this board — **CPU_FAN** locks at **70 °C**, **SYS_FAN1** at **60 °C**. Use a **flat Manual curve** in BIOS so firmware releases PWM to Linux, then follow **[`post_install.md` § 12](post_install.md#12-fan-control-coolercontrol)** for CoolerControl.

**Order:** BIOS steps below → post-install § 12 → Phase 3 Curve Optimizer.

### 2.1 Why BIOS-only curves fail

| Header | Firmware lock | Effect with CPU temp input |
|--------|---------------|---------------------------|
| **CPU_FAN** | 100 % @ **70 °C** (point 7) | Max speed for most gaming (70–85 °C) |
| **SYS_FAN1** | Points **6 + 7 @ 60 °C** | Max speed whenever CPU ≥ 60 °C |
| **SYS_FAN2** | Check in Smart Fan 6 | May lock at 70 °C instead |

Locked points cannot move to 90 °C ([Gigabyte reports](https://linustechtips.com/topic/1586458-gigabyte-smart-fan-6-maxes-out-fan-curve-at-70-degrees-c/)). **Do not use TUNE ALL** or Silent/Normal presets.

### 2.2 Open Smart Fan 6

1. **Del** at POST.
2. Press **F2** *or* **Tuner** → **Smart Fan 6**.

### 2.3 Flat Manual curve (every header)

Configure **`CPU_FAN`**, **`SYS_FAN1`**, and **`SYS_FAN2`** the same way. **Do not use TUNE ALL.**

| Setting | Value |
|---------|-------|
| Fan Speed Control | **Manual** |
| Control Mode | **PWM** |
| Temperature Input | **CPU** *(ignored once flat)* |
| Fan Stop | **Disabled** on CPU fan |
| Fan Fail Warning | **Enabled** |
| Curve Mode | **Slope** |

Set this curve on **each** header ([it87 BIOS handoff](https://github.com/frankcrawford/it87)):

| Point | Temp °C | PWM % |
|-------|---------|-------|
| 1 | 0 | 40 |
| 2 | 90 | 40 |
| 3 | 90 | 40 |
| 4 | 90 | 40 |
| 5 | 90 | 40 |
| 6 | 90 | 40 |
| 7 | 90 | 100 |

1. Click **Apply** after each header.
2. Note which physical fan (Noctua vs Phanteks T30) is on SYS_FAN1 vs SYS_FAN2 — you need this for CoolerControl.
3. **Save Fan Profile (F3)** → **F10** Save & exit.

### 2.4 Continue in Linux

Boot to Arch and complete **[post_install.md § 12 — Fan control](post_install.md#12-fan-control-coolercontrol)** (`it87-dkms-git`, CoolerControl, curves, validation). Do **Phase 3** only after fans are stable.

---

## Phase 3 — CPU undervolt (9800X3D)

**Goal:** Less heat and power with same gaming performance — **not** max benchmark scores.

### 3.1 Enable PBO

1. **Del** → **Tweaker** or **M.I.T.** → **Advanced AMD Overclocking** *(accept full mode warning if shown)*.
2. **Precision Boost Overdrive** → **Advanced** *(or Enabled)*.
3. **PBO Limits** → **Motherboard** *(start here)*.
4. **Boost Override** → **+0 MHz** *(do not OC X3D)*.
5. **Scalar** → **Auto** or **1X**.
6. **F10** → Save → boot → verify stable before CO.

### 3.2 Curve Optimizer — step by step

1. Same menu: **Curve Optimizer** → **Negative**.
2. Mode: **All Cores**.
3. Start at **−10**.
4. **F10** → Save → boot to Linux.

**Test after each step (−10, −15, −20, …):**

```bash
# 1 h normal desktop + web browsing
# 30 min gaming
stress-ng --cpu 0 --timeout 30m
dmesg | grep -i mce
```

| Result | Next action |
|--------|-------------|
| Stable, temps improved | Try **−5** more (e.g. −10 → −15) |
| Crash, freeze, or WHEA error | Revert **5** steps (e.g. −20 crash → use −15) |
| Stable but no temp gain | Stop — keep current value |

**Typical stable range:** **−15 to −25** all-core (silicon lottery — do not copy forum extremes).

### 3.3 Optional — SFF power cap

Only if CPU still exceeds **90 °C** in games **after** fans + CO:

**PBO** → **Limits** → **Manual**:

| Setting | Start value | Notes |
|---------|-------------|-------|
| PPT Limit | **120 W** | Package power cap |
| TDC Limit | **75 A** | Sustained current |
| EDC Limit | **140 A** | Peak current |

Retest gaming FPS. Raise caps if FPS drops more than ~2 %.

### 3.4 Optional — per-core Curve Optimizer

Skip unless all-core CO hits a wall and you want more tuning time.

1. **Curve Optimizer** → **Per Core**.
2. Test cores individually — give **weaker** cores **less negative** offset (e.g. −20 on strong, −10 on weak).
3. Requires many test cycles — see [`bios_optimize_plan.md`](bios_optimize_plan.md).

### 3.5 What not to change

- Positive Curve Optimizer without testing
- Manual core voltage overrides
- Disabling Global C-States as a first fix

---

## Phase 4 — Optional RAM tightening

**Skip unless XMP + CO + fans are 100 % stable for a week.**

Low priority on **9800X3D** — gaming gains are usually tiny.

| Tweak | Steps |
|-------|-------|
| Try **CL32** instead of CL34 | M.I.T. → Advanced Memory Settings → primary timing **tCL** → 32 → stress test 1 h |
| Revert | CL34 or disable manual → XMP only |

**Not recommended for daily use:** 7200+ MT/s, aggressive SOC, copied 2×16 GB presets.

---

## Phase 5 — GPU undervolt & fan (Linux)

GPU tuning is **not** in Gigabyte BIOS. Requires **Arch** + **LACT**.

### 5.1 Enable AMDGPU overdrive

Edit boot entry:

```bash
sudo nano /boot/loader/entries/arch.conf
```

Append to the **`options`** line:

```text
amdgpu.ppfeaturemask=0xffffffff
```

Example:

```text
options root=UUID=... rw amdgpu.ppfeaturemask=0xffffffff
```

Rebuild initramfs and reboot:

```bash
sudo mkinitcpio -P
sudo reboot
```

Verify:

```bash
cat /sys/module/amdgpu/parameters/ppfeaturemask
```

### 5.2 Install and start LACT

```bash
paru -S lact
sudo systemctl enable --now lactd
```

Open **LACT** from the app grid (or `lact gui`).

### 5.3 Baseline logging

Launch a repeatable game/benchmark with MangHud:

```bash
gamemoderun mangohud %command%
```

Record for **10–15 min** under load:

- GPU junction temp
- GPU power (W)
- Core clock (MHz)
- FPS

### 5.4 Undervolt procedure

In **LACT** → select **RX 7900 XT** → **Performance** tab:

1. Switch power profile to **Manual**.
2. Apply a small **voltage offset** first: **−50 mV** *(or reduce voltage in the frequency/voltage curve if using curve editor)*.
3. Apply → run the same game 30 min.
4. If stable and FPS within **~1 %** of baseline, try **−75 mV**, then **−100 mV**.
5. **Stop** when: artifacting, crash, large FPS drop, or no further temp improvement.

**Goals (reference blower in SFF):**

- Lower junction temp → less hot air recirculated over CPU
- Lower fan RPM at same performance → less noise

### 5.5 Blower fan curve (LACT)

**Thermals** tab → **Custom curve** (not automatic):

| Junction °C | Fan % |
|-------------|-------|
| 40 | 25 |
| 60 | 40 |
| 70 | 55 |
| 80 | 70 |
| 90 | 85 |
| 100 | 100 |

After undervolt validates, try **lowering each tier by ~5–10 %** and retest.

**Never** set 0 % on a reference blower GPU.

### 5.6 Save LACT profile

Screenshot or export profile settings into the **Final settings log** at the top of this doc.

### 5.7 GPU rollback

| Issue | Fix |
|-------|-----|
| Artifacts / crash | Reduce UV offset; reset LACT to default |
| Overdrive missing | Check `ppfeaturemask`; `mkinitcpio -P`; reboot |
| Settings not applying | Confirm `lactd` running: `systemctl status lactd` |

---

## Phase 6 — Validation & lock-in

### 6.1 Target metrics

| Metric | Target | Max acceptable |
|--------|--------|----------------|
| CPU gaming | 70–85 °C | 90 °C |
| CPU all-core stress | 85–95 °C | 95 °C *(AMD design)* |
| GPU junction gaming | 75–90 °C | 100 °C |
| Gaming FPS vs baseline | Within 1–2 % | — |

### 6.2 Final test suite

Run over **2–3 sessions** (not all in one day):

```bash
# Desktop + browser — 1 h
# Gaming — 2 h combined
stress-ng --cpu 0 --timeout 30m
stress-ng --vm 2 --vm-bytes 42G --timeout 30m
dmesg | grep -i mce
journalctl -b | grep -iE 'hardware error|mce'
```

### 6.3 BIOS lock-in

1. **Memory Context Restore** → **Enabled** *(faster boot)*.
2. **Save Fan Profile** again.
3. Save BIOS profile to flash / photo all tuning screens.
4. Fill in **Final settings log** at top of this document.

### 6.4 Lock-in checklist

- [ ] XMP 6800 stable 24 h+ *(or documented fallback speed)*
- [ ] BIOS flat Manual handoff saved (Phase 2)
- [ ] CoolerControl enabled — see [`post_install.md` § 12](post_install.md#12-fan-control-coolercontrol)
- [ ] Curve Optimizer value documented
- [ ] LACT GPU profile saved
- [ ] No WHEA / MCE in `dmesg`
- [ ] 1 week daily use without crashes
- [ ] Commit updated `bios_optimize.md` final values to git

---

## Troubleshooting

### Will not POST after RAM change

1. Clear CMOS.
2. One DIMM in A2, boot, disable XMP.
3. Shut down, add second DIMM, enable XMP.
4. Update BIOS.

### Random freezes after Curve Optimizer

1. Reduce CO by **5** (less negative).
2. Confirm RAM stable (`stress-ng --vm`).
3. Check `dmesg` for MCE — may be memory not CPU.

### CPU always at 95 °C in stress

Normal for **9800X3D** under **all-core** load ([TechPowerUp](https://www.techpowerup.com/review/amd-ryzen-7-9800x3d/25.html)). Worry if **gaming** constantly exceeds 90 °C — raise intakes or add PPT cap.

### GPU thermals hurt CPU temps

Reference blower recirculates heat. **Phase 5 GPU undervolt** + bottom intake curves are the main fix.

### Clear CMOS procedure

1. Shut down, switch off PSU.
2. Press **Clear CMOS** button *(or short jumper per manual)* ~5 s.
3. Power on → re-enter BIOS → redo Phases 0–2 minimum.

---

## Quick reference — BIOS menu map

| Task | Typical path (Gigabyte B850I) |
|------|-------------------------------|
| XMP | M.I.T. → Advanced Memory Settings → XMP |
| PBO / Curve Optimizer | Tweaker → Advanced AMD Overclocking |
| Above 4G / Re-Size BAR | Settings → IO Ports |
| Smart Fan 6 | F2 / Tuner → Smart Fan 6 |
| Q-Flash BIOS update | F8 or Q-Flash in BIOS |
| Load defaults | F7 or Save & Exit → Load Optimized Defaults |

---

## Related files

| File | Purpose |
|------|---------|
| [`bios_optimize_plan.md`](bios_optimize_plan.md) | Research, constraints, rationale |
| [`parts.md`](parts.md) | Full hardware list |
| [`post_install.md`](post_install.md) | Arch install, Steam, MangHud, sensors |
