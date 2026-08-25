`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_streaming_top #(
    parameter int WIDTH         = 8,
    parameter int HEIGHT        = 8,
    parameter int DATA_W        = 16,
    parameter int SKEW_ROWS     = 16,
    parameter bit A_SIGN_EXTEND = 1'b0
);
    localparam int PIXELS = WIDTH*HEIGHT;
    localparam int L1_W = WIDTH/2;
    localparam int L1_H = HEIGHT/2;
    localparam int L2_W = WIDTH/4;
    localparam int L2_H = HEIGHT/4;
    localparam int L1_COORDS = L1_W*L1_H;
    localparam int L2_COORDS = L2_W*L2_H;
    localparam int PRINT_LIMIT = 20;

    logic clk = 1'b0;
    logic rst_n;

    logic in_valid;
    logic [7:0] in_y;
    logic in_sof, in_eol, in_eof;
    logic frame_ready, busy;

    logic out_valid;
    logic [7:0] out_y;
    logic out_sof, out_eol, out_eof;
    logic range_error, arithmetic_error, buffer_error, protocol_error;

    logic cp_in_snapshot_valid;
    logic [31:0] cp_in_count; logic [15:0] cp_in_xor; logic [31:0] cp_in_a, cp_in_b;
    logic cp_l1_snapshot_valid;
    logic [31:0] cp_l1_count; logic [15:0] cp_l1_xor; logic [31:0] cp_l1_a, cp_l1_b;
    logic cp_fw_snapshot_valid;
    logic [31:0] cp_fw_count; logic [15:0] cp_fw_xor; logic [31:0] cp_fw_a, cp_fw_b;
    logic cp_rc_snapshot_valid;
    logic [31:0] cp_rc_count; logic [15:0] cp_rc_xor; logic [31:0] cp_rc_a, cp_rc_b;
    logic cp_re_snapshot_valid;
    logic [31:0] cp_re_count; logic [15:0] cp_re_xor; logic [31:0] cp_re_a, cp_re_b;

    logic [7:0] input_mem [0:PIXELS-1];
    logic [7:0] recon_mem [0:PIXELS-1];
    logic [15:0] c1_mem [0:PIXELS-1];
    logic [15:0] c2_mem [0:PIXELS-1];

    string vec_dir;
    string p_input, p_recon, p_c1, p_c2;
    integer gap_every;
    integer trace_en;

    integer errors;
    integer c1_mismatches, c2_mismatches, rc_mismatches, re_mismatches, out_mismatches;
    integer l1_x, l1_y, l1_count;
    integer l2_x, l2_y, l2_count;
    integer rc_x, rc_y, rc_count_seen;
    integer re_x, re_y, re_count_seen;
    integer out_xc, out_yc, out_count_seen;
    integer max_align_occupancy;
    integer current_align_occupancy;
    integer output_gap, max_output_gap;
    bit output_started;
    bit output_done;

    longint unsigned sim_cycle;
    longint unsigned first_input_cycle;
    longint unsigned first_output_cycle;
    longint unsigned eof_output_cycle;
    longint unsigned max_cycles;

    bit cp_in_seen, cp_l1_seen, cp_fw_seen, cp_rc_seen, cp_re_seen;

    // Shadow signatures: expected from golden data in the documented physical
    // streaming order. CP-FW is accumulated online because its order is a
    // chronological merge of two concurrently valid streams.
    logic [31:0] exp_in_count, exp_in_a, exp_in_b; logic [15:0] exp_in_xor;
    logic [31:0] exp_l1_count, exp_l1_a, exp_l1_b; logic [15:0] exp_l1_xor;
    logic [31:0] exp_fw_count, exp_fw_a, exp_fw_b; logic [15:0] exp_fw_xor;
    logic [31:0] exp_rc_count, exp_rc_a, exp_rc_b; logic [15:0] exp_rc_xor;
    logic [31:0] exp_re_count, exp_re_a, exp_re_b; logic [15:0] exp_re_xor;

    always #5 clk = ~clk;

    dwt53_streaming_top #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .DATA_W(DATA_W),
        .SKEW_ROWS(SKEW_ROWS), .CHECKPOINT_EN(1'b1),
        .A_SIGN_EXTEND(A_SIGN_EXTEND)
    ) dut (
        .sys_clk(clk), .sys_rst_n(rst_n),
        .in_valid(in_valid), .in_y(in_y), .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .frame_ready(frame_ready), .busy(busy),
        .out_valid(out_valid), .out_y(out_y), .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .range_error(range_error), .arithmetic_error(arithmetic_error),
        .buffer_error(buffer_error), .protocol_error(protocol_error),
        .cp_in_snapshot_valid(cp_in_snapshot_valid), .cp_in_count(cp_in_count),
        .cp_in_xor(cp_in_xor), .cp_in_a(cp_in_a), .cp_in_b(cp_in_b),
        .cp_l1_snapshot_valid(cp_l1_snapshot_valid), .cp_l1_count(cp_l1_count),
        .cp_l1_xor(cp_l1_xor), .cp_l1_a(cp_l1_a), .cp_l1_b(cp_l1_b),
        .cp_fw_snapshot_valid(cp_fw_snapshot_valid), .cp_fw_count(cp_fw_count),
        .cp_fw_xor(cp_fw_xor), .cp_fw_a(cp_fw_a), .cp_fw_b(cp_fw_b),
        .cp_rc_snapshot_valid(cp_rc_snapshot_valid), .cp_rc_count(cp_rc_count),
        .cp_rc_xor(cp_rc_xor), .cp_rc_a(cp_rc_a), .cp_rc_b(cp_rc_b),
        .cp_re_snapshot_valid(cp_re_snapshot_valid), .cp_re_count(cp_re_count),
        .cp_re_xor(cp_re_xor), .cp_re_a(cp_re_a), .cp_re_b(cp_re_b)
    );

    function automatic bit file_exists(input string p);
        integer fd;
        begin
            fd = $fopen(p,"r");
            if (fd != 0) begin $fclose(fd); file_exists=1'b1; end
            else file_exists=1'b0;
        end
    endfunction

    function automatic logic [31:0] sig_contrib(input logic [15:0] pattern);
        begin
            if (A_SIGN_EXTEND)
                sig_contrib = {{16{pattern[15]}},pattern};
            else
                sig_contrib = {16'd0,pattern};
        end
    endfunction

    task automatic sig_clear(
        inout logic [31:0] count,
        inout logic [15:0] xorv,
        inout logic [31:0] a,
        inout logic [31:0] b
    );
        begin count=0; xorv=0; a=0; b=0; end
    endtask

    task automatic sig_add(
        inout logic [31:0] count,
        inout logic [15:0] xorv,
        inout logic [31:0] a,
        inout logic [31:0] b,
        input logic [15:0] pattern
    );
        logic [31:0] a_new;
        begin
            a_new = a + sig_contrib(pattern);
            count = count + 1'b1;
            xorv  = xorv ^ pattern;
            a     = a_new;
            b     = b + a_new;
        end
    endtask

    task automatic check_sig(
        input string tag,
        input logic [31:0] got_count,
        input logic [15:0] got_xor,
        input logic [31:0] got_a,
        input logic [31:0] got_b,
        input logic [31:0] ex_count,
        input logic [15:0] ex_xor,
        input logic [31:0] ex_a,
        input logic [31:0] ex_b
    );
        begin
            if (got_count !== ex_count) begin
                $display("[ERROR] %s count exp=%0d got=%0d",tag,ex_count,got_count); errors=errors+1; end
            if (got_xor !== ex_xor) begin
                $display("[ERROR] %s xor exp=%04h got=%04h",tag,ex_xor,got_xor); errors=errors+1; end
            if (got_a !== ex_a) begin
                $display("[ERROR] %s A exp=%08h got=%08h",tag,ex_a,got_a); errors=errors+1; end
            if (got_b !== ex_b) begin
                $display("[ERROR] %s B exp=%08h got=%08h",tag,ex_b,got_b); errors=errors+1; end
        end
    endtask

    task automatic precompute_static_signatures;
        integer i, x, y;
        integer idx_ll, idx_hl, idx_lh, idx_hh;
        begin
            sig_clear(exp_in_count,exp_in_xor,exp_in_a,exp_in_b);
            sig_clear(exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b);
            sig_clear(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b);
            sig_clear(exp_rc_count,exp_rc_xor,exp_rc_a,exp_rc_b);
            sig_clear(exp_re_count,exp_re_xor,exp_re_a,exp_re_b);

            for (i=0;i<PIXELS;i=i+1) begin
                sig_add(exp_in_count,exp_in_xor,exp_in_a,exp_in_b,{8'd0,input_mem[i]});
                sig_add(exp_re_count,exp_re_xor,exp_re_a,exp_re_b,{8'd0,recon_mem[i]});
            end

            // CP-L1 physical order: LL,HL,LH,HH at each quartet coordinate.
            for (y=0;y<L1_H;y=y+1) begin
                for (x=0;x<L1_W;x=x+1) begin
                    idx_ll = y*WIDTH + x;
                    idx_hl = y*WIDTH + x + L1_W;
                    idx_lh = (y+L1_H)*WIDTH + x;
                    idx_hh = (y+L1_H)*WIDTH + x + L1_W;
                    sig_add(exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b,c1_mem[idx_ll]);
                    sig_add(exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b,c1_mem[idx_hl]);
                    sig_add(exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b,c1_mem[idx_lh]);
                    sig_add(exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b,c1_mem[idx_hh]);
                end
            end

            // CP-RC is reconstructed LL1 in row-major order.
            for (y=0;y<L1_H;y=y+1)
                for (x=0;x<L1_W;x=x+1)
                    sig_add(exp_rc_count,exp_rc_xor,exp_rc_a,exp_rc_b,c1_mem[y*WIDTH+x]);
        end
    endtask

    task automatic drive_idle;
        begin
            @(negedge clk);
            in_valid=0; in_y=0; in_sof=0; in_eol=0; in_eof=0;
        end
    endtask

    task automatic drive_frame;
        integer i, x, y;
        begin
            wait (frame_ready === 1'b1);
            for (i=0;i<PIXELS;i=i+1) begin
                if ((gap_every>0) && (i>0) && ((i%gap_every)==0))
                    drive_idle();
                x=i%WIDTH; y=i/WIDTH;
                @(negedge clk);
                in_valid=1'b1;
                in_y=input_mem[i];
                in_sof=(i==0);
                in_eol=(x==WIDTH-1);
                in_eof=(i==PIXELS-1);
                if (i==0)
                    first_input_cycle=sim_cycle;
            end
            drive_idle();
        end
    endtask

    // Main stage/output monitor. Sampling on negedge avoids NBA races with DUT.
    always @(negedge clk) begin : monitor_all
        integer idx_ll, idx_hl, idx_lh, idx_hh;
        logic signed [15:0] exp_s;
        logic signed [15:0] got_s;

        if (rst_n) begin
            current_align_occupancy = $unsigned(dut.u_band_align.count_q);
            if (current_align_occupancy > max_align_occupancy)
                max_align_occupancy = current_align_occupancy;

            // ---------------- Level 1 / C1 ----------------
            if (dut.l1_valid) begin
                idx_ll=l1_y*WIDTH+l1_x;
                idx_hl=l1_y*WIDTH+l1_x+L1_W;
                idx_lh=(l1_y+L1_H)*WIDTH+l1_x;
                idx_hh=(l1_y+L1_H)*WIDTH+l1_x+L1_W;

                if ($signed(dut.l1_ll) !== $signed(c1_mem[idx_ll])) begin
                    if (c1_mismatches<PRINT_LIMIT) $display("[C1] LL (%0d,%0d) exp=%0d got=%0d",l1_x,l1_y,$signed(c1_mem[idx_ll]),$signed(dut.l1_ll));
                    c1_mismatches=c1_mismatches+1; errors=errors+1; end
                if ($signed(dut.l1_hl) !== $signed(c1_mem[idx_hl])) begin
                    if (c1_mismatches<PRINT_LIMIT) $display("[C1] HL (%0d,%0d) exp=%0d got=%0d",l1_x,l1_y,$signed(c1_mem[idx_hl]),$signed(dut.l1_hl));
                    c1_mismatches=c1_mismatches+1; errors=errors+1; end
                if ($signed(dut.l1_lh) !== $signed(c1_mem[idx_lh])) begin
                    if (c1_mismatches<PRINT_LIMIT) $display("[C1] LH (%0d,%0d) exp=%0d got=%0d",l1_x,l1_y,$signed(c1_mem[idx_lh]),$signed(dut.l1_lh));
                    c1_mismatches=c1_mismatches+1; errors=errors+1; end
                if ($signed(dut.l1_hh) !== $signed(c1_mem[idx_hh])) begin
                    if (c1_mismatches<PRINT_LIMIT) $display("[C1] HH (%0d,%0d) exp=%0d got=%0d",l1_x,l1_y,$signed(c1_mem[idx_hh]),$signed(dut.l1_hh));
                    c1_mismatches=c1_mismatches+1; errors=errors+1; end

                // C2 includes these untouched high bands.
                if ($signed(dut.l1_hl) !== $signed(c2_mem[idx_hl])) begin c2_mismatches=c2_mismatches+1; errors=errors+1; end
                if ($signed(dut.l1_lh) !== $signed(c2_mem[idx_lh])) begin c2_mismatches=c2_mismatches+1; errors=errors+1; end
                if ($signed(dut.l1_hh) !== $signed(c2_mem[idx_hh])) begin c2_mismatches=c2_mismatches+1; errors=errors+1; end

                // CP-FW lane order puts Level-1 high bands before Level-2 lanes.
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_hl]);
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_lh]);
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_hh]);

                if (dut.l1_sof !== ((l1_x==0)&&(l1_y==0))) begin $display("[ERROR] l1_sof coord"); errors=errors+1; end
                if (dut.l1_eol !== (l1_x==L1_W-1)) begin $display("[ERROR] l1_eol coord"); errors=errors+1; end
                if (dut.l1_eof !== ((l1_x==L1_W-1)&&(l1_y==L1_H-1))) begin $display("[ERROR] l1_eof coord"); errors=errors+1; end

                l1_count=l1_count+1;
                if (l1_x==L1_W-1) begin l1_x=0; l1_y=l1_y+1; end
                else l1_x=l1_x+1;
            end

            // ---------------- Level 2 / C2 top-left ----------------
            if (dut.l2_valid) begin
                idx_ll=l2_y*WIDTH+l2_x;
                idx_hl=l2_y*WIDTH+l2_x+L2_W;
                idx_lh=(l2_y+L2_H)*WIDTH+l2_x;
                idx_hh=(l2_y+L2_H)*WIDTH+l2_x+L2_W;

                if ($signed(dut.l2_ll) !== $signed(c2_mem[idx_ll])) begin
                    if (c2_mismatches<PRINT_LIMIT) $display("[C2] LL2 (%0d,%0d) exp=%0d got=%0d",l2_x,l2_y,$signed(c2_mem[idx_ll]),$signed(dut.l2_ll));
                    c2_mismatches=c2_mismatches+1; errors=errors+1; end
                if ($signed(dut.l2_hl) !== $signed(c2_mem[idx_hl])) begin
                    if (c2_mismatches<PRINT_LIMIT) $display("[C2] HL2 (%0d,%0d) exp=%0d got=%0d",l2_x,l2_y,$signed(c2_mem[idx_hl]),$signed(dut.l2_hl));
                    c2_mismatches=c2_mismatches+1; errors=errors+1; end
                if ($signed(dut.l2_lh) !== $signed(c2_mem[idx_lh])) begin
                    if (c2_mismatches<PRINT_LIMIT) $display("[C2] LH2 (%0d,%0d) exp=%0d got=%0d",l2_x,l2_y,$signed(c2_mem[idx_lh]),$signed(dut.l2_lh));
                    c2_mismatches=c2_mismatches+1; errors=errors+1; end
                if ($signed(dut.l2_hh) !== $signed(c2_mem[idx_hh])) begin
                    if (c2_mismatches<PRINT_LIMIT) $display("[C2] HH2 (%0d,%0d) exp=%0d got=%0d",l2_x,l2_y,$signed(c2_mem[idx_hh]),$signed(dut.l2_hh));
                    c2_mismatches=c2_mismatches+1; errors=errors+1; end

                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_ll]);
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_hl]);
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_lh]);
                sig_add(exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b,c2_mem[idx_hh]);

                if (dut.l2_sof !== ((l2_x==0)&&(l2_y==0))) begin $display("[ERROR] l2_sof coord"); errors=errors+1; end
                if (dut.l2_eol !== (l2_x==L2_W-1)) begin $display("[ERROR] l2_eol coord"); errors=errors+1; end
                if (dut.l2_eof !== ((l2_x==L2_W-1)&&(l2_y==L2_H-1))) begin $display("[ERROR] l2_eof coord"); errors=errors+1; end

                l2_count=l2_count+1;
                if (l2_x==L2_W-1) begin l2_x=0; l2_y=l2_y+1; end
                else l2_x=l2_x+1;
            end

            // ---------------- Inverse L2 reconstructed LL1 ----------------
            if (dut.rc_valid) begin
                idx_ll=rc_y*WIDTH+rc_x;
                if ($signed(dut.rc_ll1) !== $signed(c1_mem[idx_ll])) begin
                    if (rc_mismatches<PRINT_LIMIT) $display("[RC] LL1 (%0d,%0d) exp=%0d got=%0d",rc_x,rc_y,$signed(c1_mem[idx_ll]),$signed(dut.rc_ll1));
                    rc_mismatches=rc_mismatches+1; errors=errors+1;
                end
                if (dut.rc_sof !== ((rc_x==0)&&(rc_y==0))) begin $display("[ERROR] rc_sof coord"); errors=errors+1; end
                if (dut.rc_eol !== (rc_x==L1_W-1)) begin $display("[ERROR] rc_eol coord"); errors=errors+1; end
                if (dut.rc_eof !== ((rc_x==L1_W-1)&&(rc_y==L1_H-1))) begin $display("[ERROR] rc_eof coord"); errors=errors+1; end
                rc_count_seen=rc_count_seen+1;
                if (rc_x==L1_W-1) begin rc_x=0; rc_y=rc_y+1; end else rc_x=rc_x+1;
            end

            // ---------------- Inverse L1 internal reconstructed stream ----------------
            if (dut.re_valid) begin
                idx_ll=re_y*WIDTH+re_x;
                exp_s=$signed({8'd0,recon_mem[idx_ll]});
                got_s=$signed(dut.re_sample);
                if (got_s !== exp_s) begin
                    if (re_mismatches<PRINT_LIMIT) $display("[RE] (%0d,%0d) exp=%0d got=%0d",re_x,re_y,exp_s,got_s);
                    re_mismatches=re_mismatches+1; errors=errors+1;
                end
                if (dut.re_sof !== ((re_x==0)&&(re_y==0))) begin $display("[ERROR] re_sof coord"); errors=errors+1; end
                if (dut.re_eol !== (re_x==WIDTH-1)) begin $display("[ERROR] re_eol coord"); errors=errors+1; end
                if (dut.re_eof !== ((re_x==WIDTH-1)&&(re_y==HEIGHT-1))) begin $display("[ERROR] re_eof coord"); errors=errors+1; end
                re_count_seen=re_count_seen+1;
                if (re_x==WIDTH-1) begin re_x=0; re_y=re_y+1; end else re_x=re_x+1;
            end

            // ---------------- External Y8 ----------------
            if (out_valid) begin
                idx_ll=out_yc*WIDTH+out_xc;
                if (out_y !== recon_mem[idx_ll]) begin
                    if (out_mismatches<PRINT_LIMIT) $display("[OUT] (%0d,%0d) exp=%0d got=%0d",out_xc,out_yc,recon_mem[idx_ll],out_y);
                    out_mismatches=out_mismatches+1; errors=errors+1;
                end
                if (out_sof !== ((out_xc==0)&&(out_yc==0))) begin $display("[ERROR] out_sof coord"); errors=errors+1; end
                if (out_eol !== (out_xc==WIDTH-1)) begin $display("[ERROR] out_eol coord"); errors=errors+1; end
                if (out_eof !== ((out_xc==WIDTH-1)&&(out_yc==HEIGHT-1))) begin $display("[ERROR] out_eof coord"); errors=errors+1; end

                if (!output_started) begin
                    output_started=1'b1;
                    first_output_cycle=sim_cycle;
                    output_gap=0;
                end else begin
                    if (output_gap>max_output_gap) max_output_gap=output_gap;
                    output_gap=0;
                end

                out_count_seen=out_count_seen+1;
                if (out_eof) begin output_done=1'b1; eof_output_cycle=sim_cycle; end
                if (out_xc==WIDTH-1) begin out_xc=0; out_yc=out_yc+1; end else out_xc=out_xc+1;
            end else if (output_started && !output_done) begin
                output_gap=output_gap+1;
            end

            // Snapshot comparisons. Stage shadow updates above execute first, so
            // the final frame-end lanes are included before comparison.
            if (cp_in_snapshot_valid && !cp_in_seen) begin
                check_sig("CP-IN",cp_in_count,cp_in_xor,cp_in_a,cp_in_b,
                          exp_in_count,exp_in_xor,exp_in_a,exp_in_b); cp_in_seen=1'b1; end
            if (cp_l1_snapshot_valid && !cp_l1_seen) begin
                check_sig("CP-L1",cp_l1_count,cp_l1_xor,cp_l1_a,cp_l1_b,
                          exp_l1_count,exp_l1_xor,exp_l1_a,exp_l1_b); cp_l1_seen=1'b1; end
            if (cp_fw_snapshot_valid && !cp_fw_seen) begin
                check_sig("CP-FW",cp_fw_count,cp_fw_xor,cp_fw_a,cp_fw_b,
                          exp_fw_count,exp_fw_xor,exp_fw_a,exp_fw_b); cp_fw_seen=1'b1; end
            if (cp_rc_snapshot_valid && !cp_rc_seen) begin
                check_sig("CP-RC",cp_rc_count,cp_rc_xor,cp_rc_a,cp_rc_b,
                          exp_rc_count,exp_rc_xor,exp_rc_a,exp_rc_b); cp_rc_seen=1'b1; end
            if (cp_re_snapshot_valid && !cp_re_seen) begin
                check_sig("CP-RE",cp_re_count,cp_re_xor,cp_re_a,cp_re_b,
                          exp_re_count,exp_re_xor,exp_re_a,exp_re_b); cp_re_seen=1'b1; end
        end
    end

    always @(posedge clk) begin
        sim_cycle <= sim_cycle + 1'b1;
        if (rst_n && (sim_cycle > max_cycles))
            $fatal(1,"[TIMEOUT] streaming top WIDTH=%0d HEIGHT=%0d",WIDTH,HEIGHT);
    end

    initial begin : main
        integer i;
        integer user_max_cycles;
        if ((WIDTH%4)!=0 || (HEIGHT%4)!=0)
            $fatal(1,"WIDTH/HEIGHT must be divisible by 4");

        if (!$value$plusargs("VEC_DIR=%s",vec_dir))
            vec_dir="vectors/random_0008x0008";
        if (!$value$plusargs("GAP_EVERY=%d",gap_every)) gap_every=0;
        trace_en=$test$plusargs("TRACE");

        p_input={vec_dir,"/input_y8_hex.txt"};
        p_recon={vec_dir,"/recon_y8_hex.txt"};
        p_c1={vec_dir,"/c1_packed_hex.txt"};
        p_c2={vec_dir,"/c2_packed_hex.txt"};
        if (!file_exists(p_input)||!file_exists(p_recon)||!file_exists(p_c1)||!file_exists(p_c2))
            $fatal(1,"Missing golden files under %s",vec_dir);

        $readmemh(p_input,input_mem);
        $readmemh(p_recon,recon_mem);
        $readmemh(p_c1,c1_mem);
        $readmemh(p_c2,c2_mem);

        errors=0; c1_mismatches=0; c2_mismatches=0; rc_mismatches=0; re_mismatches=0; out_mismatches=0;
        l1_x=0;l1_y=0;l1_count=0; l2_x=0;l2_y=0;l2_count=0;
        rc_x=0;rc_y=0;rc_count_seen=0; re_x=0;re_y=0;re_count_seen=0;
        out_xc=0;out_yc=0;out_count_seen=0;
        max_align_occupancy=0; output_gap=0;max_output_gap=0; output_started=0;output_done=0;
        sim_cycle=0; first_input_cycle=0;first_output_cycle=0;eof_output_cycle=0;
        cp_in_seen=0;cp_l1_seen=0;cp_fw_seen=0;cp_rc_seen=0;cp_re_seen=0;

        max_cycles=PIXELS*40+100000;
        if ($value$plusargs("MAX_CYCLES=%d",user_max_cycles)) max_cycles=user_max_cycles;

        // Independent sanity: exported reconstruction must already equal input.
        for (i=0;i<PIXELS;i=i+1) begin
            if (input_mem[i] !== recon_mem[i]) begin
                if (errors<PRINT_LIMIT) $display("[GOLDEN ERROR] input/recon differ at %0d",i);
                errors=errors+1;
            end
        end
        if (errors!=0) $fatal(1,"Golden vector set is not reversible; refusing RTL run");

        precompute_static_signatures();

        if (trace_en) begin
            $dumpfile("streaming_top.vcd");
            $dumpvars(0,tb_dwt53_streaming_top);
        end

        rst_n=0; in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
        repeat(6) @(posedge clk);
        @(negedge clk); rst_n=1;
        repeat(2) @(posedge clk);

        if (frame_ready!==1'b1) begin $display("[ERROR] frame_ready not high after reset");errors=errors+1; end

        drive_frame();
        wait(output_done);
        repeat(8) @(posedge clk);

        // Exact event counts.
        if (l1_count!=L1_COORDS) begin $display("[ERROR] L1 quartet count exp=%0d got=%0d",L1_COORDS,l1_count);errors=errors+1;end
        if (l2_count!=L2_COORDS) begin $display("[ERROR] L2 quartet count exp=%0d got=%0d",L2_COORDS,l2_count);errors=errors+1;end
        if (rc_count_seen!=PIXELS/4) begin $display("[ERROR] RC count exp=%0d got=%0d",PIXELS/4,rc_count_seen);errors=errors+1;end
        if (re_count_seen!=PIXELS) begin $display("[ERROR] RE count exp=%0d got=%0d",PIXELS,re_count_seen);errors=errors+1;end
        if (out_count_seen!=PIXELS) begin $display("[ERROR] OUT count exp=%0d got=%0d",PIXELS,out_count_seen);errors=errors+1;end

        if (c1_mismatches!=0) $display("[SUMMARY] C1 mismatches=%0d",c1_mismatches);
        if (c2_mismatches!=0) $display("[SUMMARY] C2 mismatches=%0d",c2_mismatches);
        if (rc_mismatches!=0) $display("[SUMMARY] RC mismatches=%0d",rc_mismatches);
        if (re_mismatches!=0) $display("[SUMMARY] RE mismatches=%0d",re_mismatches);
        if (out_mismatches!=0) $display("[SUMMARY] OUT mismatches=%0d",out_mismatches);

        if (!cp_in_seen) begin $display("[ERROR] no CP-IN snapshot");errors=errors+1;end
        if (!cp_l1_seen) begin $display("[ERROR] no CP-L1 snapshot");errors=errors+1;end
        if (!cp_fw_seen) begin $display("[ERROR] no CP-FW snapshot");errors=errors+1;end
        if (!cp_rc_seen) begin $display("[ERROR] no CP-RC snapshot");errors=errors+1;end
        if (!cp_re_seen) begin $display("[ERROR] no CP-RE snapshot");errors=errors+1;end

        // Reference-free Phase-1 round-trip check.
        if (cp_in_seen && cp_re_seen) begin
            if ((cp_in_count!==cp_re_count)||(cp_in_xor!==cp_re_xor)||
                (cp_in_a!==cp_re_a)||(cp_in_b!==cp_re_b)) begin
                $display("[ERROR] CP-RE != CP-IN reference-free comparison"); errors=errors+1;
            end
        end

        if (range_error) begin $display("[ERROR] range_error");errors=errors+1;end
        if (arithmetic_error) begin $display("[ERROR] arithmetic_error");errors=errors+1;end
        if (buffer_error) begin $display("[ERROR] buffer_error");errors=errors+1;end
        if (protocol_error) begin $display("[ERROR] protocol_error");errors=errors+1;end

        $display("[METRIC] image=%0dx%0d pixels=%0d",WIDTH,HEIGHT,PIXELS);
        $display("[METRIC] first_output_latency_cycles=%0d",first_output_cycle-first_input_cycle);
        $display("[METRIC] first_input_to_output_eof_cycles=%0d",eof_output_cycle-first_input_cycle);
        $display("[METRIC] max_output_valid_gap_cycles=%0d",max_output_gap);
        $display("[METRIC] max_alignment_fifo_occupancy=%0d / depth=%0d",
                 max_align_occupancy,SKEW_ROWS*L1_W);

        if (errors==0)
            $display("[PASS] tb_dwt53_streaming_top vec=%s gap_every=%0d",vec_dir,gap_every);
        else
            $fatal(1,"[FAIL] tb_dwt53_streaming_top errors=%0d",errors);
        $finish;
    end
endmodule

`default_nettype wire
