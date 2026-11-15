module fifo_out #(
        parameter  WIDTH    = 16,
        parameter  DEPTH    = 34,
        localparam LOGDEPTH = $clog2(DEPTH)
    )(
        input                   clk, 
        input                   reset,
        input [WIDTH-1:0]        IN_AXIS_TDATA,
        input                   IN_AXIS_TVALID,
        output logic            IN_AXIS_TREADY,
        output logic [WIDTH-1:0] OUT_AXIS_TDATA,
        output logic            OUT_AXIS_TVALID,
        input                   OUT_AXIS_TREADY        
    );

    logic [$clog2(DEPTH+1)-1:0] capacity;
    logic [LOGDEPTH-1:0] tail, head, tail_plus_one;
    logic rd_en;
    logic [LOGDEPTH-1:0] rd_addr;

    logic wr_en;
    assign wr_en = IN_AXIS_TVALID && IN_AXIS_TREADY;
    assign IN_AXIS_TREADY = ((capacity > 0) || (OUT_AXIS_TREADY && OUT_AXIS_TVALID));

    // Memory instance. This memory has one write port and one read port.
    memory_dual_port #(WIDTH, DEPTH) mem(.clk(clk), .data_in(IN_AXIS_TDATA), .data_out(OUT_AXIS_TDATA), 
                                        .write_addr(head), .read_addr(rd_addr), .wr_en(wr_en));

    // The "head" address represents the next free location in the RAM. When we write data,
    // we store it to write_address = head and then increment head (with wraparound) for the
    // next write.
    always_ff @(posedge clk) begin
        if (reset) 
            head <= 0;        
        else begin
            if (wr_en)
                head <= (head == DEPTH-1) ? 0 : head + 1;
        end
    end

    // The "tail" address represents the oldest valid item in the FIFO.
    // We increment this (with wraparound) every time we read.
    always_ff @(posedge clk) begin
        if (reset) begin
            tail <= 0;
        end
        else begin
            if (rd_en)
                tail <= (tail == DEPTH-1) ? 0 : tail + 1;
        end
    end

    // However, there's one difficulty here: memory reads have a one cycle delay.
    // So, when the system isn't actively reading, we use tail as the read address. 
    // Then, when the read is happening we send tail_plus_one in as the address (to 
    // prepare to read the next value after the next clock edge).
    assign tail_plus_one = (tail == DEPTH-1) ? 0 : tail+1;
    assign rd_addr = (rd_en) ? tail_plus_one : tail;
    
    // The output is valid if the FIFO is not empty.
    assign OUT_AXIS_TVALID = (capacity != DEPTH);

    // How do we know when reads happen? A read happens when OUT_AXIS_TREADY and OUT_AXIS_TVALID
    // are 1 on a positive clock edge.
    assign rd_en = (OUT_AXIS_TREADY && OUT_AXIS_TVALID);
    // Note that the rd_en doesn't go into the memory: we're just using it
    // for control.

    // Compute the capacity of the FIFO. It starts at DEPTH.
    always_ff @(posedge clk) begin
        if (reset)            
            capacity <= DEPTH;
        else begin
            if (rd_en && !wr_en)
                capacity <= capacity+1;
            
            if (wr_en && !rd_en)
                capacity <= capacity-1;
        end
    end

endmodule


module memory_dual_port #(
        parameter                WIDTH=16, SIZE=64,
        localparam               LOGSIZE=$clog2(SIZE)
    )(
        input [WIDTH-1:0]        data_in,
        output logic [WIDTH-1:0] data_out,
        input [LOGSIZE-1:0]      write_addr, read_addr,
        input                    clk, wr_en
    );
       
    logic [WIDTH-1:0] mem [SIZE];
    
    always_ff @(posedge clk) begin
        data_out <= mem[read_addr];
        if (wr_en) begin            
            mem[write_addr] <= data_in;
            
            // if we are reading and writing to same address concurrently, 
            // then output the new data
            if (read_addr == write_addr)
                data_out <= data_in;
        end
    end


endmodule
