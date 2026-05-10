/*
 * HW3: 5-Stage Pipelined RISC-V Processor 
 * Author: Mustafa Talha Gezer
 */

module riscv_multicycle import riscv_pkg::*; #(
    parameter DMemInitFile = "dmem.mem",
    parameter IMemInitFile = "imem.mem"
) (
    input  logic              clk_i,
    input  logic              rstn_i,
    input  logic [XLEN-1:0]   addr_i,
    
    output logic              update_o,
    output logic [XLEN-1:0]   data_o,
    output logic [XLEN-1:0]   pc_o,
    output logic [XLEN-1:0]   instr_o,
    output logic [4:0]        reg_addr_o,
    output logic [XLEN-1:0]   reg_data_o,
    output logic [XLEN-1:0]   mem_addr_o,
    output logic [XLEN-1:0]   mem_data_o,
    output logic              mem_wrt_o,

    output logic [XLEN-1:0]   fetch_id_o,      output logic fetch_valid_o,
    output logic [XLEN-1:0]   decode_id_o,     output logic decode_valid_o,
    output logic [XLEN-1:0]   execute_id_o,    output logic execute_valid_o,
    output logic [XLEN-1:0]   mem_id_o,        output logic mem_valid_o,
    output logic [XLEN-1:0]   writeback_id_o,  output logic writeback_valid_o
);

    logic [XLEN-1:0] instr_mem [0:2047];
    logic [XLEN-1:0] data_mem  [0:2047];
    logic [XLEN-1:0] next_instr_id;

    initial begin
        $readmemh(IMemInitFile, instr_mem, 0, 2047);
        $readmemh(DMemInitFile, data_mem, 0, 2047);
    end

    assign data_o = data_mem[addr_i[12:2]];

    logic stall, flush;

    // --- 3. FETCH (FE) STAGE ---
    logic [XLEN-1:0] fe_pc, fe_instr;
    logic [31:0] branch_target_ex; 
    
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            fe_pc <= 32'h80000000;
            next_instr_id <= 32'd1;
        end else if (flush) begin // FLUSH önceliği STALL'dan yüksektir!
            fe_pc <= branch_target_ex;
        end else if (!stall) begin
            fe_pc <= fe_pc + 4;
            if (fetch_valid_o) next_instr_id <= next_instr_id + 1;
        end
    end
    
    assign fe_instr = instr_mem[fe_pc[12:2]];
    assign fetch_id_o = (rstn_i) ? next_instr_id : 32'b0;
    assign fetch_valid_o = rstn_i && !stall && !flush;

    // --- 4. IF/ID PIPELINE REGISTER ---
    logic [XLEN-1:0] dec_pc, dec_instr, dec_id;
    logic dec_valid;

    always_ff @(posedge clk_i) begin
        if (!rstn_i || flush) begin
            dec_instr <= 32'b0;
            dec_valid <= 1'b0;
            dec_id    <= 32'b0;
        end else if (!stall) begin
            dec_pc    <= fe_pc;
            dec_instr <= fe_instr;
            dec_id    <= fetch_id_o;
            dec_valid <= fetch_valid_o;
        end
    end

    // --- 5. DECODE (DEC) STAGE ---
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] imm, rs1_data, rs2_data;
    logic        reg_we, alu_src, pc_to_alu, mem_we, branch, jump, jalr_w; 
    logic [1:0]  wb_sel;
    logic [3:0]  alu_ctrl;
    logic [2:0]  branch_type; 

    decoder u_decoder (
        .clk_i(clk_i), .instr_i(dec_instr),
        .rs1_addr_o(rs1_addr), .rs2_addr_o(rs2_addr), .rd_addr_o(rd_addr),
        .imm_o(imm), .reg_we_o(reg_we), .alu_src_o(alu_src), .pc_to_alu_o(pc_to_alu),
        .alu_ctrl_o(alu_ctrl), .mem_we_o(mem_we), .wb_sel_o(wb_sel),
        .branch_o(branch), .jump_o(jump), .jalr_o(jalr_w), 
        .branch_type_o(branch_type)
    );

    logic wb_reg_we, wb_valid;
    logic [4:0] wb_rd_addr;
    logic [31:0] wb_data;

    register_file u_regfile (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .we_i(wb_reg_we && wb_valid), 
        .rs1_addr_i(rs1_addr), .rs2_addr_i(rs2_addr),
        .rd_addr_i(wb_rd_addr), .rd_data_i(wb_data),
        .rs1_data_o(rs1_data), .rs2_data_o(rs2_data)
    );

    assign decode_id_o = dec_id;
    assign decode_valid_o = dec_valid;

    // --- 6. ID/EX PIPELINE REGISTER ---
    logic [XLEN-1:0] ex_pc, ex_imm, ex_rs1_data, ex_rs2_data, ex_id, ex_instr;
    logic [4:0]  ex_rd_addr, ex_rs1_addr, ex_rs2_addr;
    logic [3:0]  ex_alu_ctrl;
    logic [1:0]  ex_wb_sel;
    logic [2:0]  ex_branch_type;
    logic        ex_reg_we, ex_alu_src, ex_pc_to_alu, ex_mem_we, ex_branch, ex_jump, ex_jalr, ex_valid;

    always_ff @(posedge clk_i) begin
        if (!rstn_i || flush || stall) begin 
            ex_valid <= 1'b0;
            ex_reg_we <= 1'b0;
            ex_mem_we <= 1'b0;
            ex_branch <= 1'b0;
            ex_jump <= 1'b0;
            ex_jalr <= 1'b0;
            ex_instr <= 32'b0;
        end else begin
            ex_pc <= dec_pc; ex_imm <= imm; ex_rs1_data <= rs1_data; ex_rs2_data <= rs2_data;
            ex_rd_addr <= rd_addr; ex_rs1_addr <= rs1_addr; ex_rs2_addr <= rs2_addr;
            ex_alu_ctrl <= alu_ctrl; ex_wb_sel <= wb_sel; ex_reg_we <= reg_we;
            ex_alu_src <= alu_src; ex_pc_to_alu <= pc_to_alu; ex_mem_we <= mem_we;
            ex_branch <= branch; ex_jump <= jump; ex_jalr <= jalr_w; 
            ex_branch_type <= branch_type; ex_instr <= dec_instr;
            ex_id <= dec_id; ex_valid <= dec_valid;
        end
    end

    // --- 7. EXECUTE (EXE) STAGE ---
    logic [31:0] alu_a, alu_b, alu_res, ex_result;
    logic unused_zero; 
    
    assign alu_a = ex_pc_to_alu ? ex_pc : ex_rs1_data;
    assign alu_b = ex_alu_src ? ex_imm : ex_rs2_data;

    alu u_alu (
        .a_i(alu_a), .b_i(alu_b), .alu_ctrl_i(ex_alu_ctrl),
        .res_o(alu_res), .zero_o(unused_zero) 
    );

    // LUI çözümü: Eğer wb_sel 11 ise (LUI), IMM değerini ALU sonucunu ezip direkt aktar
    assign ex_result = (ex_wb_sel == 2'b11) ? ex_imm : alu_res;

    logic branch_taken;
    always_comb begin
        branch_taken = 1'b0;
        if (ex_branch) begin
            case (ex_branch_type)
                3'b100: branch_taken = (ex_rs1_data == ex_rs2_data);
                3'b101: branch_taken = (ex_rs1_data != ex_rs2_data);
                3'b000: branch_taken = (ex_rs1_data >= ex_rs2_data);
                3'b001: branch_taken = (ex_rs1_data <  ex_rs2_data);
                3'b010: branch_taken = ($signed(ex_rs1_data) >= $signed(ex_rs2_data));
                3'b011: branch_taken = ($signed(ex_rs1_data) <  $signed(ex_rs2_data));
                default: branch_taken = 1'b0;
            endcase
        end
    end

    assign branch_target_ex = ex_jalr ? ((ex_rs1_data + ex_imm) & ~32'b1) : (ex_pc + ex_imm);

    assign execute_id_o = ex_id;
    assign execute_valid_o = ex_valid;

    // --- 8. EX/MEM PIPELINE REGISTER ---
    logic [XLEN-1:0] mem_pc, mem_alu_res, mem_rs2_data, mem_id_reg, mem_instr_reg;
    logic [4:0]  mem_rd_addr_reg;
    logic [1:0]  mem_wb_sel_reg;
    logic        mem_reg_we_reg, mem_mem_we_reg, mem_valid_reg;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            mem_valid_reg <= 1'b0;
            mem_reg_we_reg <= 1'b0;
            mem_mem_we_reg <= 1'b0;
            mem_instr_reg <= 32'b0;
        end else begin
            mem_pc <= ex_pc; mem_alu_res <= ex_result; mem_rs2_data <= ex_rs2_data; // ex_result bağlandı
            mem_rd_addr_reg <= ex_rd_addr; mem_wb_sel_reg <= ex_wb_sel;
            mem_reg_we_reg <= ex_reg_we; mem_mem_we_reg <= ex_mem_we;
            mem_instr_reg <= ex_instr;
            mem_id_reg <= ex_id; mem_valid_reg <= ex_valid;
        end
    end

    // --- 9. MEMORY (MEM) STAGE ---
    assign mem_id_o = mem_id_reg;
    assign mem_valid_o = mem_valid_reg;
    
    always_ff @(posedge clk_i) begin
        if (mem_mem_we_reg && mem_valid_reg)
            data_mem[mem_alu_res[12:2]] <= mem_rs2_data;
    end

    // --- 10. MEM/WB PIPELINE REGISTER ---
    logic [XLEN-1:0] wb_pc, wb_alu_res, wb_mem_data, wb_id, wb_instr;
    logic [1:0]  wb_sel_final;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            wb_valid <= 1'b0;
            wb_reg_we <= 1'b0;
            wb_instr <= 32'b0;
        end else begin
            wb_pc <= mem_pc; wb_alu_res <= mem_alu_res;
            wb_mem_data <= data_mem[mem_alu_res[12:2]];
            wb_rd_addr <= mem_rd_addr_reg; wb_sel_final <= mem_wb_sel_reg;
            wb_reg_we <= mem_reg_we_reg; wb_instr <= mem_instr_reg;
            wb_id <= mem_id_reg; wb_valid <= mem_valid_reg;
        end
    end

    // --- 11. WRITEBACK (WB) STAGE ---
    always_comb begin
        case (wb_sel_final)
            2'b00: wb_data = wb_alu_res;
            2'b01: wb_data = wb_mem_data;
            2'b10: wb_data = wb_pc + 4;
            2'b11: wb_data = wb_alu_res; // LUI için
            default: wb_data = 32'b0;
        endcase
    end

    assign writeback_id_o = wb_id;
    assign writeback_valid_o = wb_valid;

    // --- 12. RETIRE PORT ASSIGNMENTS ---
    assign update_o   = wb_valid;
    assign pc_o       = wb_pc;
    assign instr_o    = wb_instr; // Testbench için komut ulaştırıldı
    assign reg_addr_o = wb_rd_addr;
    assign reg_data_o = wb_data;
    assign mem_addr_o = wb_alu_res;
    assign mem_data_o = wb_mem_data;
    assign mem_wrt_o  = 1'b0; 

    // --- 13. GERÇEK HAZARD UNIT LOGIC ---
    assign flush = ex_valid && (ex_jump || (ex_branch && branch_taken));

    logic dec_uses_rs1, dec_uses_rs2;
    assign dec_uses_rs1 = (rs1_addr != 5'b0);
    assign dec_uses_rs2 = (rs2_addr != 5'b0);

    logic hazard_ex, hazard_mem, hazard_wb;
    assign hazard_ex  = ex_valid  && ex_reg_we  && (ex_rd_addr != 5'b0)  && ((dec_uses_rs1 && rs1_addr == ex_rd_addr) || (dec_uses_rs2 && rs2_addr == ex_rd_addr));
    assign hazard_mem = mem_valid_reg && mem_reg_we_reg && (mem_rd_addr_reg != 5'b0) && ((dec_uses_rs1 && rs1_addr == mem_rd_addr_reg) || (dec_uses_rs2 && rs2_addr == mem_rd_addr_reg));
    assign hazard_wb  = wb_valid  && wb_reg_we  && (wb_rd_addr != 5'b0)  && ((dec_uses_rs1 && rs1_addr == wb_rd_addr) || (dec_uses_rs2 && rs2_addr == wb_rd_addr));

    // STALL çalışırken eğer o anda FLUSH varsa, stall iptal edilir (!flush)
    assign stall = dec_valid && (hazard_ex || hazard_mem || hazard_wb) && !flush;

endmodule
