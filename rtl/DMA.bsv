package DMA;

import FIFOF::*;

`define ADDR_WIDTH 32

typedef enum {
   READ,
   WRITE
} CmdType deriving (Bits, Eq, FShow);

typedef struct {
   CmdType  cmd;
   Bit#(32) addr;
   Bit#(8)  len; // number of beats
} DMA_Command deriving (Bits, FShow);

interface DMAMemory_Master_Ifc#(numeric type data_width);
   // AR
   method Bit#(`ADDR_WIDTH) ar_addr();
   method Bit#(8)           ar_len();
   method Bool              ar_valid();
   method Action            ar_ready(Bool rdy);

   // R
   method Action r_put(Bit#(data_width) r_data, Bool r_last, Bool r_valid);
   method Bool   r_ready();

   // AW
   method Bit#(`ADDR_WIDTH) aw_addr();
   method Bit#(8)           aw_len();
   method Bool              aw_valid();
   method Action            aw_ready(Bool rdy);

   // W
   method Bit#(data_width) w_data();
   method Bit#(TDiv#(data_width, 8)) w_strb();
   method Bool              w_last();
   method Bool              w_valid();
   method Action            w_ready(Bool rdy);

   // B
   method Action b_put(Bit#(2) b_resp, Bool b_valid);
   method Bool   b_ready();
endinterface

interface DMA_Ifc#(numeric type mem_width, numeric type stream_width);
   interface DMAMemory_Master_Ifc#(mem_width) mem_ifc;
   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
   method Action startWrite(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
   method Action putWriteData(Bit#(stream_width) data, Bit#(TDiv#(stream_width, 8)) strb);
   method ActionValue#(Bit#(stream_width)) getReadData();
   method ActionValue#(Bool) getWriteResp();
endinterface

module mkDMA (DMA_Ifc#(data_width, data_width));
   
   FIFOF#(Tuple2#(Bit#(data_width), Bit#(TDiv#(data_width, 8)))) write_data_fifo <- mkSizedFIFOF(16);
   FIFOF#(Bit#(data_width)) data_fifo       <- mkSizedFIFOF(16);
   
   FIFOF#(DMA_Command) cmd_fifo <- mkSizedFIFOF(16);

   // Outstanding request tracking
   FIFOF#(DMA_Command) ar_fifo <- mkSizedFIFOF(4);
   FIFOF#(DMA_Command) aw_fifo <- mkSizedFIFOF(4);
   
   FIFOF#(Bit#(8)) w_len_fifo <- mkSizedFIFOF(4);
   FIFOF#(Bool)    b_req_fifo <- mkSizedFIFOF(4);
   FIFOF#(Bool)    b_resp_fifo <- mkSizedFIFOF(16);

   Reg#(Bit#(8)) rg_active_w_len <- mkReg(0);

   Wire#(Bool) wr_ar_ready <- mkDWire(False);
   Wire#(Bit#(data_width)) wr_r_data <- mkDWire(0);
   Wire#(Bool) wr_r_last   <- mkDWire(False);
   Wire#(Bool) wr_r_valid  <- mkDWire(False);
   
   Wire#(Bool) wr_aw_ready <- mkDWire(False);
   Wire#(Bool) wr_w_ready  <- mkDWire(False);
   Wire#(Bool) wr_b_valid  <- mkDWire(False);
   Wire#(Bit#(2)) wr_b_resp <- mkDWire(0);

   // Dispatch commands to independent AXI channels
   rule rl_dispatch_cmd;
      let cmd = cmd_fifo.first;
      if (cmd.cmd == READ) begin
         if (ar_fifo.notFull) begin
            cmd_fifo.deq;
            ar_fifo.enq(cmd);
         end
      end else begin
         if (aw_fifo.notFull && w_len_fifo.notFull && b_req_fifo.notFull) begin
            cmd_fifo.deq;
            aw_fifo.enq(cmd);
            w_len_fifo.enq(cmd.len);
            b_req_fifo.enq(True);
         end
      end
   endrule

   // ----- READ CHANNELS -----
   rule rl_send_ar (ar_fifo.notEmpty);
      if (wr_ar_ready) begin
         ar_fifo.deq;
      end
   endrule

   rule rl_read_data (wr_r_valid && data_fifo.notFull);
      data_fifo.enq(wr_r_data);
   endrule

   // ----- WRITE CHANNELS -----
   rule rl_send_aw (aw_fifo.notEmpty);
      if (wr_aw_ready) begin
         aw_fifo.deq;
      end
   endrule

   rule rl_start_w_burst (rg_active_w_len == 0);
      rg_active_w_len <= w_len_fifo.first;
      w_len_fifo.deq;
   endrule

   rule rl_send_w_beat (rg_active_w_len > 0);
      if (wr_w_ready && write_data_fifo.notEmpty) begin
         write_data_fifo.deq;
         rg_active_w_len <= rg_active_w_len - 1;
      end
   endrule

   rule rl_wait_b (b_req_fifo.notEmpty && wr_b_valid && b_resp_fifo.notFull);
      b_req_fifo.deq;
      b_resp_fifo.enq(True);
   endrule

   // ----- INTERFACE -----
   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {cmd: READ, addr: addr, len: len});
   endmethod

   method Action startWrite(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {cmd: WRITE, addr: addr, len: len});
   endmethod

   method Action putWriteData(Bit#(data_width) data, Bit#(TDiv#(data_width, 8)) strb);
      write_data_fifo.enq(tuple2(data, strb));
   endmethod

   method ActionValue#(Bit#(data_width)) getReadData();
      let d = data_fifo.first;
      data_fifo.deq;
      return d;
   endmethod

   method ActionValue#(Bool) getWriteResp();
      let b = b_resp_fifo.first;
      b_resp_fifo.deq;
      return b;
   endmethod

   interface DMAMemory_Master_Ifc mem_ifc;
      // AR Channel
      method Bit#(`ADDR_WIDTH) ar_addr(); return ar_fifo.first.addr; endmethod
      method Bit#(8) ar_len(); return ar_fifo.first.len - 1; endmethod
      method Bool ar_valid(); return ar_fifo.notEmpty; endmethod
      method Action ar_ready(Bool rdy); wr_ar_ready <= rdy; endmethod

      // R Channel
      method Action r_put(Bit#(data_width) r_data, Bool r_last, Bool r_valid);
         wr_r_data <= r_data;
         wr_r_last <= r_last;
         wr_r_valid <= r_valid;
      endmethod
      method Bool r_ready(); return data_fifo.notFull; endmethod

      // AW Channel
      method Bit#(`ADDR_WIDTH) aw_addr(); return aw_fifo.first.addr; endmethod
      method Bit#(8) aw_len(); return aw_fifo.first.len - 1; endmethod
      method Bool aw_valid(); return aw_fifo.notEmpty; endmethod
      method Action aw_ready(Bool rdy); wr_aw_ready <= rdy; endmethod

      // W Channel
      method Bit#(data_width) w_data(); return tpl_1(write_data_fifo.first); endmethod
      method Bit#(TDiv#(data_width, 8)) w_strb(); return tpl_2(write_data_fifo.first); endmethod
      method Bool w_last();
         return rg_active_w_len == 1;
      endmethod
      method Bool w_valid();
         return (rg_active_w_len > 0) && write_data_fifo.notEmpty;
      endmethod
      method Action w_ready(Bool rdy); wr_w_ready <= rdy; endmethod

      // B Channel
      method Action b_put(Bit#(2) b_resp, Bool b_valid); 
         wr_b_resp <= b_resp;
         wr_b_valid <= b_valid;
      endmethod
      method Bool b_ready(); return b_req_fifo.notEmpty && b_resp_fifo.notFull; endmethod
   endinterface

endmodule
endpackage
