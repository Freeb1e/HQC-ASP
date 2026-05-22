module HQC_ASP_Top (
        input logic clk,
        input logic rst_n,

        input logic [127:0] bram_dense_data,//dense polynomial
        output logic [15:0] bram_dense_addr,

        input logic [127:0] bram_sparse_data,//sparse polynomial(addrinput)
        output logic [15:0] bram_sparse_addr,

        input logic [127:0] bram_out_data,//output polynomial
        output logic [15:0] bram_out_addr,
        output logic [127:0] bram_out_data_w,
        output logic [15:0] bram_out_addr_w,

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

    function automatic logic [15:0] block_cnt2addr(
        input logic [8:0] block_cnt
    );
        begin
            block_cnt2addr = {3'b000, block_cnt, 4'b0000};
        end
    endfunction

    typedef enum logic [2:0] {
                OUT_IDLE,
                OUT_START,
                OUT_PREFETCH_TAIL_1,
                OUT_PREFETCH_TAIL_2,
                OUT_PREFTCH_HEAD,
                OUT_LOAD_POS,
                OUT_CALC
            } state_space_1;

    state_space_1 out_state;

    typedef enum logic [1:0] {
            CALC_IDLE,
            CALC_SEG_A,
            CALC_SEG_B,
            CALC_SEG_C
            } state_space_2;

    state_space_2 calc_state;

    logic [127:0] tail_buffer_1, tail_buffer_2, head_buffer;
    logic [8:0] block_cnt;
    logic [8:0] result_cnt;
    logic [255:0] calc_buffer;
    logic bdbias;
    logic pipe_fill;
    logic pipe_ready;
    logic one_pos_done;
    logic [15:0] current_pos;
    logic [6:0] current_pos_mod;
    logic [8:0] current_pos_block;
    logic [7:0] shift_amount;
    logic [7:0] shift_amount_C;

    assign current_pos_mod = current_pos[6:0];
    assign current_pos_block = current_pos[15:7];
    assign bdbias = (current_pos_mod > {1'b0, nmod}) ? 1'b1 : 1'b0;
    assign shift_amount = bdbias ? (8'd128 + {2'd0, nmod} - {1'b0, current_pos_mod}): ({2'd0, nmod} - {1'b0, current_pos_mod});
    assign shift_amount_C = 8'd128 - {1'b0, current_pos_mod};

    // Strategy 2: fixed nmod shift replaces variable barrel shifter
    logic [255:0] segB_upper;
    always_comb begin
        case (nmod)
            6'd5:    segB_upper = ({128'd0, head_buffer} << 5)  | {128'd0, tail_buffer_2};
            6'd11:   segB_upper = ({128'd0, head_buffer} << 11) | {128'd0, tail_buffer_2};
            6'd37:   segB_upper = ({128'd0, head_buffer} << 37) | {128'd0, tail_buffer_2};
            default: segB_upper = {128'd0, tail_buffer_2};
        endcase
    end

    // Strategy 2: precomputed nmod mask
    logic [127:0] nmod_mask;
    always_comb begin
        case (nmod)
            6'd5:    nmod_mask = 128'h1F;
            6'd11:   nmod_mask = 128'h7FF;
            6'd37:   nmod_mask = 128'h1FFFFFFFFF;
            default: nmod_mask = '0;
        endcase
    end

    // Strategy 1: single shared 256-bit barrel shifter for SEG_A/B/C
    // Pipeline: register inputs to break critical path
    logic [255:0] shifter_src;
    logic [7:0]   shifter_shift;
    logic [255:0] shifter_src_reg;
    logic [7:0]   shifter_shift_reg;
    logic [127:0] shifter_out;

    always_comb begin
        case (calc_state)
            CALC_SEG_A: begin
                shifter_src   = calc_buffer;
                shifter_shift = shift_amount;
            end
            CALC_SEG_B: begin
                shifter_src   = bdbias ? {segB_upper[127:0], tail_buffer_1} : segB_upper;
                shifter_shift = shift_amount;
            end
            CALC_SEG_C: begin
                shifter_src   = calc_buffer;
                shifter_shift = shift_amount_C;
            end
            default: begin
                shifter_src   = calc_buffer;
                shifter_shift = '0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        shifter_src_reg   <= shifter_src;
        shifter_shift_reg <= shifter_shift;
    end
    assign shifter_out =  [shifter_shift_reg +: 128];
    logic start_oncepos;
    always_comb begin//bram_dense_addr
        bram_dense_addr = '0;
        case (out_state)
            OUT_IDLE: begin
                bram_dense_addr = block_cnt2addr(n - 9'd1);
            end
            OUT_PREFETCH_TAIL_1: begin
                bram_dense_addr = block_cnt2addr(n);
            end
            OUT_PREFETCH_TAIL_2: begin
                bram_dense_addr = block_cnt2addr(9'd0);
            end
            OUT_PREFTCH_HEAD: begin
                bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias});
            end
            OUT_LOAD_POS: begin
                bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias});
            end
            OUT_CALC: begin
                if (calc_state == CALC_IDLE)
                    bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias} + 9'd1);
                else
                    bram_dense_addr = block_cnt2addr(block_cnt);
            end
            default: begin
                bram_dense_addr = '0;
            end
        endcase
    end
    

    always_comb begin//bram_out_addr (read side, aligned with pipeline)
        bram_out_addr = '0;
        case (calc_state)
            CALC_IDLE: begin
                bram_out_addr = block_cnt2addr(9'd0);
            end
            CALC_SEG_A: begin
                bram_out_addr = pipe_ready ? block_cnt2addr(result_cnt + 9'd1) : block_cnt2addr(result_cnt);
            end
            CALC_SEG_B: begin
                bram_out_addr = block_cnt2addr(current_pos_block);
            end
            CALC_SEG_C: begin
                bram_out_addr = pipe_ready ? block_cnt2addr(result_cnt + 9'd1) : block_cnt2addr(result_cnt);
            end
            default: begin
                bram_out_addr = '0;
            end
        endcase
    end
    always_ff@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_state <= OUT_IDLE;
            start_oncepos <= 1'b0;
        end
        else begin
            case (out_state)
                OUT_IDLE: begin
                    if (start) begin
                        out_state <= OUT_PREFETCH_TAIL_1;
                    end
                end
                OUT_PREFETCH_TAIL_1: begin
                    out_state <= OUT_PREFETCH_TAIL_2;
                    tail_buffer_1 <= bram_dense_data;
                end
                OUT_PREFETCH_TAIL_2: begin
                    out_state <= OUT_PREFTCH_HEAD;
                    tail_buffer_2 <= bram_dense_data;
                end
                OUT_PREFTCH_HEAD: begin
                    out_state <= OUT_CALC;
                    head_buffer <= bram_dense_data;
                    start_oncepos <= 1'b1;
                end
                OUT_CALC: begin
                        if (one_pos_done) begin
                            if (weight_cnt >= weight) begin
                                out_state <= OUT_IDLE;
                            end else begin
                                out_state <= OUT_LOAD_POS;
                            end
                        end else begin
                            start_oncepos <= 1'b0;
                        end
                end
                OUT_LOAD_POS: begin
                    out_state <= OUT_CALC;
                    start_oncepos <= 1'b1;
                end
                default: begin
                    out_state <= OUT_IDLE;
                end
            endcase
        end
    end

    always_ff@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_state <= CALC_IDLE;
            calc_buffer <= '0;
            block_cnt <= '0;
            result_cnt <= '0;
            pipe_fill <= 1'b0;
            pipe_ready <= 1'b0;
            wen <= 1'b0;
            one_pos_done <= 1'b0;
            weight_cnt <= '0;
        end
        else begin
            if(one_pos_done)
                one_pos_done <= 1'b0;
            if(out_state == OUT_IDLE)
                weight_cnt <= '0;

            case (calc_state)
                CALC_IDLE: begin
                    wen <= 1'b0;
                    pipe_fill <= 1'b0;
                    pipe_ready <= 1'b0;
                    if (start_oncepos) begin
                        if (current_pos_block == 9'd0) begin
                            calc_state <= CALC_SEG_B;
                            result_cnt <= '0;
                        end else begin
                            calc_state <= CALC_SEG_A;
                            block_cnt <= n - current_pos_block - {8'd0, bdbias} + 9'd2;
                            result_cnt <= '0;
                            calc_buffer <= {bram_dense_data, calc_buffer[255:128]};
                        end
                    end
                end
                CALC_SEG_A: begin
                    calc_buffer <= {bram_dense_data, calc_buffer[255:128]};
                    block_cnt <= block_cnt + 9'd1;

                    if (pipe_ready) begin
                        bram_out_data_w <= shifter_out ^ bram_out_data;
                        bram_out_addr_w <= block_cnt2addr(result_cnt);
                        wen <= 1'b1;
                        result_cnt <= result_cnt + 9'd1;
                        if (result_cnt == current_pos_block - 9'd1) begin
                            calc_state <= CALC_SEG_B;
                            pipe_fill <= 1'b0;
                            pipe_ready <= 1'b0;
                        end
                    end else if (pipe_fill) begin
                        pipe_ready <= 1'b1;
                        wen <= 1'b0;
                    end else begin
                        pipe_fill <= 1'b1;
                        wen <= 1'b0;
                    end
                end
                CALC_SEG_B: begin
                    if (pipe_ready) begin
                        if (current_pos_block == n)
                            bram_out_data_w <= (shifter_out ^ bram_out_data) & nmod_mask;
                        else
                            bram_out_data_w <= shifter_out ^ bram_out_data;
                        bram_out_addr_w <= block_cnt2addr(current_pos_block);
                        wen <= 1'b1;
                        result_cnt <= result_cnt + 9'd1;
                        if (current_pos_block >= n) begin
                            calc_state <= CALC_IDLE;
                            pipe_fill <= 1'b0;
                            pipe_ready <= 1'b0;
                            one_pos_done <= 1'b1;
                            weight_cnt <= weight_cnt + 8'd1;
                        end else begin
                            calc_state <= CALC_SEG_C;
                            pipe_fill <= 1'b0;
                            pipe_ready <= 1'b0;
                            calc_buffer <= {head_buffer, 128'd0};
                            block_cnt <= 9'd2;
                        end
                    end else if (pipe_fill) begin
                        pipe_ready <= 1'b1;
                        wen <= 1'b0;
                    end else begin
                        pipe_fill <= 1'b1;
                        wen <= 1'b0;
                        block_cnt <= 9'd1;
                    end
                end
                CALC_SEG_C: begin
                    calc_buffer <= {bram_dense_data, calc_buffer[255:128]};
                    block_cnt <= block_cnt + 9'd1;

                    if (pipe_ready) begin
                        if (result_cnt == n)
                            bram_out_data_w <= (shifter_out ^ bram_out_data) & nmod_mask;
                        else
                            bram_out_data_w <= shifter_out ^ bram_out_data;
                        bram_out_addr_w <= block_cnt2addr(result_cnt);
                        wen <= 1'b1;
                        result_cnt <= result_cnt + 9'd1;
                        if (result_cnt == n) begin
                            calc_state <= CALC_IDLE;
                            pipe_fill <= 1'b0;
                            pipe_ready <= 1'b0;
                            one_pos_done <= 1'b1;
                            weight_cnt <= weight_cnt + 8'd1;
                        end
                    end else if (pipe_fill) begin
                        pipe_ready <= 1'b1;
                        wen <= 1'b0;
                    end else begin
                        pipe_fill <= 1'b1;
                        wen <= 1'b0;
                    end
                end
            endcase
        end
    end

    assign wmask = 16'hFFFF;

    logic [2:0] weight_idx;
    logic [7:0] weight_cnt;
    assign weight_idx = weight_cnt[2:0];
    assign bram_sparse_addr = {7'd0, weight_cnt[7:3], 4'b0000};
    always_comb begin
        case (weight_idx)
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

    

        always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n      <= '0;
            nmod   <= '0;
            weight <= '0;
        end
        else if (out_state == OUT_IDLE) begin
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
endmodule
