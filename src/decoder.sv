/* verilator lint_off UNUSEDSIGNAL */


module decoder import riscv_pkg::*; (
    input  logic        clk_i,   
    input  logic [31:0] instr_i,
    
    // DATAPATH ADDRESS AND VALUE OUTPUTS
    output logic [4:0]  rs1_addr_o,
    output logic [4:0]  rs2_addr_o,
    output logic [4:0]  rd_addr_o,
    output logic [31:0] imm_o,         
    
    // Control Unit Outputs
    output logic        reg_we_o,      // Register Write Enable (Register File we_i)
    output logic        alu_src_o,     // ALU B source: 0 = RS2, 1 = IMM
    output logic        pc_to_alu_o,   // ALU A source: 0 = RS1, 1 = PC (for AUIPC)
    output logic [3:0]  alu_ctrl_o,    // 4-bit operation command for the ALU
    output logic        mem_we_o,      // Data Memory Write Enable
    output logic [1:0]  wb_sel_o,      // Write-Back selector: 00:ALU, 01:Mem, 10:PC+4, 11:IMM
    output logic        branch_o,      // Instruction is a branch?
    output logic [2:0]  branch_type_o, // Branch type (funct3 for BEQ, BNE, etc.)
    output logic        jump_o,        // Instruction is a Jump (JAL or JALR)?
    output logic        jalr_o         // Target PC is RS1 + IMM?
);

    // 1st step :  Extracting signals according to the Custom ISA
    logic [6:0] opcode;
    logic [2:0] funct3;

    assign opcode     = instr_i[19:13];
    assign rs2_addr_o = instr_i[24:20];
    assign rs1_addr_o = instr_i[12:8];
    assign funct3     = instr_i[7:5];
    assign rd_addr_o  = instr_i[4:0];

    // 2nd step: Combinational Decoding Logic
    always_comb begin
        // default calues
        imm_o         = '0;
        reg_we_o      = 1'b0;
        alu_src_o     = 1'b0;
        pc_to_alu_o   = 1'b0;
        alu_ctrl_o    = 4'b0000; // default ALU: ADD
        mem_we_o      = 1'b0;
        wb_sel_o      = 2'b00;
        branch_o      = 1'b0;
        branch_type_o = 3'b000;
        jump_o        = 1'b0;
        jalr_o        = 1'b0;

        // 3rd step: Routing based on Opcode
        case (opcode)
            
            // LUI
            7'b1110101: begin 
                reg_we_o = 1'b1;
                wb_sel_o = 2'b11; 
                imm_o    = {instr_i[31:20], instr_i[12:5], 12'b0};
            end

            // AUIPC
            7'b1110100: begin 
                reg_we_o    = 1'b1;
                wb_sel_o    = 2'b00; 
                pc_to_alu_o = 1'b1;  
                alu_src_o   = 1'b1; 
                alu_ctrl_o  = 4'b0000; // ADD
                imm_o       = {instr_i[31:20], instr_i[12:5], 12'b0};
            end

            // JAL 
            7'b1101111: begin 
                reg_we_o = 1'b1;
                wb_sel_o = 2'b10;
                jump_o   = 1'b1;
                imm_o    = { {11{instr_i[31]}}, instr_i[31], instr_i[12:5], instr_i[20], instr_i[30:21], 1'b0 };
            end

            // JALR 
            7'b1100111: begin 
                reg_we_o = 1'b1;
                wb_sel_o = 2'b10; 
                jump_o   = 1'b1;
                jalr_o   = 1'b1;
                imm_o    = { {20{instr_i[31]}}, instr_i[31:20] };
            end

            // Branch 
            7'b1100011: begin 
                branch_o      = 1'b1;
                branch_type_o = funct3; 
                alu_src_o     = 1'b0;   
                alu_ctrl_o    = 4'b1000; // SUB 
                imm_o         = { {19{instr_i[31]}}, instr_i[31], instr_i[0], instr_i[30:25], instr_i[4:1], 1'b0 };
            end

            // Load 
            7'b1100000: begin 
                reg_we_o   = 1'b1;
                wb_sel_o   = 2'b01;   
                alu_src_o  = 1'b1;    
                alu_ctrl_o = 4'b0000; 
                imm_o      = { {20{instr_i[31]}}, instr_i[31:20] };
            end

            // Store 
            7'b1100001: begin 
                mem_we_o   = 1'b1;    
                alu_src_o  = 1'b1;   
                alu_ctrl_o = 4'b0000; 
                imm_o      = { {20{instr_i[31]}}, instr_i[31:25], instr_i[4:0] };
            end

            // I-Type 
            7'b1100100: begin 
                reg_we_o   = 1'b1;
                wb_sel_o   = 2'b00; 
                alu_src_o  = 1'b1;  // ALU B = IMM

                // Shift and Arithmetic logic
                if (funct3 == 3'b001 || funct3 == 3'b101) begin
                    imm_o = { 27'b0, instr_i[24:20] }; 
                end else begin
                    imm_o = { {20{instr_i[31]}}, instr_i[31:20] };
                end
                
                //Assign ALU Operation Code (based on alu.sv definitions)
                case (funct3)
                    3'b000: alu_ctrl_o = 4'b0000; // ADDI
                    3'b010: alu_ctrl_o = 4'b0010; // SLTI
                    3'b011: alu_ctrl_o = 4'b0011; // SLTIU
                    3'b100: alu_ctrl_o = 4'b0110; // ORI
                    3'b110: alu_ctrl_o = 4'b0100; // XORI
                    3'b111: alu_ctrl_o = 4'b0111; // ANDI
                    3'b001: alu_ctrl_o = 4'b0001; // SLLI
                    3'b101: begin
                        if (instr_i[31:25] == 7'b0000000)
                            alu_ctrl_o = 4'b0101; // SRLI
                        else if (instr_i[31:25] == 7'b0000010)
                            alu_ctrl_o = 4'b1101; // SRAI
                    end
                    default: ;
                endcase
            end

            // R-Type
            7'b1110001: begin 
                reg_we_o  = 1'b1;
                wb_sel_o  = 2'b00; 
                alu_src_o = 1'b0;  // ALU B = RS2

                case (funct3)
                    3'b000: begin
                        if (instr_i[31:25] == 7'b0000000)      alu_ctrl_o = 4'b0000; // ADD
                        else if (instr_i[31:25] == 7'b0000010) alu_ctrl_o = 4'b1000; // SUB
                    end
                    3'b001: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0001; // SLL
                    3'b010: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0010; // SLT
                    3'b011: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0011; // SLTU
                    3'b100: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0100; // XOR
                    3'b101: begin
                        if (instr_i[31:25] == 7'b0000000)      alu_ctrl_o = 4'b0101; // SRL
                        else if (instr_i[31:25] == 7'b0000010) alu_ctrl_o = 4'b1101; // SRA
                    end
                    3'b110: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0110; // OR
                    3'b111: if (instr_i[31:25] == 7'b0000000) alu_ctrl_o = 4'b0111; // AND
                    default: ; 
                endcase
            end

            default: ; // all signals remain at 0 for unknown opcodes
        endcase
    end

endmodule

