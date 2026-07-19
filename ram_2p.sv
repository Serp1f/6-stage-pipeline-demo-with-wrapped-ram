// 双端口ram，支持1读1写，读会有1个时钟延迟
module ram_2p #(
    parameter DEPTH = 32,
    parameter WIDTH = 32,
    parameter RAM_LAT = 1
) (
    input   clk,
    
    input   wen,
    input   [$clog2(DEPTH)-1:0] waddr,
    input   [WIDTH-1:0] wdata,

    input   ren,
    input   [$clog2(DEPTH)-1:0] raddr,
    output  [WIDTH-1:0] rdata
);

    logic   [DEPTH-1:0][WIDTH-1:0] mem;
    logic   [RAM_LAT:0]                 ren_p;
    logic   [RAM_LAT-1:0]               ren_p_tmp;
    logic   [RAM_LAT:0][WIDTH-1:0]      rdata_p;
    logic   [RAM_LAT-1:0][WIDTH-1:0]    rdata_p_tmp;

    always_ff @(posedge clk ) begin
        if(wen)
            mem[waddr] <= wdata;                    
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            ren_p_tmp[i] <= ren_p[i];
        end
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<RAM_LAT;i=i+1) begin
            if(ren_p[i])
                rdata_p_tmp[i] <= rdata_p[i];
        end
    end

    always_comb begin
        ren_p[0] = ren;
        rdata_p[0] = mem[raddr];
        for(int i=1;i<=RAM_LAT;i=i+1) begin
            ren_p[i] = ren_p_tmp[i-1];
            rdata_p[i] = rdata_p_tmp[i-1];
        end
    end
    
    assign rdata = rdata_p[RAM_LAT];
    
endmodule