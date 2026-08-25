# Recommended RTL / TB Tool Flow

## Fast local loop — Linux

Use **Verilator** for:

- `--lint-only` on every edit;
- fast small-vector regression;
- randomized regression;
- full 1280x720 regression without dumping huge waveforms;
- optional coverage.

For large frames, keep waveform tracing OFF by default. Turn it on only around a
small failing case or a narrow debug window.

## Detailed waveform/debug — Questa

Use **Questa-Altera / Questa FPGA Edition** for:

- SystemVerilog event-driven behavior;
- assertions;
- waveform inspection;
- checking difficult marker / flush / bank timing;
- cross-checking a small/medium regression against Verilator.

Do not make 1280x720 + full VCD/WLF your normal debug loop; it is much slower and
creates very large trace files.

## MATLAB golden model — Windows or Linux

MATLAB remains the independent oracle. Export deterministic vectors/signatures
to files, then consume the same files in Verilator and Questa. The simulator
should not call MATLAB internally.

A simple workflow is:

```text
MATLAB -> vectors/*.hex + signatures
                     |
        +------------+------------+
        |                         |
   Verilator                    Questa
 fast/full-frame          waveform/debug subset
```

## FPGA implementation — Quartus

Use Quartus with Cyclone-V device support for DE10-Nano:

1. compile the unmodified Terasic camera/HDMI reference project;
2. record M10K, ALM/FF, DSP, PLL and Fmax baseline;
3. compile the streaming DWT core standalone;
4. inspect RAM inference and TimeQuest;
5. integrate the core into the Terasic project;
6. repeat the resource/timing report;
7. program the DE10 only after regression passes.

## EDA Playground

Good for tiny isolated examples such as Forward-1D or a 4x4 smoke TB. It is not
the recommended place for 1280x720 regression because runtime, memory, file I/O
and waveform limits are outside your control.

## Suggested division between your dual-boot OSes

```text
Windows:
  MATLAB
  Questa-Altera (if already installed here)
  Quartus / Programmer (convenient for DE10 bring-up)

Linux:
  Verilator
  lint/regression scripts
  Git
  Python helper scripts
```

You do not need the same simulator on both OSes. Keep the RTL/TB/vector tree in
Git or a shared data partition so both sides use the exact same snapshot.
