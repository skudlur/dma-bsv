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
   Bit#(8)  len; // number of beats
} DMA_Command deriving (Bits, FShow);

interface DMAMemory_Master_Ifc;
   // AR
   method Bit#(`ADDR_WIDTH) ar_addr();
   method Bit#(8)           ar_len();
   method Bool              ar_valid();
   method Action            ar_ready(Bool rdy);

   // R
   method Action r_put(Bit#(`DATA_WIDTH) r_data, Bool r_last, Bool r_valid);
   method Bool   r_ready();

   // AW
   method Bit#(`ADDR_WIDTH) aw_addr();
   method Bit#(8)           aw_len();
   method Bool              aw_valid();
   method Action            aw_ready(Bool rdy);

   // W
   method Bit#(`DATA_WIDTH) w_data();
   method Bool              w_last();
   method Bool              w_valid();
   method Action            w_ready(Bool rdy);

   // B
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
   Reg#(Bit#(8))  rg_r_len  <- mkReg(0);
   Reg#(Bit#(8))  rg_w_len  <- mkReg(0);
   Reg#(Bit#(8))  rg_b_len  <- mkReg(0);

   Reg#(Bool)     rg_ar_pending <- mkReg(False);
   Reg#(Bool)     rg_aw_pending <- mkReg(False);

   Reg#(Bit#(32)) rg_addr <- mkReg(0);
   Reg#(Bit#(8))  rg_len  <- mkReg(0);
   
   FIFOF#(Bit#(32))    data_fifo       <- mkFIFOF();
   FIFOF#(Bit#(32))    write_data_fifo <- mkSizedFIFOF(16);
   FIFOF#(DMA_Command) cmd_fifo        <- mkFIFOF();

   Wire#(Bool)         wr_ar_ready <- mkDWire(False);
   Wire#(Bit#(32))     wr_r_data   <- mkDWire(0);
   Wire#(Bool)         wr_r_last   <- mkDWire(False);
   Wire#(Bool)         wr_r_valid  <- mkDWire(False);
   
   Wire#(Bool)         wr_aw_ready <- mkDWire(False);
   Wire#(Bool)         wr_w_ready  <- mkDWire(False);
   Wire#(Bool)         wr_b_valid  <- mkDWire(False);
   Wire#(Bit#(2))      wr_b_resp   <- mkDWire(0);

   rule rl_start_transfer (!rg_ar_pending && !rg_aw_pending && rg_r_len == 0 && rg_w_len == 0 && rg_b_len == 0 && cmd_fifo.notEmpty);
      let cmd = cmd_fifo.first;
      cmd_fifo.deq;
      rg_addr <= cmd.addr;
      rg_len  <= cmd.len;
      if (cmd.cmd == READ) begin
         rg_ar_pending <= True;
         rg_r_len      <= cmd.len;
      end else begin
         rg_aw_pending <= True;
         rg_w_len      <= cmd.len;
         rg_b_len      <= 1;
      end
   endrule

   // ----- READ CHANNELS -----
   rule rl_send_ar (rg_ar_pending);
      if (wr_ar_ready) begin
         rg_ar_pending <= False;
      end
   endrule

   rule rl_read_data (rg_r_len > 0);
      if (wr_r_valid && data_fifo.notFull) begin
         data_fifo.enq(wr_r_data);
         rg_r_len <= rg_r_len - 1;
      end
   endrule

   rule rl_dump_read_data;
      let d = data_fifo.first;
      data_fifo.deq;
      $display("DMA Received Data: %x", d);
   endrule

   // ----- WRITE CHANNELS -----
   rule rl_send_aw (rg_aw_pending);
      if (wr_aw_ready) begin
         rg_aw_pending <= False;
      end
   endrule

   rule rl_send_w (rg_w_len > 0);
      if (wr_w_ready && write_data_fifo.notEmpty) begin
         let w = write_data_fifo.first;
         write_data_fifo.deq;
         rg_w_len <= rg_w_len - 1;
      end
   endrule

   rule rl_wait_b (rg_b_len > 0);
      if (wr_b_valid) begin
         $display("DMA: B valid received!");
         rg_b_len <= rg_b_len - 1;
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
      method Bit#(`ADDR_WIDTH) ar_addr(); return rg_addr; endmethod
      method Bit#(8) ar_len(); return rg_len - 1; endmethod
      method Bool ar_valid(); return rg_ar_pending; endmethod
      method Action ar_ready(Bool rdy); wr_ar_ready <= rdy; endmethod

      // R Channel
      method Action r_put(Bit#(`DATA_WIDTH) r_data, Bool r_last, Bool r_valid);
         wr_r_data <= r_data;
         wr_r_last <= r_last;
         wr_r_valid <= r_valid;
      endmethod
      method Bool r_ready(); return data_fifo.notFull && (rg_r_len > 0); endmethod

      // AW Channel
      method Bit#(`ADDR_WIDTH) aw_addr(); return rg_addr; endmethod
      method Bit#(8) aw_len(); return rg_len - 1; endmethod
      method Bool aw_valid(); return rg_aw_pending; endmethod
      method Action aw_ready(Bool rdy); wr_aw_ready <= rdy; endmethod

      // W Channel
      method Bit#(`DATA_WIDTH) w_data(); return write_data_fifo.first; endmethod
      method Bool w_last(); return rg_w_len == 1; endmethod
      method Bool w_valid(); return (rg_w_len > 0) && write_data_fifo.notEmpty; endmethod
      method Action w_ready(Bool rdy); wr_w_ready <= rdy; endmethod

      // B Channel
      method Action b_put(Bit#(2) b_resp, Bool b_valid); 
         wr_b_resp <= b_resp;
         wr_b_valid <= b_valid;
      endmethod
      method Bool b_ready(); return rg_b_len > 0; endmethod
   endinterface

endmodule
endpackage
