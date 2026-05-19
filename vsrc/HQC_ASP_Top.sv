module HQC_ASP_Top (
        input logic clk,
        input logic rst_n,

        input logic [127:0] bram_dense_data,//dense polynomial
        output logic [15:0] bram_dense_addr,

        input logic [127:0] bram_sparse_data,//sparse polynomial(addrinput)
        output logic [15:0] bram_sparse_addr,

        input logic [127:0] bram_out_data,//output polynomial
        output logic [15:0] bram_out_addr,
        output logic [15:0] wmask,
        output logic wen,

        input logic [2:0] HQC_MODE,
        input logic start
    );

    parameter [8:0] n_HQC1 = 138 , n_HQC2 = 280 , n_HQC3 = 450;
    parameter [5:0] nmod_HQC1 = 5 , nmod_HQC2 = 11 , nmod_HQC3 = 37;
    parameter [7:0] weight_HQC1 = 66 , weight_HQC2 = 100, weight_HQC3 = 131;
    parameter [7:0] weight_re_HQC1 = 75 , weight_re_HQC2 = 114, weight_re_HQC3 = 149;

    logic [8:0] n;
    logic [5:0] nmod;
    logic [7:0] weight;

    typedef enum{
                IDLE,
                CALC
            }state_space;

    state_space current_state;
    logic calc_done;
    assign calc_done = 1'b0;

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_state <= IDLE;
        end
        else begin
            case(current_state)
                IDLE: begin
                    current_state <= (start)? CALC : IDLE;
                end
                CALC: begin
                    current_state <= (calc_done)? IDLE : CALC;
                end
            endcase
            ]
        end
    end

    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n      <= '0;
            nmod   <= '0;
            weight <= '0;
        end
        else if (current_state == IDLE) begin
            case (HQC_MODE[2:1])
                2'd1: begin
                    n      <= n_HQC1;
                    nmod   <= nmod_HQC1;
                    weight <= HQC_MODE[0] ? weight_re_HQC1 : weight_HQC1;
                end
                2'd2: begin
                    n      <= n_HQC2;
                    nmod   <= nmod_HQC2;
                    weight <= HQC_MODE[0] ? weight_re_HQC2 : weight_HQC2;
                end
                2'd3: begin
                    n      <= n_HQC3;
                    nmod   <= nmod_HQC3;
                    weight <= HQC_MODE[0] ? weight_re_HQC3 : weight_HQC3;
                end
                default: begin
                    n      <= '0;
                    nmod   <= '0;
                    weight <= '0;
                end
            endcase
        end
    end
    logic [7:0] weight_counter;
    logic [15:0] current_pos;
    logic pos_loaded;
    logic bitdone,bitinit;
    assign bram_sparse_addr = {7'd0, weight_counter[7:3], 4'b000};

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            weight_counter <= 8'd0;
            pos_loaded<=1'b1;
        end
        else begin
            if(bitdone && weight_counter < weight) begin
                weight_counter <= weight_counter + 8'd1;
                pos_loaded <= 1'b1;
                bitinit <=1'b1;
            end
        end
    end
    always_comb begin
        case (idx)
            3'd0:
                current_pos = bram_sparse_data[15:0];
            3'd1:
                current_pos = bram_sparse_data[31:16];
            3'd2:
                current_pos = bram_sparse_data[47:32];
            3'd3:
                current_pos = bram_sparse_data[63:48];
            3'd4:
                current_pos = bram_sparse_data[79:64];
            3'd5:
                current_pos = bram_sparse_data[95:80];
            3'd6:
                current_pos = bram_sparse_data[111:96];
            3'd7:
                current_pos = bram_sparse_data[127:112];
        endcase
    end
    logic [6:0] current_bias;
    logic [8:0] current_block;
    logic [127:0] polynomial_buffer_0,polynomial_buffer_1;
    logic [127:0] shifted_polynomial;
    logic block
    always_comb begin
        current_bias = current_pos[6:0];
        current_block = current_pos[15:7];
        bram_dense_addr = {current_block + block_counter, 7'b0};
        if(bram_dense_addr >n) begin
            bram_dense_addr = n - bram_dense_addr;
        end else begin
            bram_dense_addr = bram_dense_addr;
        end
    end

    always_comb begin
        shifted_polynomial = 
    end
    logic [8:0] block_counter;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            polynomial_buffer_0 <= 127'b0;
            polynomial_buffer_1 <= 127'b0;
        end
        else begin
            polynomial_buffer_0 <= bram_dense_data;
            polynomial_buffer_1 <= polynomial_buffer_0;
        end
    end
endmodule
