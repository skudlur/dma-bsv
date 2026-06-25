package Gearbox;

import FIFOF::*;
import Vector::*;

interface Gearbox#(numeric type in_w, numeric type out_w);
   method Action enq(Bit#(in_w) data);
   method ActionValue#(Bit#(out_w)) deq();
   method Bool notFull();
   method Bool notEmpty();
endinterface

// DownSizer: in_w > out_w, in_w is a multiple of out_w
module mkDownSizer (Gearbox#(in_w, out_w))
   provisos(
      Div#(in_w, out_w, n),
      Mul#(n, out_w, in_w)
   );

   FIFOF#(Bit#(in_w)) in_fifo <- mkFIFOF;
   FIFOF#(Bit#(out_w)) out_fifo <- mkFIFOF;
   Reg#(Vector#(n, Bit#(out_w))) rg_data <- mkReg(replicate(0));
   Reg#(UInt#(32)) rg_count <- mkReg(0);

   rule rl_unpack_first (rg_count == 0);
      Vector#(n, Bit#(out_w)) d = unpack(in_fifo.first);
      in_fifo.deq;
      out_fifo.enq(d[0]);
      rg_data <= d;
      if (fromInteger(valueOf(n)) > 1) begin
         rg_count <= 1;
      end
   endrule

   rule rl_unpack_rest (rg_count > 0);
      out_fifo.enq(rg_data[rg_count]);
      if (rg_count == fromInteger(valueOf(n)) - 1) begin
         rg_count <= 0;
      end else begin
         rg_count <= rg_count + 1;
      end
   endrule

   method Action enq(Bit#(in_w) data);
      in_fifo.enq(data);
   endmethod

   method ActionValue#(Bit#(out_w)) deq();
      let d = out_fifo.first;
      out_fifo.deq;
      return d;
   endmethod

   method Bool notFull();
      return in_fifo.notFull();
   endmethod

   method Bool notEmpty();
      return out_fifo.notEmpty();
   endmethod

endmodule

// UpSizer: out_w > in_w, out_w is a multiple of in_w
module mkUpSizer (Gearbox#(in_w, out_w))
   provisos(
      Div#(out_w, in_w, n),
      Mul#(n, in_w, out_w)
   );

   FIFOF#(Bit#(in_w)) in_fifo <- mkFIFOF;
   FIFOF#(Bit#(out_w)) out_fifo <- mkFIFOF;
   Reg#(Vector#(n, Bit#(in_w))) rg_data <- mkReg(replicate(0));
   Reg#(UInt#(32)) rg_count <- mkReg(0);

   rule rl_pack;
      let data = in_fifo.first;
      in_fifo.deq;
      
      Vector#(n, Bit#(in_w)) next_data = rg_data;
      next_data[rg_count] = data;
      
      if (rg_count == fromInteger(valueOf(n) - 1)) begin
         out_fifo.enq(pack(next_data));
         rg_count <= 0;
      end else begin
         rg_data <= next_data;
         rg_count <= rg_count + 1;
      end
   endrule

   method Action enq(Bit#(in_w) data);
      in_fifo.enq(data);
   endmethod

   method ActionValue#(Bit#(out_w)) deq();
      let d = out_fifo.first;
      out_fifo.deq;
      return d;
   endmethod

   method Bool notFull();
      return in_fifo.notFull();
   endmethod

   method Bool notEmpty();
      return out_fifo.notEmpty();
   endmethod

endmodule

endpackage
