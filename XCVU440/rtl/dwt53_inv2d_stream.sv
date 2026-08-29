`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_inv2d_stream
// One-level streaming Inverse 2D reversible Le Gall 5/3 transform.
//
// Input is a row-major stream of parallel subband samples at one logical
// coordinate: {LL, HL, LH, HH}. The inverse order is mandatory:
//   1) inverse vertical: (LL,LH)->L_row and (HL,HH)->H_row
//   2) inverse horizontal: (L_row,H_row)->reconstructed pixels
//
// The module stores only bounded per-column vertical state plus two ping-pong
// 2-row block buffers. It never stores a complete frame.
//
// Timing-closure note: a throughput-1 V1 register separates inverse vertical
// and inverse horizontal arithmetic. This preserves sample order/bit arithmetic
// while shortening the register-to-M10K combinational path.
//
// PIXEL_GAP controls the output pacing:
//   PIXEL_GAP=1 : one reconstructed pixel every clock while a row-pair drains.
//   PIXEL_GAP=4 : one reconstructed pixel every four clocks.
// This is used by the top-level schedule to keep the reconstructed LL1 stream
// aligned with the stored Level-1 high bands without pixel-level backpressure.
// -----------------------------------------------------------------------------
module dwt53_inv2d_stream #(
    parameter int SUB_W     = 640,
    parameter int SUB_H     = 360,
    parameter int DATA_W    = 16,
    parameter int PIXEL_GAP = 1
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    input  wire  signed [DATA_W-1:0]     in_ll,
    input  wire  signed [DATA_W-1:0]     in_hl,
    input  wire  signed [DATA_W-1:0]     in_lh,
    input  wire  signed [DATA_W-1:0]     in_hh,
    input  wire                          in_sof,
    input  wire                          in_eol,
    input  wire                          in_eof,

    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     out_sample,
    output logic                         out_sof,
    output logic                         out_eol,
    output logic                         out_eof,

    output logic                         overflow_error,
    output logic                         buffer_error,
    output logic                         protocol_error
);

    localparam int OUT_W = 2 * SUB_W;
    localparam int OUT_H = 2 * SUB_H;
    localparam int X_W   = (SUB_W <= 2) ? 1 : $clog2(SUB_W);
    localparam int Y_W   = (SUB_H <= 2) ? 1 : $clog2(SUB_H);
    localparam int EXT_W = DATA_W + 5;
    localparam int WORD_W= 4 * DATA_W;

    initial begin
        if (SUB_W < 2 || SUB_H < 2)
            $error("dwt53_inv2d_stream: SUB_W and SUB_H must be >= 2");
        if (PIXEL_GAP < 1)
            $error("dwt53_inv2d_stream: PIXEL_GAP must be >= 1");
    end

    // -------------------------------------------------------------------------
    // Input subband coordinates.
    // -------------------------------------------------------------------------
    logic [X_W-1:0] in_x_q;
    logic [Y_W-1:0] in_y_q;

    // Vertical inverse state per column.
    // prev_h_* = H[n-1]; prev_e_* = reconstructed e[n-1].
    // Xilinx-portability copy: force the four vertical-state arrays into
    // UltraScale block RAM. The frozen Quartus B0 source remains unchanged.
    (* ram_style = "block" *) logic signed [DATA_W-1:0] prev_h_l_mem [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] prev_e_l_mem [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] prev_h_h_mem [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] prev_e_h_mem [0:SUB_W-1];

    logic signed [DATA_W-1:0] q_prev_h_l, q_prev_e_l;
    logic signed [DATA_W-1:0] q_prev_h_h, q_prev_e_h;

    logic                     s0_valid_q;
    logic signed [DATA_W-1:0] s0_ll_q, s0_hl_q, s0_lh_q, s0_hh_q;
    logic [X_W-1:0]           s0_x_q;
    logic [Y_W-1:0]           s0_y_q;
    logic                     s0_eof_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_x_q      <= '0;
            in_y_q      <= '0;
            s0_valid_q  <= 1'b0;
            s0_ll_q     <= '0;
            s0_hl_q     <= '0;
            s0_lh_q     <= '0;
            s0_hh_q     <= '0;
            s0_x_q      <= '0;
            s0_y_q      <= '0;
            s0_eof_q    <= 1'b0;
        end else begin
            s0_valid_q <= in_valid;
            if (in_valid) begin
                s0_ll_q    <= in_ll;
                s0_hl_q    <= in_hl;
                s0_lh_q    <= in_lh;
                s0_hh_q    <= in_hh;
                s0_x_q     <= in_x_q;
                s0_y_q     <= in_y_q;
                s0_eof_q   <= in_eof;

                if (in_sof) begin
                    in_x_q <= (in_eol ? '0 : {{(X_W-1){1'b0}},1'b1});
                    in_y_q <= (in_eol ? {{(Y_W-1){1'b0}},1'b1} : '0);
                end else if (in_eof) begin
                    in_x_q <= '0;
                    in_y_q <= '0;
                end else if (in_eol) begin
                    in_x_q <= '0;
                    in_y_q <= in_y_q + 1'b1;
                end else begin
                    in_x_q <= in_x_q + 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Inverse vertical arithmetic.
    // -------------------------------------------------------------------------
    logic signed [EXT_W-1:0] ll_ext, hl_ext, lh_ext, hh_ext;
    logic signed [EXT_W-1:0] phl_ext, pel_ext, phh_ext, peh_ext;
    logic signed [EXT_W-1:0] ecur_l, ecur_h;
    logic signed [EXT_W-1:0] v_l_even, v_l_odd;
    logic signed [EXT_W-1:0] v_h_even, v_h_odd;

    assign ll_ext  = {{(EXT_W-DATA_W){s0_ll_q[DATA_W-1]}}, s0_ll_q};
    assign hl_ext  = {{(EXT_W-DATA_W){s0_hl_q[DATA_W-1]}}, s0_hl_q};
    assign lh_ext  = {{(EXT_W-DATA_W){s0_lh_q[DATA_W-1]}}, s0_lh_q};
    assign hh_ext  = {{(EXT_W-DATA_W){s0_hh_q[DATA_W-1]}}, s0_hh_q};

    assign phl_ext = {{(EXT_W-DATA_W){q_prev_h_l[DATA_W-1]}}, q_prev_h_l};
    assign pel_ext = {{(EXT_W-DATA_W){q_prev_e_l[DATA_W-1]}}, q_prev_e_l};
    assign phh_ext = {{(EXT_W-DATA_W){q_prev_h_h[DATA_W-1]}}, q_prev_h_h};
    assign peh_ext = {{(EXT_W-DATA_W){q_prev_e_h[DATA_W-1]}}, q_prev_e_h};

    assign ecur_l = ll_ext -
        ((((s0_y_q == 0) ? lh_ext : phl_ext) + lh_ext + 2) >>> 2);
    assign ecur_h = hl_ext -
        ((((s0_y_q == 0) ? hh_ext : phh_ext) + hh_ext + 2) >>> 2);

    // For y>0, current e[n] lets us finish reconstructed pair n-1.
    assign v_l_even = pel_ext;
    assign v_l_odd  = phl_ext + ((pel_ext + ecur_l) >>> 1);
    assign v_h_even = peh_ext;
    assign v_h_odd  = phh_ext + ((peh_ext + ecur_h) >>> 1);

    // -------------------------------------------------------------------------
    // V1 timing pipeline: inverse-vertical -> inverse-horizontal.
    //
    // TimeQuest on Cyclone V showed the former critical path crossing the
    // complete vertical inverse, complete horizontal inverse, block packing,
    // and the M10K write-data port in one cycle.  Registering the four vertical
    // intermediate samples here cuts that arithmetic cone at the natural 2-D
    // transform boundary without changing the Le Gall 5/3 arithmetic itself.
    // Metadata is delayed with the samples so row/bank/write scheduling remains
    // aligned.  First/last-column conditions are predecoded into 1-bit V1 flags
    // so the horizontal stage does not rebuild X-wide boundary comparators.
    // One V1 item can be accepted and one can be consumed every cycle.
    // -------------------------------------------------------------------------
    logic                         v1_valid_q;
    logic                         v1_is_flush_q;
    logic [X_W-1:0]               v1_x_q;
    // Predecoded horizontal-boundary flags.  Registering these on the S0->V1
    // boundary removes the X-wide equality comparators from the V1 critical
    // cycle (TimeQuest showed v1_x_q -> overflow_error as the remaining path).
    logic                         v1_first_x_q;
    logic                         v1_last_x_q;
    logic [Y_W-1:0]               v1_block_row_q;
    logic signed [EXT_W-1:0]      v1_l_even_q, v1_l_odd_q;
    logic signed [EXT_W-1:0]      v1_h_even_q, v1_h_odd_q;

    // -------------------------------------------------------------------------
    // Horizontal inverse state for the two rows reconstructed in parallel.
    // This stage now consumes only registered V1 vertical results.
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] h_prev_h_even_q, h_prev_e_even_q;
    logic signed [DATA_W-1:0] h_prev_h_odd_q,  h_prev_e_odd_q;

    logic signed [EXT_W-1:0] hph_even_ext, hpe_even_ext;
    logic signed [EXT_W-1:0] hph_odd_ext,  hpe_odd_ext;
    logic signed [EXT_W-1:0] h_e_cur_even, h_e_cur_odd;

    assign hph_even_ext = {{(EXT_W-DATA_W){h_prev_h_even_q[DATA_W-1]}}, h_prev_h_even_q};
    assign hpe_even_ext = {{(EXT_W-DATA_W){h_prev_e_even_q[DATA_W-1]}}, h_prev_e_even_q};
    assign hph_odd_ext  = {{(EXT_W-DATA_W){h_prev_h_odd_q[DATA_W-1]}},  h_prev_h_odd_q};
    assign hpe_odd_ext  = {{(EXT_W-DATA_W){h_prev_e_odd_q[DATA_W-1]}},  h_prev_e_odd_q};

    assign h_e_cur_even = v1_l_even_q -
        ((((v1_first_x_q) ? v1_h_even_q : hph_even_ext) + v1_h_even_q + 2) >>> 2);
    assign h_e_cur_odd  = v1_l_odd_q -
        ((((v1_first_x_q) ? v1_h_odd_q : hph_odd_ext) + v1_h_odd_q + 2) >>> 2);

    logic signed [EXT_W-1:0] p00_prev, p01_prev, p10_prev, p11_prev;
    logic signed [EXT_W-1:0] p00_last, p01_last, p10_last, p11_last;

    assign p00_prev = hpe_even_ext;
    assign p01_prev = hph_even_ext + ((hpe_even_ext + h_e_cur_even) >>> 1);
    assign p10_prev = hpe_odd_ext;
    assign p11_prev = hph_odd_ext + ((hpe_odd_ext + h_e_cur_odd) >>> 1);

    // Horizontal right boundary e[M] = e[M-1].
    assign p00_last = h_e_cur_even;
    assign p01_last = v1_h_even_q + h_e_cur_even;
    assign p10_last = h_e_cur_odd;
    assign p11_last = v1_h_odd_q + h_e_cur_odd;

    function automatic logic fits_data_w(
        input logic signed [EXT_W-1:0] value
    );
        logic signed [DATA_W-1:0] narrowed;
        logic signed [EXT_W-1:0] widened_back;
        begin
            narrowed     = value[DATA_W-1:0];
            widened_back = {{(EXT_W-DATA_W){narrowed[DATA_W-1]}}, narrowed};
            fits_data_w  = (widened_back == value);
        end
    endfunction

    function automatic logic [WORD_W-1:0] pack_block(
        input logic signed [EXT_W-1:0] a00,
        input logic signed [EXT_W-1:0] a01,
        input logic signed [EXT_W-1:0] a10,
        input logic signed [EXT_W-1:0] a11
    );
        begin
            pack_block = {
                a11[DATA_W-1:0],
                a10[DATA_W-1:0],
                a01[DATA_W-1:0],
                a00[DATA_W-1:0]
            };
        end
    endfunction

    // -------------------------------------------------------------------------
    // Two ping-pong block-row buffers.
    // Each entry stores a 2x2 reconstructed block:
    //   lane0=p00, lane1=p01, lane2=p10, lane3=p11.
    // One bank therefore stores exactly two output rows, not a frame.
    //
    // v0.2 change: the drain side uses a registered synchronous read pipeline.
    // This coding style is compatible with block-RAM inference; there is no
    // combinational array read on the output path.
    // -------------------------------------------------------------------------
    // Physical implementation: one simple-dual-port M10K-backed RAM.
    // The two logical ping-pong banks occupy contiguous address ranges:
    //   bank 0 -> [0 .. SUB_W-1]
    //   bank 1 -> [SUB_W .. 2*SUB_W-1]
    //
    // Keeping a single write request and a single synchronous read request is
    // intentional: Quartus 20.1 could not infer the previous two arrays as M10K
    // because each array had several procedural write sites.
    localparam int BLOCK_DEPTH  = 2 * SUB_W;
    localparam int BLOCK_ADDR_W = (BLOCK_DEPTH <= 2) ? 1 : $clog2(BLOCK_DEPTH);
    localparam logic [BLOCK_ADDR_W-1:0] BLOCK_BANK1_BASE = SUB_W;
    localparam logic [X_W-1:0]          BLOCK_LAST_X     = SUB_W-1;

    (* ram_style = "block" *) logic [WORD_W-1:0] block_mem [0:BLOCK_DEPTH-1];

    logic                    block_wr_en;
    logic [BLOCK_ADDR_W-1:0] block_wr_addr;
    logic [WORD_W-1:0]       block_wr_data;
    logic                    block_wr_collision;

    logic [BLOCK_ADDR_W-1:0] block_rd_addr;
    logic [WORD_W-1:0]       block_rd_data_q;

    function automatic logic [BLOCK_ADDR_W-1:0] block_addr(
        input logic             bank,
        input logic [X_W-1:0]   bx
    );
        logic [BLOCK_ADDR_W-1:0] bx_ext;
        begin
            bx_ext = {{(BLOCK_ADDR_W-X_W){1'b0}}, bx};
            block_addr = bank ? (BLOCK_BANK1_BASE + bx_ext) : bx_ext;
        end
    endfunction

    logic bank0_ready_q, bank1_ready_q;
    logic drain_buffer_error_q;
    logic bank0_set_q, bank1_set_q;
    logic bank0_clear_q, bank1_clear_q;
    logic [Y_W-1:0] bank0_row_q, bank1_row_q;

    logic fill_sel_q;
    logic active_fill_bank_q;
    logic [Y_W-1:0] active_block_row_q;

    logic last_block_pending_q;
    logic [WORD_W-1:0] last_block_word_q;
    logic last_block_bank_q;
    logic [Y_W-1:0] last_block_row_q;

    // A bank can be released by the drain engine on the same clock edge that
    // the transform side starts the next row-pair. bank*_ready_q is still 1
    // before that edge, so account for the same-edge release explicitly.
    wire bank0_release_now;
    wire bank1_release_now;

    wire fill_bank_free =
        fill_sel_q ? (!bank1_ready_q || bank1_release_now)
                   : (!bank0_ready_q || bank0_release_now);

    // Drain-side effective-ready masks. bank*_clear_q is asserted on the same
    // edge that emits the final pixel of a bank, while bank*_ready_q is cleared
    // one clock later by the ownership FF. Without this mask the read scheduler
    // can see a stale ready=1 for one cycle and request the just-drained bank
    // again, replaying an entire reconstructed row pair.
    wire bank0_drain_ready = bank0_ready_q && !bank0_clear_q;
    wire bank1_drain_ready = bank1_ready_q && !bank1_clear_q;

    // -------------------------------------------------------------------------
    // Bottom-boundary flush. After the final input subband row, one final
    // vertical reconstructed row-pair remains. Sweep the bounded column state.
    // v0.2 waits until the selected ping-pong bank is genuinely free before
    // starting the sweep, preventing overwrite of a bank still being drained.
    // -------------------------------------------------------------------------
    logic bottom_flush_request_q;
    logic flush_active_q;
    logic [X_W:0] flush_issue_count_q;

    logic flush_pipe_valid_q;
    logic [X_W-1:0] flush_x_pipe_q;
    logic signed [EXT_W-1:0] f_phl_ext, f_pel_ext, f_phh_ext, f_peh_ext;
    logic signed [EXT_W-1:0] f_v_l_even, f_v_l_odd;
    logic signed [EXT_W-1:0] f_v_h_even, f_v_h_odd;

    // Normal input reads and bottom-flush reads are frame-atomically exclusive,
    // so both consumers share the same registered RAM read data.
    assign f_phl_ext = {{(EXT_W-DATA_W){q_prev_h_l[DATA_W-1]}}, q_prev_h_l};
    assign f_pel_ext = {{(EXT_W-DATA_W){q_prev_e_l[DATA_W-1]}}, q_prev_e_l};
    assign f_phh_ext = {{(EXT_W-DATA_W){q_prev_h_h[DATA_W-1]}}, q_prev_h_h};
    assign f_peh_ext = {{(EXT_W-DATA_W){q_prev_e_h[DATA_W-1]}}, q_prev_e_h};

    // Vertical boundary e[M] = e[M-1] => odd = H + e.
    assign f_v_l_even = f_pel_ext;
    assign f_v_l_odd  = f_phl_ext + f_pel_ext;
    assign f_v_h_even = f_peh_ext;
    assign f_v_h_odd  = f_phh_ext + f_peh_ext;

    // -------------------------------------------------------------------------
    // Xilinx-compatible vertical-state RAM ports.
    //
    // The normal transform and bottom flush share one synchronous read port.
    // Flush has priority only for an already-illegal overlap with new input;
    // legal operation keeps the two request classes mutually exclusive.
    // All memory accesses and the read-data registers are clock-only. Reset
    // clears their associated valid/control state elsewhere instead.
    // -------------------------------------------------------------------------
    wire prev_flush_rd_req =
        flush_active_q && (flush_issue_count_q < SUB_W);
    wire prev_mem_rd_req = in_valid || prev_flush_rd_req;
    wire [X_W-1:0] prev_mem_rd_addr = prev_flush_rd_req ?
        flush_issue_count_q[X_W-1:0] : in_x_q;

    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (prev_mem_rd_req) begin
                q_prev_h_l <= prev_h_l_mem[prev_mem_rd_addr];
                q_prev_e_l <= prev_e_l_mem[prev_mem_rd_addr];
                q_prev_h_h <= prev_h_h_mem[prev_mem_rd_addr];
                q_prev_e_h <= prev_e_h_mem[prev_mem_rd_addr];
            end

            if (s0_valid_q) begin
                prev_h_l_mem[s0_x_q] <= s0_lh_q;
                prev_e_l_mem[s0_x_q] <= ecur_l[DATA_W-1:0];
                prev_h_h_mem[s0_x_q] <= s0_hh_q;
                prev_e_h_mem[s0_x_q] <= ecur_h[DATA_W-1:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main transform/control state.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1_valid_q              <= 1'b0;
            v1_is_flush_q           <= 1'b0;
            v1_x_q                  <= '0;
            v1_first_x_q            <= 1'b0;
            v1_last_x_q             <= 1'b0;
            v1_block_row_q          <= '0;
            v1_l_even_q             <= '0;
            v1_l_odd_q              <= '0;
            v1_h_even_q             <= '0;
            v1_h_odd_q              <= '0;

            h_prev_h_even_q         <= '0;
            h_prev_e_even_q         <= '0;
            h_prev_h_odd_q          <= '0;
            h_prev_e_odd_q          <= '0;

            bank0_set_q             <= 1'b0;
            bank1_set_q             <= 1'b0;
            bank0_row_q             <= '0;
            bank1_row_q             <= '0;

            fill_sel_q              <= 1'b0;
            active_fill_bank_q      <= 1'b0;
            active_block_row_q      <= '0;

            last_block_pending_q    <= 1'b0;
            last_block_word_q       <= '0;
            last_block_bank_q       <= 1'b0;
            last_block_row_q        <= '0;

            bottom_flush_request_q  <= 1'b0;
            flush_active_q          <= 1'b0;
            flush_issue_count_q     <= '0;
            flush_pipe_valid_q      <= 1'b0;
            flush_x_pipe_q          <= '0;

            overflow_error          <= 1'b0;
            buffer_error            <= 1'b0;
            protocol_error          <= 1'b0;
        end else begin
            if (drain_buffer_error_q || block_wr_collision)
                buffer_error <= 1'b1;

            bank0_set_q <= 1'b0;
            bank1_set_q <= 1'b0;

            // V1 is a throughput-1 pipeline register.  The old V1 item is
            // consumed below on this edge while a new vertical result may be
            // captured for the next cycle.
            v1_valid_q <= 1'b0;

            // Commit the pending right-edge block. This completes a bank and
            // marks it ready for the drain engine.
            if (last_block_pending_q) begin
                if (!last_block_bank_q) begin
                    bank0_set_q <= 1'b1;
                    bank0_row_q <= last_block_row_q;
                end else begin
                    bank1_set_q <= 1'b1;
                    bank1_row_q <= last_block_row_q;
                end
                fill_sel_q           <= ~last_block_bank_q;
                last_block_pending_q <= 1'b0;
            end

            // -----------------------------------------------------------------
            // Stage S0: vertical inverse and bounded per-column state update.
            // y=0 initializes vertical state but does not yet produce an output
            // row pair.  For y>0, register the completed vertical pair into V1.
            // -----------------------------------------------------------------
            if (s0_valid_q) begin
                if (flush_active_q)
                    protocol_error <= 1'b1;

                if (!fits_data_w(ecur_l) || !fits_data_w(ecur_h))
                    overflow_error <= 1'b1;

                if (s0_y_q > 0) begin
                    v1_valid_q     <= 1'b1;
                    v1_is_flush_q  <= 1'b0;
                    v1_x_q         <= s0_x_q;
                    v1_first_x_q   <= (s0_x_q == '0);
                    v1_last_x_q    <= (s0_x_q == BLOCK_LAST_X);
                    v1_block_row_q <= s0_y_q - 1'b1;
                    v1_l_even_q    <= v_l_even;
                    v1_l_odd_q     <= v_l_odd;
                    v1_h_even_q    <= v_h_even;
                    v1_h_odd_q     <= v_h_odd;

                    // Keep vertical-range diagnostics on the vertical side of
                    // the new pipeline boundary.
                    if (!fits_data_w(v_l_even) || !fits_data_w(v_l_odd) ||
                        !fits_data_w(v_h_even) || !fits_data_w(v_h_odd))
                        overflow_error <= 1'b1;
                end

                if (s0_eof_q)
                    bottom_flush_request_q <= 1'b1;
            end

            // -----------------------------------------------------------------
            // Stage V1: horizontal inverse, block formation, and right boundary.
            // All arithmetic here starts from registered vertical intermediates.
            // -----------------------------------------------------------------
            if (v1_valid_q) begin
                if (v1_first_x_q) begin
                    active_fill_bank_q <= fill_sel_q;
                    active_block_row_q <= v1_block_row_q;

                    if ((!fill_sel_q && bank0_ready_q && !bank0_release_now) ||
                        ( fill_sel_q && bank1_ready_q && !bank1_release_now))
                        buffer_error <= 1'b1;
                end

                h_prev_h_even_q <= v1_h_even_q[DATA_W-1:0];
                h_prev_e_even_q <= h_e_cur_even[DATA_W-1:0];
                h_prev_h_odd_q  <= v1_h_odd_q[DATA_W-1:0];
                h_prev_e_odd_q  <= h_e_cur_odd[DATA_W-1:0];

                if (!fits_data_w(h_e_cur_even) || !fits_data_w(h_e_cur_odd))
                    overflow_error <= 1'b1;

                if (!v1_first_x_q) begin
                    if (!fits_data_w(p00_prev) || !fits_data_w(p01_prev) ||
                        !fits_data_w(p10_prev) || !fits_data_w(p11_prev))
                        overflow_error <= 1'b1;

                    if (v1_last_x_q) begin
                        if (last_block_pending_q)
                            buffer_error <= 1'b1;

                        last_block_pending_q <= 1'b1;
                        last_block_bank_q    <= active_fill_bank_q;
                        last_block_row_q     <= active_block_row_q;
                        last_block_word_q    <=
                            pack_block(p00_last,p01_last,p10_last,p11_last);

                        if (!fits_data_w(p00_last) || !fits_data_w(p01_last) ||
                            !fits_data_w(p10_last) || !fits_data_w(p11_last))
                            overflow_error <= 1'b1;

                        // The final V1 item of the bottom-boundary sweep is the
                        // point at which the flush is logically complete.  Keep
                        // the request active until then so new frame input cannot
                        // overlap an in-flight V1 flush sample.
                        if (v1_is_flush_q) begin
                            flush_active_q          <= 1'b0;
                            bottom_flush_request_q  <= 1'b0;
                        end
                    end
                end
            end

            // Begin bottom flush only after every normal item has crossed V1,
            // after the normal final block commit, and when the selected bank is
            // free.  The added !v1_valid_q is required by the timing pipeline.
            if (bottom_flush_request_q && !flush_active_q &&
                !last_block_pending_q && !s0_valid_q && !v1_valid_q &&
                fill_bank_free) begin
                flush_active_q      <= 1'b1;
                flush_issue_count_q <= '0;
            end

            // Synchronous read pipeline for the final vertical boundary row.
            flush_pipe_valid_q <= 1'b0;
            if (prev_flush_rd_req) begin
                flush_x_pipe_q      <= flush_issue_count_q[X_W-1:0];
                flush_pipe_valid_q  <= 1'b1;
                flush_issue_count_q <= flush_issue_count_q + 1'b1;
            end

            // Register bottom-boundary vertical results into the same V1
            // boundary used by normal traffic.  Normal and flush production are
            // frame-atomically separated; overlap is therefore a protocol error.
            if (flush_pipe_valid_q) begin
                if (s0_valid_q && (s0_y_q > 0))
                    protocol_error <= 1'b1;

                v1_valid_q     <= 1'b1;
                v1_is_flush_q  <= 1'b1;
                v1_x_q         <= flush_x_pipe_q;
                v1_first_x_q   <= (flush_x_pipe_q == '0);
                v1_last_x_q    <= (flush_x_pipe_q == BLOCK_LAST_X);
                v1_block_row_q <= SUB_H-1;
                v1_l_even_q    <= f_v_l_even;
                v1_l_odd_q     <= f_v_l_odd;
                v1_h_even_q    <= f_v_h_even;
                v1_h_odd_q     <= f_v_h_odd;

                if (!fits_data_w(f_v_l_even) || !fits_data_w(f_v_l_odd) ||
                    !fits_data_w(f_v_h_even) || !fits_data_w(f_v_h_odd))
                    overflow_error <= 1'b1;
            end

            // New external input after EOF before flush is complete is illegal
            // for this frame-atomic streaming core.
            if (in_valid && (bottom_flush_request_q || flush_active_q))
                protocol_error <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Block-buffer write arbitration.
    //
    // After the V1 pipeline, normal and bottom-flush traffic share one
    // horizontal/block producer. The legal schedule permits at most one
    // block-buffer write per cycle:
    //   1) pending right-edge commit,
    //   2) V1 reconstructed block.
    //
    // Priority only defines deterministic behavior if an illegal overlap ever
    // occurs; block_wr_collision makes that condition sticky-visible as a
    // buffer_error. The regression-proven schedule should never assert it.
    // -------------------------------------------------------------------------
    always_comb begin
        block_wr_en        = 1'b0;
        block_wr_addr      = '0;
        block_wr_data      = '0;
        block_wr_collision = 1'b0;

        if (last_block_pending_q) begin
            block_wr_en   = 1'b1;
            block_wr_addr = block_addr(last_block_bank_q, BLOCK_LAST_X);
            block_wr_data = last_block_word_q;
        end

        // Normal and bottom-flush samples share the registered V1 horizontal
        // stage, so they also share one block-write producer here.
        if (v1_valid_q && !v1_first_x_q) begin
            if (block_wr_en)
                block_wr_collision = 1'b1;
            else begin
                block_wr_en   = 1'b1;
                block_wr_addr = block_addr(active_fill_bank_q, v1_x_q - 1'b1);
                block_wr_data = pack_block(p00_prev,p01_prev,p10_prev,p11_prev);
            end
        end
    end

    // Bank ownership flags are centralized here so each ready bit has exactly
    // one procedural driver.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank0_ready_q <= 1'b0;
            bank1_ready_q <= 1'b0;
        end else begin
            if (bank0_clear_q)
                bank0_ready_q <= 1'b0;
            if (bank1_clear_q)
                bank1_ready_q <= 1'b0;
            if (bank0_set_q)
                bank0_ready_q <= 1'b1;
            if (bank1_set_q)
                bank1_ready_q <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // BRAM-safe synchronous bank read and row-major drain.
    //
    // A bank word contains two pixels from the first reconstructed row and two
    // from the second. The read port is synchronous; one next-word prefetch is
    // enough because each word supplies two output pixels. For PIXEL_GAP=1 the
    // next word is requested while pixel 0 of the current word is emitted and is
    // therefore available by the time pixel 1 completes. Larger PIXEL_GAP values
    // simply hold the prefetched word longer.
    // -------------------------------------------------------------------------
    logic rd_req;
    logic rd_req_bank;
    logic [X_W-1:0] rd_req_bx;
    logic rd_req_row_phase;
    logic [Y_W-1:0] rd_req_block_row;

    logic rd_resp_valid_q;
    wire  [WORD_W-1:0] rd_data_q;
    assign rd_data_q = block_rd_data_q;
    logic rd_bank_q;
    logic [X_W-1:0] rd_bx_q;
    logic rd_row_phase_q;
    logic [Y_W-1:0] rd_block_row_q;

    logic cur_valid_q;
    logic [WORD_W-1:0] cur_word_q;
    logic cur_bank_q;
    logic [X_W-1:0] cur_bx_q;
    logic cur_row_phase_q;
    logic cur_pix_phase_q;
    logic [Y_W-1:0] cur_block_row_q;

    logic next_valid_q;
    logic [WORD_W-1:0] next_word_q;
    logic next_bank_q;
    logic [X_W-1:0] next_bx_q;
    logic next_row_phase_q;
    logic [Y_W-1:0] next_block_row_q;

    integer gap_count_q;

    wire emit_now = cur_valid_q && (gap_count_q == 0);

    // True on the edge that emits the final pixel stored in a bank.
    assign bank0_release_now =
        emit_now && cur_pix_phase_q && cur_row_phase_q &&
        (cur_bx_q == SUB_W-1) && !cur_bank_q;

    assign bank1_release_now =
        emit_now && cur_pix_phase_q && cur_row_phase_q &&
        (cur_bx_q == SUB_W-1) && cur_bank_q;

    function automatic logic signed [DATA_W-1:0] select_pixel(
        input logic [WORD_W-1:0] word,
        input logic row_phase,
        input logic pix_phase
    );
        begin
            case ({row_phase,pix_phase})
                2'b00: select_pixel = word[0*DATA_W +: DATA_W];
                2'b01: select_pixel = word[1*DATA_W +: DATA_W];
                2'b10: select_pixel = word[2*DATA_W +: DATA_W];
                default: select_pixel = word[3*DATA_W +: DATA_W];
            endcase
        end
    endfunction

    // Decide which word to request. Only one synchronous read is outstanding.
    always_comb begin
        rd_req           = 1'b0;
        rd_req_bank      = 1'b0;
        rd_req_bx        = '0;
        rd_req_row_phase = 1'b0;
        rd_req_block_row = '0;

        // Initial word of the oldest ready bank. The logical block-row tag
        // preserves output order even if bank-ready pulses are not simultaneous.
        if (!cur_valid_q && !next_valid_q && !rd_resp_valid_q) begin
            if (bank0_drain_ready && bank1_drain_ready) begin
                if (bank0_row_q <= bank1_row_q) begin
                    rd_req           = 1'b1;
                    rd_req_bank      = 1'b0;
                    rd_req_bx        = '0;
                    rd_req_row_phase = 1'b0;
                    rd_req_block_row = bank0_row_q;
                end else begin
                    rd_req           = 1'b1;
                    rd_req_bank      = 1'b1;
                    rd_req_bx        = '0;
                    rd_req_row_phase = 1'b0;
                    rd_req_block_row = bank1_row_q;
                end
            end else if (bank0_drain_ready) begin
                rd_req           = 1'b1;
                rd_req_bank      = 1'b0;
                rd_req_bx        = '0;
                rd_req_row_phase = 1'b0;
                rd_req_block_row = bank0_row_q;
            end else if (bank1_drain_ready) begin
                rd_req           = 1'b1;
                rd_req_bank      = 1'b1;
                rd_req_bx        = '0;
                rd_req_row_phase = 1'b0;
                rd_req_block_row = bank1_row_q;
            end
        end
        // Prefetch the next word while pixel 0 of the current word is emitted.
        else if (emit_now && !cur_pix_phase_q &&
                 !next_valid_q && !rd_resp_valid_q) begin
            if (cur_bx_q != SUB_W-1) begin
                rd_req           = 1'b1;
                rd_req_bank      = cur_bank_q;
                rd_req_bx        = cur_bx_q + 1'b1;
                rd_req_row_phase = cur_row_phase_q;
                rd_req_block_row = cur_block_row_q;
            end else if (!cur_row_phase_q) begin
                rd_req           = 1'b1;
                rd_req_bank      = cur_bank_q;
                rd_req_bx        = '0;
                rd_req_row_phase = 1'b1;
                rd_req_block_row = cur_block_row_q;
            end else begin
                // End of a bank: prefetch the other bank only if it is already
                // complete. Otherwise the drain safely pauses between row pairs.
                if (!cur_bank_q && bank1_drain_ready) begin
                    rd_req           = 1'b1;
                    rd_req_bank      = 1'b1;
                    rd_req_bx        = '0;
                    rd_req_row_phase = 1'b0;
                    rd_req_block_row = bank1_row_q;
                end else if (cur_bank_q && bank0_drain_ready) begin
                    rd_req           = 1'b1;
                    rd_req_bank      = 1'b0;
                    rd_req_bx        = '0;
                    rd_req_row_phase = 1'b0;
                    rd_req_block_row = bank0_row_q;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Single physical M10K RAM port pair.
    //
    // One registered read port + one write port, with no reset on the memory
    // array or read-data register. This is the canonical structure we want
    // Quartus to map into M10K blocks.
    // -------------------------------------------------------------------------
    assign block_rd_addr = block_addr(rd_req_bank, rd_req_bx);

    always_ff @(posedge clk) begin
        if (block_wr_en)
            block_mem[block_wr_addr] <= block_wr_data;

        if (rd_req)
            block_rd_data_q <= block_mem[block_rd_addr];
    end

    // Register the metadata alongside the synchronous RAM read request.
    // block_rd_data_q itself is registered in the RAM process above.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_resp_valid_q <= 1'b0;
            rd_bank_q       <= 1'b0;
            rd_bx_q         <= '0;
            rd_row_phase_q  <= 1'b0;
            rd_block_row_q  <= '0;
        end else begin
            rd_resp_valid_q <= rd_req;
            if (rd_req) begin
                rd_bank_q      <= rd_req_bank;
                rd_bx_q        <= rd_req_bx;
                rd_row_phase_q <= rd_req_row_phase;
                rd_block_row_q <= rd_req_block_row;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_valid_q       <= 1'b0;
            cur_word_q        <= '0;
            cur_bank_q        <= 1'b0;
            cur_bx_q          <= '0;
            cur_row_phase_q   <= 1'b0;
            cur_pix_phase_q   <= 1'b0;
            cur_block_row_q   <= '0;

            next_valid_q      <= 1'b0;
            next_word_q       <= '0;
            next_bank_q       <= 1'b0;
            next_bx_q         <= '0;
            next_row_phase_q  <= 1'b0;
            next_block_row_q  <= '0;

            gap_count_q       <= 0;

            out_valid         <= 1'b0;
            out_sample        <= '0;
            out_sof           <= 1'b0;
            out_eol           <= 1'b0;
            out_eof           <= 1'b0;
            bank0_clear_q       <= 1'b0;
            bank1_clear_q       <= 1'b0;
            drain_buffer_error_q<= 1'b0;
        end else begin
            out_valid     <= 1'b0;
            out_sof       <= 1'b0;
            out_eol       <= 1'b0;
            out_eof       <= 1'b0;
            bank0_clear_q      <= 1'b0;
            bank1_clear_q      <= 1'b0;

            // Capture a read response.  A response that arrives while the
            // second pixel of cur_word_q is emitted is handled by the handoff
            // block below.  In that cycle the old next slot may be promoted to
            // cur and the arriving response can refill next on the same edge.
            // Looking only at pre-edge next_valid_q would falsely report a full
            // two-entry queue for legal PIXEL_GAP=1 operation.
            if (rd_resp_valid_q) begin
                if (!cur_valid_q) begin
                    cur_valid_q       <= 1'b1;
                    cur_word_q        <= rd_data_q;
                    cur_bank_q        <= rd_bank_q;
                    cur_bx_q          <= rd_bx_q;
                    cur_row_phase_q   <= rd_row_phase_q;
                    cur_pix_phase_q   <= 1'b0;
                    cur_block_row_q   <= rd_block_row_q;
                    gap_count_q       <= 0;
                end else if (!(emit_now && cur_pix_phase_q)) begin
                    if (!next_valid_q) begin
                        next_valid_q     <= 1'b1;
                        next_word_q      <= rd_data_q;
                        next_bank_q      <= rd_bank_q;
                        next_bx_q        <= rd_bx_q;
                        next_row_phase_q <= rd_row_phase_q;
                        next_block_row_q <= rd_block_row_q;
                    end else begin
                        drain_buffer_error_q <= 1'b1;
                    end
                end
            end

            if (gap_count_q > 0)
                gap_count_q <= gap_count_q - 1;

            if (emit_now) begin
                out_valid  <= 1'b1;
                out_sample <= select_pixel(cur_word_q,
                                           cur_row_phase_q,
                                           cur_pix_phase_q);

                out_sof <= (cur_block_row_q == 0) &&
                           !cur_row_phase_q &&
                           (cur_bx_q == 0) && !cur_pix_phase_q;

                out_eol <= (cur_bx_q == SUB_W-1) && cur_pix_phase_q;

                out_eof <= (cur_block_row_q == SUB_H-1) &&
                           cur_row_phase_q &&
                           (cur_bx_q == SUB_W-1) && cur_pix_phase_q;

                gap_count_q <= PIXEL_GAP - 1;

                if (!cur_pix_phase_q) begin
                    cur_pix_phase_q <= 1'b1;
                end else begin
                    // Finished both pixels represented by this word for the
                    // current output row.
                    if (cur_row_phase_q && (cur_bx_q == SUB_W-1)) begin
                        if (!cur_bank_q)
                            bank0_clear_q <= 1'b1;
                        else
                            bank1_clear_q <= 1'b1;
                    end

                    // Advance from a queued prefetch, or consume a response
                    // arriving on this exact edge. Otherwise pause until the
                    // next synchronous read response is available.
                    if (next_valid_q) begin
                        cur_valid_q       <= 1'b1;
                        cur_word_q        <= next_word_q;
                        cur_bank_q        <= next_bank_q;
                        cur_bx_q          <= next_bx_q;
                        cur_row_phase_q   <= next_row_phase_q;
                        cur_pix_phase_q   <= 1'b0;
                        cur_block_row_q   <= next_block_row_q;

                        // Same-cycle dequeue/enqueue: promote the queued word
                        // and retain a simultaneously arriving BRAM response as
                        // the new next word instead of flagging/dropping it.
                        if (rd_resp_valid_q) begin
                            next_valid_q     <= 1'b1;
                            next_word_q      <= rd_data_q;
                            next_bank_q      <= rd_bank_q;
                            next_bx_q        <= rd_bx_q;
                            next_row_phase_q <= rd_row_phase_q;
                            next_block_row_q <= rd_block_row_q;
                        end else begin
                            next_valid_q <= 1'b0;
                        end
                    end else if (rd_resp_valid_q) begin
                        cur_valid_q       <= 1'b1;
                        cur_word_q        <= rd_data_q;
                        cur_bank_q        <= rd_bank_q;
                        cur_bx_q          <= rd_bx_q;
                        cur_row_phase_q   <= rd_row_phase_q;
                        cur_pix_phase_q   <= 1'b0;
                        cur_block_row_q   <= rd_block_row_q;
                    end else begin
                        cur_valid_q     <= 1'b0;
                        cur_pix_phase_q <= 1'b0;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
