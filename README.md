# P1 — Pipelined Fixed-Point VWAP Datapath (Arty A7-100T)

Streams `(price, size)` trade records into a fully pipelined fixed-point datapath
and computes a **rolling volume-weighted average price** over a sliding window:

```
VWAP = Σ(price · size) / Σ(size)      over the last WIN records
```

"Trading math in hardware" — the canonical low-latency datapath. The design is
built to make the **latency-vs-throughput** distinction concrete and to force
every fixed-point width to be *derived and justified*, never guessed.

- **Target:** `xc7a100tcsg324-1`, 100 MHz
- **Language:** SystemVerilog; AXI-Stream in and out
- **No floating point anywhere.**

## Datapath

```
 s_axis            stage 1          stage 2              stage 3            m_axis
(price,size) ─▶ mult_stage ─▶ window_accum ─────────▶ divider ─────────▶ (vwap)
 tvalid/tready   p*size        Σ(p·s), Σ(size)         Σps / Σsize        tvalid/tready
                 1 cycle       1 cycle                 DW+2 cycles        back-pressured
```

- **Throughput:** 1 record/cycle ingest (`s_axis_tready` always high — the
  add/subtract accumulator keeps up at line rate).
- **Latency:** a result for a beat appears **2 + (DW+2)** cycles later. Measured by
  `latency_cycles` = **38 cycles** (≈ 380 ns at 100 MHz) for the default config.

These are *different numbers* and the design reports both.

## Fixed-point formats (all derived in `rtl/vwap_pkg.sv`)

| Signal        | Format   | Width | Why                                            |
|---------------|----------|-------|------------------------------------------------|
| price         | Q8.8 u   | 16    | integer price 0..255, 1/256 tick               |
| size          | u int    | 16    | lot size 0..65535                              |
| price·size    | Q16.8    | 32    | widths add: (8+8).(8+0)                         |
| Σ(price·size) | —        | 35    | product + log2(WIN)=3 bits of window headroom  |
| Σ(size)       | —        | 19    | size + 3 bits                                   |
| VWAP          | Q.8      | ≤35   | the ·256 scaling is already in Σps, so the      |
|               |          |       | integer quotient *is* the Q.8 result           |

The "no pre-shift" result is the subtle bit: because `price` carries 8 fractional
bits into `Σps`, dividing by the integer `Σsize` yields VWAP already in Q.8.

## The sliding window

`window_accum` keeps a WIN-deep shift register and does **O(1) work per beat**:
add the newest `price·size`/`size`, subtract the record leaving the window. The
naive alternative — summing all WIN entries every cycle — is a long adder tree
that wrecks Fmax. (Before the window fills, nothing is subtracted.)

## The divide (the expensive stage)

`divider.sv` is an honest 1-bit/cycle sequential restoring divider: fixed
`DW+2`-cycle latency, deterministic. In an interview the point is knowing *why*
a full-width divide can't be a single combinational stage at any sane Fmax, and
the ways to get it off the hot path:
- precompute a **reciprocal** of `Σsize` (it changes slowly) and multiply,
- Newton-Raphson refinement,
- restructure so the divide is not on the critical path.

(Stretch goal: swap in reciprocal-multiply and compare Fmax/latency.)

## Back-pressure

The output is a real AXI-Stream: while `m_axis_tvalid && !m_axis_tready` the data
is held stable and **no new divide is launched**, so a result is never corrupted
or dropped mid-handshake. This ripples back to the divider — correct flow control.

## Build & verify

```bash
make sim      # tb_vwap in xsim (randomized streams vs reference model + SVA)
make bit      # synth + implement -> timing/util reports
```

## Verification

`tb_vwap` (passes in xsim v2026.1):
- randomized `(price,size)` beats with random `tvalid` gaps;
- a **reference model** (SV queue) maintains the golden sliding window and sums;
  a monitor checks `sum_ps`/`sum_sz` on every accumulator beat;
- a second monitor snapshots dividend/divisor at each divide start and checks the
  quotient against a golden floor-divide on completion;
- the output consumer applies **random back-pressure**;
- **SVA** asserts the AXIS rule: data/valid stable while `tvalid && !tready`.

Result: **300 sum checks + 98 divide checks, 0 errors, SVA clean.**

## Results

> `xc7a100tcsg324-1`, 100 MHz target, Vivado 2026.1.

| Metric               | Value                          |
|----------------------|--------------------------------|
| Setup slack (WNS)    | +2.771 ns @ 10.0 ns target     |
| Fmax                 | ~138 MHz                       |
| Slice LUTs           | 291 (0.46 %)                   |
| Slice registers (FF) | 384 (0.30 %)                   |
| DSP48                | 3                              |
| BRAM                 | 0                              |
| Latency              | 38 cycles (~380 ns @ 100 MHz)  |
| Throughput           | 1 record / cycle               |

**Critical path:** the 35-bit compare-and-subtract inside the sequential divider
— which is precisely why the divide is the slow stage. The multiply + accumulate
would run far faster on their own; the divider sets Fmax. Moving to a
reciprocal-multiply (stretch goal) would lift Fmax and cut latency at the cost of
a reciprocal table / Newton iterations.

## Interview talking points

- **Where the critical path is** and why the sequential divide keeps per-stage
  logic short (so Fmax stays high) at the cost of latency.
- **Fixed-point choices**: the Q-formats, where bits grow, and that dividing by
  the integer `Σsize` lands the result back in Q.8 with no rounding step.
- **Latency vs throughput**: 1 record/cycle in, result 38 cycles later — know both.
- **Why divide is expensive** and how a reciprocal-multiply removes it from the
  hot path.
- **How back-pressure ripples upstream** without losing data.

## Repo layout

```
rtl/  vwap_pkg.sv  mult_stage.sv  window_accum.sv  divider.sv  vwap_top.sv
tb/   tb_vwap.sv
scripts/ sim.sh  build.sh  build.tcl
```

> Hardware/host integration (streaming records in and reading VWAP + latency back
> over the P0 UART bridge via a `feedgen` host app) is the on-board step — deferred
> until the Arty is connected; the datapath itself is fully verified in simulation.
