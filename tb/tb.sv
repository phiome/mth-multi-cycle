`timescale 1 ns / 1 ps
module tb ();
    logic [riscv_pkg::XLEN-1:0] addr;
    logic [riscv_pkg::XLEN-1:0] data;
    logic [riscv_pkg::XLEN-1:0] pc;
    logic [riscv_pkg::XLEN-1:0] instr_;
    logic [riscv_pkg::XLEN-1:0] instr;
    logic [                4:0] reg_addr;
    logic [riscv_pkg::XLEN-1:0] reg_data;
    logic [riscv_pkg::XLEN-1:0] mem_addr;
    logic [riscv_pkg::XLEN-1:0] mem_data;     
    logic                       update;
    logic                       mem_wrt;
    logic clk;
    logic rstn;
    logic [riscv_pkg::XLEN-1:0] fetch_id;
    logic                       fetch_valid;
    logic [riscv_pkg::XLEN-1:0] decode_id;
    logic                       decode_valid;
    logic [riscv_pkg::XLEN-1:0] execute_id;
    logic                       execute_valid;
    logic [riscv_pkg::XLEN-1:0] mem_id;
    logic                       mem_valid;
    logic [riscv_pkg::XLEN-1:0] writeback_id;
    logic                       writeback_valid;

  
  descrambler i_descrambler(
    .instruction_i(instr_),
    .instruction_o(instr)
  );

  riscv_multicycle i_core_model (
      .clk_i      (clk),
      .rstn_i     (rstn),
      .addr_i     (addr),
      .update_o   (update),
      .data_o     (data),
      .pc_o       (pc),
      .instr_o    (instr_),
      .reg_addr_o (reg_addr),
      .reg_data_o (reg_data),
      .mem_addr_o (mem_addr),
      .mem_data_o (mem_data),
      .mem_wrt_o  (mem_wrt),

      .fetch_id_o(fetch_id),
      .fetch_valid_o(fetch_valid),
      .decode_id_o(decode_id),
      .decode_valid_o(decode_valid),
      .execute_id_o(execute_id),
      .execute_valid_o(execute_valid),
      .mem_id_o(mem_id),
      .mem_valid_o(mem_valid),
      .writeback_id_o(writeback_id),
      .writeback_valid_o(writeback_valid)
  );


  `ifndef RUN_WITHOUT_PIPELINE
    konata i_konata(
      .clk_i(clk),
      .rstn_i(rstn),

      .fetch_id_i(fetch_id),
      .fetch_valid_i(fetch_valid),

      .decode_id_i(decode_id),
      .decode_valid_i(decode_valid),

      .execute_id_i(execute_id),
      .execute_valid_i(execute_valid),

      .mem_id_i(mem_id),
      .mem_valid_i(mem_valid),

      .writeback_id_i(writeback_id),
      .writeback_valid_i(writeback_valid)
    );
  `endif





  integer file_pointer;
  initial begin
    file_pointer = $fopen("model.log", "w");
    #4;
    forever begin
      if (update) begin
        if (reg_addr == 0) begin
          $fwrite(file_pointer, "0x%8h (0x%8h)", pc, instr);
        end else begin
          if (reg_addr > 9) begin
            $fwrite(file_pointer, "0x%8h (0x%8h) x%0d 0x%8h", pc, instr, reg_addr, reg_data);
          end else begin
            $fwrite(file_pointer, "0x%8h (0x%8h) x%0d  0x%8h", pc, instr, reg_addr, reg_data);
          end
        end
        if (mem_wrt == 1) begin
          $fwrite(file_pointer, " mem 0x%8h 0x%8h", mem_addr, mem_data);
        end
        $fwrite(file_pointer, "\n");
        #2;
      end else #1;
    end
  end
  initial
    forever begin
      clk = 0;
      #1;
      clk = 1;
      #1;
    end
  initial begin
    rstn = 0;
    #4;
    rstn = 1;
    #20000;
    for (int i = 0; i < 10; i++) begin
      addr = i;
      $display("data @ mem[0x%8h] = %8h", addr, data);
    end
    $finish;
  end


  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();
  end

endmodule
