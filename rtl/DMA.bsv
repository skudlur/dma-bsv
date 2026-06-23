package DMA;

import FIFOF::*;

`define ADDR_WIDTH 32
`define DATA_WIDTH 32

typedef enum {
   IDLE,
   SEND_ADDR,
   READ_DATA
} State deriving (Bits, Eq, FShow);

typedef struct {
   Bit#(32) addr;
   Bit#(8)  len;
} DMA_Command deriving (Bits, FShow);

interface DMAMemory_Master_Ifc;
   method Bit#(`ADDR_WIDTH) ar_addr();
   method Bool   ar_valid();
   method Action ar_ready(Bool rdy);

   method Action r_put(Bit#(`DATA_WIDTH) r_data, Bool r_valid);
   method Bool   r_ready();

   method Bit#(`ADDR_WIDTH) aw_addr();
   method Bool   aw_valid();
   method Action aw_ready(Bool rdy);

   method Bit#(`DATA_WIDTH) w_data();
   method Bool   w_valid();
   method Action w_ready(Bool rdy);

   method Action b_put(Bit#(2) b_resp, Bool b_valid);
   method Bool   b_ready();
endinterface

interface DMA_Ifc;
   interface DMAMemory_Master_Ifc mem_ifc;
   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
endinterface

module mkDMA (DMA_Ifc);
   Reg#(State)         state       <- mkReg(IDLE);
   Reg#(Bit#(32))      rg_cur_addr <- mkReg(0);
   Reg#(Bit#(8))       rg_read_len <- mkReg(0);
   FIFOF#(Bit#(32))    data_fifo   <- mkFIFOF();
   FIFOF#(DMA_Command) cmd_fifo    <- mkFIFOF();

   Wire#(Bool)         wr_ar_ready <- mkWire();
   Wire#(Bit#(32))     wr_r_data   <- mkWire();
   Wire#(Bool)         wr_r_valid  <- mkWire();

   rule rl_start_transfer(state == IDLE && cmd_fifo.notEmpty);
      let cmd_flit = cmd_fifo.first;
      cmd_fifo.deq;
      rg_cur_addr <= cmd_flit.addr;
      rg_read_len <= cmd_flit.len;
      state <= SEND_ADDR;
   endrule

   rule rl_send_address(state == SEND_ADDR);
      if (wr_ar_ready) begin
         state <= READ_DATA;
      end
   endrule

   rule rl_read_data(state == READ_DATA);
      if (wr_r_valid && data_fifo.notFull) begin
         data_fifo.enq(wr_r_data);
         if (rg_read_len == 1) begin
            state <= IDLE;
         end
         else begin
            rg_read_len <= rg_read_len - 1;
            rg_cur_addr <= rg_cur_addr + 4;
            state <= SEND_ADDR;
         end
      end
   endrule

   rule rl_dump_data;
      let d = data_fifo.first;
      data_fifo.deq;
      $display("DMA Received Data: %x", d);
   endrule

   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {addr: addr, len: len});
   endmethod

   interface DMAMemory_Master_Ifc mem_ifc;
      method Bit#(`ADDR_WIDTH) ar_addr();
         return rg_cur_addr;
      endmethod
      method Bool ar_valid();
         return state == SEND_ADDR;
      endmethod
      method Action ar_ready(Bool rdy);
         wr_ar_ready <= rdy;
      endmethod

      method Action r_put(Bit#(`DATA_WIDTH) r_data, Bool r_valid);
         wr_r_data <= r_data;
         wr_r_valid <= r_valid;
      endmethod
      method Bool r_ready();
         return data_fifo.notFull && (state == READ_DATA);
      endmethod

      method Bit#(`ADDR_WIDTH) aw_addr(); return 0; endmethod
      method Bool aw_valid(); return False; endmethod
      method Action aw_ready(Bool rdy); endmethod

      method Bit#(`DATA_WIDTH) w_data(); return 0; endmethod
      method Bool w_valid(); return False; endmethod
      method Action w_ready(Bool rdy); endmethod

      method Action b_put(Bit#(2) b_resp, Bool b_valid); endmethod
      method Bool b_ready(); return False; endmethod
   endinterface

endmodule
endpackage
