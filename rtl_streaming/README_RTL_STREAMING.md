# RTL Streaming v0.2 — Le Gall 5/3 DWT/IDWT

Status: **second RTL design drop; architecture complete, two v0.1 hardware blockers repaired; not yet regression- or synthesis-certified.**

This directory is a clean-room streaming implementation derived from:

1. `DWT53_SYSTEM_SPEC_v0.5.md`,
2. the frozen reversible Le Gall 5/3 algorithm and MATLAB golden model,
3. the streaming block diagram developed for this project.

It intentionally does **not** use `rtl_baseline` hierarchy, scheduling, RAM
organization, or control logic as a design source.

## v0.2 changes

### 1. End-of-frame inverse bank overwrite hazard repaired

The final inverse vertical boundary row requires a bottom flush after the last
subband sample. v0.1 could begin this flush while the selected ping-pong bank
was still marked ready / being drained. It raised `buffer_error` but could still
overwrite the bank.

v0.2 does not start bottom flush until:

```text
bottom_flush_request
AND no pending right-edge block
AND no normal input stage item
AND selected fill bank is FREE
```

Thus the bottom sweep waits safely; no pixel backpressure is needed because the
external input frame has already ended.

### 2. Inverse ping-pong drain changed to synchronous BRAM read

v0.1 drained the block bank with an asynchronous array read. v0.2 replaces it
with a registered synchronous read port plus one-word prefetch. The intent is
to make Quartus M10K inference realistic and remove a large combinational RAM
read from the pixel output path.

For `PIXEL_GAP=1`, the next word is requested while pixel 0 of the current word
is emitted, so it is available when pixel 1 completes. For larger gaps the word
is simply held until needed.

**Quartus synthesis report remains authoritative** for whether the arrays are
actually inferred as M10Ks.

### 3. Checkpoint A/B recurrence shortened

v0.1 serially updated `A` and `B` up to eight times inside one clock. v0.2 uses
the exactly equivalent per-cycle equations:

```text
A' = A + sum(v_i)
B' = B + K*A + weighted_sum(v_i)
```

where weights preserve lane0 -> lane7 order. The transformation was checked
against the original recurrence on randomized software cases for both zero-fill
and sign-extension modes. No multiplication operator is used; scaling by 0..8
is implemented with shifts/adds.

## Files

| File | Purpose |
|---|---|
| `dwt53_fwd1d_pair_stream.sv` | Streaming Forward-1D lifting nucleus. |
| `dwt53_fwd2d_stream.sv` | Horizontal 5/3 + bounded circulating vertical state; emits LL/HL/LH/HH. |
| `dwt53_inv2d_stream.sv` | Inverse vertical then horizontal; bounded per-column state + BRAM-oriented ping-pong row banks. |
| `dwt53_band_align.sv` | Circulating FIFO delaying HL1/LH1/HH1 until reconstructed LL1 arrives. |
| `dwt53_checkpoint8.sv` | Passive up-to-8-lane count/xor/A/B checkpoint. |
| `dwt53_streaming_top.sv` | Two-level Forward -> two-level Inverse streaming core and Phase-1 checkpoints. |
| `rtl_streaming.f` | Compile order. |
| `Makefile` | Local Verilator lint entry point. |
| `TOOL_FLOW.md` | Recommended simulation/synthesis workflow. |

## Frozen arithmetic implemented

Forward 1D:

```text
e[n] = x[2n]
o[n] = x[2n+1]
d[n] = o[n] - floor((e[n] + e[n+1]) / 2)
s[n] = e[n] + floor((d[n-1] + d[n] + 2) / 4)
e[M] = e[M-1]
d[-1] = d[0]
L[n] = s[n]
H[n] = d[n]
```

Inverse 1D:

```text
H[-1] = H[0]
e[n] = L[n] - floor((H[n-1] + H[n] + 2) / 4)
e[M] = e[M-1]
o[n] = H[n] + floor((e[n] + e[n+1]) / 2)
x[2n] = e[n]
x[2n+1] = o[n]
```

Arithmetic right shifts implement the required floor division by 2 and 4.

## Top-level dataflow

```text
Y8
 |
 v
Forward 2D L1
 |  LL1 + HL1/LH1/HH1
 |        |
 |        +----> bounded band-align FIFO ---------------------+
 v                                                          |
Forward 2D L2 (LL1 only)                                   |
 |                                                          |
 v                                                          |
Inverse 2D L2 -> reconstructed LL1 -------------------------+
 |
 v
Inverse 2D L1
 |
 v
range check -> reconstructed Y8
```

Forward and inverse are separate RTL instances.

## 1280x720 storage character

The design does not allocate a 1280x720 coefficient frame. Storage scales with
line width / fixed skew depth rather than image height. With the default
`SKEW_ROWS=16`, the architectural storage is on the order of hundreds of kbit,
not a 14.75-Mbit full 16-bit frame plane.

This does **not** yet prove the complete DE10-Nano reference design fits: camera
and HDMI logic also consume M10Ks. Measure the unmodified Terasic project first,
then integrate this core and compare the Quartus resource report.

## Frame interface

```text
input:
    in_valid
    in_y[7:0]
    in_sof
    in_eol
    in_eof

output:
    frame_ready
    out_valid
    out_y[7:0]
    out_sof
    out_eol
    out_eof
```

`frame_ready` is frame-level admission, not pixel-level backpressure. Once an
SOF is accepted, the complete frame is consumed without DUT-requested stalls.

## Phase-1 checkpoints implemented

- `CP-IN`
- `CP-L1`
- `CP-FW`
- `CP-RC`
- `CP-RE`

`CP-TX` and `CP-RT` belong to the later DE10/HAPS link wrappers.

### Streaming B order used by this RTL

CP-L1, per logical coordinate:

```text
LL1 -> HL1 -> LH1 -> HH1
```

CP-FW, if both streams are active in one clock:

```text
HL1 -> LH1 -> HH1 -> LL2 -> HL2 -> LH2 -> HH2
```

Before final sign-off, this order must be frozen in the spec and the MATLAB
reference-signature exporter must generate `B` in the same order.

## Still provisional / must be measured

1. `SKEW_ROWS=16` is a safe design default, not the measured minimum.
2. Inverse-Level-2 uses `PIXEL_GAP=4` as the current rate-matching schedule.
3. M10K inference must be confirmed in Quartus; attributes are requests, not proof.
4. Core Fmax / timing is unknown until synthesis + TimeQuest.
5. Physical HAPS W_CLK/R_CLK CDC and return-link sideband are Phase-2 wrappers.
6. Signature extension policy remains parameterized (`A_SIGN_EXTEND`).
7. `CP-LL1` remains optional/open.
8. Full 1280x720 bit-exact regression has not yet been run.

## Verification gate before hardware

Do not call this RTL hardware-ready until all of the following pass:

1. Verilator/Questa compile + lint with zero real errors.
2. 4x4, 8x8, 8x12, 12x8, 16x16, 64x64 MATLAB bit-exact regression.
3. Stage checks: L1, L2, reconstructed LL1, final reconstructed Y8.
4. FIFO overflow/underflow = 0; inverse `buffer_error` = 0.
5. Checkpoint count/xor/A/B matches the matching streaming-order references.
6. Full 1280x720 synthetic frame bit-exact.
7. Full 1280x720 natural/test image bit-exact.
8. Quartus synthesis: expected M10K inference, DSP=0, resource budget fits.
9. TimeQuest Fmax meets the chosen core-clock bound.
10. Only then integrate with camera/crop/Y8 and HDMI on DE10-Nano.
