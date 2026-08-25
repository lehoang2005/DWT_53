`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_fwd2d_stream #(
    parameter int WIDTH  = 8,
    parameter int HEIGHT = 8,
    parameter int LEVEL  = 1,
    parameter int DATA_W = 16
);
    localparam int IMG_W = (LEVEL == 1) ? WIDTH  : WIDTH/2;
    localparam int IMG_H = (LEVEL == 1) ? HEIGHT : HEIGHT/2;
    localparam int SUB_W = IMG_W/2;
    localparam int SUB_H = IMG_H/2;
    localparam int PIXELS = WIDTH*HEIGHT;
    localparam int IN_SAMPLES = IMG_W*IMG_H;
    localparam int OUT_COORDS = SUB_W*SUB_H;

    logic clk = 1'b0;
    logic rst_n;
    logic in_valid;
    logic signed [DATA_W-1:0] in_sample;
    logic in_sof, in_eol, in_eof;

    logic out_valid;
    logic signed [DATA_W-1:0] out_ll, out_hl, out_lh, out_hh;
    logic out_sof, out_eol, out_eof;
    logic overflow_error, protocol_error;

    logic [7:0] input_y8 [0:PIXELS-1];
    logic [DATA_W-1:0] c1 [0:PIXELS-1];
    logic [DATA_W-1:0] c2 [0:PIXELS-1];

    string vec_dir;
    string p_input, p_c1, p_c2;
    integer errors;
    integer out_x, out_yc, out_count;
    integer gap_every;
    integer cycles, max_cycles;

    always #5 clk = ~clk;

    dwt53_fwd2d_stream #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .DATA_W(DATA_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_sample(in_sample),
        .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .out_valid(out_valid), .out_ll(out_ll), .out_hl(out_hl),
        .out_lh(out_lh), .out_hh(out_hh),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .overflow_error(overflow_error), .protocol_error(protocol_error)
    );

    function automatic bit file_exists(input string p);
        integer fd;
        begin
            fd = $fopen(p, "r");
            if (fd != 0) begin $fclose(fd); file_exists = 1'b1; end
            else file_exists = 1'b0;
        end
    endfunction

    function automatic logic signed [DATA_W-1:0] source_sample(input integer idx);
        integer x, y;
        begin
            if (LEVEL == 1) begin
                source_sample = $signed({8'd0, input_y8[idx]});
            end else begin
                x = idx % IMG_W;
                y = idx / IMG_W;
                source_sample = $signed(c1[y*WIDTH + x]);
            end
        end
    endfunction

    task automatic drive_idle;
        begin
            @(negedge clk);
            in_valid  = 1'b0;
            in_sample = '0;
            in_sof    = 1'b0;
            in_eol    = 1'b0;
            in_eof    = 1'b0;
        end
    endtask

    task automatic drive_frame;
        integer i, x, y;
        begin
            for (i = 0; i < IN_SAMPLES; i = i + 1) begin
                if ((gap_every > 0) && (i > 0) && ((i % gap_every) == 0))
                    drive_idle();
                x = i % IMG_W;
                y = i / IMG_W;
                @(negedge clk);
                in_valid  = 1'b1;
                in_sample = source_sample(i);
                in_sof    = (i == 0);
                in_eol    = (x == IMG_W-1);
                in_eof    = (i == IN_SAMPLES-1);
            end
            drive_idle();
        end
    endtask

    task automatic compare_one(
        input string name,
        input logic signed [DATA_W-1:0] got,
        input integer full_idx
    );
        logic signed [DATA_W-1:0] exp;
        begin
            exp = (LEVEL == 1) ? $signed(c1[full_idx]) : $signed(c2[full_idx]);
            if (got !== exp) begin
                $display("[ERROR] L%0d %s coord=(%0d,%0d) full_idx=%0d exp=%0d got=%0d",
                         LEVEL, name, out_x, out_yc, full_idx, exp, got);
                errors = errors + 1;
            end
        end
    endtask

    always @(negedge clk) begin
        integer idx_ll, idx_hl, idx_lh, idx_hh;
        if (rst_n && out_valid) begin
            if (out_count >= OUT_COORDS) begin
                $display("[ERROR] extra fwd2d output coordinate");
                errors = errors + 1;
            end else begin
                if (LEVEL == 1) begin
                    idx_ll = out_yc*WIDTH + out_x;
                    idx_hl = out_yc*WIDTH + (out_x + SUB_W);
                    idx_lh = (out_yc + SUB_H)*WIDTH + out_x;
                    idx_hh = (out_yc + SUB_H)*WIDTH + (out_x + SUB_W);
                end else begin
                    // Level-2 packed block occupies the top-left LL1 quadrant,
                    // but the golden C2 file still has full-frame row stride WIDTH.
                    idx_ll = out_yc*WIDTH + out_x;
                    idx_hl = out_yc*WIDTH + (out_x + SUB_W);
                    idx_lh = (out_yc + SUB_H)*WIDTH + out_x;
                    idx_hh = (out_yc + SUB_H)*WIDTH + (out_x + SUB_W);
                end

                compare_one("LL", out_ll, idx_ll);
                compare_one("HL", out_hl, idx_hl);
                compare_one("LH", out_lh, idx_lh);
                compare_one("HH", out_hh, idx_hh);

                if (out_sof !== ((out_x == 0) && (out_yc == 0))) begin
                    $display("[ERROR] out_sof at coord=(%0d,%0d)", out_x, out_yc);
                    errors = errors + 1;
                end
                if (out_eol !== (out_x == SUB_W-1)) begin
                    $display("[ERROR] out_eol at coord=(%0d,%0d)", out_x, out_yc);
                    errors = errors + 1;
                end
                if (out_eof !== ((out_x == SUB_W-1) && (out_yc == SUB_H-1))) begin
                    $display("[ERROR] out_eof at coord=(%0d,%0d)", out_x, out_yc);
                    errors = errors + 1;
                end
            end

            out_count = out_count + 1;
            if (out_x == SUB_W-1) begin
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
                $fatal(1, "[TIMEOUT] fwd2d LEVEL=%0d", LEVEL);
        end
    end

    initial begin
        if ((WIDTH % 4) != 0 || (HEIGHT % 4) != 0)
            $fatal(1, "WIDTH/HEIGHT must be divisible by 4");
        if ((LEVEL != 1) && (LEVEL != 2))
            $fatal(1, "LEVEL must be 1 or 2");

        if (!$value$plusargs("VEC_DIR=%s", vec_dir))
            vec_dir = "vectors/random_0008x0008";
        if (!$value$plusargs("GAP_EVERY=%d", gap_every))
            gap_every = 0;

        p_input = {vec_dir, "/input_y8_hex.txt"};
        p_c1    = {vec_dir, "/c1_packed_hex.txt"};
        p_c2    = {vec_dir, "/c2_packed_hex.txt"};
        if (!file_exists(p_input) || !file_exists(p_c1) || !file_exists(p_c2))
            $fatal(1, "Missing golden files under %s", vec_dir);

        $readmemh(p_input, input_y8);
        $readmemh(p_c1, c1);
        $readmemh(p_c2, c2);

        errors = 0; out_x = 0; out_yc = 0; out_count = 0;
        cycles = 0; max_cycles = IN_SAMPLES*20 + 1000;
        rst_n = 1'b0;
        in_valid = 1'b0; in_sample = '0; in_sof = 0; in_eol = 0; in_eof = 0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        drive_frame();
        wait (out_count == OUT_COORDS);
        repeat (4) @(posedge clk);

        if (overflow_error) begin $display("[ERROR] overflow_error"); errors = errors + 1; end
        if (protocol_error) begin $display("[ERROR] protocol_error"); errors = errors + 1; end
        if (out_count != OUT_COORDS) begin
            $display("[ERROR] out_count exp=%0d got=%0d", OUT_COORDS, out_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("[PASS] tb_dwt53_fwd2d_stream LEVEL=%0d IMG=%0dx%0d gap_every=%0d",
                     LEVEL, IMG_W, IMG_H, gap_every);
        else
            $fatal(1, "[FAIL] tb_dwt53_fwd2d_stream errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
