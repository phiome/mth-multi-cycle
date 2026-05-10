

module alu import riscv_pkg::*; (
    input  logic [XLEN-1:0] a_i,        // first operanf
    input  logic [XLEN-1:0] b_i,        // second operand
    input  logic [3:0]      alu_ctrl_i, // ALU operation selector signal
    
    output logic [XLEN-1:0] res_o,      // result of operation
    output logic            zero_o      // Zero flag: logic high if the result is 0
);

    // Combinational Operation Logic

    always_comb begin
        case (alu_ctrl_i)
            4'b0000: res_o = a_i + b_i;                                // ADD / ADDI
            4'b1000: res_o = a_i - b_i;                                // SUB
            4'b0001: res_o = a_i << b_i[4:0];                          // SLL / SLLI 
            4'b0101: res_o = a_i >> b_i[4:0];                          // SRL / SRLI 
            4'b1101: res_o = $signed(a_i) >>> b_i[4:0];                // SRA / SRAI 
            
            // Set Less Than
            4'b0010: res_o = {31'b0, ($signed(a_i) < $signed(b_i))};   // SLT / SLTI
            4'b0011: res_o = {31'b0, (a_i < b_i)};                     // SLTU / SLTIU
            
            // Bitwise logical operations
            4'b0100: res_o = a_i ^ b_i;                                // XOR / XORI
            4'b0110: res_o = a_i | b_i;                                // OR / ORI
            4'b0111: res_o = a_i & b_i;                                // AND / ANDI
            
            // default case for safety 
            default: res_o = '0; 
        endcase
    end

    // ZERO FLAG (for Branching Logic)
    // This flag is set high if the ALU result is exactly zero.
    // Example for BEQ (Branch if Equal): Subtracting A from B results in 0 if they are equal, triggering the flag
    assign zero_o = (res_o == '0) ? 1'b1 : 1'b0;

endmodule
