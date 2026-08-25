# DWT53 2D/two-level reference vector set

- Source: `DWT53_TEST_FRAME_V1_w1280_h720`
- Shape: 720 rows x 1280 columns
- Input/reconstruction: unsigned Y8, two HEX digits
- Coefficients: signed 16-bit two's complement, 4 HEX digits
- Matrix serialization: row-major (`reshape(A.', [], 1)`)
- Packed layout: `[LL HL; LH HH]`; level 2 replaces only LL1

## Files

`input_y8_*`, `c1_packed_*`, `c2_packed_*`, `ll1_*`, and `recon_y8_*`
are matched DEC/HEX pairs. `reference_manifest.txt` is deterministic and
is the artifact-of-record manifest. The legacy `manifest.txt` is retained
only for compatibility and contains volatile generation metadata.

`signatures.txt` includes count, XOR, A/sum and order-sensitive B.
`signature_sweep.csv` covers W={8,13,16} x {zero-fill,sign-extend};
unrepresentable configurations are marked OUT_OF_RANGE, never wrapped.
`subband_ranges.csv` reports every sizing-relevant row stage/subband
against the theoretical bounds frozen in system spec Section D.2.
B in this set uses packed row-major order; do not
compare it with a streaming checkpoint until OI-011 documents a matching
emission order. Count/XOR/A remain useful under their stated profile.
