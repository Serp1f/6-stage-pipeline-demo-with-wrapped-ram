module pipeline_alu #(
    parameter   DWIDTH = 4
)
(
    input   clk,
    input   rstn,

    input   i_valid,
    output  i_ready,
    input   i_opcode,           // 0: add, 1: mult
    input   [DWIDTH-1:0] a,     // 操作数a
    input   [DWIDTH-1:0] b,     // 操作数b

    output  o_valid,
    input   o_ready,
    output  logic [DWIDTH-1:0] c,

// bypass   signal
    output  [DWIDTH-1:0] c_1cycle
);


    logic   opcode_p1;
    logic   valid_p0,valid_p1;
    logic   ready_p0,ready_p1;
    logic   [DWIDTH-1:0] op_1cycle_res,op_1cycle_res_tmp;      // add result
    logic   [2*DWIDTH-1:0] op_2cycle_res;      // mult result

// ================== pipeline ctrl ================//

    assign  valid_p0 = i_valid;
    always_ff @(posedge clk) begin
        if(~rstn)
            valid_p1 <= 1'b0;
        else if(ready_p0)
            valid_p1 <= valid_p0;
    end

    assign  ready_p1 = o_ready;
// 当此时在ALU第一级的指令是乘法指令且与P1的指令地址相同，阻塞P1
    assign  ready_p0 = ~valid_p1 || ready_p1;

    always_ff @(posedge clk) begin
        if(~rstn)
            opcode_p1 <= 'd0;
        else if(valid_p0 && ready_p0)
            opcode_p1 <= i_opcode;
    end


// ================ op add ======================//

    assign op_1cycle_res_tmp = (~i_opcode) ? a + b : 'd0;

    always_ff @(posedge clk) begin
        if(~rstn)
            op_1cycle_res <= 'd0;
        else if(valid_p0 && ready_p0 && ~i_opcode) 
            op_1cycle_res <= op_1cycle_res_tmp;
    end

// ================ op mult =====================//
// mult运算延迟2个时钟周期，目前实现的办法是将a拆分成上半和下半，
// 第一个时钟周期作两个部分的乘法
// 第二时钟周期作两个部分的加法
// 当然这个方法不是最优的，如果直接两数相乘，插入1拍寄存器，采用retime综合，时序最优
    localparam  HALF_WIDTH0 = DWIDTH/2;
    localparam  HALF_WIDTH1 = DWIDTH - HALF_WIDTH0;
    logic   [DWIDTH+HALF_WIDTH0-1:0]     mult_tmp0;
    logic   [DWIDTH+HALF_WIDTH1-1:0]     mult_tmp1;
    
    always_ff @(posedge clk) begin
        if(~rstn) begin
            mult_tmp0 <= 'd0;
            mult_tmp1 <= 'd0;
        end
        else if(valid_p0 && ready_p0 && i_opcode) begin
            mult_tmp0 <= a[HALF_WIDTH0-1:0] * b;
            mult_tmp1 <= a[DWIDTH-1:HALF_WIDTH0] * b;
        end
    end

    assign  op_2cycle_res = {mult_tmp1,{HALF_WIDTH0{1'b0}}} + {{HALF_WIDTH1{1'b0}},mult_tmp0};

// ========================== output =============================//

    always_comb begin
        case(opcode_p1)
        'd0:    c = op_1cycle_res;              // ignore overflow
        'd1:    c = op_2cycle_res[DWIDTH-1:0];   // ignore overflow
        default:    c = 'd0;   
        endcase
    end
    assign  c_1cycle = op_1cycle_res_tmp;

    assign  i_ready = ready_p0;
    assign  o_valid = valid_p1;

endmodule