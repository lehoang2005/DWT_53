`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_fwd2d_stream
// One-level streaming Forward 2D reversible Le Gall 5/3 transform.
//
// Architecture:
//   row-major samples -> horizontal 1D lifting -> circulating vertical state
//   -> parallel {LL, HL, LH, HH} samples.
//
// No complete frame is stored. Vertical state is bounded by SUB_W = IMG_W/2.
// The state arrays hold:
//   - previous even row of horizontal L/H coefficients,
//   - previous odd row,
//   - previous vertical detail d[n-1].
// This is a circulating fixed-depth line-state window reused for every row/frame.
//
// Output lane order is fixed:
//   out_ll = horizontal low,  vertical low
//   out_hl = horizontal high, vertical low
//   out_lh = horizontal low,  vertical high
//   out_hh = horizontal high, vertical high
// -----------------------------------------------------------------------------
module dwt53_fwd2d_stream #(
    parameter int IMG_W  = 1280,
    parameter int IMG_H  = 720,
    parameter int DATA_W = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    input  wire  signed [DATA_W-1:0]     in_sample,
    input  wire                          in_sof,
    input  wire                          in_eol,
    input  wire                          in_eof,

    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     out_ll,
    output logic signed [DATA_W-1:0]     out_hl,
    output logic signed [DATA_W-1:0]     out_lh,
    output logic signed [DATA_W-1:0]     out_hh,
    output logic                         out_sof,
    output logic                         out_eol,
    output logic                         out_eof,

    output logic                         overflow_error,
    output logic                         protocol_error
);

    localparam int SUB_W = IMG_W / 2;
    localparam int SUB_H = IMG_H / 2;
    localparam int X_W   = (SUB_W <= 2) ? 1 : $clog2(SUB_W);
    localparam int Y_W   = (IMG_H <= 2) ? 1 : $clog2(IMG_H);
    localparam int EXT_W = DATA_W + 4;

    initial begin
        if ((IMG_W % 2) != 0 || (IMG_H % 2) != 0)
            $error("dwt53_fwd2d_stream: IMG_W and IMG_H must be even");
        if (IMG_W < 4 || IMG_H < 4)
            $error("dwt53_fwd2d_stream: project streaming implementation expects >= 4x4");
    end

    // -------------------------------------------------------------------------
    // Row start derivation. SOF is explicit; later row starts follow accepted EOL.
    // -------------------------------------------------------------------------
    logic row_start_pending_q;
    logic row_sov;

    assign row_sov = in_sof | row_start_pending_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_start_pending_q <= 1'b0;
        end else if (in_valid) begin
            if (in_eol)
                row_start_pending_q <= 1'b1;
            else
                row_start_pending_q <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Horizontal streaming 1D transform.
    // -------------------------------------------------------------------------
    logic                     h_valid;
    logic signed [DATA_W-1:0] h_l;
    logic signed [DATA_W-1:0] h_h;
    logic                     h_sov;
    logic                     h_eov;
    logic                     h_overflow;
    logic                     h_protocol;

    dwt53_fwd1d_pair_stream #(
        .DATA_W(DATA_W)
    ) u_row_fwd (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_valid       (in_valid),
        .in_sample      (in_sample),
        .in_sov         (row_sov),
        .in_eov         (in_eol),
        .out_valid      (h_valid),
        .out_l          (h_l),
        .out_h          (h_h),
        .out_sov        (h_sov),
        .out_eov        (h_eov),
        .overflow_error (h_overflow),
        .protocol_error (h_protocol)
    );

    // Coordinate of the horizontal pair stream.
    logic [X_W-1:0] h_col_q;
    logic [Y_W-1:0] h_row_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_col_q <= '0;
            h_row_q <= '0;
        end else if (h_valid) begin
            if (h_eov) begin
                h_col_q <= '0;
                if (h_row_q == IMG_H-1)
                    h_row_q <= '0;
                else
                    h_row_q <= h_row_q + 1'b1;
            end else begin
                h_col_q <= h_col_q + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bounded vertical state.
    // Packed as separate memories for clarity. The logical storage is 3 rows
    // per horizontal branch (L-row and H-row), each SUB_W samples wide.
    // -------------------------------------------------------------------------
    // Xilinx-portability copy: force the six line-state arrays into UltraScale
    // block RAM. The frozen Quartus B0 source retains its M10K attributes.
    (* ram_style = "block" *) logic signed [DATA_W-1:0] even_l_mem [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] odd_l_mem  [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] dprev_l_mem[0:SUB_W-1];

    (* ram_style = "block" *) logic signed [DATA_W-1:0] even_h_mem [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] odd_h_mem  [0:SUB_W-1];
    (* ram_style = "block" *) logic signed [DATA_W-1:0] dprev_h_mem[0:SUB_W-1];

    // Single outstanding synchronous read pipeline.
    logic signed [DATA_W-1:0] even_l_q, odd_l_q, dprev_l_q;
    logic signed [DATA_W-1:0] even_h_q, odd_h_q, dprev_h_q;

    logic                     s0_valid_q;
    logic signed [DATA_W-1:0] s0_l_q, s0_h_q;
    logic [X_W-1:0]           s0_col_q;
    logic [Y_W-1:0]           s0_row_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_valid_q<= 1'b0;
            s0_l_q    <= '0;
            s0_h_q    <= '0;
            s0_col_q  <= '0;
            s0_row_q  <= '0;
        end else begin
            s0_valid_q <= h_valid;
            if (h_valid) begin
                s0_l_q   <= h_l;
                s0_h_q   <= h_h;
                s0_col_q <= h_col_q;
                s0_row_q <= h_row_q;
            end
        end
    end

    // Arithmetic for the vertical lifting step.
    logic signed [EXT_W-1:0] cur_l_ext, cur_h_ext;
    logic signed [EXT_W-1:0] even_l_ext, odd_l_ext, dprev_l_ext;
    logic signed [EXT_W-1:0] even_h_ext, odd_h_ext, dprev_h_ext;

    logic signed [EXT_W-1:0] d_l_mid, s_l_mid;
    logic signed [EXT_W-1:0] d_h_mid, s_h_mid;
    logic signed [EXT_W-1:0] d_l_bottom, s_l_bottom;
    logic signed [EXT_W-1:0] d_h_bottom, s_h_bottom;

    assign cur_l_ext   = {{(EXT_W-DATA_W){s0_l_q[DATA_W-1]}}, s0_l_q};
    assign cur_h_ext   = {{(EXT_W-DATA_W){s0_h_q[DATA_W-1]}}, s0_h_q};
    assign even_l_ext  = {{(EXT_W-DATA_W){even_l_q[DATA_W-1]}}, even_l_q};
    assign odd_l_ext   = {{(EXT_W-DATA_W){odd_l_q[DATA_W-1]}}, odd_l_q};
    assign dprev_l_ext = {{(EXT_W-DATA_W){dprev_l_q[DATA_W-1]}}, dprev_l_q};

    assign even_h_ext  = {{(EXT_W-DATA_W){even_h_q[DATA_W-1]}}, even_h_q};
    assign odd_h_ext   = {{(EXT_W-DATA_W){odd_h_q[DATA_W-1]}}, odd_h_q};
    assign dprev_h_ext = {{(EXT_W-DATA_W){dprev_h_q[DATA_W-1]}}, dprev_h_q};

    assign d_l_mid = odd_l_ext - ((even_l_ext + cur_l_ext) >>> 1);
    assign d_h_mid = odd_h_ext - ((even_h_ext + cur_h_ext) >>> 1);

    // First vertical output row is generated at source row 2; d[-1] = d[0].
    assign s_l_mid = even_l_ext +
        ((((s0_row_q == 2) ? d_l_mid : dprev_l_ext) + d_l_mid + 2) >>> 2);
    assign s_h_mid = even_h_ext +
        ((((s0_row_q == 2) ? d_h_mid : dprev_h_ext) + d_h_mid + 2) >>> 2);

    // Bottom boundary e[M] = e[M-1].
    assign d_l_bottom = cur_l_ext - even_l_ext;
    assign d_h_bottom = cur_h_ext - even_h_ext;
    assign s_l_bottom = even_l_ext + ((dprev_l_ext + d_l_bottom + 2) >>> 2);
    assign s_h_bottom = even_h_ext + ((dprev_h_ext + d_h_bottom + 2) >>> 2);

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

    // -------------------------------------------------------------------------
    // Xilinx-compatible line-state RAM ports.
    //
    // All RAM reads/writes and their read-data registers live in this
    // clock-only process. Reset clears only the control/valid state elsewhere;
    // RAM contents and read data need no reset because s0_valid_q masks them.
    // This preserves the original one-cycle synchronous-read pipeline.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (h_valid) begin
                even_l_q  <= even_l_mem[h_col_q];
                odd_l_q   <= odd_l_mem[h_col_q];
                dprev_l_q <= dprev_l_mem[h_col_q];

                even_h_q  <= even_h_mem[h_col_q];
                odd_h_q   <= odd_h_mem[h_col_q];
                dprev_h_q <= dprev_h_mem[h_col_q];
            end

            if (s0_valid_q) begin
                if (s0_row_q == 0) begin
                    even_l_mem[s0_col_q] <= s0_l_q;
                    even_h_mem[s0_col_q] <= s0_h_q;
                end else if (s0_row_q[0] && (s0_row_q != IMG_H-1)) begin
                    odd_l_mem[s0_col_q] <= s0_l_q;
                    odd_h_mem[s0_col_q] <= s0_h_q;
                end else if (!s0_row_q[0]) begin
                    even_l_mem[s0_col_q]  <= s0_l_q;
                    even_h_mem[s0_col_q]  <= s0_h_q;
                    dprev_l_mem[s0_col_q] <= d_l_mid[DATA_W-1:0];
                    dprev_h_mem[s0_col_q] <= d_h_mid[DATA_W-1:0];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Vertical state update and four-lane subband emission.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid      <= 1'b0;
            out_ll         <= '0;
            out_hl         <= '0;
            out_lh         <= '0;
            out_hh         <= '0;
            out_sof        <= 1'b0;
            out_eol        <= 1'b0;
            out_eof        <= 1'b0;
            overflow_error <= 1'b0;
            protocol_error <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
            out_eof   <= 1'b0;

            if (h_overflow)
                overflow_error <= 1'b1;
            if (h_protocol)
                protocol_error <= 1'b1;

            // The horizontal 5/3 core may legally emit back-to-back pairs at
            // the right boundary of an even-length row: one pair when the final
            // even sample arrives and the boundary pair on the final odd sample.
            // This vertical pipeline is fully pipelined (one read request can be
            // accepted every clock), so adjacent h_valid cycles are legal.

            if (s0_valid_q) begin
                if (s0_row_q == 0) begin
                    // First even row e[0].
                end else if (s0_row_q[0] && (s0_row_q != IMG_H-1)) begin
                    // Interior odd row o[n].
                end else if (!s0_row_q[0]) begin
                    // Interior even row e[n+1]: d[n] and s[n] are now known.
                    out_valid <= 1'b1;
                    out_ll    <= s_l_mid[DATA_W-1:0];
                    out_lh    <= d_l_mid[DATA_W-1:0];
                    out_hl    <= s_h_mid[DATA_W-1:0];
                    out_hh    <= d_h_mid[DATA_W-1:0];

                    out_sof   <= (s0_row_q == 2) && (s0_col_q == 0);
                    out_eol   <= (s0_col_q == SUB_W-1);
                    out_eof   <= 1'b0;

                    if (!fits_data_w(s_l_mid) || !fits_data_w(d_l_mid) ||
                        !fits_data_w(s_h_mid) || !fits_data_w(d_h_mid))
                        overflow_error <= 1'b1;

                end else begin
                    // Final odd row: use right/bottom boundary without waiting
                    // for a nonexistent next even row.
                    out_valid <= 1'b1;
                    out_ll    <= s_l_bottom[DATA_W-1:0];
                    out_lh    <= d_l_bottom[DATA_W-1:0];
                    out_hl    <= s_h_bottom[DATA_W-1:0];
                    out_hh    <= d_h_bottom[DATA_W-1:0];

                    out_sof   <= 1'b0;
                    out_eol   <= (s0_col_q == SUB_W-1);
                    out_eof   <= (s0_col_q == SUB_W-1);

                    if (!fits_data_w(s_l_bottom) || !fits_data_w(d_l_bottom) ||
                        !fits_data_w(s_h_bottom) || !fits_data_w(d_h_bottom))
                        overflow_error <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
