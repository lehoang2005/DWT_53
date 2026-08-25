`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_inv2d_stream #(
    parameter int WIDTH  = 8,
    parameter int HEIGHT = 8,
    parameter int LEVEL  = 1,
    parameter int DATA_W = 16,
    parameter int PIXEL_GAP = (LEVEL == 1) ? 1 : 4
);
    localparam int SUB_W = (LEVEL == 1) ? WIDTH/2  : WIDTH/4;
    localparam int SUB_H = (LEVEL == 1) ? HEIGHT/2 : HEIGHT/4;
    localparam int OUT_W = 2*SUB_W;
    localparam int OUT_H = 2*SUB_H;
    localparam int IN_COORDS = SUB_W*SUB_H;
    localparam int OUT_SAMPLES = OUT_W*OUT_H;
    localparam int PIXELS = WIDTH*HEIGHT;

    logic clk = 1'b0;
    logic rst_n;

    logic in_valid;
    logic signed [DATA_W-1:0] in_ll, in_hl, in_lh, in_hh;
    logic in_sof, in_eol, in_eof;

    logic out_valid;
    logic signed [DATA_W-1:0] out_sample;
    logic out_sof, out_eol, out_eof;
    logic overflow_error, buffer_error, protocol_error;

    logic [7:0] input_y8 [0:PIXELS-1];
    logic [7:0] recon_y8 [0:PIXELS-1];
    logic [DATA_W-1:0] c1 [0:PIXELS-1];
    logic [DATA_W-1:0] c2 [0:PIXELS-1];

    string vec_dir;
    string p_input, p_recon, p_c1, p_c2;
    integer errors;
    integer out_x, out_yc, out_count;
    integer cycles, max_cycles;

    always #5 clk = ~clk;

    dwt53_inv2d_stream #(
        .SUB_W(SUB_W), .SUB_H(SUB_H), .DATA_W(DATA_W), .PIXEL_GAP(PIXEL_GAP)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ll(in_ll), .in_hl(in_hl), .in_lh(in_lh), .in_hh(in_hh),
        .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .out_valid(out_valid), .out_sample(out_sample),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .overflow_error(overflow_error), .buffer_error(buffer_error), .protocol_error(protocol_error)
    );

    function automatic bit file_exists(input string p);
        integer fd;
        begin
            fd = $fopen(p, "r");
            if (fd != 0) begin $fclose(fd); file_exists = 1'b1; end
            else file_exists = 1'b0;
        end
    endfunction

    function automatic logic signed [DATA_W-1:0] coeff_at(
        input integer sy,
        input integer sx,
        input integer band
    );
        integer idx;
        begin
            // band: 0=LL,1=HL,2=LH,3=HH.
            if (LEVEL == 1) begin
                case (band)
                    0: idx = sy*WIDTH + sx;
                    1: idx = sy*WIDTH + (sx + SUB_W);
                    2: idx = (sy + SUB_H)*WIDTH + sx;
                    default: idx = (sy + SUB_H)*WIDTH + (sx + SUB_W);
                endcase
                coeff_at = $signed(c1[idx]);
            end else begin
                // Level-2 packed block lives inside C2's top-left LL1 quadrant.
                case (band)
                    0: idx = sy*WIDTH + sx;
                    1: idx = sy*WIDTH + (sx + SUB_W);
                    2: idx = (sy + SUB_H)*WIDTH + sx;
                    default: idx = (sy + SUB_H)*WIDTH + (sx + SUB_W);
                endcase
                coeff_at = $signed(c2[idx]);
            end
        end
    endfunction

    function automatic logic signed [DATA_W-1:0] expected_output(
        input integer oy,
        input integer ox
    );
        integer idx;
        begin
            if (LEVEL == 1) begin
                idx = oy*WIDTH + ox;
                expected_output = $signed({8'd0, recon_y8[idx]});
            end else begin
                // Reconstructed LL1 is the top-left quadrant of C1.
                idx = oy*WIDTH + ox;
                expected_output = $signed(c1[idx]);
            end
        end
    endfunction

    task automatic drive_idle;
        begin
            @(negedge clk);
            in_valid = 1'b0;
            in_ll = '0; in_hl = '0; in_lh = '0; in_hh = '0;
            in_sof = 1'b0; in_eol = 1'b0; in_eof = 1'b0;
        end
    endtask

    task automatic drive_coeff_frame;
        integer i, sx, sy;
        begin
            for (i = 0; i < IN_COORDS; i = i + 1) begin
                sx = i % SUB_W;
                sy = i / SUB_W;
                @(negedge clk);
                in_valid = 1'b1;
                in_ll = coeff_at(sy,sx,0);
                in_hl = coeff_at(sy,sx,1);
                in_lh = coeff_at(sy,sx,2);
                in_hh = coeff_at(sy,sx,3);
                in_sof = (i == 0);
                in_eol = (sx == SUB_W-1);
                in_eof = (i == IN_COORDS-1);
            end
            drive_idle();
        end
    endtask

    always @(negedge clk) begin
        logic signed [DATA_W-1:0] exp;
        if (rst_n && out_valid) begin
            if (out_count >= OUT_SAMPLES) begin
                $display("[ERROR] extra inv2d output sample %0d", $signed(out_sample));
                errors = errors + 1;
            end else begin
                exp = expected_output(out_yc,out_x);
                if (out_sample !== exp) begin
                    $display("[ERROR] inv L%0d out(%0d,%0d) exp=%0d got=%0d",
                             LEVEL, out_x, out_yc, exp, $signed(out_sample));
                    errors = errors + 1;
                end
                if (out_sof !== ((out_x == 0) && (out_yc == 0))) begin
                    $display("[ERROR] out_sof at (%0d,%0d)",out_x,out_yc);
                    errors = errors + 1;
                end
                if (out_eol !== (out_x == OUT_W-1)) begin
                    $display("[ERROR] out_eol at (%0d,%0d)",out_x,out_yc);
                    errors = errors + 1;
                end
                if (out_eof !== ((out_x == OUT_W-1) && (out_yc == OUT_H-1))) begin
                    $display("[ERROR] out_eof at (%0d,%0d)",out_x,out_yc);
                    errors = errors + 1;
                end
            end

            out_count = out_count + 1;
            if (out_x == OUT_W-1) begin
                out_x = 0;
                out_yc = out_yc + 1;
            end else begin
                out_x = out_x + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (cycles > max_cycles)
                $fatal(1, "[TIMEOUT] inv2d LEVEL=%0d", LEVEL);
        end
    end

    initial begin
        if ((WIDTH % 4) != 0 || (HEIGHT % 4) != 0)
            $fatal(1, "WIDTH/HEIGHT must be divisible by 4");
        if ((LEVEL != 1) && (LEVEL != 2))
            $fatal(1, "LEVEL must be 1 or 2");

        if (!$value$plusargs("VEC_DIR=%s", vec_dir))
            vec_dir = "vectors/random_0008x0008";

        p_input = {vec_dir, "/input_y8_hex.txt"};
        p_recon = {vec_dir, "/recon_y8_hex.txt"};
        p_c1    = {vec_dir, "/c1_packed_hex.txt"};
        p_c2    = {vec_dir, "/c2_packed_hex.txt"};
        if (!file_exists(p_input) || !file_exists(p_recon) ||
            !file_exists(p_c1) || !file_exists(p_c2))
            $fatal(1, "Missing golden files under %s", vec_dir);

        $readmemh(p_input, input_y8);
        $readmemh(p_recon, recon_y8);
        $readmemh(p_c1, c1);
        $readmemh(p_c2, c2);

        errors = 0; out_x = 0; out_yc = 0; out_count = 0;
        cycles = 0; max_cycles = OUT_SAMPLES*(PIXEL_GAP+12) + IN_COORDS*8 + 5000;

        rst_n = 1'b0;
        in_valid = 1'b0;
        in_ll='0; in_hl='0; in_lh='0; in_hh='0;
        in_sof=0; in_eol=0; in_eof=0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        drive_coeff_frame();
        wait (out_count == OUT_SAMPLES);
        repeat (6) @(posedge clk);

        if (overflow_error) begin $display("[ERROR] overflow_error"); errors=errors+1; end
        if (buffer_error) begin $display("[ERROR] buffer_error"); errors=errors+1; end
        if (protocol_error) begin $display("[ERROR] protocol_error"); errors=errors+1; end

        if (errors == 0)
            $display("[PASS] tb_dwt53_inv2d_stream LEVEL=%0d SUB=%0dx%0d PIXEL_GAP=%0d",
                     LEVEL, SUB_W, SUB_H, PIXEL_GAP);
        else
            $fatal(1, "[FAIL] tb_dwt53_inv2d_stream errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
