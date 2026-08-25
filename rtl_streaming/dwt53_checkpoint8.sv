`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_checkpoint8
// Passive 8-lane signature checkpoint.
//
// Frozen signature core:
//   count += 1
//   xor   ^= two's-complement pattern(v)
//   A     += value(v)          modulo 2^32
//   B     += A_new             modulo 2^32
//
// Lane order within a cycle is lane0 -> lane7. This order is significant for B.
// The top-level README documents the lane mapping at each checkpoint.
//
// v0.2 timing change:
// Instead of serially updating A and B once per active lane (which creates a
// long accumulator-dependent adder chain), the same ordered recurrence is
// collapsed algebraically for the whole cycle:
//
//   A' = A + sum(v_i)
//   B' = B + K*A + sum_i(weight_i * v_i)
//
// where K is the number of active lanes and weight_i is the number of active
// lanes at or after lane i. This is exactly equivalent to applying the frozen
// sample recurrence lane0 -> lane7, but removes the repeated A/B dependency
// from the critical path. No '*' operator is used, so this helper cannot infer
// a dedicated multiplier for the small 0..8 scale factors.
//
// A_SIGN_EXTEND=0 implements the incumbent golden-model zero-fill behaviour.
// The specification still marks the extension-rule choice as an open item;
// therefore this is a parameter, not a hidden architectural assumption.
// -----------------------------------------------------------------------------
module dwt53_checkpoint8 #(
    parameter int SAMPLE_W      = 16,
    parameter bit A_SIGN_EXTEND = 1'b0
) (
    input  logic                           clk,
    input  logic                           rst_n,

    input  logic                           frame_start,
    input  logic                           frame_end,

    input  logic [7:0]                     lane_mask,
    input  logic [8*SAMPLE_W-1:0]          samples_flat,

    output logic                           snapshot_valid,
    output logic [31:0]                    sig_count,
    output logic [SAMPLE_W-1:0]            sig_xor,
    output logic [31:0]                    sig_a,
    output logic [31:0]                    sig_b
);

    initial begin
        if (SAMPLE_W > 32)
            $error("dwt53_checkpoint8: SAMPLE_W must be <= 32");
    end

    logic signed [SAMPLE_W-1:0] sample_arr [0:7];

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_unpack
            assign sample_arr[gi] =
                samples_flat[gi*SAMPLE_W +: SAMPLE_W];
        end
    endgenerate

    function automatic logic [31:0] a_contribution(
        input logic signed [SAMPLE_W-1:0] v
    );
        begin
            if (A_SIGN_EXTEND)
                a_contribution = {{(32-SAMPLE_W){v[SAMPLE_W-1]}}, v};
            else
                a_contribution = {{(32-SAMPLE_W){1'b0}}, v};
        end
    endfunction

    // Multiply a modulo-2^32 value by a small integer 0..8 using only
    // shifts/adds. Overflow is intentionally discarded modulo 2^32.
    function automatic logic [31:0] scale_0_to_8(
        input logic [31:0] v,
        input logic [3:0]  k
    );
        logic [31:0] v2, v4, v8;
        begin
            v2 = v << 1;
            v4 = v << 2;
            v8 = v << 3;
            case (k)
                4'd0: scale_0_to_8 = 32'd0;
                4'd1: scale_0_to_8 = v;
                4'd2: scale_0_to_8 = v2;
                4'd3: scale_0_to_8 = v2 + v;
                4'd4: scale_0_to_8 = v4;
                4'd5: scale_0_to_8 = v4 + v;
                4'd6: scale_0_to_8 = v4 + v2;
                4'd7: scale_0_to_8 = v4 + v2 + v;
                default: scale_0_to_8 = v8; // k=8
            endcase
        end
    endfunction

    logic [31:0] count_q, count_n;
    logic [SAMPLE_W-1:0] xor_q, xor_n;
    logic [31:0] a_q, a_n;
    logic [31:0] b_q, b_n;

    logic [31:0] c [0:7];
    logic [3:0]  suffix_k [0:7];
    logic [3:0]  lane_count;
    logic [SAMPLE_W-1:0] lane_xor;
    logic [31:0] lane_sum;
    logic [31:0] lane_weighted_sum;

    logic [31:0] base_count;
    logic [SAMPLE_W-1:0] base_xor;
    logic [31:0] base_a, base_b;

    integer i;
    always_comb begin
        // Masked A-contributions and order weights.
        for (i = 0; i < 8; i = i + 1)
            c[i] = lane_mask[i] ? a_contribution(sample_arr[i]) : 32'd0;

        suffix_k[7] = lane_mask[7] ? 4'd1 : 4'd0;
        for (i = 6; i >= 0; i = i - 1)
            suffix_k[i] = suffix_k[i+1] + (lane_mask[i] ? 4'd1 : 4'd0);

        lane_count = suffix_k[0];

        // XOR is over the two's-complement sample patterns, independent of the
        // A extension policy.
        lane_xor = '0;
        for (i = 0; i < 8; i = i + 1)
            if (lane_mask[i])
                lane_xor = lane_xor ^ sample_arr[i];

        // Written as balanced expressions so synthesis is free to form trees.
        lane_sum =
            (c[0] + c[1]) + (c[2] + c[3]) +
            (c[4] + c[5]) + (c[6] + c[7]);

        lane_weighted_sum =
            (scale_0_to_8(c[0], suffix_k[0]) +
             scale_0_to_8(c[1], suffix_k[1])) +
            (scale_0_to_8(c[2], suffix_k[2]) +
             scale_0_to_8(c[3], suffix_k[3])) +
            (scale_0_to_8(c[4], suffix_k[4]) +
             scale_0_to_8(c[5], suffix_k[5])) +
            (scale_0_to_8(c[6], suffix_k[6]) +
             scale_0_to_8(c[7], suffix_k[7]));

        if (frame_start) begin
            base_count = 32'd0;
            base_xor   = '0;
            base_a     = 32'd0;
            base_b     = 32'd0;
        end else begin
            base_count = count_q;
            base_xor   = xor_q;
            base_a     = a_q;
            base_b     = b_q;
        end

        count_n = base_count + {{28{1'b0}}, lane_count};
        xor_n   = base_xor ^ lane_xor;
        a_n     = base_a + lane_sum;
        b_n     = base_b + scale_0_to_8(base_a, lane_count) +
                  lane_weighted_sum;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_q        <= 32'd0;
            xor_q          <= '0;
            a_q            <= 32'd0;
            b_q            <= 32'd0;

            snapshot_valid <= 1'b0;
            sig_count      <= 32'd0;
            sig_xor        <= '0;
            sig_a          <= 32'd0;
            sig_b          <= 32'd0;
        end else begin
            count_q <= count_n;
            xor_q   <= xor_n;
            a_q     <= a_n;
            b_q     <= b_n;

            snapshot_valid <= frame_end;
            if (frame_end) begin
                // Snapshot includes all lanes accepted on the frame_end cycle.
                sig_count <= count_n;
                sig_xor   <= xor_n;
                sig_a     <= a_n;
                sig_b     <= b_n;
            end
        end
    end

endmodule

`default_nettype wire
