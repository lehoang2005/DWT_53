# DWT53 deterministic test frame rule — V1

This file freezes the rule shared by MATLAB and the DE10-Nano test-frame
generator for `VID-010` / `GLD-015`.

For zero-based coordinates `x` (column) and `y` (row):

```text
t = 17*x + 31*y + ((x & 255) XOR (y & 255)) + 127*((x+y) & 1)
Y8(x,y) = t & 255
```

- Origin is the top-left active pixel: `(x,y)=(0,0)`.
- Raster order is left-to-right, then top-to-bottom.
- No state carries between pixels or frames.
- Every new frame restarts at `(0,0)` and is therefore identical.
- The active shape for the final mode is width 1280, height 720.
- MATLAB entry point: `gen_test_frame(720,1280)`.

The first 16 pixels of row zero are:

```text
00 91 24 B5 48 D9 6C FD 90 21 B4 45 D8 69 FC 8D
```

Equivalent SystemVerilog arithmetic (illustrative; integrate with the DE10
raster counters and test-pattern mux):

```systemverilog
function automatic logic [7:0] dwt53_test_pixel(
    input logic [15:0] x,
    input logic [15:0] y
);
    logic [31:0] t;
    begin
        t = ({16'd0, x} * 32'd17)
          + ({16'd0, y} * 32'd31)
          + {24'd0, (x[7:0] ^ y[7:0])}
          + ((x[0] ^ y[0]) ? 32'd127 : 32'd0);
        dwt53_test_pixel = t[7:0];
    end
endfunction
```

The constants synthesize as shifts/adds; no runtime multiplier is required.
The MATLAB implementation uses wider unsigned integer arithmetic and truncates
only once, to the low eight bits, exactly as above.
