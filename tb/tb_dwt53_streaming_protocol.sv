`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_streaming_protocol #(
    parameter int WIDTH=8,
    parameter int HEIGHT=8
);
    logic clk=0, rst_n;
    logic in_valid; logic [7:0] in_y; logic in_sof,in_eol,in_eof;
    logic frame_ready,busy;
    logic out_valid; logic [7:0] out_y; logic out_sof,out_eol,out_eof;
    logic range_error,arithmetic_error,buffer_error,protocol_error;
    logic cp_in_snapshot_valid; logic [31:0] cp_in_count; logic [15:0] cp_in_xor; logic [31:0] cp_in_a,cp_in_b;
    logic cp_l1_snapshot_valid; logic [31:0] cp_l1_count; logic [15:0] cp_l1_xor; logic [31:0] cp_l1_a,cp_l1_b;
    logic cp_fw_snapshot_valid; logic [31:0] cp_fw_count; logic [15:0] cp_fw_xor; logic [31:0] cp_fw_a,cp_fw_b;
    logic cp_rc_snapshot_valid; logic [31:0] cp_rc_count; logic [15:0] cp_rc_xor; logic [31:0] cp_rc_a,cp_rc_b;
    logic cp_re_snapshot_valid; logic [31:0] cp_re_count; logic [15:0] cp_re_xor; logic [31:0] cp_re_a,cp_re_b;
    integer errors;

    always #5 clk=~clk;

    dwt53_streaming_top #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SKEW_ROWS(16),.CHECKPOINT_EN(1'b0)) dut (
        .sys_clk(clk),.sys_rst_n(rst_n),
        .in_valid(in_valid),.in_y(in_y),.in_sof(in_sof),.in_eol(in_eol),.in_eof(in_eof),
        .frame_ready(frame_ready),.busy(busy),
        .out_valid(out_valid),.out_y(out_y),.out_sof(out_sof),.out_eol(out_eol),.out_eof(out_eof),
        .range_error(range_error),.arithmetic_error(arithmetic_error),.buffer_error(buffer_error),.protocol_error(protocol_error),
        .cp_in_snapshot_valid(cp_in_snapshot_valid),.cp_in_count(cp_in_count),.cp_in_xor(cp_in_xor),.cp_in_a(cp_in_a),.cp_in_b(cp_in_b),
        .cp_l1_snapshot_valid(cp_l1_snapshot_valid),.cp_l1_count(cp_l1_count),.cp_l1_xor(cp_l1_xor),.cp_l1_a(cp_l1_a),.cp_l1_b(cp_l1_b),
        .cp_fw_snapshot_valid(cp_fw_snapshot_valid),.cp_fw_count(cp_fw_count),.cp_fw_xor(cp_fw_xor),.cp_fw_a(cp_fw_a),.cp_fw_b(cp_fw_b),
        .cp_rc_snapshot_valid(cp_rc_snapshot_valid),.cp_rc_count(cp_rc_count),.cp_rc_xor(cp_rc_xor),.cp_rc_a(cp_rc_a),.cp_rc_b(cp_rc_b),
        .cp_re_snapshot_valid(cp_re_snapshot_valid),.cp_re_count(cp_re_count),.cp_re_xor(cp_re_xor),.cp_re_a(cp_re_a),.cp_re_b(cp_re_b)
    );

    task automatic drive(input logic v,input logic [7:0] y,input logic sof,input logic eol,input logic eof);
        begin
            @(negedge clk); in_valid=v; in_y=y; in_sof=sof; in_eol=eol; in_eof=eof;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk); rst_n=0; in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
            repeat(4) @(posedge clk);
            @(negedge clk); rst_n=1;
            repeat(2) @(posedge clk);
        end
    endtask

    task automatic expect_protocol_error(input string name);
        begin
            repeat(3) @(posedge clk);
            if (!protocol_error) begin
                $display("[ERROR] %s did not assert protocol_error",name);
                errors=errors+1;
            end else begin
                $display("[PASS-NEG] %s asserted protocol_error",name);
            end
        end
    endtask

    initial begin
        errors=0; rst_n=0;in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;

        // T17: valid while idle without SOF.
        reset_dut();
        drive(1,8'h11,0,0,0); drive(0,0,0,0,0);
        expect_protocol_error("valid_without_sof");

        // T18: duplicate SOF in an active frame.
        reset_dut();
        drive(1,8'h01,1,0,0); // pixel 0
        drive(1,8'h02,1,0,0); // illegal duplicate SOF
        drive(0,0,0,0,0);
        expect_protocol_error("duplicate_sof");

        // T19: EOL asserted too early.
        reset_dut();
        drive(1,8'h01,1,0,0);
        drive(1,8'h02,0,1,0); // x=1, not WIDTH-1
        drive(0,0,0,0,0);
        expect_protocol_error("early_eol");

        // T20: EOF asserted at a non-final coordinate.
        reset_dut();
        drive(1,8'h01,1,0,0);
        drive(1,8'h02,0,0,1);
        drive(0,0,0,0,0);
        expect_protocol_error("early_eof");

        if (errors==0)
            $display("[PASS] tb_dwt53_streaming_protocol");
        else
            $fatal(1,"[FAIL] tb_dwt53_streaming_protocol errors=%0d",errors);
        $finish;
    end
endmodule

`default_nettype wire
