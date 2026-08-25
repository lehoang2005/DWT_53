`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_checkpoint8 #(
    parameter int SAMPLE_W = 16,
    parameter bit A_SIGN_EXTEND = 1'b0
);
    logic clk = 1'b0;
    logic rst_n;
    logic frame_start, frame_end;
    logic [7:0] lane_mask;
    logic [8*SAMPLE_W-1:0] samples_flat;
    logic snapshot_valid;
    logic [31:0] sig_count;
    logic [SAMPLE_W-1:0] sig_xor;
    logic [31:0] sig_a, sig_b;

    logic [31:0] exp_count, exp_a, exp_b;
    logic [SAMPLE_W-1:0] exp_xor;
    integer errors;

    always #5 clk = ~clk;

    dwt53_checkpoint8 #(
        .SAMPLE_W(SAMPLE_W), .A_SIGN_EXTEND(A_SIGN_EXTEND)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .frame_start(frame_start), .frame_end(frame_end),
        .lane_mask(lane_mask), .samples_flat(samples_flat),
        .snapshot_valid(snapshot_valid), .sig_count(sig_count), .sig_xor(sig_xor),
        .sig_a(sig_a), .sig_b(sig_b)
    );

    function automatic logic [31:0] contrib(input logic signed [SAMPLE_W-1:0] v);
        begin
            if (A_SIGN_EXTEND)
                contrib = {{(32-SAMPLE_W){v[SAMPLE_W-1]}},v};
            else
                contrib = {{(32-SAMPLE_W){1'b0}},v};
        end
    endfunction

    task automatic shadow_clear;
        begin
            exp_count = 32'd0;
            exp_xor   = '0;
            exp_a     = 32'd0;
            exp_b     = 32'd0;
        end
    endtask

    task automatic shadow_add(input logic signed [SAMPLE_W-1:0] v);
        logic [31:0] a_new;
        begin
            a_new    = exp_a + contrib(v);
            exp_count = exp_count + 1'b1;
            exp_xor   = exp_xor ^ v;
            exp_a     = a_new;
            exp_b     = exp_b + a_new;
        end
    endtask

    task automatic shadow_cycle(
        input logic fs,
        input logic [7:0] mask,
        input logic [8*SAMPLE_W-1:0] flat
    );
        integer i;
        logic signed [SAMPLE_W-1:0] v;
        begin
            if (fs)
                shadow_clear();
            for (i=0; i<8; i=i+1) begin
                if (mask[i]) begin
                    v = $signed(flat[i*SAMPLE_W +: SAMPLE_W]);
                    shadow_add(v);
                end
            end
        end
    endtask

    task automatic drive_cycle(
        input logic fs,
        input logic fe,
        input logic [7:0] mask,
        input logic [8*SAMPLE_W-1:0] flat
    );
        begin
            @(negedge clk);
            frame_start  = fs;
            frame_end    = fe;
            lane_mask    = mask;
            samples_flat = flat;
            shadow_cycle(fs,mask,flat);
            @(negedge clk);
            frame_start  = 1'b0;
            frame_end    = 1'b0;
            lane_mask    = 8'd0;
            samples_flat = '0;
        end
    endtask

    function automatic logic [8*SAMPLE_W-1:0] pack8(
        input logic signed [SAMPLE_W-1:0] v0,
        input logic signed [SAMPLE_W-1:0] v1,
        input logic signed [SAMPLE_W-1:0] v2,
        input logic signed [SAMPLE_W-1:0] v3,
        input logic signed [SAMPLE_W-1:0] v4,
        input logic signed [SAMPLE_W-1:0] v5,
        input logic signed [SAMPLE_W-1:0] v6,
        input logic signed [SAMPLE_W-1:0] v7
    );
        begin
            pack8 = {v7,v6,v5,v4,v3,v2,v1,v0};
        end
    endfunction

    task automatic check_snapshot(input string tag);
        begin
            if (!snapshot_valid) begin
                $display("[ERROR] %s snapshot_valid not asserted", tag);
                errors = errors + 1;
            end
            if (sig_count !== exp_count) begin
                $display("[ERROR] %s count exp=%08x got=%08x",tag,exp_count,sig_count);
                errors = errors + 1;
            end
            if (sig_xor !== exp_xor) begin
                $display("[ERROR] %s xor exp=%0h got=%0h",tag,exp_xor,sig_xor);
                errors = errors + 1;
            end
            if (sig_a !== exp_a) begin
                $display("[ERROR] %s A exp=%08x got=%08x",tag,exp_a,sig_a);
                errors = errors + 1;
            end
            if (sig_b !== exp_b) begin
                $display("[ERROR] %s B exp=%08x got=%08x",tag,exp_b,sig_b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        frame_start=0; frame_end=0; lane_mask=0; samples_flat='0;
        shadow_clear();
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Frame 1: sparse masks, negative values, and a multi-lane frame-end cycle.
        drive_cycle(1'b1,1'b0,8'b0000_0011,
                    pack8(16'sd1,-16'sd1,0,0,0,0,0,0));
        drive_cycle(1'b0,1'b0,8'b0001_0101,
                    pack8(-16'sd327,16'sd22,16'sd123,16'sd7,-16'sd2040,0,0,0));

        @(negedge clk);
        frame_start  = 1'b0;
        frame_end    = 1'b1;
        lane_mask    = 8'hFF;
        samples_flat = pack8(16'sd0,16'sd255,-16'sd510,16'sd638,
                             -16'sd2040,16'sd2168,-16'sd17,16'sd99);
        shadow_cycle(1'b0,8'hFF,samples_flat);
        @(negedge clk);
        check_snapshot("frame1");
        frame_end=0; lane_mask=0; samples_flat='0;

        // Frame 2 proves frame_start clears the previous state and that the
        // frame_start/frame_end cycle itself is included.
        @(negedge clk);
        frame_start  = 1'b1;
        frame_end    = 1'b1;
        lane_mask    = 8'b0000_0101;
        samples_flat = pack8(16'sd5,0,-16'sd2,0,0,0,0,0);
        shadow_cycle(1'b1,lane_mask,samples_flat);
        @(negedge clk);
        check_snapshot("frame2");
        frame_start=0; frame_end=0; lane_mask=0; samples_flat='0;

        repeat (2) @(posedge clk);
        if (errors == 0)
            $display("[PASS] tb_dwt53_checkpoint8 SAMPLE_W=%0d A_SIGN_EXTEND=%0d",SAMPLE_W,A_SIGN_EXTEND);
        else
            $fatal(1,"[FAIL] tb_dwt53_checkpoint8 errors=%0d",errors);
        $finish;
    end
endmodule

`default_nettype wire
