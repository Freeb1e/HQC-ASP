module TEST_PLATFORM (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [2:0] HQC_MODE
);

    logic [127:0] dense_data;
    logic [15:0] dense_addr;

    logic [127:0] sparse_data;
    logic [15:0] sparse_addr;

    logic [127:0] out_rdata;
    logic [15:0] out_raddr;
    logic [127:0] out_wdata;
    logic [15:0] out_waddr;
    logic [15:0] out_wmask;
    logic out_wen;

    HQC_ASP_Top u_hqc_asp_top (
        .clk(clk),
        .rst_n(rst_n),

        .bram_dense_data(dense_data),
        .bram_dense_addr(dense_addr),

        .bram_sparse_data(sparse_data),
        .bram_sparse_addr(sparse_addr),

        .bram_out_data(out_rdata),
        .bram_out_addr(out_raddr),
        .bram_out_data_w(out_wdata),
        .bram_out_addr_w(out_waddr),
        .wmask(out_wmask),
        .wen(out_wen),

        .HQC_MODE(HQC_MODE),
        .start(start)
    );

    block_ram_128bit #(
        .BRAM_ID(0)
    ) u_dense_ram (
        .clk(clk),
        .raddr({16'd0, dense_addr}),
        .waddr(32'd0),
        .wdata(128'd0),
        .wmask(16'd0),
        .wen(1'b0),
        .rdata(dense_data)
    );

    block_ram_128bit #(
        .BRAM_ID(1)
    ) u_sparse_ram (
        .clk(clk),
        .raddr({16'd0, sparse_addr}),
        .waddr(32'd0),
        .wdata(128'd0),
        .wmask(16'd0),
        .wen(1'b0),
        .rdata(sparse_data)
    );

    block_ram_128bit #(
        .BRAM_ID(2)
    ) u_out_ram (
        .clk(clk),
        .raddr({16'd0, out_raddr}),
        .waddr({16'd0, out_waddr}),
        .wdata(out_wdata),
        .wmask(out_wmask),
        .wen(out_wen),
        .rdata(out_rdata)
    );

endmodule
