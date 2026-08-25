`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// dwt53_fwd1d_pair_stream
// Clean-room streaming Forward 1D reversible Le Gall 5/3 lifting core.
//
// Source of truth:
//   d[n] = o[n] - floor((e[n] + e[n+1]) / 2)
//   s[n] = e[n] + floor((d[n-1] + d[n] + 2) / 4)
//   e[M] = e[M-1], d[-1] = d[0]
//   L[n] = s[n], H[n] = d[n]
//
// Input vector must have even length. One sample may be accepted every clock.
// Output is one parallel {L,H} pair per two accepted input samples after startup.
// Arithmetic right shift implements floor division by powers of two for signed
// two's-complement values.
// -----------------------------------------------------------------------------
module dwt53_fwd1d_pair_stream #(
    parameter int DATA_W = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    input  wire  signed [DATA_W-1:0]     in_sample,
    input  wire                          in_sov,     // first sample of vector
    input  wire                          in_eov,     // last sample of vector

    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     out_l,
    output logic signed [DATA_W-1:0]     out_h,
    output logic                         out_sov,    // first output pair
    output logic                         out_eov,    // last output pair

    output logic                         overflow_error,
    output logic                         protocol_error
);

    localparam int EXT_W = DATA_W + 3;

    logic signed [DATA_W-1:0] e_prev_q;
    logic signed [DATA_W-1:0] o_prev_q;
    logic signed [DATA_W-1:0] d_prev_q;

    logic expect_odd_q;
    logic have_d_prev_q;
    logic first_pair_q;
    logic vector_active_q;

    logic signed [EXT_W-1:0] in_ext;
    logic signed [EXT_W-1:0] e_ext;
    logic signed [EXT_W-1:0] o_ext;
    logic signed [EXT_W-1:0] dprev_ext;

    logic signed [EXT_W-1:0] d_even_calc;
    logic signed [EXT_W-1:0] s_even_calc;
    logic signed [EXT_W-1:0] d_last_calc;
    logic signed [EXT_W-1:0] s_last_calc;
    logic signed [EXT_W-1:0] prev_d_for_even;
    logic signed [EXT_W-1:0] prev_d_for_last;

    assign in_ext    = {{(EXT_W-DATA_W){in_sample[DATA_W-1]}}, in_sample};
    assign e_ext     = {{(EXT_W-DATA_W){e_prev_q[DATA_W-1]}}, e_prev_q};
    assign o_ext     = {{(EXT_W-DATA_W){o_prev_q[DATA_W-1]}}, o_prev_q};
    assign dprev_ext = {{(EXT_W-DATA_W){d_prev_q[DATA_W-1]}}, d_prev_q};

    // Normal case: current accepted sample is e[n+1].
    assign d_even_calc =
        o_ext - ((e_ext + in_ext) >>> 1);

    assign prev_d_for_even =
        have_d_prev_q ? dprev_ext : d_even_calc; // d[-1] = d[0] at first pair

    assign s_even_calc =
        e_ext + ((prev_d_for_even + d_even_calc + 2) >>> 2);

    // End boundary: e[M] = e[M-1], hence floor((e+e)/2) = e.
    assign d_last_calc =
        in_ext - e_ext; // here in_sample is the final odd sample o[M-1]

    assign prev_d_for_last =
        have_d_prev_q ? dprev_ext : d_last_calc;

    assign s_last_calc =
        e_ext + ((prev_d_for_last + d_last_calc + 2) >>> 2);

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e_prev_q       <= '0;
            o_prev_q       <= '0;
            d_prev_q       <= '0;
            expect_odd_q   <= 1'b0;
            have_d_prev_q  <= 1'b0;
            first_pair_q   <= 1'b0;
            vector_active_q<= 1'b0;

            out_valid      <= 1'b0;
            out_l          <= '0;
            out_h          <= '0;
            out_sov        <= 1'b0;
            out_eov        <= 1'b0;

            overflow_error <= 1'b0;
            protocol_error <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            out_sov   <= 1'b0;
            out_eov   <= 1'b0;

            if (in_valid) begin
                if (in_sov) begin
                    if (vector_active_q)
                        protocol_error <= 1'b1;
                    if (in_eov)
                        protocol_error <= 1'b1; // project vectors are even and >= 2

                    // x[0] = e[0]
                    e_prev_q        <= in_sample;
                    expect_odd_q    <= 1'b1;
                    have_d_prev_q   <= 1'b0;
                    first_pair_q    <= 1'b1;
                    vector_active_q <= 1'b1;
                end else if (!vector_active_q) begin
                    protocol_error <= 1'b1;
                end else if (expect_odd_q) begin
                    // Current sample is o[n].
                    if (in_eov) begin
                        // Final odd sample. Apply right boundary immediately.
                        out_valid <= 1'b1;
                        out_l     <= s_last_calc[DATA_W-1:0];
                        out_h     <= d_last_calc[DATA_W-1:0];
                        out_sov   <= first_pair_q;
                        out_eov   <= 1'b1;

                        if (!fits_data_w(s_last_calc) || !fits_data_w(d_last_calc))
                            overflow_error <= 1'b1;

                        first_pair_q     <= 1'b0;
                        vector_active_q  <= 1'b0;
                        expect_odd_q     <= 1'b0;
                        have_d_prev_q    <= 1'b0;
                    end else begin
                        o_prev_q     <= in_sample;
                        expect_odd_q <= 1'b0;
                    end
                end else begin
                    // Current sample is e[n+1], so d[n] and s[n] are now known.
                    if (in_eov)
                        protocol_error <= 1'b1; // even-length vector must end on odd sample

                    out_valid <= 1'b1;
                    out_l     <= s_even_calc[DATA_W-1:0];
                    out_h     <= d_even_calc[DATA_W-1:0];
                    out_sov   <= first_pair_q;
                    out_eov   <= 1'b0;

                    if (!fits_data_w(s_even_calc) || !fits_data_w(d_even_calc))
                        overflow_error <= 1'b1;

                    d_prev_q       <= d_even_calc[DATA_W-1:0];
                    e_prev_q       <= in_sample;
                    have_d_prev_q  <= 1'b1;
                    first_pair_q   <= 1'b0;
                    expect_odd_q   <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
