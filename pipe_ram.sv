module pipe_ram #(
    parameter   DEPTH = 32,
    parameter   DWIDTH = 16,
    parameter   RAM_LAT = 2
)(
    input   clk,
    input   rstn,

    input   wen,
    input   [$clog2(DEPTH)-1:0] waddr,
    input   [DWIDTH-1:0] wdata,

    input   i_vld,
    output  i_rdy,
    input   [$clog2(DEPTH)-1:0] i_addr,

    output  o_vld,
    input   o_rdy,
    output  logic   [DWIDTH-1:0] o_data
);

    localparam  AWIDTH = $clog2(DEPTH);
    logic   ren;

    logic   [RAM_LAT:0]                 ren_p;
    logic   [RAM_LAT-1:0]               ren_p_tmp;
    logic   [RAM_LAT:0][AWIDTH-1:0]     raddr_p;
    logic   [RAM_LAT-1:0][AWIDTH-1:0]   raddr_p_tmp;

    logic   [RAM_LAT:0]     valid_p;
    logic   [RAM_LAT-1:0]   valid_p_tmp;
    logic   [RAM_LAT:0]     ready_p;

    logic   [RAM_LAT:0][AWIDTH-1:0]     pipe_addr_p;
    logic   [RAM_LAT-1:0][AWIDTH-1:0]   pipe_addr_p_tmp;
    logic   [RAM_LAT:0][DWIDTH-1:0]     pipe_data_p;
    logic   [RAM_LAT-1:0][DWIDTH-1:0]   pipe_data_p_tmp;
    logic   [RAM_LAT:0][1:0]            pipe_dready_p;
    logic   [RAM_LAT-1:0][1:0]          pipe_dready_p_tmp;
    logic   dready_next;

    logic   [RAM_LAT:0]         raddr_match;
    logic   [RAM_LAT:0]         waddr_match;
    logic   [RAM_LAT-1:0]       bypass_to_p0;
    logic   [RAM_LAT:0][1:0]    mux_sel_p;

    logic   [DEPTH-1:0]     addr_accessed;
    logic   ram_wen;
    logic   [AWIDTH-1:0]    ram_waddr;
    logic   [DWIDTH-1:0]    ram_wdata;

    logic   ram_ren;
    logic   [AWIDTH-1:0]    ram_raddr;
    logic   [DWIDTH-1:0]    ram_rdata;

// ================== pipeline valid ===================//

    assign  valid_p = {valid_p_tmp,i_vld};
    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn) 
                valid_p_tmp[i] <= 1'b0;
            else if(ready_p[i])
                valid_p_tmp[i] <= valid_p[i];
        end
    end

    always_comb begin
        ready_p[RAM_LAT] = o_rdy;
        for(int i=RAM_LAT-1;i>=0;i=i-1) begin
            ready_p[i] = ready_p[i+1] | ~valid_p[i+1];
        end 
    end

// =================== un-backpress-able pipeline =================== //


    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn)   
                ren_p_tmp[i] <= 1'b0;
            else
                ren_p_tmp[i] <= ren_p[i];
        end
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                raddr_p_tmp[i] <= 'd0;
            else if(ren_p[i])
                raddr_p_tmp[i] <= raddr_p[i];
        end
    end

    always_comb begin
        ren_p[0] = ram_ren;
        raddr_p[0] = ram_raddr;
        for(int i=1;i<=RAM_LAT;i=i+1) begin
            ren_p[i] = ren_p_tmp[i-1];
            raddr_p[i] = raddr_p_tmp[i-1];
        end
    end
