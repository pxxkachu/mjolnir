# Mjolnir — BIOS & Tuning Optimization Plan

Design document for balancing **performance, thermals, and noise** on the Mjolnir SFF gaming build. Hardware source of truth: [`parts.md`](parts.md).

**Scope of this document:** research-backed **plan only**. Step-by-step BIOS walkthrough and Linux GPU tuning guide follow in **`bios_optimize.md`** (to implement after this plan is approved).

---

## Executive summary

| Area | Where tuned | Primary goal |
|------|-------------|--------------|
| **Foundation BIOS** | Gigabyte B850I BIOS | UEFI, Re-Size BAR, latest AGESA |
| **RAM** | BIOS (XMP → optional manual) | Stable **6800 XMP** on 2×48 GB dual-rank |
| **CPU undervolt** | BIOS (PBO + Curve Optimizer) | Lower heat/noise; keep gaming perf |
| **Fan curves** | BIOS (Smart Fan 6) | Cool bottom-intake SFF under load |
| **GPU undervolt / fan** | **Linux (LACT)** — not motherboard BIOS | Cut blower heat/recirculation; same FPS |

This build is **thermally constrained** (47 mm CPU cooler, reference blower GPU, dual bottom intake). The plan prioritizes **efficiency tuning** over chasing clocks — especially on the **9800X3D**, where Curve Optimizer undervolting often beats raw overclocking for gaming.

---

## System constraints (why this plan looks the way it does)

```
                    ┌─────────────────────────────┐
  Cool air in ─────►│ Bottom: Noctua A12x15 slim  │
  (both intake)     │ Bottom: Phanteks T30        │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  Thorzone Mjolnir (SFF)       │
                    │  ┌─────────┐  ┌────────────┐  │
                    │  │ 9800X3D │  │ 7900 XT    │  │
                    │  │ AXP90   │  │ ref blower │──┼──► hot air recirculates
                    │  │ -X47    │  │ (into case)│  │    into case
                    │  └─────────┘  └────────────┘  │
                    │         PSU exhaust ↑           │
                    └─────────────────────────────┘
```

