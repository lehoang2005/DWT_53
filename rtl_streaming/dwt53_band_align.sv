`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_band_align
// Bounded FIFO that delays Level-1 high bands {HL1,LH1,HH1} until the
// reconstructed LL1 stream emerges from inverse Level 2.
//
// Push order is the natural Level-1 subband coordinate order.
// Pop is driven by reconstructed LL1 valid samples. One cycle after pop request,
// an aligned quartet {LL1_rec, HL1, LH1, HH1} is emitted.
//
// This is a circulating fixed-depth buffer; storage does not scale with image
// height. Depth is a microarchitecture parameter and must be validated against
// measured pipeline skew before final RTL freeze.
// -----------------------------------------------------------------------------
module dwt53_band_align #(
    parameter int DATA_W = 16,
    parameter int DEPTH  = 16 * 640
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         push_valid,
    input  logic signed [DATA_W-1:0]     push_hl,
    input  logic signed [DATA_W-1:0]     push_lh,
    input  logic signed [DATA_W-1:0]     push_hh,

    input  logic                         ll_valid,
    input  logic signed [DATA_W-1:0]     ll_sample,
    input  logic                         ll_sof,
    input  logic                         ll_eol,
    input  logic                         ll_eof,

    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     out_ll,
    output logic signed [DATA_W-1:0]     out_hl,
    output logic signed [DATA_W-1:0]     out_lh,
    output logic signed [DATA_W-1:0]     out_hh,
    output logic                         out_sof,
    output logic                         out_eol,
    output logic                         out_eof,

    output logic                         overflow_error,
    output logic                         underflow_error
);

    localparam int WORD_W = 3 * DATA_W;
    localparam int AW     = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam int CW     = (DEPTH <= 2) ? 2 : $clog2(DEPTH+1);

    initial begin
        if (DEPTH < 2)
            $error("dwt53_band_align: DEPTH must be >= 2");
    end

    (* ramstyle = "M10K" *) logic [WORD_W-1:0] mem [0:DEPTH-1];

    logic [AW-1:0] wr_ptr_q, rd_ptr_q;
    logic [CW-1:0] count_q;

    logic [WORD_W-1:0] rd_q;
    logic               pop_pending_q;

    logic signed [DATA_W-1:0] ll_hold_q;
    logic ll_sof_hold_q, ll_eol_hold_q, ll_eof_hold_q;

    wire do_push = push_valid && (count_q < DEPTH);
    wire do_pop  = ll_valid   && (count_q != 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_q        <= '0;
            rd_ptr_q        <= '0;
            count_q         <= '0;
            rd_q            <= '0;
            pop_pending_q   <= 1'b0;
            ll_hold_q       <= '0;
            ll_sof_hold_q   <= 1'b0;
            ll_eol_hold_q   <= 1'b0;
            ll_eof_hold_q   <= 1'b0;

            out_valid       <= 1'b0;
            out_ll          <= '0;
            out_hl          <= '0;
            out_lh          <= '0;
            out_hh          <= '0;
            out_sof         <= 1'b0;
            out_eol         <= 1'b0;
            out_eof         <= 1'b0;

            overflow_error  <= 1'b0;
            underflow_error <= 1'b0;
        end else begin
            out_valid <= pop_pending_q;
            out_sof   <= pop_pending_q && ll_sof_hold_q;
            out_eol   <= pop_pending_q && ll_eol_hold_q;
            out_eof   <= pop_pending_q && ll_eof_hold_q;

            if (pop_pending_q) begin
                out_ll <= ll_hold_q;
                out_hl <= rd_q[0*DATA_W +: DATA_W];
                out_lh <= rd_q[1*DATA_W +: DATA_W];
                out_hh <= rd_q[2*DATA_W +: DATA_W];
            end

            pop_pending_q <= 1'b0;

            if (push_valid) begin
                if (count_q == DEPTH) begin
                    overflow_error <= 1'b1;
                end else begin
                    mem[wr_ptr_q] <= {push_hh, push_lh, push_hl};
                    if (wr_ptr_q == DEPTH-1)
                        wr_ptr_q <= '0;
                    else
                        wr_ptr_q <= wr_ptr_q + 1'b1;
                end
            end

            if (ll_valid) begin
                if (count_q == 0) begin
                    underflow_error <= 1'b1;
                end else begin
                    // Synchronous-read model: data becomes rd_q for use next cycle.
                    rd_q          <= mem[rd_ptr_q];
                    ll_hold_q     <= ll_sample;
                    ll_sof_hold_q <= ll_sof;
                    ll_eol_hold_q <= ll_eol;
                    ll_eof_hold_q <= ll_eof;
                    pop_pending_q <= 1'b1;

                    if (rd_ptr_q == DEPTH-1)
                        rd_ptr_q <= '0;
                    else
                        rd_ptr_q <= rd_ptr_q + 1'b1;
                end
            end

            case ({do_push,do_pop})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

endmodule

`default_nettype wire
