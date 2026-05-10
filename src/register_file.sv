

module register_file import riscv_pkg::*; (
    input  logic             clk_i,
    input  logic             rstn_i,
    input  logic             we_i,          // Write Enable
    
    input  logic [4:0]       rs1_addr_i,    // Read Address 1
    input  logic [4:0]       rs2_addr_i,    // Read Address 2
    input  logic [4:0]       rd_addr_i,     // Write Address
    
    input  logic [XLEN-1:0]  rd_data_i,     // Write Data
    
    output logic [XLEN-1:0]  rs1_data_o,    // Read Data 1
    output logic [XLEN-1:0]  rs2_data_o     // Read Data 2
);

    // 32x32 array of registers
    logic [XLEN-1:0] registers [31:0];

    
    // READ LOGIC (comb)
    
    // if req addr is x0 output 0 immediatly
    assign rs1_data_o = (rs1_addr_i == 5'b0) ? '0 : registers[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'b0) ? '0 : registers[rs2_addr_i];

 
    // Write and Reset Logic (Sync)

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 1; i < 32; i++) begin
                registers[i] <= '0;
            end
        end 
        else begin
            if (we_i && (rd_addr_i != 5'b0)) begin
                registers[rd_addr_i] <= rd_data_i;
            end
        end
    end

endmodule