// ==================== backpress-able pipeline =================== //

    always_comb begin
        pipe_addr_p[0] = i_addr;
        for(int i=1;i<=RAM_LAT;i=i+1) begin
            pipe_addr_p[i] = pipe_addr_p_tmp[i-1];
        end
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                pipe_addr_p_tmp[i] <= 'd0;
            else if(valid_p[i] && ready_p[i])
                pipe_addr_p_tmp[i] <= pipe_addr_p[i];    
        end
    end

    always_comb begin
        pipe_data_p[0] = 'd0;
        for(int i=1;i<=RAM_LAT;i=i+1) begin
            pipe_data_p[i] = pipe_data_p_tmp[i-1];
        end
        for(int i=RAM_LAT-1;i>=0;i=i-1) begin   // 隐含优先级p1>p2>...>pN
            if(bypass_to_p0[i])
                pipe_data_p[0] = pipe_data_p[i+1];
        end
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                pipe_data_p_tmp[i] <= 'd0;
            // 流水线前进时，使用前一级的mux_sel更新
            else if(valid_p[i] && ready_p[i]) begin
                case(mux_sel_p[i])
                2'd0:   pipe_data_p_tmp[i] <= pipe_data_p[i]; 
                2'd1:   pipe_data_p_tmp[i] <= ram_rdata;    // 从RAM读出数据，并且地址匹配，更新data
                2'd2:   pipe_data_p_tmp[i] <= wdata;        // 向RAM写入数据，并且地址匹配，更新data
                default:    pipe_data_p_tmp[i] <= pipe_data_p_tmp[i];
                endcase
            end
            // 流水线不前进时，使用这一级的mux_sel更新
            else if(valid_p[i+1] && ~ready_p[i+1]) begin
                case(mux_sel_p[i+1])
                2'd1:   pipe_data_p_tmp[i] <= ram_rdata;    // 从RAM读出数据，并且地址匹配，更新data
                2'd2:   pipe_data_p_tmp[i] <= wdata;    // 向RAM写入数据，并且地址匹配，更新data
                default:    pipe_data_p_tmp[i] <= pipe_data_p_tmp[i];
                endcase
            end
        end
    end
  
    always_comb begin
        pipe_dready_p[0] = 1'b0;
        for(int i=1;i<=RAM_LAT;i=i+1) begin
            pipe_dready_p[i] = pipe_dready_p_tmp[i-1];
        end
        for(int i=RAM_LAT-1;i>=0;i=i-1) begin   // 隐含优先级p1>p2>...>pN
            if(bypass_to_p0[i])
                pipe_dready_p[0] = pipe_dready_p[i+1];
        end
        if(~addr_accessed[i_addr])  // 如果该地址未被访问，则不读取该地址，并且认为数据也是有效的
            pipe_dready_p[0] = 2'b01;
    end
    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                pipe_dready_p_tmp[i] <= 'd0;
            // 流水线前进时，使用前一级的mux_sel更新
            else if(valid_p[i] && ready_p[i]) begin
                case(mux_sel_p[i])
                2'd0:   pipe_dready_p_tmp[i] <= pipe_dready_p[i]; 
                2'd1:   pipe_dready_p_tmp[i] <= 2'b01;    // 从RAM读出数据，并且地址匹配，更新data，标记数据已准备好
                2'd2:   pipe_dready_p_tmp[i] <= 2'b10;    // 向RAM写入数据，并且地址匹配，更新data，标记数据已准备好
                default:    pipe_dready_p_tmp[i] <= pipe_dready_p_tmp[i];
                endcase
            end
            // 流水线不前进时，使用这一级的mux_sel更新
            else if(valid_p[i+1] && ~ready_p[i+1]) begin
                case(mux_sel_p[i+1])
                2'd1:   pipe_dready_p_tmp[i] <= 2'b01;  // 从RAM读出数据，并且地址匹配，更新data，标记数据已准备好
                2'd2:   pipe_dready_p_tmp[i] <= 2'b10;  // 向RAM写入数据，并且地址匹配，更新data，标记数据已准备好
                default:    pipe_dready_p_tmp[i] <= pipe_dready_p_tmp[i];
                endcase
            end
        end
    end

    always_comb begin
        if(valid_p[RAM_LAT]) begin
            dready_next = (raddr_match[RAM_LAT] | waddr_match[RAM_LAT]) ? 1'b1 : |pipe_dready_p[RAM_LAT];
        end
        else 
            dready_next = 1'b0;
    end

// ===================== bypass & update check ========================= //

    always_comb begin
        for(int i=0;i<=RAM_LAT;i=i+1) begin
            if(valid_p[i] && ren_p[RAM_LAT])
                raddr_match[i] = pipe_addr_p[i] == raddr_p[RAM_LAT];
            else 
                raddr_match[i] = 1'b0; 
        end
    end

    always_comb begin
        for(int i=0;i<=RAM_LAT;i=i+1) begin
            if(valid_p[i] && wen) 
                waddr_match[i] = pipe_addr_p[i] == waddr;
            else    
                waddr_match[i] = 1'b0;
        end
    end

    always_comb begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(valid_p[0] && valid_p[i+1])
                bypass_to_p0[i] = i_addr == pipe_addr_p[i+1];
            else 
                bypass_to_p0[i] = 1'b0;
        end
    end

    always_comb begin
        for(int i=0;i<=RAM_LAT;i=i+1) begin
            if(waddr_match[i])  // 写入的优先级最高
                mux_sel_p[i] = 4'd2;
            else if(raddr_match[i] && ~pipe_dready_p[i][1]) // 没有被写入更新
                mux_sel_p[i] = 4'd1;
            else 
                mux_sel_p[i] = 4'd0;
        end
    end

// ======================== RAM =============================//
    assign  ram_wen = wen;
    assign  ram_waddr  = waddr;
    assign  ram_wdata = wdata;

// 当流水线能够接收数据，并且流水线内无匹配的地址，并且该地址已经被访问（数据是有效的），才能读ram
    assign  ram_ren = i_vld && i_rdy && (~|bypass_to_p0) && addr_accessed[i_addr];
    assign  ram_raddr = i_addr;

    ram_2p #(DEPTH,DWIDTH,RAM_LAT)   u_ram
    (
        .clk(clk),
        
        .wen(ram_wen),
        .waddr(ram_waddr),
        .wdata(ram_wdata),
        .ren(ram_ren),
        .raddr(ram_raddr),
        .rdata(ram_rdata)
    );

// ================= ram_accessed ====================== //

    logic [DEPTH-1:0] addr_accessed_set_mask;
    assign  addr_accessed_set_mask = 1 << i_addr;
    always_ff @(posedge clk ) begin
        if(~rstn)
            addr_accessed <= {DEPTH{1'b0}};
        else if(valid_p[0] && ready_p[0])
            addr_accessed <= addr_accessed | addr_accessed_set_mask;
    end

// ========================= output ======================//


    assign  i_rdy = ready_p[0];
    assign  o_vld = valid_p[RAM_LAT] && dready_next;
    assign  o_data = (waddr_match[RAM_LAT]) ? wdata : 
                     (raddr_match[RAM_LAT] && ~pipe_dready_p[RAM_LAT][1]) ? ram_rdata : pipe_data_p[RAM_LAT];

endmodule