`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_streaming_top
// Clean-room two-level streaming Le Gall 5/3 DWT -> IDWT core.
//
// DESIGN BASIS ONLY:
//   - frozen algorithm/system specification,
//   - MATLAB golden model,
//   - streaming block diagram.
// No rtl_baseline module or scheduling is reused.
//
// This is the core-clock arithmetic architecture. The board-specific
// W_CLK/R_CLK physical wrapper and CDC are intentionally outside this file
// because the system specification still leaves parts of that integration open.
//
// Frame policy:
//   * frame_ready permits STARTING a new frame.
//   * once SOF is accepted, the complete frame is consumed without per-pixel
//     ready/backpressure.
//   * a new frame is not accepted until the reconstructed EOF is emitted.
// -----------------------------------------------------------------------------
module dwt53_streaming_top #(
    parameter int WIDTH           = 1280,
    parameter int HEIGHT          = 720,
    parameter int DATA_W          = 16,
    parameter int SKEW_ROWS       = 16,
    parameter bit CHECKPOINT_EN   = 1'b1,
    parameter bit A_SIGN_EXTEND   = 1'b0
) (
    input  logic                 sys_clk,
    input  logic                 sys_rst_n,

    input  logic                 in_valid,
    input  logic [7:0]           in_y,
    input  logic                 in_sof,
    input  logic                 in_eol,
    input  logic                 in_eof,

    output logic                 frame_ready,
    output logic                 busy,

    output logic                 out_valid,
    output logic [7:0]           out_y,
    output logic                 out_sof,
    output logic                 out_eol,
    output logic                 out_eof,

    output logic                 range_error,
    output logic                 arithmetic_error,
    output logic                 buffer_error,
    output logic                 protocol_error,

    // HAPS/core-side checkpoint snapshots.
    output logic                 cp_in_snapshot_valid,
    output logic [31:0]          cp_in_count,
    output logic [15:0]          cp_in_xor,
    output logic [31:0]          cp_in_a,
    output logic [31:0]          cp_in_b,

    output logic                 cp_l1_snapshot_valid,
    output logic [31:0]          cp_l1_count,
    output logic [15:0]          cp_l1_xor,
    output logic [31:0]          cp_l1_a,
    output logic [31:0]          cp_l1_b,

    output logic                 cp_fw_snapshot_valid,
    output logic [31:0]          cp_fw_count,
    output logic [15:0]          cp_fw_xor,
    output logic [31:0]          cp_fw_a,
    output logic [31:0]          cp_fw_b,

    output logic                 cp_rc_snapshot_valid,
    output logic [31:0]          cp_rc_count,
    output logic [15:0]          cp_rc_xor,
    output logic [31:0]          cp_rc_a,
    output logic [31:0]          cp_rc_b,

    output logic                 cp_re_snapshot_valid,
    output logic [31:0]          cp_re_count,
    output logic [15:0]          cp_re_xor,
    output logic [31:0]          cp_re_a,
    output logic [31:0]          cp_re_b
);

    localparam int L1_W = WIDTH  / 2;
    localparam int L1_H = HEIGHT / 2;
    localparam int L2_W = WIDTH  / 4;
    localparam int L2_H = HEIGHT / 4;
    localparam int IN_X_W = (WIDTH  <= 2) ? 1 : $clog2(WIDTH);
    localparam int IN_Y_W = (HEIGHT <= 2) ? 1 : $clog2(HEIGHT);
    localparam int BAND_FIFO_DEPTH = SKEW_ROWS * L1_W;

    initial begin
        if ((WIDTH % 4) != 0 || (HEIGHT % 4) != 0)
            $error("dwt53_streaming_top: WIDTH and HEIGHT must be divisible by 4");
        if (DATA_W != 16)
            $error("dwt53_streaming_top: project spec freezes coefficient storage at 16 bits");
        if (SKEW_ROWS < 2)
            $error("dwt53_streaming_top: SKEW_ROWS must be >= 2");
    end

    // -------------------------------------------------------------------------
    // Frame admission and explicit input geometry checking.
    // -------------------------------------------------------------------------
    logic frame_active_q;
    logic [IN_X_W-1:0] in_x_q;
    logic [IN_Y_W-1:0] in_y_q;
    logic core_in_valid;
    logic input_protocol_error_q;

    assign frame_ready  = ~frame_active_q;
    assign busy         = frame_active_q;

    assign core_in_valid =
        in_valid && (frame_active_q || (frame_ready && in_sof));

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            frame_active_q <= 1'b0;
            in_x_q         <= '0;
            in_y_q         <= '0;
            input_protocol_error_q <= 1'b0;
        end else begin
            if (in_valid && !frame_active_q && !in_sof)
                input_protocol_error_q <= 1'b1;

            if (in_valid && frame_active_q && in_sof)
                input_protocol_error_q <= 1'b1;

            if (core_in_valid) begin
                if (in_sof && ((in_x_q != 0) || (in_y_q != 0)))
                    input_protocol_error_q <= 1'b1;

                if (in_eol != (in_x_q == WIDTH-1))
                    input_protocol_error_q <= 1'b1;

                if (in_eof != ((in_x_q == WIDTH-1) && (in_y_q == HEIGHT-1)))
                    input_protocol_error_q <= 1'b1;

                if (in_sof)
                    frame_active_q <= 1'b1;

                if (in_eof) begin
                    in_x_q <= '0;
                    in_y_q <= '0;
                end else if (in_eol) begin
                    in_x_q <= '0;
                    in_y_q <= in_y_q + 1'b1;
                end else begin
                    in_x_q <= in_x_q + 1'b1;
                end
            end

            if (out_valid && out_eof)
                frame_active_q <= 1'b0;
        end
    end

    logic signed [DATA_W-1:0] in_sample_s;
    assign in_sample_s = $signed({{(DATA_W-8){1'b0}}, in_y});

    // -------------------------------------------------------------------------
    // Forward Level 1: full 1280x720 frame -> LL1/HL1/LH1/HH1 quartet stream.
    // -------------------------------------------------------------------------
    logic l1_valid, l1_sof, l1_eol, l1_eof;
    logic signed [DATA_W-1:0] l1_ll, l1_hl, l1_lh, l1_hh;
    logic l1_overflow, l1_protocol;

    dwt53_fwd2d_stream #(
        .IMG_W (WIDTH),
        .IMG_H (HEIGHT),
        .DATA_W(DATA_W)
    ) u_fwd_l1 (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .in_valid       (core_in_valid),
        .in_sample      (in_sample_s),
        .in_sof         (in_sof),
        .in_eol         (in_eol),
        .in_eof         (in_eof),
        .out_valid      (l1_valid),
        .out_ll         (l1_ll),
        .out_hl         (l1_hl),
        .out_lh         (l1_lh),
        .out_hh         (l1_hh),
        .out_sof        (l1_sof),
        .out_eol        (l1_eol),
        .out_eof        (l1_eof),
        .overflow_error (l1_overflow),
        .protocol_error (l1_protocol)
    );

    // -------------------------------------------------------------------------
    // Forward Level 2: ONLY LL1 is decomposed.
    // -------------------------------------------------------------------------
    logic l2_valid, l2_sof, l2_eol, l2_eof;
    logic signed [DATA_W-1:0] l2_ll, l2_hl, l2_lh, l2_hh;
    logic l2_overflow, l2_protocol;

    dwt53_fwd2d_stream #(
        .IMG_W (L1_W),
        .IMG_H (L1_H),
        .DATA_W(DATA_W)
    ) u_fwd_l2 (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .in_valid       (l1_valid),
        .in_sample      (l1_ll),
        .in_sof         (l1_sof),
        .in_eol         (l1_eol),
        .in_eof         (l1_eof),
        .out_valid      (l2_valid),
        .out_ll         (l2_ll),
        .out_hl         (l2_hl),
        .out_lh         (l2_lh),
        .out_hh         (l2_hh),
        .out_sof        (l2_sof),
        .out_eol        (l2_eol),
        .out_eof        (l2_eof),
        .overflow_error (l2_overflow),
        .protocol_error (l2_protocol)
    );

    // -------------------------------------------------------------------------
    // Inverse Level 2: LL2/HL2/LH2/HH2 -> reconstructed LL1.
    // Output is deliberately paced one LL1 sample every four core clocks.
    // -------------------------------------------------------------------------
    logic rc_valid, rc_sof, rc_eol, rc_eof;
    logic signed [DATA_W-1:0] rc_ll1;
    logic il2_overflow, il2_buffer, il2_protocol;

    dwt53_inv2d_stream #(
        .SUB_W     (L2_W),
        .SUB_H     (L2_H),
        .DATA_W    (DATA_W),
        .PIXEL_GAP (4)
    ) u_inv_l2 (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .in_valid       (l2_valid),
        .in_ll          (l2_ll),
        .in_hl          (l2_hl),
        .in_lh          (l2_lh),
        .in_hh          (l2_hh),
        .in_sof         (l2_sof),
        .in_eol         (l2_eol),
        .in_eof         (l2_eof),
        .out_valid      (rc_valid),
        .out_sample     (rc_ll1),
        .out_sof        (rc_sof),
        .out_eol        (rc_eol),
        .out_eof        (rc_eof),
        .overflow_error (il2_overflow),
        .buffer_error   (il2_buffer),
        .protocol_error (il2_protocol)
    );

    // -------------------------------------------------------------------------
    // Delay untouched Level-1 high bands until reconstructed LL1 arrives.
    // -------------------------------------------------------------------------
    logic a_valid, a_sof, a_eol, a_eof;
    logic signed [DATA_W-1:0] a_ll, a_hl, a_lh, a_hh;
    logic align_overflow, align_underflow;

    dwt53_band_align #(
        .DATA_W(DATA_W),
        .DEPTH (BAND_FIFO_DEPTH)
    ) u_band_align (
        .clk             (sys_clk),
        .rst_n           (sys_rst_n),
        .push_valid      (l1_valid),
        .push_hl         (l1_hl),
        .push_lh         (l1_lh),
        .push_hh         (l1_hh),
        .ll_valid        (rc_valid),
        .ll_sample       (rc_ll1),
        .ll_sof          (rc_sof),
        .ll_eol          (rc_eol),
        .ll_eof          (rc_eof),
        .out_valid       (a_valid),
        .out_ll          (a_ll),
        .out_hl          (a_hl),
        .out_lh          (a_lh),
        .out_hh          (a_hh),
        .out_sof         (a_sof),
        .out_eol         (a_eol),
        .out_eof         (a_eof),
        .overflow_error  (align_overflow),
        .underflow_error (align_underflow)
    );

    // -------------------------------------------------------------------------
    // Inverse Level 1: reconstructed LL1 + delayed HL1/LH1/HH1 -> Y image.
    // -------------------------------------------------------------------------
    logic re_valid, re_sof, re_eol, re_eof;
    logic signed [DATA_W-1:0] re_sample;
    logic il1_overflow, il1_buffer, il1_protocol;

    dwt53_inv2d_stream #(
        .SUB_W     (L1_W),
        .SUB_H     (L1_H),
        .DATA_W    (DATA_W),
        .PIXEL_GAP (1)
    ) u_inv_l1 (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .in_valid       (a_valid),
        .in_ll          (a_ll),
        .in_hl          (a_hl),
        .in_lh          (a_lh),
        .in_hh          (a_hh),
        .in_sof         (a_sof),
        .in_eol         (a_eol),
        .in_eof         (a_eof),
        .out_valid      (re_valid),
        .out_sample     (re_sample),
        .out_sof        (re_sof),
        .out_eol        (re_eol),
        .out_eof        (re_eof),
        .overflow_error (il1_overflow),
        .buffer_error   (il1_buffer),
        .protocol_error (il1_protocol)
    );

    // Final exact-range check. No clipping/saturation is allowed.
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            out_valid   <= 1'b0;
            out_y       <= 8'd0;
            out_sof     <= 1'b0;
            out_eol     <= 1'b0;
            out_eof     <= 1'b0;
            range_error <= 1'b0;
        end else begin
            out_valid <= re_valid;
            out_sof   <= re_valid && re_sof;
            out_eol   <= re_valid && re_eol;
            out_eof   <= re_valid && re_eof;

            if (re_valid) begin
                out_y <= re_sample[7:0];
                if ((re_sample < 0) || (re_sample > 255))
                    range_error <= 1'b1;
            end
        end
    end

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            arithmetic_error <= 1'b0;
            buffer_error     <= 1'b0;
            protocol_error   <= 1'b0;
        end else begin
            if (l1_overflow || l2_overflow || il2_overflow || il1_overflow)
                arithmetic_error <= 1'b1;

            if (il2_buffer || il1_buffer || align_overflow || align_underflow)
                buffer_error <= 1'b1;

            if (input_protocol_error_q ||
                l1_protocol || l2_protocol || il2_protocol || il1_protocol)
                protocol_error <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Checkpoint lane packing.
    // Streaming B-order is explicitly documented:
    // CP-L1: lane order LL1, HL1, LH1, HH1 per logical coordinate.
    // CP-FW: chronological merge. At a clock with both streams:
    //        HL1,LH1,HH1 then LL2,HL2,LH2,HH2.
    // CP-RC / CP-RE / CP-IN: one lane.
    // -------------------------------------------------------------------------
    logic [8*16-1:0] cp_in_flat, cp_l1_flat, cp_fw_flat, cp_rc_flat, cp_re_flat;
    logic [7:0] cp_in_mask, cp_l1_mask, cp_fw_mask, cp_rc_mask, cp_re_mask;

    assign cp_in_flat = {
        16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,
        {{8{1'b0}},in_y}
    };
    assign cp_in_mask = core_in_valid ? 8'b0000_0001 : 8'b0;

    assign cp_l1_flat = {
        16'd0,16'd0,16'd0,16'd0,
        l1_hh,l1_lh,l1_hl,l1_ll
    };
    assign cp_l1_mask = l1_valid ? 8'b0000_1111 : 8'b0;

    assign cp_fw_flat = {
        16'd0,
        l2_hh,l2_lh,l2_hl,l2_ll,
        l1_hh,l1_lh,l1_hl
    };
    assign cp_fw_mask = {
        1'b0,
        {4{l2_valid}},
        {3{l1_valid}}
    };

    assign cp_rc_flat = {
        16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,rc_ll1
    };
    assign cp_rc_mask = rc_valid ? 8'b0000_0001 : 8'b0;

    assign cp_re_flat = {
        16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,16'd0,re_sample
    };
    assign cp_re_mask = re_valid ? 8'b0000_0001 : 8'b0;

    generate
        if (CHECKPOINT_EN) begin : g_checkpoints
            dwt53_checkpoint8 #(
                .SAMPLE_W(16),
                .A_SIGN_EXTEND(A_SIGN_EXTEND)
            ) u_cp_in (
                .clk           (sys_clk),
                .rst_n         (sys_rst_n),
                .frame_start   (core_in_valid && in_sof),
                .frame_end     (core_in_valid && in_eof),
                .lane_mask     (cp_in_mask),
                .samples_flat  (cp_in_flat),
                .snapshot_valid(cp_in_snapshot_valid),
                .sig_count     (cp_in_count),
                .sig_xor       (cp_in_xor),
                .sig_a         (cp_in_a),
                .sig_b         (cp_in_b)
            );

            dwt53_checkpoint8 #(
                .SAMPLE_W(16),
                .A_SIGN_EXTEND(A_SIGN_EXTEND)
            ) u_cp_l1 (
                .clk           (sys_clk),
                .rst_n         (sys_rst_n),
                .frame_start   (l1_valid && l1_sof),
                .frame_end     (l1_valid && l1_eof),
                .lane_mask     (cp_l1_mask),
                .samples_flat  (cp_l1_flat),
                .snapshot_valid(cp_l1_snapshot_valid),
                .sig_count     (cp_l1_count),
                .sig_xor       (cp_l1_xor),
                .sig_a         (cp_l1_a),
                .sig_b         (cp_l1_b)
            );

            dwt53_checkpoint8 #(
                .SAMPLE_W(16),
                .A_SIGN_EXTEND(A_SIGN_EXTEND)
            ) u_cp_fw (
                .clk           (sys_clk),
                .rst_n         (sys_rst_n),
                .frame_start   (l1_valid && l1_sof),
                .frame_end     (l2_valid && l2_eof),
                .lane_mask     (cp_fw_mask),
                .samples_flat  (cp_fw_flat),
                .snapshot_valid(cp_fw_snapshot_valid),
                .sig_count     (cp_fw_count),
                .sig_xor       (cp_fw_xor),
                .sig_a         (cp_fw_a),
                .sig_b         (cp_fw_b)
            );

            dwt53_checkpoint8 #(
                .SAMPLE_W(16),
                .A_SIGN_EXTEND(A_SIGN_EXTEND)
            ) u_cp_rc (
                .clk           (sys_clk),
                .rst_n         (sys_rst_n),
                .frame_start   (rc_valid && rc_sof),
                .frame_end     (rc_valid && rc_eof),
                .lane_mask     (cp_rc_mask),
                .samples_flat  (cp_rc_flat),
                .snapshot_valid(cp_rc_snapshot_valid),
                .sig_count     (cp_rc_count),
                .sig_xor       (cp_rc_xor),
                .sig_a         (cp_rc_a),
                .sig_b         (cp_rc_b)
            );

            dwt53_checkpoint8 #(
                .SAMPLE_W(16),
                .A_SIGN_EXTEND(A_SIGN_EXTEND)
            ) u_cp_re (
                .clk           (sys_clk),
                .rst_n         (sys_rst_n),
                .frame_start   (re_valid && re_sof),
                .frame_end     (re_valid && re_eof),
                .lane_mask     (cp_re_mask),
                .samples_flat  (cp_re_flat),
                .snapshot_valid(cp_re_snapshot_valid),
                .sig_count     (cp_re_count),
                .sig_xor       (cp_re_xor),
                .sig_a         (cp_re_a),
                .sig_b         (cp_re_b)
            );
        end else begin : g_no_checkpoints
            always_comb begin
                cp_in_snapshot_valid = 1'b0;
                cp_in_count = 32'd0; cp_in_xor = 16'd0; cp_in_a = 32'd0; cp_in_b = 32'd0;

                cp_l1_snapshot_valid = 1'b0;
                cp_l1_count = 32'd0; cp_l1_xor = 16'd0; cp_l1_a = 32'd0; cp_l1_b = 32'd0;

                cp_fw_snapshot_valid = 1'b0;
                cp_fw_count = 32'd0; cp_fw_xor = 16'd0; cp_fw_a = 32'd0; cp_fw_b = 32'd0;

                cp_rc_snapshot_valid = 1'b0;
                cp_rc_count = 32'd0; cp_rc_xor = 16'd0; cp_rc_a = 32'd0; cp_rc_b = 32'd0;

                cp_re_snapshot_valid = 1'b0;
                cp_re_count = 32'd0; cp_re_xor = 16'd0; cp_re_a = 32'd0; cp_re_b = 32'd0;
            end
        end
    endgenerate

endmodule

`default_nettype wire
