/*
 * HW3: 5-Stage Pipelined RISC-V Processor 
 * Author: Mustafa Talha Gezer
 */

module riscv_multicycle import riscv_pkg::*; #(
    parameter DMemInitFile = "dmem.mem",
    parameter IMemInitFile = "imem.mem"
) (
    input  logic              clk_i,           // System clock
    input  logic              rstn_i,          // System reset
    input  logic [XLEN-1:0]   addr_i,          // Memory address input for reading
    
    output logic              update_o,        // Retire signal
    output logic [XLEN-1:0]   data_o,          // Memory data output for reading
    output logic [XLEN-1:0]   pc_o,            // Retired program counter
    output logic [XLEN-1:0]   instr_o,         // Retired instruction
    output logic [4:0]        reg_addr_o,      // Retired register address
    output logic [XLEN-1:0]   reg_data_o,      // Retired register data
    output logic [XLEN-1:0]   mem_addr_o,      // Retired memory address
    output logic [XLEN-1:0]   mem_data_o,      // Retired memory data
    output logic              mem_wrt_o,       // Retired memory write enable

    // Pipeline Monitoring Signals
    output logic [XLEN-1:0]   fetch_id_o,      output logic fetch_valid_o,
    output logic [XLEN-1:0]   decode_id_o,     output logic decode_valid_o,
    output logic [XLEN-1:0]   execute_id_o,    output logic execute_valid_o,
    output logic [XLEN-1:0]   mem_id_o,        output logic mem_valid_o,
    output logic [XLEN-1:0]   writeback_id_o,  output logic writeback_valid_o
);

    // --- 1. MEMORY AND ID TRACKING ---
    logic [XLEN-1:0] instr_mem [0:2047];
    logic [XLEN-1:0] data_mem  [0:2047];
    logic [XLEN-1:0] next_instr_id;

    initial begin
        $readmemh(IMemInitFile, instr_mem, 0, 2047);
        $readmemh(DMemInitFile, data_mem, 0, 2047);
    end

    // Testbench'in arka kapıdan (backdoor) bellek okuması için gerekli atama
    assign data_o = data_mem[addr_i[12:2]];

    // --- 2. HAZARD UNIT SIGNALS ---
    logic stall, flush;

    // --- 3. FETCH (FE) STAGE ---
    logic [XLEN-1:0] fe_pc, fe_instr;
    logic [31:0] branch_target_ex; // Execute aşamasından gelecek dallanma hedefi
    
    // NOT: Hocanın konata.sv dosyasıyla uyumlu olmak için tüm resetler SENKRON yapıldı
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            fe_pc <= 32'h80000000;
            next_instr_id <= 32'd1;
        end else if (!stall) begin
            if (flush) fe_pc <= branch_target_ex; // Branch recovery
            else fe_pc <= fe_pc + 4;
            
            if (fetch_valid_o) next_instr_id <= next_instr_id + 1;
        end
    end
    
    assign fe_instr = instr_mem[fe_pc[12:2]];
    assign fetch_id_o = (rstn_i) ? next_instr_id : 32'b0;
    assign fetch_valid_o = rstn_i && !stall;

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
    logic        reg_we, alu_src, pc_to_alu, mem_we, branch, jump, jalr_w; // 'jalr_w' olarak değiştirildi
    logic [1:0]  wb_sel;
    logic [3:0]  alu_ctrl;
    logic [2:0]  unused_branch_type; // Eksik pin hatasını çözmek için sahte kablo

    decoder u_decoder (
        .clk_i(clk_i), .instr_i(dec_instr),
        .rs1_addr_o(rs1_addr), .rs2_addr_o(rs2_addr), .rd_addr_o(rd_addr),
        .imm_o(imm), .reg_we_o(reg_we), .alu_src_o(alu_src), .pc_to_alu_o(pc_to_alu),
        .alu_ctrl_o(alu_ctrl), .mem_we_o(mem_we), .wb_sel_o(wb_sel),
        .branch_o(branch), .jump_o(jump), .jalr_o(jalr_w), // 'jalr_w' bağlandı
        .branch_type_o(unused_branch_type) // Boş kalmaması için bağlandı
    );

    // Writeback aşamasından gelen geri bildirimler (Feedback)
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
    logic [XLEN-1:0] ex_pc, ex_imm, ex_rs1_data, ex_rs2_data, ex_id;
    logic [4:0]  ex_rd_addr, ex_rs1_addr, ex_rs2_addr;
    logic [3:0]  ex_alu_ctrl;
    logic [1:0]  ex_wb_sel;
    logic        ex_reg_we, ex_alu_src, ex_pc_to_alu, ex_mem_we, ex_branch, ex_jump, ex_jalr, ex_valid;

    always_ff @(posedge clk_i) begin
        if (!rstn_i || flush || stall) begin
            ex_valid <= 1'b0;
            ex_reg_we <= 1'b0;
            ex_mem_we <= 1'b0;
        end else begin
            ex_pc <= dec_pc; ex_imm <= imm; ex_rs1_data <= rs1_data; ex_rs2_data <= rs2_data;
            ex_rd_addr <= rd_addr; ex_rs1_addr <= rs1_addr; ex_rs2_addr <= rs2_addr;
            ex_alu_ctrl <= alu_ctrl; ex_wb_sel <= wb_sel; ex_reg_we <= reg_we;
            ex_alu_src <= alu_src; ex_pc_to_alu <= pc_to_alu; ex_mem_we <= mem_we;
            ex_branch <= branch; ex_jump <= jump; ex_jalr <= jalr_w; // 'jalr_w' ataması
            ex_id <= dec_id; ex_valid <= dec_valid;
        end
    end

    // --- 7. EXECUTE (EXE) STAGE ---
    logic [31:0] alu_a, alu_b, alu_res;
    logic unused_zero; // ALU'nun zero_o pini için sahte kablo
    
    assign alu_a = ex_pc_to_alu ? ex_pc : ex_rs1_data;
    assign alu_b = ex_alu_src ? ex_imm : ex_rs2_data;

    alu u_alu (
        .a_i(alu_a), .b_i(alu_b), .alu_ctrl_i(ex_alu_ctrl),
        .res_o(alu_res), .zero_o(unused_zero) // Pin bağlandı
    );

    // Basitleştirilmiş Branch/Jump Hedef Hesabı
    assign branch_target_ex = ex_jalr ? (ex_rs1_data + ex_imm) : (ex_pc + ex_imm);

    assign execute_id_o = ex_id;
    assign execute_valid_o = ex_valid;

    // --- 8. EX/MEM PIPELINE REGISTER ---
    logic [XLEN-1:0] mem_pc, mem_alu_res, mem_rs2_data, mem_id_reg;
    logic [4:0]  mem_rd_addr_reg;
    logic [1:0]  mem_wb_sel_reg;
    logic        mem_reg_we_reg, mem_mem_we_reg, mem_valid_reg;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            mem_valid_reg <= 1'b0;
            mem_reg_we_reg <= 1'b0;
            mem_mem_we_reg <= 1'b0;
        end else begin
            mem_pc <= ex_pc; mem_alu_res <= alu_res; mem_rs2_data <= ex_rs2_data;
            mem_rd_addr_reg <= ex_rd_addr; mem_wb_sel_reg <= ex_wb_sel;
            mem_reg_we_reg <= ex_reg_we; mem_mem_we_reg <= ex_mem_we;
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
    logic [XLEN-1:0] wb_pc, wb_alu_res, wb_mem_data, wb_id;
    logic [1:0]  wb_sel_final;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            wb_valid <= 1'b0;
            wb_reg_we <= 1'b0;
        end else begin
            wb_pc <= mem_pc; wb_alu_res <= mem_alu_res;
            wb_mem_data <= data_mem[mem_alu_res[12:2]];
            wb_rd_addr <= mem_rd_addr_reg; wb_sel_final <= mem_wb_sel_reg;
            wb_reg_we <= mem_reg_we_reg;
            wb_id <= mem_id_reg; wb_valid <= mem_valid_reg;
        end
    end

    // --- 11. WRITEBACK (WB) STAGE ---
    always_comb begin
        case (wb_sel_final)
            2'b00: wb_data = wb_alu_res;
            2'b01: wb_data = wb_mem_data;
            2'b10: wb_data = wb_pc + 4;
            default: wb_data = 32'b0;
        endcase
    end

    assign writeback_id_o = wb_id;
    assign writeback_valid_o = wb_valid;

    // --- 12. RETIRE PORT ASSIGNMENTS (Hocanın Beklediği Final Çıkışlar) ---
    assign update_o   = wb_valid;
    assign pc_o       = wb_pc;
    assign instr_o    = 32'h0; // Basit şablon için 0 bırakıldı, gerekirse boru hattında taşınabilir
    assign reg_addr_o = wb_rd_addr;
    assign reg_data_o = wb_data;
    assign mem_addr_o = wb_alu_res;
    assign mem_data_o = wb_mem_data;
    assign mem_wrt_o  = 1'b0; // Bellek yazma işlemi MEM aşamasında halledildi

    // --- 13. HAZARD UNIT LOGIC (Basit Load-Use Stall) ---
    assign stall = (ex_valid && ex_mem_we && (ex_rd_addr == rs1_addr || ex_rd_addr == rs2_addr));
    assign flush = 1'b0; // İlerleyen aşamalarda Branch mantığı buraya eklenecek

endmodule
