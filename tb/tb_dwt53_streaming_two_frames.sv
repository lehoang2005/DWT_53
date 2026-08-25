`timescale 1ns/1ps
`default_nettype none

module tb_dwt53_streaming_two_frames #(
    parameter int WIDTH=8,
    parameter int HEIGHT=8,
    parameter int SKEW_ROWS=16
);
    localparam int PIXELS=WIDTH*HEIGHT;
    logic clk=0,rst_n;
    logic in_valid; logic[7:0] in_y; logic in_sof,in_eol,in_eof;
    logic frame_ready,busy,out_valid; logic[7:0] out_y; logic out_sof,out_eol,out_eof;
    logic range_error,arithmetic_error,buffer_error,protocol_error;
    logic [7:0] input_mem[0:PIXELS-1];
    string vec_dir,p_input;
    integer errors,out_idx,frame_out,cycles;

    logic s0v,s1v,s2v,s3v,s4v; logic[31:0] s0c,s1c,s2c,s3c,s4c; logic[15:0] s0x,s1x,s2x,s3x,s4x; logic[31:0] s0a,s1a,s2a,s3a,s4a,s0b,s1b,s2b,s3b,s4b;

    always #5 clk=~clk;

    dwt53_streaming_top #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SKEW_ROWS(SKEW_ROWS),.CHECKPOINT_EN(1'b1)) dut (
        .sys_clk(clk),.sys_rst_n(rst_n),.in_valid(in_valid),.in_y(in_y),.in_sof(in_sof),.in_eol(in_eol),.in_eof(in_eof),
        .frame_ready(frame_ready),.busy(busy),.out_valid(out_valid),.out_y(out_y),.out_sof(out_sof),.out_eol(out_eol),.out_eof(out_eof),
        .range_error(range_error),.arithmetic_error(arithmetic_error),.buffer_error(buffer_error),.protocol_error(protocol_error),
        .cp_in_snapshot_valid(s0v),.cp_in_count(s0c),.cp_in_xor(s0x),.cp_in_a(s0a),.cp_in_b(s0b),
        .cp_l1_snapshot_valid(s1v),.cp_l1_count(s1c),.cp_l1_xor(s1x),.cp_l1_a(s1a),.cp_l1_b(s1b),
        .cp_fw_snapshot_valid(s2v),.cp_fw_count(s2c),.cp_fw_xor(s2x),.cp_fw_a(s2a),.cp_fw_b(s2b),
        .cp_rc_snapshot_valid(s3v),.cp_rc_count(s3c),.cp_rc_xor(s3x),.cp_rc_a(s3a),.cp_rc_b(s3b),
        .cp_re_snapshot_valid(s4v),.cp_re_count(s4c),.cp_re_xor(s4x),.cp_re_a(s4a),.cp_re_b(s4b)
    );

    function automatic bit file_exists(input string p); integer fd; begin fd=$fopen(p,"r"); if(fd)begin$fclose(fd);file_exists=1;end else file_exists=0; end endfunction

    task automatic send_one_frame;
        integer i,x;
        begin
            wait(frame_ready===1'b1);
            for(i=0;i<PIXELS;i=i+1)begin
                x=i%WIDTH;
                @(negedge clk);in_valid=1;in_y=input_mem[i];in_sof=(i==0);in_eol=(x==WIDTH-1);in_eof=(i==PIXELS-1);
            end
            @(negedge clk);in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
        end
    endtask

    always @(negedge clk) if(rst_n&&out_valid) begin
        if(out_y!==input_mem[out_idx])begin $display("[ERROR] frame=%0d idx=%0d exp=%0d got=%0d",frame_out,out_idx,input_mem[out_idx],out_y);errors=errors+1;end
        if(out_sof!== (out_idx==0))begin $display("[ERROR] SOF frame=%0d idx=%0d",frame_out,out_idx);errors=errors+1;end
        if(out_eol!== ((out_idx%WIDTH)==WIDTH-1))begin $display("[ERROR] EOL frame=%0d idx=%0d",frame_out,out_idx);errors=errors+1;end
        if(out_eof!== (out_idx==PIXELS-1))begin $display("[ERROR] EOF frame=%0d idx=%0d",frame_out,out_idx);errors=errors+1;end
        if(out_idx==PIXELS-1)begin out_idx=0;frame_out=frame_out+1;end else out_idx=out_idx+1;
    end

    always @(posedge clk)begin cycles=cycles+1;if(rst_n&&cycles>PIXELS*120+200000)$fatal(1,"[TIMEOUT] two frames");end

    initial begin
        errors=0;out_idx=0;frame_out=0;cycles=0;rst_n=0;in_valid=0;in_y=0;in_sof=0;in_eol=0;in_eof=0;
        if(!$value$plusargs("VEC_DIR=%s",vec_dir))vec_dir="vectors/random_0008x0008";
        p_input={vec_dir,"/input_y8_hex.txt"};if(!file_exists(p_input))$fatal(1,"missing %s",p_input);$readmemh(p_input,input_mem);
        repeat(6)@(posedge clk);@(negedge clk);rst_n=1;
        send_one_frame();
        wait(frame_out==1);
        // Do not start frame 2 until DUT explicitly re-advertises frame_ready.
        send_one_frame();
        wait(frame_out==2);repeat(8)@(posedge clk);
        if(range_error||arithmetic_error||buffer_error||protocol_error)begin $display("[ERROR] positive-run error flag");errors=errors+1;end
        if(errors==0)$display("[PASS] tb_dwt53_streaming_two_frames");else $fatal(1,"[FAIL] two_frames errors=%0d",errors);
        $finish;
    end
endmodule

`default_nettype wire
