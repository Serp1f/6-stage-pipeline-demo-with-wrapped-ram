module pipeline_demo #(
    parameter   DEPTH = 32,
    parameter   DWIDTH = 16
) (
    input       clk,
    input       rstn,

    input   i_valid,     // 操作使能
    output  i_ready,
    input   i_opcode,
    input   [$clog2(DEPTH)-1:0] i_addr,
    input   [DWIDTH-1:0] i_ins,

    output  o_valid,
    input   o_ready,
    output  [DWIDTH-1:0] o_data
);

    localparam PIPE_STAGE = 5;
    logic [3:0][DWIDTH-1:0]                 pipe_ins_p;
    logic [3:0]                             pipe_opcode_p;
    logic [PIPE_STAGE:0][$clog2(DEPTH)-1:0] pipe_addr_p;
    logic [DWIDTH-1:0]                      pipe_data_p3,pipe_data_p5;

    logic [DEPTH-1:0]   addr_accessed;

    // 以前向传播来命名
    logic   [PIPE_STAGE-1:0]    pipe_valid_tmp;
    logic   [PIPE_STAGE:0]  pipe_valid_p,pipe_ready_p;
    logic   op_2cycle_block;        // 延迟为2的指令还在ALU的第一级，此时无法转发数据，反压P1的指令，不让其进入ALU

    logic ram_wen,ram_ren,ram_ren_q;
    logic [$clog2(DEPTH)-1:0]   ram_waddr,ram_raddr;
    logic [DWIDTH-1:0]   ram_wdata,ram_rdata;
    logic [DEPTH-1:0]   addr_accessed_set_mask;

    logic   [DWIDTH-1:0]        bypass_data_p2_s0,bypass_data_p2_s1,bypass_data_p2_s2;
    logic   [DWIDTH-1:0]        alu_res,alu_res_1cycle;
    logic   [PIPE_STAGE:0]      bypass_to_p0;       // p0被其他级bypass，可以不用读RAM，低功耗考虑,0:tie 0,1: P1, 1:P2 ...
    logic   [PIPE_STAGE:0]      bypass_to_p2;       // p1被其他级bypass，需要作数据转发给ALU,0,1:tie 0,1: P2, 1:P3 ...
    logic   [PIPE_STAGE:0]      addr_eq_p0;         // 地址与p0的地址一致,0:tie 0,  1: P1, 1:P2 ...
    logic   [PIPE_STAGE:0]      addr_eq_p2;         // 地址与p1的地址一致,0,1,2:tie 0,  1: P2, 1:P3 ...

// =============== pipeline ===============//

// valid的前向传播
    always_ff @(posedge clk) begin
        for(int i=0;i<2;i=i+1) begin
            if(~rstn)
                pipe_valid_tmp[i] <= 1'b0;
            else if(pipe_ready_p[i])
                pipe_valid_tmp[i] <= pipe_valid_p[i];
        end
    end

    always_ff @(posedge clk) begin
        if(~rstn)
            pipe_valid_tmp[2] <= 1'b0;
        else if(pipe_valid_tmp[1] && pipe_ready_p[2] && ~op_2cycle_block)
            pipe_valid_tmp[2] <= 1'b1;
        else if(pipe_valid_tmp[2] && pipe_ready_p[3])
            pipe_valid_tmp[2] <= 1'b0;
    end

    always_ff @(posedge clk) begin
        for(int i=3;i<PIPE_STAGE;i=i+1) begin
            if(~rstn)
                pipe_valid_tmp[i] <= 1'b0;
            else if(pipe_ready_p[i])
                pipe_valid_tmp[i] <= pipe_valid_p[i];
        end
    end

    assign  pipe_valid_p = {pipe_valid_tmp,i_valid};

//  当此时在ALU第一级的指令是乘法指令且与P1的指令地址相同，阻塞P2
    assign  op_2cycle_block = pipe_valid_p[3] && pipe_valid_p[2] && pipe_opcode_p[3] && addr_eq_p2[3];

// ready的反向传播
    always_comb begin
        pipe_ready_p[PIPE_STAGE] = o_ready;
        for(int i=PIPE_STAGE-1;i>=0;i=i-1) begin
            if(i==2) 
                pipe_ready_p[2] = ~pipe_valid_p[3] || pipe_ready_p[3] && ~op_2cycle_block;
            else
                pipe_ready_p[i] = pipe_ready_p[i+1] || ~pipe_valid_p[i+1];
        end
    end

// ================ bypass check ================ //
    always_comb begin
        addr_eq_p2[2:0] = 3'b000;
        bypass_to_p2[2:0] = 3'b000;
        for(int i=3;i<=PIPE_STAGE;i=i+1) begin
            addr_eq_p2[i] = pipe_addr_p[i] == pipe_addr_p[2];
            bypass_to_p2[i] = pipe_valid_p[2] && pipe_valid_p[i] && addr_eq_p2[i]; 
        end
    end
    
