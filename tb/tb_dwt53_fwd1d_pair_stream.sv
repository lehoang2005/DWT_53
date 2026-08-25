`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_fwd1d_pair_stream #(
    parameter int N      = 8,
    parameter int DATA_W = 16
);
    localparam int M = N/2;

    logic clk = 1'b0;
    logic rst_n;

    logic in_valid;
    logic signed [DATA_W-1:0] in_sample;
    logic in_sov, in_eov;

    logic out_valid;
    logic signed [DATA_W-1:0] out_l, out_h;
    logic out_sov, out_eov;
    logic overflow_error, protocol_error;

    logic [DATA_W-1:0] input_mem [0:N-1];
    logic [DATA_W-1:0] golden_l [0:M-1];
    logic [DATA_W-1:0] golden_h [0:M-1];

    string vec_dir;
    string input_path, l_path, h_path;
    integer errors;
    integer out_idx;
    integer gap_every;
    integer cycles;
    integer max_cycles;

    always #5 clk = ~clk;

    dwt53_fwd1d_pair_stream #(
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_sample(in_sample),
        .in_sov(in_sov), .in_eov(in_eov),
        .out_valid(out_valid), .out_l(out_l), .out_h(out_h),
        .out_sov(out_sov), .out_eov(out_eov),
        .overflow_error(overflow_error), .protocol_error(protocol_error)
    );

    function automatic bit file_exists(input string p);
        integer fd;
        begin
            fd = $fopen(p, "r");
            if (fd != 0) begin
                $fclose(fd);
                file_exists = 1'b1;
            end else begin
                file_exists = 1'b0;
            end
        end
    endfunction

    task automatic idle_cycle;
        begin
            @(negedge clk);
            in_valid  = 1'b0;
            in_sample = '0;
            in_sov    = 1'b0;
            in_eov    = 1'b0;
        end
    endtask

    task automatic drive_vector;
        integer i;
        begin
            for (i = 0; i < N; i = i + 1) begin
                if ((gap_every > 0) && (i > 0) && ((i % gap_every) == 0))
                    idle_cycle();

                @(negedge clk);
                in_valid  = 1'b1;
                in_sample = $signed(input_mem[i]);
                in_sov    = (i == 0);
                in_eov    = (i == N-1);
            end
            idle_cycle();
        end
    endtask

    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (out_idx >= M) begin
                $display("[ERROR] extra output pair L=%0d H=%0d", $signed(out_l), $signed(out_h));
                errors = errors + 1;
            end else begin
                if (out_l !== $signed(golden_l[out_idx])) begin
                    $display("[ERROR] L[%0d] exp=%0d got=%0d", out_idx,
                             $signed(golden_l[out_idx]), $signed(out_l));
                    errors = errors + 1;
                end
                if (out_h !== $signed(golden_h[out_idx])) begin
                    $display("[ERROR] H[%0d] exp=%0d got=%0d", out_idx,
                             $signed(golden_h[out_idx]), $signed(out_h));
                    errors = errors + 1;
                end
                if (out_sov !== (out_idx == 0)) begin
                    $display("[ERROR] out_sov mismatch at pair %0d", out_idx);
                    errors = errors + 1;
                end
                if (out_eov !== (out_idx == M-1)) begin
                    $display("[ERROR] out_eov mismatch at pair %0d", out_idx);
                    errors = errors + 1;
                end
            end
            out_idx = out_idx + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (cycles > max_cycles)
                $fatal(1, "[TIMEOUT] fwd1d did not finish");
        end
    end

    initial begin
        if ((N < 2) || ((N % 2) != 0))
            $fatal(1, "N must be even and >=2");

        if (!$value$plusargs("VEC_DIR=%s", vec_dir))
            vec_dir = "vectors/1d";
        if (!$value$plusargs("GAP_EVERY=%d", gap_every))
            gap_every = 0;

        input_path = {vec_dir, "/input_hex.txt"};
        l_path     = {vec_dir, "/L_hex.txt"};
        h_path     = {vec_dir, "/H_hex.txt"};

        if (!file_exists(input_path) || !file_exists(l_path) || !file_exists(h_path))
            $fatal(1, "Missing 1D golden files under %s", vec_dir);

        $readmemh(input_path, input_mem);
        $readmemh(l_path, golden_l);
        $readmemh(h_path, golden_h);

        errors     = 0;
        out_idx    = 0;
        cycles     = 0;
        max_cycles = N*20 + 100;

        rst_n     = 1'b0;
        in_valid  = 1'b0;
        in_sample = '0;
        in_sov    = 1'b0;
        in_eov    = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        drive_vector();
        wait (out_idx == M);
        repeat (4) @(posedge clk);

        if (overflow_error) begin
            $display("[ERROR] overflow_error asserted");
            errors = errors + 1;
        end
        if (protocol_error) begin
            $display("[ERROR] protocol_error asserted");
            errors = errors + 1;
        end
        if (out_idx != M) begin
            $display("[ERROR] output pair count exp=%0d got=%0d", M, out_idx);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("[PASS] tb_dwt53_fwd1d_pair_stream N=%0d gap_every=%0d", N, gap_every);
        else
            $fatal(1, "[FAIL] tb_dwt53_fwd1d_pair_stream errors=%0d", errors);

        $finish;
    end
endmodule

`default_nettype wire
