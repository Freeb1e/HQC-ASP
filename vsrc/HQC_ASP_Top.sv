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

        input logic weight_sel,
        input logic start
    );

    localparam [8:0] n    = 9'd138;
    localparam [5:0] nmod = 6'd5;
    localparam [7:0] WEIGHT_NORMAL = 8'd66;
    localparam [7:0] WEIGHT_RE     = 8'd75;

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
                OUT_PREFETCH_TAIL,
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

    logic [127:0] tail_buffer, head_buffer;
    logic [8:0] block_cnt;
    logic [8:0] result_cnt;
    logic [255:0] calc_buffer;
    logic bdbias;
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

    logic fast_next;
    assign fast_next = one_pos_done && (weight_cnt[2:0] != 3'd0);

    logic [8:0] pos_block_latched;
    logic       bdbias_latched;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos_block_latched <= '0;
            bdbias_latched    <= '0;
        end else if (out_state == OUT_LOAD_POS || out_state == OUT_PREFTCH_HEAD || fast_next) begin
            pos_block_latched <= current_pos_block;
            bdbias_latched    <= bdbias;
        end
    end

    logic [255:0] segB_upper;
    assign segB_upper = ({128'd0, head_buffer} << 5) | {128'd0, tail_buffer};

    localparam [127:0] nmod_mask = 128'h1F;

    logic [255:0] shifter_src;
    logic [7:0]   shifter_shift;
    logic [127:0] shifter_out;

    always_comb begin
        case (calc_state)
            CALC_SEG_A: begin
                shifter_src   = calc_buffer;
                shifter_shift = shift_amount;
            end
            CALC_SEG_B: begin
                shifter_src   = bdbias ? {segB_upper[127:0], bram_dense_data} : segB_upper;
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

    assign shifter_out = shifter_src[shifter_shift +: 128];
    logic start_oncepos;
    always_comb begin//bram_dense_addr
        bram_dense_addr = '0;
        case (out_state)
            OUT_IDLE: begin
                bram_dense_addr = block_cnt2addr(n);
            end
            OUT_PREFETCH_TAIL: begin
                bram_dense_addr = block_cnt2addr(9'd0);
            end
            OUT_PREFTCH_HEAD: begin
                bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias});
            end
            OUT_LOAD_POS: begin
                bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias});
            end
            OUT_CALC: begin
                if (fast_next)
                    bram_dense_addr = block_cnt2addr(n - current_pos_block - {8'd0, bdbias});
                else if (calc_state == CALC_IDLE)
                    bram_dense_addr = block_cnt2addr(n - pos_block_latched - {8'd0, bdbias_latched} + 9'd1);
                else if (calc_state == CALC_SEG_B && !pipe_ready)
                    bram_dense_addr = block_cnt2addr(n - 9'd1);
                else if (calc_state == CALC_SEG_A && pipe_ready && result_cnt == current_pos_block - 9'd1)
                    bram_dense_addr = block_cnt2addr(n - 9'd1);
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
                        out_state <= OUT_PREFETCH_TAIL;
                    end
                end
                OUT_PREFETCH_TAIL: begin
                    out_state <= OUT_PREFTCH_HEAD;
                    tail_buffer <= bram_dense_data;
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
                            end else if (weight_cnt[2:0] != 3'd0) begin
                                start_oncepos <= 1'b1;
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
                    pipe_ready <= 1'b0;
                    if (start_oncepos) begin
                        if (current_pos_block == 9'd0) begin
                            calc_state <= CALC_SEG_B;
                            result_cnt <= '0;
                        end else begin
                            calc_state <= CALC_SEG_A;
                            block_cnt <= n - pos_block_latched - {8'd0, bdbias_latched} + 9'd2;
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
                            block_cnt <= 9'd1;
                        end
                    end else begin
                        pipe_ready <= 1'b1;
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
                            pipe_ready <= 1'b0;
                            one_pos_done <= 1'b1;
                            weight_cnt <= weight_cnt + 8'd1;
                        end else begin
                            calc_state <= CALC_SEG_C;
                            pipe_ready <= 1'b0;
                            calc_buffer <= {head_buffer, 128'd0};
                            block_cnt <= 9'd2;
                        end
                    end else begin
                        pipe_ready <= 1'b1;
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
                            pipe_ready <= 1'b0;
                            one_pos_done <= 1'b1;
                            weight_cnt <= weight_cnt + 8'd1;
                        end
                    end else begin
                        pipe_ready <= 1'b1;
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
    assign current_pos = bram_sparse_data[weight_idx*16 +: 16];

    

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight <= '0;
        end
        else if (out_state == OUT_IDLE) begin
            weight <= weight_sel ? WEIGHT_RE : WEIGHT_NORMAL;
        end
    end
endmodule
