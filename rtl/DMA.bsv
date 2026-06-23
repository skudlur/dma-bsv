package DMA;

import FIFOF::*;

`define ADDR_WIDTH 32
`define DATA_WIDTH 32

typedef enum {
   READ,
   WRITE
} CmdType deriving (Bits, Eq, FShow);

typedef struct {
   CmdType  cmd;
   Bit#(32) addr;
   Bit#(8)  len;
} DMA_Command deriving (Bits, FShow);

typedef enum {
   IDLE,
   SEND_AR_ADDR,
   READ_DATA,
   SEND_AW_ADDR,
   SEND_W_DATA,
   WAIT_B_RESP
} State deriving (Bits, Eq, FShow);

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
   method Action startWrite(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
   method Action putWriteData(Bit#(`DATA_WIDTH) data);
endinterface

module mkDMA (DMA_Ifc);
   Reg#(State)         state           <- mkReg(IDLE);
   Reg#(Bit#(32))      rg_cur_addr     <- mkReg(0);
   Reg#(Bit#(8))       rg_transfer_len <- mkReg(0);
   
   FIFOF#(Bit#(32))    data_fifo       <- mkFIFOF();
   FIFOF#(Bit#(32))    write_data_fifo <- mkSizedFIFOF(16);
   FIFOF#(DMA_Command) cmd_fifo        <- mkFIFOF();

   Wire#(Bool)         wr_ar_ready <- mkDWire(False);
   Wire#(Bit#(32))     wr_r_data   <- mkDWire(0);
   Wire#(Bool)         wr_r_valid  <- mkDWire(False);
   
   Wire#(Bool)         wr_aw_ready <- mkDWire(False);
   Wire#(Bool)         wr_w_ready  <- mkDWire(False);
   Wire#(Bool)         wr_b_valid  <- mkDWire(False);
   Wire#(Bit#(2))      wr_b_resp   <- mkDWire(0);

   rule rl_start_transfer(state == IDLE && cmd_fifo.notEmpty);
      let cmd_flit = cmd_fifo.first;
      cmd_fifo.deq;
      rg_cur_addr <= cmd_flit.addr;
      rg_transfer_len <= cmd_flit.len;
      if (cmd_flit.cmd == READ) begin
         state <= SEND_AR_ADDR;
      end else begin
         state <= SEND_AW_ADDR;
      end
   endrule

   // ----- READ CHANNELS -----
   rule rl_send_ar_address(state == SEND_AR_ADDR);
      if (wr_ar_ready) begin
         state <= READ_DATA;
      end
   endrule

   rule rl_read_data(state == READ_DATA);
      if (wr_r_valid && data_fifo.notFull) begin
         data_fifo.enq(wr_r_data);
         if (rg_transfer_len == 1) begin
            state <= IDLE;
         end
         else begin
            rg_transfer_len <= rg_transfer_len - 1;
            rg_cur_addr <= rg_cur_addr + 4;
            state <= SEND_AR_ADDR;
         end
      end
   endrule

   rule rl_dump_read_data;
      let d = data_fifo.first;
      data_fifo.deq;
      $display("DMA Received Data: %x", d);
   endrule

   // ----- WRITE CHANNELS -----
   rule rl_send_aw_address(state == SEND_AW_ADDR);
      if (wr_aw_ready) begin
         state <= SEND_W_DATA;
      end
   endrule

   rule rl_send_w_data(state == SEND_W_DATA);
      if (wr_w_ready && write_data_fifo.notEmpty) begin
         write_data_fifo.deq;
         state <= WAIT_B_RESP;
      end
   endrule

   rule rl_wait_b_resp(state == WAIT_B_RESP);
      if (wr_b_valid) begin
         if (rg_transfer_len == 1) begin
            state <= IDLE;
         end else begin
            rg_transfer_len <= rg_transfer_len - 1;
            rg_cur_addr <= rg_cur_addr + 4;
            state <= SEND_AW_ADDR;
         end
      end
   endrule

   // ----- INTERFACE -----
   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {cmd: READ, addr: addr, len: len});
   endmethod

   method Action startWrite(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {cmd: WRITE, addr: addr, len: len});
   endmethod

   method Action putWriteData(Bit#(`DATA_WIDTH) data);
      write_data_fifo.enq(data);
   endmethod

   interface DMAMemory_Master_Ifc mem_ifc;
      // AR Channel
      method Bit#(`ADDR_WIDTH) ar_addr(); return rg_cur_addr; endmethod
      method Bool ar_valid(); return state == SEND_AR_ADDR; endmethod
      method Action ar_ready(Bool rdy); wr_ar_ready <= rdy; endmethod

      // R Channel
      method Action r_put(Bit#(`DATA_WIDTH) r_data, Bool r_valid);
         wr_r_data <= r_data;
         wr_r_valid <= r_valid;
      endmethod
      method Bool r_ready(); return data_fifo.notFull && (state == READ_DATA); endmethod

      // AW Channel
      method Bit#(`ADDR_WIDTH) aw_addr(); return rg_cur_addr; endmethod
      method Bool aw_valid(); return state == SEND_AW_ADDR; endmethod
      method Action aw_ready(Bool rdy); wr_aw_ready <= rdy; endmethod

      // W Channel
      method Bit#(`DATA_WIDTH) w_data(); return write_data_fifo.first; endmethod
      method Bool w_valid(); return state == SEND_W_DATA && write_data_fifo.notEmpty; endmethod
      method Action w_ready(Bool rdy); wr_w_ready <= rdy; endmethod

      // B Channel
      method Action b_put(Bit#(2) b_resp, Bool b_valid); 
         wr_b_resp <= b_resp;
         wr_b_valid <= b_valid;
      endmethod
      method Bool b_ready(); return state == WAIT_B_RESP; endmethod
   endinterface

endmodule
endpackage
