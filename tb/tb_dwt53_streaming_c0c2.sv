`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_streaming_c0c2 #(
    parameter int WIDTH=8,
    parameter int HEIGHT=8,
    parameter int SKEW_ROWS=16
);
    localparam int PIXELS=WIDTH*HEIGHT;
    logic clk=0,rst_n;
    logic in_valid; logic [7:0] in_y; logic in_sof,in_eol,in_eof;
    logic [7:0] input_mem[0:PIXELS-1];
    string vec_dir,p_input;
    integer errors, out_count, cycles;

    logic c0_ready,c0_busy,c0_ov; logic [7:0] c0_y; logic c0_sof,c0_eol,c0_eof;
    logic c0_range,c0_arith,c0_buf,c0_proto;
    logic c2_ready,c2_busy,c2_ov; logic [7:0] c2_y; logic c2_sof,c2_eol,c2_eof;
    logic c2_range,c2_arith,c2_buf,c2_proto;

    // Unused checkpoint ports.
    logic q0v,q1v,q2v,q3v,q4v; logic [31:0] q0c,q1c,q2c,q3c,q4c; logic[15:0] q0x,q1x,q2x,q3x,q4x; logic[31:0] q0a,q1a,q2a,q3a,q4a,q0b,q1b,q2b,q3b,q4b;
    logic p0v,p1v,p2v,p3v,p4v; logic [31:0] p0c,p1c,p2c,p3c,p4c; logic[15:0] p0x,p1x,p2x,p3x,p4x; logic[31:0] p0a,p1a,p2a,p3a,p4a,p0b,p1b,p2b,p3b,p4b;

    always #5 clk=~clk;

    dwt53_streaming_top #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SKEW_ROWS(SKEW_ROWS),.CHECKPOINT_EN(1'b0)) c0 (
        .sys_clk(clk),.sys_rst_n(rst_n),.in_valid(in_valid),.in_y(in_y),.in_sof(in_sof),.in_eol(in_eol),.in_eof(in_eof),
        .frame_ready(c0_ready),.busy(c0_busy),.out_valid(c0_ov),.out_y(c0_y),.out_sof(c0_sof),.out_eol(c0_eol),.out_eof(c0_eof),
        .range_error(c0_range),.arithmetic_error(c0_arith),.buffer_error(c0_buf),.protocol_error(c0_proto),
        .cp_in_snapshot_valid(q0v),.cp_in_count(q0c),.cp_in_xor(q0x),.cp_in_a(q0a),.cp_in_b(q0b),
        .cp_l1_snapshot_valid(q1v),.cp_l1_count(q1c),.cp_l1_xor(q1x),.cp_l1_a(q1a),.cp_l1_b(q1b),
        .cp_fw_snapshot_valid(q2v),.cp_fw_count(q2c),.cp_fw_xor(q2x),.cp_fw_a(q2a),.cp_fw_b(q2b),
        .cp_rc_snapshot_valid(q3v),.cp_rc_count(q3c),.cp_rc_xor(q3x),.cp_rc_a(q3a),.cp_rc_b(q3b),
        .cp_re_snapshot_valid(q4v),.cp_re_count(q4c),.cp_re_xor(q4x),.cp_re_a(q4a),.cp_re_b(q4b)
    );

    dwt53_streaming_top #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SKEW_ROWS(SKEW_ROWS),.CHECKPOINT_EN(1'b1)) c2 (
        .sys_clk(clk),.sys_rst_n(rst_n),.in_valid(in_valid),.in_y(in_y),.in_sof(in_sof),.in_eol(in_eol),.in_eof(in_eof),
        .frame_ready(c2_ready),.busy(c2_busy),.out_valid(c2_ov),.out_y(c2_y),.out_sof(c2_sof),.out_eol(c2_eol),.out_eof(c2_eof),
        .range_error(c2_range),.arithmetic_error(c2_arith),.buffer_error(c2_buf),.protocol_error(c2_proto),
        .cp_in_snapshot_valid(p0v),.cp_in_count(p0c),.cp_in_xor(p0x),.cp_in_a(p0a),.cp_in_b(p0b),
        .cp_l1_snapshot_valid(p1v),.cp_l1_count(p1c),.cp_l1_xor(p1x),.cp_l1_a(p1a),.cp_l1_b(p1b),
        .cp_fw_snapshot_valid(p2v),.cp_fw_count(p2c),.cp_fw_xor(p2x),.cp_fw_a(p2a),.cp_fw_b(p2b),
        .cp_rc_snapshot_valid(p3v),.cp_rc_count(p3c),.cp_rc_xor(p3x),.cp_rc_a(p3a),.cp_rc_b(p3b),
        .cp_re_snapshot_valid(p4v),.cp_re_count(p4c),.cp_re_xor(p4x),.cp_re_a(p4a),.cp_re_b(p4b)
    );

    function automatic bit file_exists(input string p); integer fd; begin fd=$fopen(p,"r"); if(fd) begin $fclose(fd);file_exists=1;end else file_exists=0; end endfunction

    task automatic drive_frame;
        integer i,x;
        begin
            wait(c0_ready&&c2_ready);
            for(i=0;i<PIXELS;i=i+1) begin
                x=i%WIDTH;
                @(negedge clk); in_valid=1;in_y=input_mem[i];in_sof=(i==0);in_eol=(x==WIDTH-1);in_eof=(i==PIXELS-1);
            end
            @(negedge clk); in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
        end
    endtask

    always @(negedge clk) if(rst_n) begin
        if(c0_ready!==c2_ready) begin $display("[ERROR] frame_ready C0/C2 differ"); errors=errors+1; end
        if(c0_busy!==c2_busy) begin $display("[ERROR] busy C0/C2 differ"); errors=errors+1; end
        if(c0_ov!==c2_ov) begin $display("[ERROR] out_valid C0/C2 differ cycle=%0d",cycles); errors=errors+1; end
        if(c0_ov&&c2_ov) begin
            if(c0_y!==c2_y||c0_sof!==c2_sof||c0_eol!==c2_eol||c0_eof!==c2_eof) begin
                $display("[ERROR] output payload/markers C0/C2 differ at output %0d",out_count); errors=errors+1;
            end
            out_count=out_count+1;
        end
        if(c0_range!==c2_range||c0_arith!==c2_arith||c0_buf!==c2_buf||c0_proto!==c2_proto) begin
            $display("[ERROR] datapath error flags C0/C2 differ"); errors=errors+1;
        end
    end

    always @(posedge clk) begin cycles=cycles+1; if(rst_n&&cycles>PIXELS*50+100000)$fatal(1,"[TIMEOUT] C0/C2"); end

    initial begin
        errors=0;out_count=0;cycles=0;rst_n=0;in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
        if(!$value$plusargs("VEC_DIR=%s",vec_dir))vec_dir="vectors/random_0008x0008";
        p_input={vec_dir,"/input_y8_hex.txt"}; if(!file_exists(p_input))$fatal(1,"missing %s",p_input); $readmemh(p_input,input_mem);
        repeat(6)@(posedge clk); @(negedge clk);rst_n=1;
        drive_frame(); wait(c0_ov&&c0_eof); repeat(6)@(posedge clk);
        if(out_count!=PIXELS)begin $display("[ERROR] output count exp=%0d got=%0d",PIXELS,out_count);errors=errors+1;end
        if(c0_range||c0_arith||c0_buf||c0_proto||c2_range||c2_arith||c2_buf||c2_proto)begin $display("[ERROR] positive-run error flag");errors=errors+1;end
        if(errors==0)$display("[PASS] tb_dwt53_streaming_c0c2 vec=%s",vec_dir); else $fatal(1,"[FAIL] C0/C2 errors=%0d",errors);
        $finish;
    end
endmodule

`default_nettype wire
