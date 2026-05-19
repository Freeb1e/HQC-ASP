module block_ram_64bit #(
    parameter int BRAM_ID = 0 // 默认为 0
)(
    input  logic        clk,
    input  logic [31:0] raddr,
    input  logic [31:0] waddr,
    input  logic [63:0] wdata,
    input  logic [7:0]  wmask,
    input  logic        wen,
    output logic [63:0] rdata
);

    import "DPI-C" function void pmem_read(input int raddr, input int bramid ,output longint rdata);
    import "DPI-C" function void pmem_write(input int waddr, input int bramid,input longint wdata, input byte wmask);

    longint rdata_temp; 

    always @(posedge clk) begin
        if(wen) begin
            pmem_write(int'(waddr), BRAM_ID, longint'(wdata), byte'(wmask));
        end
        pmem_read(int'(raddr), BRAM_ID, rdata_temp);
        rdata <= rdata_temp;
    end

endmodule

module block_ram_128bit #(
    parameter int BRAM_ID = 0
)(
    input  logic         clk,
    input  logic [31:0]  raddr,
    input  logic [31:0]  waddr,
    input  logic [127:0] wdata,
    input  logic [15:0]  wmask,
    input  logic         wen,
    output logic [127:0] rdata
);

    logic [63:0] rdata_low;
    logic [63:0] rdata_high;
    logic [31:0] raddr_high;
    logic [31:0] waddr_high;

    assign raddr_high = raddr + 32'd8;
    assign waddr_high = waddr + 32'd8;

    block_ram_64bit #(
        .BRAM_ID(BRAM_ID)
    ) u_low_ram (
        .clk(clk),
        .raddr(raddr),
        .waddr(waddr),
        .wdata(wdata[63:0]),
        .wmask(wmask[7:0]),
        .wen(wen),
        .rdata(rdata_low)
    );

    block_ram_64bit #(
        .BRAM_ID(BRAM_ID)
    ) u_high_ram (
        .clk(clk),
        .raddr(raddr_high),
        .waddr(waddr_high),
        .wdata(wdata[127:64]),
        .wmask(wmask[15:8]),
        .wen(wen),
        .rdata(rdata_high)
    );

    assign rdata = {rdata_high, rdata_low};

endmodule