// ================ ram ================== //

    assign  ram_wen     = pipe_valid_p[PIPE_STAGE] && pipe_ready_p[PIPE_STAGE];
    assign  ram_waddr   = pipe_addr_p[PIPE_STAGE];
    assign  ram_wdata   = pipe_data_p5;

// 反压控制由流水线完成，不用pipe_ram内部的流水线反压控制
    pipe_ram #(DEPTH,DWIDTH,2) u_ram
    (
        .clk(clk),
        .rstn(rstn),
        
        .wen(ram_wen),
        .waddr(ram_waddr),
        .wdata(ram_wdata),

        .i_vld(pipe_valid_p[0]),
        .i_rdy(),
        .i_addr(i_addr),

        .o_vld(),
        .o_rdy(pipe_ready_p[2]),
        .o_data(ram_rdata)
    );

// ============== pipeline E0 ===============//
    assign  pipe_addr_p[0] = i_addr;
    assign  pipe_ins_p[0] = i_ins;
    assign  pipe_opcode_p[0] = i_opcode;

// =============== pipeline E1 ============= //

    always_ff @( posedge clk ) begin 
        if(~rstn) begin
            pipe_addr_p[1] <= {$clog2(DEPTH){1'b0}};
            pipe_ins_p[1] <= {DWIDTH{1'b0}};
            pipe_opcode_p[1] <= 1'b0;
        end
        else if(pipe_valid_p[0] && pipe_ready_p[0]) begin
            pipe_addr_p[1] <= pipe_addr_p[0];
            pipe_ins_p[1] <= pipe_ins_p[0];
            pipe_opcode_p[1] <= pipe_opcode_p[0];
        end
    end
    
// ================ pipeline E2 ================= //

    always_ff @(posedge clk) begin
        if(~rstn) begin
            pipe_addr_p[2] <= {$clog2(DEPTH){1'b0}}; 
            pipe_opcode_p[2] <= 'b0;
            pipe_ins_p[2] <= 'd0;
        end
        else if(pipe_valid_p[1] && pipe_ready_p[1]) begin
            pipe_addr_p[2] <= pipe_addr_p[1];
            pipe_opcode_p[2] <= pipe_opcode_p[1];
            pipe_ins_p[2] <= pipe_ins_p[1];
        end
    end

// ================= pipeline E3 ==================//

    always_ff @(posedge clk) begin
        if(~rstn) begin
            pipe_addr_p[3] <= {$clog2(DEPTH){1'b0}}; 
            pipe_opcode_p[3] <= 'b0;
            pipe_ins_p[3] <= 'd0;
            pipe_data_p3 <= 'd0;
        end
        else if(pipe_valid_p[2] && pipe_ready_p[2] && ~op_2cycle_block) begin
            pipe_addr_p[3] <= pipe_addr_p[2];
            pipe_opcode_p[3] <= pipe_opcode_p[2];
            pipe_ins_p[3] <= pipe_ins_p[2];
            pipe_data_p3 <= bypass_data_p2_s2;
        end
    end

// ==================== ALU ====================//

// 注意mux顺序，离P2最近的指令优先级最高
    assign  bypass_data_p2_s0 = bypass_to_p2[5] ? pipe_data_p5  :   ram_rdata;
    assign  bypass_data_p2_s1 = bypass_to_p2[4] ? alu_res       :   bypass_data_p2_s0;
    assign  bypass_data_p2_s2 = bypass_to_p2[3] ? alu_res_1cycle:   bypass_data_p2_s1;

// 反压控制由流水线完成，不用alu内部的流水线反压控制
    pipeline_alu #(DWIDTH) u_alu (
        .clk(clk),
        .rstn(rstn),

        .i_valid(pipe_valid_p[3]),
        .i_ready(),
        .i_opcode(pipe_opcode_p[3]),
        .a(pipe_data_p3),
        .b(pipe_ins_p[3]),

        .o_valid(),
        .o_ready(pipe_ready_p[4]),
        .c(alu_res),

        .c_1cycle(alu_res_1cycle)
    );


// ================= pipeline E4 ==================//

    always_ff @(posedge clk) begin
        if(~rstn) begin
            pipe_addr_p[4] <= {$clog2(DEPTH){1'b0}}; 
        end
        else if(pipe_valid_p[3] && pipe_ready_p[3]) begin
            pipe_addr_p[4] <= pipe_addr_p[3];
        end
    end

// ================= pipeline E5 ==================//

    always_ff @(posedge clk) begin
        if(~rstn) begin
            pipe_addr_p[5] <= {$clog2(DEPTH){1'b0}}; 
            pipe_data_p5 <= {DWIDTH{1'b0}};
        end
        else if(pipe_valid_p[4] && pipe_ready_p[4]) begin
            pipe_addr_p[5] <= pipe_addr_p[4];
            pipe_data_p5 <= alu_res;
        end
    end

// ============== output ================//

    assign  i_ready = pipe_ready_p[0];
    assign  o_valid = pipe_valid_p[PIPE_STAGE];
    assign  o_data  = pipe_data_p5;


endmodule