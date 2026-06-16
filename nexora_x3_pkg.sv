// nexora_x3_pkg
`timescale 1ns / 1ps

package nexora_x3_pkg;

    localparam DATA_WIDTH     = 64;
    localparam ADDR_WIDTH     = 64;
    localparam INSTR_WIDTH    = 32;
    localparam REG_ADDR_WIDTH = 5;
    localparam REG_COUNT      = 32;

    localparam IMEM_SIZE_BYTES  = 65536;   
    localparam DMEM_SIZE_BYTES  = 131072;  
    localparam IMEM_DEPTH       = IMEM_SIZE_BYTES / 4;  
    localparam DMEM_DEPTH       = DMEM_SIZE_BYTES / 4;  

    localparam logic [ADDR_WIDTH-1:0] BOOT_ROM_BASE    = 64'h0000_0000_0000_0000;
    localparam logic [ADDR_WIDTH-1:0] IMEM_BASE        = 64'h0000_0000_0001_0000;
    localparam logic [ADDR_WIDTH-1:0] DMEM_BASE        = 64'h0000_0000_0002_0000;
    localparam logic [ADDR_WIDTH-1:0] GPU_SMEM_BASE    = 64'h0000_0000_1000_0000;
    localparam logic [ADDR_WIDTH-1:0] TENSOR_BUF_BASE  = 64'h0000_0000_2000_0000;
    localparam logic [ADDR_WIDTH-1:0] UART_BASE        = 64'h0000_0000_8000_0000;
    localparam logic [ADDR_WIDTH-1:0] SPI_BASE         = 64'h0000_0000_8000_0100;
    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE        = 64'h0000_0000_8000_0200;
    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE       = 64'h0000_0000_8000_0300;
    localparam logic [ADDR_WIDTH-1:0] EXT_DRAM_BASE    = 64'h0000_0000_F000_0000;

    localparam PIPE_STAGES    = 5;
    localparam logic [ADDR_WIDTH-1:0] PC_RESET_VAL   = 64'h0000_0000_0001_0000;  

    typedef enum logic [6:0] {
        OP_R_TYPE   = 7'b0110011,  
        OP_I_TYPE   = 7'b0010011,  
        OP_LOAD     = 7'b0000011,  
        OP_STORE    = 7'b0100011,  
        OP_BRANCH   = 7'b1100011,  
        OP_LUI      = 7'b0110111,  
        OP_AUIPC    = 7'b0010111,  
        OP_JAL      = 7'b1101111,  
        OP_JALR     = 7'b1100111,  
        OP_SYSTEM   = 7'b1110011,  
        OP_FENCE    = 7'b0001111   
    } opcode_t;

    typedef enum logic [2:0] {
        F3_ADD_SUB = 3'b000,
        F3_SLL     = 3'b001,
        F3_SLT     = 3'b010,
        F3_SLTU    = 3'b011,
        F3_XOR     = 3'b100,
        F3_SRL_SRA = 3'b101,
        F3_OR      = 3'b110,
        F3_AND     = 3'b111
    } funct3_alu_t;

    typedef enum logic [2:0] {
        F3_BEQ  = 3'b000,
        F3_BNE  = 3'b001,
        F3_BLT  = 3'b100,
        F3_BGE  = 3'b101,
        F3_BLTU = 3'b110,
        F3_BGEU = 3'b111
    } funct3_branch_t;

    typedef enum logic [2:0] {
        F3_LB  = 3'b000,
        F3_LH  = 3'b001,
        F3_LW  = 3'b010,
        F3_LBU = 3'b100,
        F3_LHU = 3'b101
    } funct3_load_t;

    typedef enum logic [2:0] {
        F3_SB = 3'b000,
        F3_SH = 3'b001,
        F3_SW = 3'b010
    } funct3_store_t;

    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001,
        ALU_PASS_B = 4'b1010,  
        ALU_NOP  = 4'b1111
    } alu_op_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0] pc;
        logic [INSTR_WIDTH-1:0] instruction;
        logic                   valid;
    } if_id_reg_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]     pc;
        logic [INSTR_WIDTH-1:0]    instruction;
        logic [DATA_WIDTH-1:0]     rs1_data;
        logic [DATA_WIDTH-1:0]     rs2_data;
        logic [REG_ADDR_WIDTH-1:0] rs1_addr;
        logic [REG_ADDR_WIDTH-1:0] rs2_addr;
        logic [REG_ADDR_WIDTH-1:0] rd_addr;
        logic [DATA_WIDTH-1:0]     imm;
        alu_op_t                   alu_op;
        logic                      alu_src;      
        logic                      mem_read;
        logic                      mem_write;
        logic                      reg_write;
        logic                      branch;
        logic                      jump;
        logic                      is_jalr;
        logic [2:0]                funct3;
        logic                      valid;
    } id_ex_reg_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]     alu_result;
        logic [DATA_WIDTH-1:0]     rs2_data;     
        logic [REG_ADDR_WIDTH-1:0] rd_addr;
        logic                      mem_read;
        logic                      mem_write;
        logic                      reg_write;
        logic [2:0]                funct3;
        logic [DATA_WIDTH-1:0]     pc_plus4;     
        logic                      is_jump;      
        logic                      valid;
    } ex_mem_reg_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]     alu_result;
        logic [DATA_WIDTH-1:0]     mem_data;
        logic [REG_ADDR_WIDTH-1:0] rd_addr;
        logic                      reg_write;
        logic                      mem_read;     
        logic                      is_jump;      
        logic [DATA_WIDTH-1:0]     pc_plus4;
        logic                      valid;
    } mem_wb_reg_t;

    typedef struct packed {
        logic [3:0]  state;        
        logic [31:0] counter;      
        logic        valid;        
        logic        error;        
    } debug_signals_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]  pc;
        logic [INSTR_WIDTH-1:0] instruction;
        logic                   pipeline_stall;
        logic                   pipeline_flush;
        logic                   branch_taken;
        logic                   illegal_instr;
        logic [REG_ADDR_WIDTH-1:0] rd_addr;
        logic [DATA_WIDTH-1:0]  rd_data;
        logic                   rd_write;
    } cpu_debug_t;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] wdata;
        logic                  read_en;
        logic                  write_en;
        logic [7:0]            byte_en;   
    } mem_req_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0] rdata;
        logic                  ready;
        logic                  error;
    } mem_resp_t;

    localparam AXI_ADDR_WIDTH = 64;
    localparam AXI_DATA_WIDTH = 128; 
    localparam AXI_ID_WIDTH   = 4;
    localparam AXI_LEN_WIDTH  = 8;   
    localparam AXI_SIZE_WIDTH = 3;

    localparam NOC_FLIT_WIDTH  = 64;
    localparam NOC_ADDR_X_BITS = 2;
    localparam NOC_ADDR_Y_BITS = 2;
    localparam NOC_VC_COUNT    = 2;
    localparam NOC_BUFFER_DEPTH = 4;

    localparam GPU_NUM_WARPS       = 4;
    localparam GPU_THREADS_PER_WARP = 32;
    localparam GPU_SIMD_LANES      = 32;

    localparam TENSOR_ARRAY_DIM   = 8;   
    localparam TENSOR_DATA_WIDTH  = 8;   
    localparam TENSOR_ACC_WIDTH   = 32;  

    function automatic int clog2(input int value);
        int result;
        int v;

        begin
            result = 0;
            v = value - 1;

            while (v > 0) begin
                v = v >> 1;
                result = result + 1;
            end

            clog2 = result;
        end
    endfunction

    typedef struct packed {
        logic [DATA_WIDTH-1:0]     pc;
        logic [INSTR_WIDTH-1:0]    instruction;
        logic [DATA_WIDTH-1:0]     op_a;
        logic [DATA_WIDTH-1:0]     op_b;
        logic [REG_ADDR_WIDTH-1:0] rd_addr;
        logic                      reg_write;
        alu_op_t                   alu_op;
    } dispatch_packet_t;

    localparam NOC_X_MAX   = 4;
    localparam NOC_Y_MAX   = 4;
    localparam NOC_PAYLOAD = 32;

    typedef enum logic [2:0] {
        FLIT_HEAD  = 3'b001,
        FLIT_BODY  = 3'b010,
        FLIT_TAIL  = 3'b100
    } flit_type_t;

    typedef struct packed {
        flit_type_t             flit_type;
        logic [NOC_ADDR_X_BITS-1:0] dst_x;
        logic [NOC_ADDR_Y_BITS-1:0] dst_y;
        logic [NOC_ADDR_X_BITS-1:0] src_x;
        logic [NOC_ADDR_Y_BITS-1:0] src_y;
        logic [1:0]             vc_id;        
        logic [3:0]             msg_type;     
        logic [NOC_PAYLOAD-1:0] payload;
    } noc_flit_t;

    typedef enum logic [1:0] {
        DIR_NORTH = 2'd0,
        DIR_EAST  = 2'd1,
        DIR_SOUTH = 2'd2,
        DIR_WEST  = 2'd3
    } noc_dir_t;

    localparam ISSUE_WIDTH      = 4;
    localparam ALU_COUNT        = 16;
    localparam ROB_DEPTH        = 64;
    localparam QUEUE_DEPTH      = 16;

    localparam WARP_COUNT       = 4;
    localparam THREADS_PER_WARP = 32;
    localparam GPU_REG_COUNT    = 32;
    localparam GPU_SHARED_MEM_WORDS = 16384;

    typedef enum logic [3:0] {
        GPU_NOP    = 4'h0,
        GPU_IADD   = 4'h1,  
        GPU_IMUL   = 4'h2,  
        GPU_FADD   = 4'h3,  
        GPU_FMUL   = 4'h4,  
        GPU_LD     = 4'h5,  
        GPU_ST     = 4'h6,  
        GPU_LDS    = 4'h7,  
        GPU_STS    = 4'h8,  
        GPU_BAR    = 4'h9,  
        GPU_BRA    = 4'hA,  
        GPU_EXIT   = 4'hB,  
        GPU_PIM    = 4'hC   
    } gpu_op_t;

    typedef struct packed {
        gpu_op_t              op;
        logic [4:0]           rd;
        logic [4:0]           rs1;
        logic [4:0]           rs2;
        logic [15:0]          imm;
        logic                 valid;
    } gpu_instr_t;

    typedef enum logic [1:0] {
        WARP_IDLE     = 2'd0,
        WARP_RUNNING  = 2'd1,
        WARP_STALLED  = 2'd2,
        WARP_DONE     = 2'd3
    } warp_state_t;

    typedef struct packed {
        warp_state_t state;
        logic [31:0] pc;
        logic [31:0] active_mask;  
    } warp_t;

    typedef enum logic [1:0] {
        MESI_INVALID   = 2'b00,
        MESI_SHARED    = 2'b01,
        MESI_EXCLUSIVE = 2'b10,
        MESI_MODIFIED  = 2'b11
    } mesi_state_t;

    typedef enum logic [2:0] {
        COH_READ        = 3'h0,  
        COH_READ_EX     = 3'h1,  
        COH_INVALIDATE  = 3'h2,  
        COH_WB_DATA     = 3'h3,  
        COH_FETCH_INV   = 3'h4,  
        COH_UPGRADE     = 3'h5,  
        COH_DATA_RESP   = 3'h6,  
        COH_ACK         = 3'h7   
    } coh_msg_t;

    typedef struct packed {
        coh_msg_t             msg_type;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [3:0]           requester_id;  
    } coh_req_t;

    typedef struct packed {
        coh_msg_t             msg_type;
        logic [DATA_WIDTH-1:0] data;
        logic                 ack;
        logic [3:0]           ack_count;    
    } coh_resp_t;

    localparam TENSOR_DIM      = 8;

    localparam int NUM_CPU_CLUSTERS    = 4;
    localparam int NUM_GPU_CLUSTERS    = 8;
    localparam int NUM_TENSOR_CLUSTERS = 4;
    localparam TENSOR_IBITS    = 8;   
    localparam TENSOR_ABITS    = 32;  
    localparam WEIGHT_FIFO_D   = 16;
    localparam ACT_BUFFER_D    = 16;

    typedef enum logic [2:0] {
        TENS_NOP        = 3'h0,
        TENS_LOAD_W     = 3'h1,  
        TENS_LOAD_ACT   = 3'h2,  
        TENS_MATMUL     = 3'h3,  
        TENS_RELU       = 3'h4,  
        TENS_STORE_OUT  = 3'h5,  
        TENS_DONE       = 3'h6
    } tensor_op_t;

    typedef enum logic [2:0] {
        TENS_FSM_IDLE      = 3'd0,
        TENS_FSM_LOAD_W    = 3'd1,
        TENS_FSM_LOAD_ACT  = 3'd2,
        TENS_FSM_COMPUTE   = 3'd3,
        TENS_FSM_RELU      = 3'd4,
        TENS_FSM_STORE     = 3'd5,
        TENS_FSM_DRAIN     = 3'd6
    } tensor_fsm_t;

    localparam PIM_VECTOR_DEPTH  = 16;   

    typedef enum logic [2:0] {
        PIM_VEC_ADD  = 3'h0,  
        PIM_VEC_MUL  = 3'h1,  
        PIM_RELU     = 3'h2,  
        PIM_RED_SUM  = 3'h3,  
        PIM_VEC_MAC  = 3'h4   
    } pim_op_t;

    typedef struct packed {
        pim_op_t              op;
        logic [ADDR_WIDTH-1:0] addr_a;     
        logic [ADDR_WIDTH-1:0] addr_b;     
        logic [ADDR_WIDTH-1:0] addr_dst;   
    } pim_cmd_t;

    localparam LLC_SETS       = 256;
    localparam LLC_WAYS       = 4;
    localparam LLC_LINE_BYTES = 128;    
    localparam LLC_TOTAL_KB   = (LLC_SETS * LLC_WAYS * LLC_LINE_BYTES) / 1024;  

endpackage : nexora_x3_pkg