| Component | Thermal reality |
|-----------|-----------------|
| **9800X3D + AXP90-X47** | ~**76–85 °C** gaming typical; **up to 95 °C** on long all-core loads is AMD-normal ([TechPowerUp](https://www.techpowerup.com/review/amd-ryzen-7-9800x3d/25.html)). Cooler ~**105 W sustained** ceiling in 47 mm class. |
| **2×48 GB DDR5** | **Dual-rank high capacity** — memory controller stress; **6800 XMP is aggressive** on AM5 (Intel-validated kit); may need BIOS updates, manual FCLK, or fallback to 6400/6000 ([Overclock.net dual-rank thread](https://www.overclock.net/threads/amd-high-capacity-ddr5-oc-dual-rank-dimms.1816297/)). **9800X3D gaming is cache-bound** — faster RAM yields diminishing returns ([Igor'sLab](https://www.igorslab.de/en/amd-ryzen-7-9800x3d-in-gaming-test-overclocked-undervolted-and-found-to-be-good/4/)). |
| **7900 XT reference** | Blower dumps heat **into** the case → CPU cooler fights GPU waste heat. **GPU undervolt + fan curve** matters as much as CPU tuning. |
| **Bottom-only intake** | Positive pressure; **dust filters** need maintenance. No dedicated top exhaust fan — rely on vents + PSU + GPU blower path. |

---

## BIOS vs Linux: who owns what

| Setting | Tool | Notes |
|---------|------|-------|
| XMP, EXPO, SOC, timings | **BIOS** | Gigabyte M.I.T. / AMD Overclocking |
| PBO, Curve Optimizer, PPT limits | **BIOS** | AMD Overclocking menu |
| Smart Fan 6 flat handoff | **BIOS** | Release PWM to OS |
| Case/CPU fan curves | **Linux: CoolerControl** | `post_install.md` § 12 |
| Re-Size BAR / Above 4G | **BIOS** | Tweaker → Settings |
| GPU voltage / clock curve | **Linux: LACT** | Needs `amdgpu.ppfeaturemask` kernel param ([Arch AMDGPU wiki](https://wiki.archlinux.org/title/Amdgpu)) |
| GPU fan curve (blower) | **Linux: LACT** | Not available in Gigabyte BIOS |
| Monitoring | **Linux** | `lm_sensors`, `amdgpu_top`, `mangohud`, `cpupower`, `watch sensors` |

---

## Prerequisites

### Before changing anything

1. **Update BIOS** on Gigabyte B850I AORUS PRO to latest stable (not beta unless fixing a known issue). AM5 + 2×48 GB training improved across AGESA releases ([example dual 48 GB fix](https://www.overclock.net/threads/9800x3d-rog-x670e-hero-48x2-memory-dual-channel-issue.1814233/)).
2. **Clear CMOS procedure** documented (jumper or button) — required when RAM or CO goes too far.
3. **Save BIOS profile** via Smart Fan / BIOS profile save before experiments ([Gigabyte Smart Fan 6](https://download.gigabyte.com/FileList/Manual/mb_manual_amd800-bios_e_20260512.pdf)).
4. **Baseline logging** (stock BIOS except Re-Size BAR + XMP):
   - Gaming: CPU/GPU peak temps, FPS (one repeatable title)
   - Optional all-core: `stress-ng` or Cinebench equivalent from Linux
5. **Arch monitoring packages** (already mostly in install): `lm_sensors`, `cpupower`, `mangohud`; add **`lact`** in tuning phase.

### Gigabyte BIOS access

| Action | Key / path |
|--------|------------|
| Enter BIOS | **Del** at POST |
| Smart Fan 6 | **F2** or **Tuner** → **Smart Fan 6** |
| Save & exit | **F10** |
| Load Optimized Defaults | **F7** or Exit menu |

Reference manual: [Gigabyte AMD 800 Series BIOS Setup](https://download.gigabyte.com/FileList/Manual/mb_manual_amd800-bios_e_20260512.pdf).

---

## Optimization phases (order matters)

```
Phase 0 ─ Foundation BIOS (no OC)
    ↓
Phase 1 ─ RAM: XMP stable @ 6800
    ↓
Phase 2 ─ Fan control: BIOS handoff (bios_optimize.md) + CoolerControl (post_install.md § 12)
    ↓
Phase 3 ─ CPU: PBO + Curve Optimizer undervolt
    ↓
Phase 4 ─ RAM: optional minor tighten (only if Phase 1 rock-solid)
    ↓
Phase 5 ─ GPU: Linux LACT undervolt + blower fan curve
    ↓
Phase 6 ─ Validation & daily-driver lock-in
```

**Do not** start Curve Optimizer before RAM and fans are stable — unstable memory mimics CPU instability ([SilverPC 9800X3D CO guide](https://blog.silverpc.hu/2025/10/20/the-silent-crash-how-to-diagnose-why-your-ryzen-9800x3d-pbo-undervolt-freezes-your-pc-instantly/)).

---

## Phase 0 — Foundation BIOS

Apply once; rarely changed.

| Setting | Value | Menu (typical Gigabyte) |
|---------|-------|---------------------------|
| CSM Support | **Disabled** | BIOS → Settings |
| Secure Boot | User choice (off for Linux ease) | BIOS → Settings |
| Above 4G Decoding | **Enabled** | Settings → IO Ports |
| Re-Size BAR Support | **Enabled** | Settings → IO Ports |
| IOMMU / SVM | **Disabled** (no VMs) | Settings → IO Ports |
| PCIe Gen | **Auto** or Gen4 for GPU if troubleshooting | Peripherals |
| ERP | **Disabled** (wake/USB behavior) | Settings → Platform Power |
| AMD fTPM | Enabled (default) | Trusted Computing |

**Do not touch yet:** manual CPU ratio, manual core voltage, exotic memory subtimings.

---

## Phase 1 — RAM optimization (Ripjaws S5 2×48 GB @ 6800)

**Kit:** G.Skill **F5-6800J3446F48GX2-RS5K** — Ripjaws S5, 6800 MT/s, CL34-46-46-108, 1.35 V, **Intel XMP 3.0** ([G.Skill spec](https://www.gskill.com/specification/165/377/1684291674/F5-6800J3446F48GX2-RS5K-Specification)). SPD default: 5600 MT/s @ 1.10 V. **33 mm** low-profile height.

### 1A — XMP only (daily driver baseline)

| Step | Action |
|------|--------|
| 1 | **M.I.T.** → **Advanced Memory Settings** → **XMP** → **XMP I** (or profile showing **6800 MT/s**) → **Enabled** |
| 2 | Confirm displayed speed **6800 MT/s**, timings **34-46-46-108**, **1.35 V** DRAM |
| 3 | **FCLK** → **3400 MHz** for UCLK 1:1 at 6800 *(if board shows MCLK/UCLK; otherwise leave Auto and verify)* |
| 4 | **Memory Context Restore** → **Disabled** during initial validation; **Enabled** after 24 h stable |
| 5 | Boot → Linux → verify with `dmidecode -t memory` / `sudo lshw -class memory` |

**Reality check:** 2×48 GB dual-rank @ **6800** on AM5 is harder than EXPO kits. If XMP fails to train, step down to **6400** or **6000** before chasing SOC/voltage ([96 GB OC thread](https://www.overclock.net/threads/96gb-2x48-ddr5-6000-oc-help-questions.1819103/)).

### 1B — Stability testing (Linux)

Run after every RAM change:

| Test | Command / tool | Duration |
|------|----------------|----------|
| Quick smoke | Boot + 30 min gaming | 30 min |
| Memory stress | `stress-ng --vm 4 --vm-bytes 80G --timeout 1h` (adjust to leave headroom) | 1 h |
| Optional | `memtest86+` from USB (offline) | 1–4 passes |

**Pass criteria:** No crashes, no MCE in `dmesg`, no game stutter.

### 1C — If XMP fails to train / unstable

Troubleshoot in order:

1. Update BIOS
2. Reseat DIMMs (A2 + B2 slots per manual — **2-DIMM config only**)
3. Clear CMOS → enable XMP again
4. Manual fallback: **6800 MT/s**, **1.35 V** DRAM, primary timings **34-46-46-108**, **FCLK 3400** (UCLK 1:1 at 6800)
5. If still failing: **6400** or **6000 MT/s** with proportional FCLK (3200 / 3000) — document actual stable speed
6. **VSOC** — leave Auto first; if needed, small bump only; **stay ≤ 1.30 V** long-term ([AMD guidance cited in tuning community](https://blog.silverpc.hu/2025/10/20/the-silent-crash-how-to-diagnose-why-your-ryzen-9800x3d-pbo-undervolt-freezes-your-pc-instantly/))
7. Advanced (last resort for 48 GB): **PMIC voltages** on Auto; do not copy 2×16 GB Hynix A-die presets blindly

### 1D — Optional RAM tightening (Phase 4 — advanced)

Only after CPU CO and fans are done. **Low priority** for this build.

| Tweak | Risk | Expected gain |
|-------|------|---------------|
| CL34 → CL32 (if stable) | High on 2×48 GB | Small latency; marginal in games on X3D |
| Manual tRFC, tRCD subtimings | High on 48 GB | Benchmark only |
| 6800 → 7200 | **Very high** on 2×48 GB | Often unstable; not recommended |

**Recommendation:** **Run XMP 6800** if it trains cleanly; otherwise lock in the highest stable speed (6400/6000) for daily use. Revisit manual tuning only if bored and stable.

---

## Phase 2 — Fan control (BIOS handoff + Arch)

- **BIOS:** [`bios_optimize.md` Phase 2](bios_optimize.md#phase-2--fan-control-bios-handoff) — flat Manual ~40 % PWM per header
- **Linux:** [`post_install.md` § 12](post_install.md#12-fan-control-coolercontrol) — `it87-dkms-git`, CoolerControl, GPU+CPU mix curves

Gigabyte Smart Fan 6 locks CPU_FAN @ 70 °C and SYS_FAN1 @ 60 °C — OS control required for gaming.

### Fan header mapping (confirm in manual — fill at build time)

| Physical fan | Likely header | Control mode |
|--------------|---------------|--------------|
| AXP90-X47 (CPU) | **CPU_FAN** | **PWM** (4-pin) |
| Noctua A12x15 (bottom) | **SYS_FAN** _?_ | **PWM** — set explicitly, not Auto |
| Phanteks T30 (bottom) | **SYS_FAN** _?_ | **PWM** |
| PSU fan | *(not controlled by board)* | Corsair internal curve |

> **Action at build:** Label which SYS_FAN is Noctua vs T30; update this table in `bios_optimize.md`.

### Global Smart Fan 6 rules

| Rule | Setting |
|------|---------|
| Control mode | **PWM** for all 4-pin fans ([Noctua](https://www.noctua.at/en/support/faqs/how-do-i-optimise-my-fan-settings)) |
| Curve mode | **Manual** (not Silent preset — too weak for SFF) |
| Fan Stop | **Off** on CPU fan; **optional** on Noctua at idle (≤40 °C) |
| Temperature source — CPU fan | **CPU** |
| Temperature source — bottom intakes | **CPU** or **System 1** (chipset) — prefer **CPU** so intakes ramp with gaming load |
| Fail warning | **Enabled** on CPU + system fans |

### Starting curves (adjust after logging)

**CPU fan (AXP90-X47)** — ~10 % faster than case fans at each step ([Noctua guidance](https://www.noctua.at/en/support/faqs/how-do-i-optimise-my-fan-settings)):

| CPU temp °C | PWM % | Notes |
|-------------|-------|-------|
| 40 | 30 | Above minimum stable RPM |
| 55 | 45 | Light gaming |
| 70 | 65 | Sustained gaming |
| 80 | 85 | Heavy load |
| 90 | 100 | Before/throttle zone |

**Bottom intakes (both headers — start identical; split later if needed):**

| CPU temp °C | PWM % | Notes |
|-------------|-------|-------|
| 40 | 25 | Quiet idle (Noctua may allow lower) |
| 55 | 40 | |
| 70 | 60 | Critical for blower GPU heat |
| 80 | 80 | |
| 90 | 100 | Max case airflow |

**Phanteks T30 optional cap:** If noise dominates, set **max PWM 85 %** on T30 header only — it moves more air per RPM than the Noctua.

### Tuning loop

1. Log temps: gaming 30 min + optional all-core stress 10 min
2. If **CPU > 90 °C** in games → raise bottom intakes first (+5 % at 70/80 °C points)
3. If **GPU hotspot high** → bottom intakes + GPU undervolt (Phase 5)
4. If **noise at idle** → lower sub-50 °C points only; keep high-load points aggressive

---

## Phase 3 — CPU undervolt (9800X3D)

**Goal:** Reduce power and heat while preserving gaming performance. **Not** maximum multicore benchmark scores.

### 3A — Enable PBO framework

| Setting | Value | Location |
|---------|-------|----------|
| Precision Boost Overdrive | **Advanced** or **Enabled** | AMD Overclocking → PBO |
| PBO Limits | **Motherboard** first; switch to **Manual** if thermally too hot | PBO section |
| Boost Override | **+0 MHz** (X3D — do not chase OC) | PBO |
| Scalar | **Auto** or **1X** | PBO |

**Optional SFF thermal cap** (if AXP90 cannot keep <90 °C gaming after fans):

| Setting | Suggested range | Effect |
|---------|-----------------|--------|
| PPT Limit | **100–120 W** | Hard cap on package power |
| TDC Limit | **70–80 A** | Sustained current cap |
| EDC Limit | **120–150 A** | Peak current cap |

Use caps **only if** Curve Optimizer + fans insufficient. Test gaming FPS impact.

### 3B — Curve Optimizer (primary undervolt tool)

| Step | Action |
|------|--------|
| 1 | **Curve Optimizer** → sign **Negative** |
| 2 | Start **All Cores → −10** |
| 3 | Boot → test gaming 1 h + light desktop |
| 4 | If stable, step **−5** (→ −15, −20, …) |
| 5 | Stop when: crash, WHEA error, freeze on light load, or **no further temp improvement** |

**Community range:** Many 9800X3D samples stable **−15 to −25** all-core ([Overclock.net](https://www.overclock.net/threads/9800x3d-curve-optimizer-tips.1814218/), [Igor'sLab](https://www.igorslab.de/en/amd-ryzen-7-9800x3d-in-gaming-test-overclocked-undervolted-and-found-to-be-good/4/)). **Silicon lottery** — do not chase forum max.

**Per-core tuning (optional, time-consuming):** If one core limits stability, use **Per Core** CO — weakest core less negative ([Igor'sLab](https://www.igorslab.de/en/amd-ryzen-7-9800x3d-in-gaming-test-overclocked-undervolted-and-found-to-be-good/4/)).

### 3C — Stability testing (Linux-focused)

| Regime | Test | Why |
|--------|------|-----|
| Single-core boost | Gaming menus, single-thread app | CO fails at high boost / light load |
| All-core | `stress-ng --cpu 0 --timeout 30m` | Catches low-frequency high-current faults |
| Real workload | Your heaviest game 2 h | Catches what synthetics miss |

**Watch:** `dmesg | grep -i mce`, random freezes, audio crackle (also check `rtkit`).

**Windows-only tools** (if dual-boot): CoreCycler / y-cruncher per-core — gold standard but not required on Linux-only.

### 3D — What NOT to do on 9800X3D

- **Positive** Curve Optimizer (needs validation; usually not goal)
- High **CO −30+** without testing — instant freeze risk
- **Manual core voltage** overrides without expertise
- Disabling **CPPC** / **Global C-State** as first move — hurts idle efficiency

---

## Phase 4 — Optional RAM tighten

Deferred until Phases 1–3 complete. See [Phase 1D](#1d--optional-ram-tightening-phase-4--advanced).

---

## Phase 5 — GPU undervolt & blower fan (Linux)

**Not in motherboard BIOS** except Re-Size BAR (Phase 0).

### 5A — Enable overdrive on Arch

Add to `/boot/loader/entries/arch.conf` `options` line:

```text
amdgpu.ppfeaturemask=0xffffffff
```

Rebuild initramfs if needed; reboot. Verify:

```bash
cat /sys/module/amdgpu/parameters/ppfeaturemask
```

([Arch AMDGPU — overclocking](https://wiki.archlinux.org/title/Amdgpu), [LACT](https://github.com/ilya-zlobintsev/LACT))

### 5B — Install LACT

```bash
paru -S lact
# enable lact daemon per package instructions
```

### 5C — Undervolt strategy (7900 XT reference)

| Step | Action |
|------|--------|
| 1 | Baseline: log **GPU power, junction temp, core clock** in game (`mangohud`) |
| 2 | LACT → **Performance** → manual → **voltage offset** (negative) or clock/voltage curve |
| 3 | Start conservative: **−50 mV** offset or step down voltage points at 2000–2500 MHz range |
| 4 | Test same game 30 min — compare FPS ±1 % and **junction temp drop** |
| 5 | Find **minimum voltage** that holds target clocks under load |

**Goals for reference blower in SFF:**

- **Lower junction temp** → less case heat → helps CPU cooler
- **Lower fan RPM** at same perf → noise reduction
- Typical win: **same performance, −20–40 W**, −5–15 °C junction

### 5D — Blower fan curve (LACT)

Reference cards are loud — custom curve is high value:

| Junction °C | Fan % (starting point) |
|-------------|------------------------|
| 40 | 25 |
| 60 | 40 |
| 70 | 55 |
| 80 | 70 |
| 90 | 85 |
| 100 | 100 |

Undervolt allows **lower fan %** at each tier after validation.

**Do not** set zero RPM on blower cards.

---

## Phase 6 — Validation & lock-in

### Target metrics (adjust to your noise preference)

| Metric | Target (starting goal) | Acceptable max |
|--------|------------------------|----------------|
| CPU gaming | 70–85 °C | 90 °C |
| CPU all-core stress | 85–95 °C | 95 °C (AMD design) |
| GPU junction gaming | 75–90 °C | 100 °C |
| Noise | Subjective — T30 not at 100 % daily | — |
| Gaming FPS | Within **1–2 %** of Phase 0 baseline | — |

### Lock-in checklist

- [ ] Save **BIOS profile** to flash + photo/export fan curves
- [ ] Document final CO value, PBO limits, XMP settings in `bios_optimize.md`
- [ ] Export LACT profile / screenshot curve
- [ ] Enable **Memory Context Restore** if disabled during tuning
- [ ] 1 week daily use without WHEA / crash

---

## Risk matrix

| Change | Risk | Rollback |
|--------|------|----------|
| XMP enable | Low | Clear CMOS / disable XMP |
| Fan curves | Low | Load Optimized Defaults or saved profile |
| Curve Optimizer −10…−20 | Medium | Reset CO to 0 |
| PPT cap | Low | Set to motherboard max |
| RAM manual timings | **High** on 48 GB | XMP only + CMOS |
| GPU UV too aggressive | Medium | LACT reset / remove ppfeaturemask |

---

## Deliverables (project roadmap)

| File | Status | Purpose |
|------|--------|---------|
| `bios_optimize_plan.md` | **Done** | Research + phased strategy |
| `bios_optimize.md` | **Done** | Step-by-step BIOS + LACT guide |
| `parts.md` | Link back | Hardware reference |
| `post_install.md` | Extend later | LACT install, `lm_sensors`, monitoring commands |

### Suggested implementation order

1. ~~Write plan~~ ✓
2. ~~Write `bios_optimize.md`~~ ✓
3. Build PC; map fan headers; fill header table in `bios_optimize.md`
4. Phase 0–2 on first boot (foundation + XMP + fans)
5. Phase 3 CPU CO tuning over 2–3 sessions
6. Phase 5 GPU LACT after Arch gaming stack installed
7. Record **final stable values** in `bios_optimize.md` log tables

---

## References

- [Gigabyte AMD 800 Series BIOS Manual](https://download.gigabyte.com/FileList/Manual/mb_manual_amd800-bios_e_20260512.pdf) — Smart Fan 6, XMP/EXPO
- [Noctua — optimise fan settings](https://www.noctua.at/en/support/faqs/how-do-i-optimise-my-fan-settings)
- [Igor'sLab — 9800X3D undervolting / Curve Optimizer](https://www.igorslab.de/en/amd-ryzen-7-9800x3d-in-gaming-test-overclocked-undervolted-and-found-to-be-good/4/)
- [Overclock.net — 9800X3D Curve Optimizer tips](https://www.overclock.net/threads/9800x3d-curve-optimizer-tips.1814218/)
- [Overclock.net — AMD high capacity 2×48 GB DDR5](https://www.overclock.net/threads/amd-high-capacity-ddr5-oc-dual-rank-dimms.1816297/)
- [TechPowerUp — 9800X3D thermals (95 °C target behavior)](https://www.techpowerup.com/review/amd-ryzen-7-9800x3d/25.html)
- [Arch AMDGPU wiki](https://wiki.archlinux.org/title/Amdgpu)
- [LACT — Linux GPU control](https://github.com/ilya-zlobintsev/LACT)
- [`parts.md`](parts.md) — Mjolnir hardware profile
