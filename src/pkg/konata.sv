module konata
	(
		input logic clk_i,
		input logic rstn_i,

		input logic [31:0] fetch_id_i,
		input logic fetch_valid_i,

		input logic [31:0] decode_id_i,
		input logic decode_valid_i,

		input logic [31:0] execute_id_i,
		input logic execute_valid_i,

		input logic [31:0] mem_id_i,
		input logic mem_valid_i,

		input logic [31:0] writeback_id_i,
		input logic writeback_valid_i
	);

	logic [31:0] fetch_id_q;
	logic [31:0] fetch_id_q2;
	logic [31:0] decode_id_q;
	logic [31:0] decode_id_q2;
	logic [31:0] execute_id_q;
	logic [31:0] execute_id_q2;
	logic [31:0] mem_id_q;
	logic [31:0] mem_id_q2;
	logic [31:0] writeback_id_q;
	logic [31:0] writeback_id_q2;



  	`define konata_write(args) $fwrite(file, $sformatf args );
  

	integer file;
	initial begin
	    file=$fopen("konata.log", "w");
	    if(file!=0) begin 
			$display("konata.log opened successfully"); 
			`konata_write(("Kanata\t0004\n"));
			`konata_write(("C=\t0\n"));
	    end else begin 
	    	$display("konata.log could not open"); 
	    end
	end

	always_ff @(posedge clk_i) begin
		if(!rstn_i) begin
			fetch_id_q<='0;
			fetch_id_q2<='0;
			decode_id_q<='0;
			decode_id_q2<='0;
			execute_id_q<='0;
			execute_id_q2<='0;
			mem_id_q<='0;
			mem_id_q2<='0;
			writeback_id_q<='0;
			writeback_id_q2<='0;
		end else begin
			writeback_id_q <= writeback_id_i   != '0 ? writeback_id_i : writeback_id_q;
			writeback_id_q2<= writeback_id_q != '0 ? writeback_id_q : writeback_id_q2;
			if(writeback_id_i < writeback_id_q && writeback_id_i!='0) begin
				$error("invalid instruction order on writeback stage. writeback_id_i(%0d) should be greater than %0d", writeback_id_i, writeback_id_q);
			end else begin
				if(writeback_id_q!='0 && writeback_id_q2<writeback_id_q) begin 
					`konata_write(("E\t%0d\t0\tWRB\n", writeback_id_q));
					`konata_write(("R\t%0d\t%0d\t0\n", writeback_id_q, writeback_id_q));
				end
				if(writeback_valid_i && writeback_id_i > writeback_id_q) begin
					`konata_write(("S\t%0d\t0\tWRB\n", writeback_id_i));
				end
			end 

			mem_id_q <= mem_id_i != '0 ? mem_id_i : mem_id_q;
			mem_id_q2 <= mem_id_q != '0 ? mem_id_q : mem_id_q2;
			if(mem_id_i < mem_id_q && mem_id_i!='0) begin
				$error("invalid instruction order on mem stage. mem_id_i(%0d) should be greater than %0d", mem_id_i, mem_id_q);
			end else begin 
				if(mem_id_q!='0 && mem_id_q2<mem_id_q) `konata_write(("E\t%0d\t0\tMEM\n", mem_id_q));
				if(mem_valid_i && mem_id_i > mem_id_q) `konata_write(("S\t%0d\t0\tMEM\n", mem_id_i));
			end


			execute_id_q <= execute_id_i != '0 ? execute_id_i : execute_id_q;
			execute_id_q2 <= execute_id_q != '0 ? execute_id_q : execute_id_q2;
			if(execute_id_i < execute_id_q && execute_id_i!='0) begin
				$error("invalid instruction order on execute stage. execute_id_i(%0d) should be greater than %0d", execute_id_i, execute_id_q);
			end else begin 
				if(execute_id_q!='0 && execute_id_q2<execute_id_q) `konata_write(("E\t%0d\t0\tEXE\n", execute_id_q));
				if(execute_valid_i && execute_id_i > execute_id_q) `konata_write(("S\t%0d\t0\tEXE\n", execute_id_i));
			end

			decode_id_q <= decode_id_i != '0 ? decode_id_i : decode_id_q;
			decode_id_q2 <= decode_id_q != '0 ? decode_id_q : decode_id_q2;
			if(decode_id_i < decode_id_q && decode_id_i!='0) begin
				$error("invalid instruction order on decode stage. decode_id_i(%0d) should be greater than %0d", decode_id_i, decode_id_q);
			end else begin 
				if(decode_id_q!='0 && decode_id_q2<decode_id_q) `konata_write(("E\t%0d\t0\tDEC\n", decode_id_q));
				if(decode_valid_i && decode_id_i > decode_id_q) begin
					`konata_write(("S\t%0d\t0\tDEC\n", decode_id_i));
				end
			end

			fetch_id_q2 <= fetch_id_q != '0 ? fetch_id_q : fetch_id_q2;
			if(fetch_valid_i) begin
				fetch_id_q <= fetch_id_i != '0 ? fetch_id_i : fetch_id_q;
				if(fetch_id_i < fetch_id_q && fetch_id_i!='0) begin
					$error("invalid instruction order on fetch stage. fetch_id_i(%0d) should be greater than %0d", fetch_id_i, fetch_id_q);
				end else begin 
					if(fetch_id_q!='0 && fetch_id_q2<fetch_id_q) `konata_write(("E\t%0d\t0\tFE\n", fetch_id_q));
					if(fetch_valid_i && fetch_id_i > fetch_id_q) begin
						`konata_write(("I\t%0d\t%0d\t0\n", fetch_id_i, fetch_id_i));
						`konata_write(("S\t%0d\t0\tFE\n", fetch_id_i));
					end
				end
			end

			`konata_write(("C\t1\n"));
		end
	end

	
endmodule

